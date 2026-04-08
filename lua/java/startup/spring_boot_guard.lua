local log = require('java-core.utils.log2')

local M = {}

local pending_commands = {}
local spring_boot_ready = false

local function flush_pending()
	if not spring_boot_ready then
		return
	end

	local queued_commands = pending_commands
	pending_commands = {}

	for _, cmd in ipairs(queued_commands) do
		local ok, err = pcall(cmd.fn)
		if not ok then
			log.error('Failed to flush spring boot command', err)
		end
	end
end

function M.install()
	local ok, util = pcall(require, 'spring_boot.util')
	if not ok then
		return
	end

	if util.__guard_installed then
		return
	end
	util.__guard_installed = true

	util.get_client = function(name) -- luacheck: ignore
		local clients = vim.lsp.get_clients({ name = name })
		if clients and #clients > 0 then
			return clients[1]
		end
		return nil
	end

	util.get_spring_boot_client = function()
		local clients = vim.lsp.get_clients({ name = 'spring-boot' })
		if clients and #clients > 0 then
			return clients[1]
		end
		return nil
	end

	util.boot_execute_command = function(command, param, callback) -- luacheck: ignore
		if spring_boot_ready then
			local client = util.get_spring_boot_client()
			if client then
				local err, resp = util.execute_command(client, command, param, callback)
				if err then
					log.error('Error executeCommand: ' .. command, err)
				end
				return resp
			end
			spring_boot_ready = false
		end

		local client = util.get_spring_boot_client()
		if client then
			spring_boot_ready = true
			flush_pending()
			local err, resp = util.execute_command(client, command, param, callback)
			if err then
				log.error('Error executeCommand: ' .. command, err)
			end
			return resp
		end

		table.insert(pending_commands, {
			fn = function()
				local replay_client = util.get_spring_boot_client()
				if not replay_client then
					error('spring-boot client missing during queued command replay')
				end
				local err = util.execute_command(replay_client, command, param, callback)
				if err then
					log.error('Error executeCommand: ' .. command, err)
				end
			end,
		})

		return nil
	end

	vim.api.nvim_create_autocmd('LspAttach', {
		callback = function(args)
			local client = vim.lsp.get_client_by_id(args.data.client_id)
			if not client or client.name ~= 'spring-boot' then
				return
			end

			spring_boot_ready = true
			flush_pending()
		end,
	})
end

return M
