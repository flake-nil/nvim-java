# nvim-java Customization Plan (Clean Local Setup)

> Last updated: 2026-04-08
> Purpose: keep local `nvim-java` setup clean, reproducible, and copyable to a new repo.

---

## Scope

This plan tracks 3 customizations:

1. Use `diego-velez/nvim-java` async branch commit (1 commit ahead of main)
2. Map JDTLS to Homebrew install (skip slow JDTLS download host)
3. Add a safe Spring Boot startup guard for LSP timing race

---

## 1) Use async-network fork commit (pinned)

### Why

- Fork branch keeps UI responsive during package downloads.
- Pinning a commit keeps behavior stable when branch updates.

### Current reference

- Repo: `diego-velez/nvim-java`
- Branch: `refactor/async_network_io`
- Commit: `4a2f72e` (`refactor!: download packages asynchrono...`)
- Base main commit shown in local clone: `602a5f7`

### Plugin spec pattern

```lua
{
  "diego-velez/nvim-java",
  branch = "refactor/async_network_io",
  commit = "4a2f72e",
  ft = "java",
}
```

---

## 2) Use Homebrew JDTLS via nvim-java package path mapping

### Why

- nvim-java normally downloads JDTLS from Eclipse host.
- Host can be too slow (multi-hour installs).
- We can pre-map Homebrew JDTLS into nvim-java expected folder.

### Mapping

```bash
mkdir -p ~/.local/share/nvim/nvim-java/packages/jdtls
ln -sfn /opt/homebrew/opt/jdtls/libexec ~/.local/share/nvim/nvim-java/packages/jdtls/1.54.0
```

### nvim-java config pin

```lua
require("java").setup({
  jdtls = { version = "1.54.0" },
  jdk = { auto_install = false }, -- use SDKMAN/system JDK
})
```

### Notes

- `1.54.0` is the **folder/version key** nvim-java checks.
- Symlink target can be newer brew JDTLS (`/opt/homebrew/opt/jdtls/libexec`).
- If symlink is removed or version key changes, nvim-java downloads again.

### Verify

```bash
ls ~/.local/share/nvim/nvim-java/packages/jdtls/1.54.0/plugins/org.eclipse.equinox.launcher_*.jar
```

---

## 3) Spring Boot startup timing guard (keep feature enabled)

### Problem

Intermittent startup race can produce:

- `Client not found: spring-boot`
- downstream DAP/LSP command noise during early attach window

### Goal

- Keep `spring_boot_tools` enabled
- Avoid hard failure/noisy notify when client attaches slightly later

### Guard strategy

Patch `spring_boot.util` at runtime from your local config (do **not** edit plugin source):

- replace immediate client lookup with `wait_for_client(name, timeout_ms)`
- wrap `boot_execute_command(...)` to skip once if client still unavailable
- warn once per command instead of throwing repeated errors

### Config pattern (local patch)

```lua
local function install_spring_boot_client_guard()
  local ok, util = pcall(require, "spring_boot.util")
  if not ok or util.__client_guard_installed then
    return
  end
  util.__client_guard_installed = true

  local function find_client(name)
    local clients = vim.lsp.get_clients({ name = name })
    return (clients and #clients > 0) and clients[1] or nil
  end

  local function wait_for_client(name, timeout_ms)
    local client = find_client(name)
    if client then
      return client
    end
    if not vim.in_fast_event() then
      vim.wait(timeout_ms, function()
        client = find_client(name)
        return client ~= nil
      end, 100, false)
    end
    return client
  end

  util.get_client = function(name)
    return wait_for_client(name, 3000)
  end

  util.get_spring_boot_client = function()
    return wait_for_client("spring-boot", 3000)
  end
end

install_spring_boot_client_guard()

require("java").setup({
  spring_boot_tools = { enable = true },
})
```

### Verify

- Open Java project, run `:LspInfo`
- Confirm `jdtls` attached; `spring-boot` appears when relevant buffers are active
- Confirm no repeated `Client not found: spring-boot` notifications

---

## Suggested structure for new repo

- Keep plugin spec in `lua/plugins/nvim-java.lua`
- Keep guard helper in separate file (example: `lua/config/java_spring_boot_guard.lua`)
- Require helper from plugin config before `require("java").setup(...)`

This keeps the customization explicit and easy to remove when upstream fixes land.
