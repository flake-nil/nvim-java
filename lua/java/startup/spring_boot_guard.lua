local event = require('java-core.utils.event')

local M = {}

local pending_commands = {}
local jdtls_ready = false

local function flush_pending()
	if not jdtls_ready then
		return
	end

	for _, cmd in ipairs(pending_commands) do
		cmd.fn()
	end
	pending_commands = {}
end

function M.install()
	local ok, sb_jdtls = pcall(require, 'spring_boot.jdtls')
	if not ok then
		return
	end

	if sb_jdtls.__guard_installed then
		return
	end
	sb_jdtls.__guard_installed = true

	local orig_execute_command = sb_jdtls.execute_command

	sb_jdtls.execute_command = function(command, param) -- luacheck: ignore
		if jdtls_ready then
			return orig_execute_command(command, param)
		end

		local client = sb_jdtls.get_jdtls_client()
		if client then
			jdtls_ready = true
			flush_pending()
			return orig_execute_command(command, param)
		end

		table.insert(pending_commands, {
			fn = function()
				orig_execute_command(command, param)
			end,
		})
		return nil
	end

	local ok2, util = pcall(require, 'spring_boot.util')
	if ok2 then
		util.get_client = function(name) -- luacheck: ignore
			local clients = vim.lsp.get_clients({ name = name })
			if clients and #clients > 0 then
				return clients[1]
			end
			return nil
		end

		util.get_spring_boot_client = function() -- luacheck: ignore
			local clients = vim.lsp.get_clients({ name = 'spring-boot' })
			if clients and #clients > 0 then
				return clients[1]
			end
			return nil
		end

		util.boot_execute_command = function(command, param, callback) -- luacheck: ignore
			local client = util.get_spring_boot_client()
			if not client then
				return nil
			end

			local err, resp = util.execute_command(client, command, param, callback)
			if err then
				print('Error executeCommand: ' .. command .. '\n' .. vim.inspect(err))
			end
			return resp
		end
	end

	event.on_jdtls_attach({
		once = true,
		callback = function()
			jdtls_ready = true
			flush_pending()
		end,
	})
end

return M
