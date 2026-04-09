--- Silences spring-boot.nvim's "Client not found" error notifications.
--- The original spring_boot.util.get_client calls vim.notify(ERROR) when
--- a client is missing, which is expected before spring-boot LS attaches.
--- These overrides return nil silently instead.
local M = {}

function M.install()
	local ok, util = pcall(require, 'spring_boot.util')
	if not ok then
		return
	end

	if util.__guard_installed then
		return
	end
	util.__guard_installed = true

	util.get_client = function(name)
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
end

return M
