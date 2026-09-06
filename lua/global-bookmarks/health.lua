local M = {}

function M.check()
  vim.health.start("global-bookmarks.nvim")

  local ok, bookmarks = pcall(require, "global-bookmarks")
  if not ok then
    vim.health.error("failed to require global-bookmarks: " .. tostring(bookmarks))
    return
  end

  if type(bookmarks) ~= "table" then
    vim.health.error("global-bookmarks did not return a module table")
    return
  end

  local public_functions = {
    "list",
    "is_bookmarked",
    "toggle",
    "toggle_current_file",
    "open",
  }

  for _, name in ipairs(public_functions) do
    if type(bookmarks[name]) == "function" then
      vim.health.ok("public API: " .. name)
    else
      vim.health.error("public API member is missing or invalid: " .. name)
    end
  end

  vim.health.info("expected storage path: " .. vim.fn.stdpath("data") .. "/global-bookmarks.json")

  vim.health.start("Telescope integration")
  if package.loaded["telescope"] ~= nil then
    vim.health.ok("Telescope is loaded")
  else
    vim.health.info("Telescope is not currently loaded and was not force-loaded by the healthcheck")
  end

  vim.health.start("NvimTree integration")
  local api = package.loaded["nvim-tree.api"]
  if api == nil then
    vim.health.info("NvimTree API is not currently loaded and was not force-loaded by the healthcheck")
  else
    vim.health.ok("NvimTree API is loaded")
    if type(api.Decorator) == "table" and type(api.Decorator.extend) == "function" then
      vim.health.ok("NvimTree decorator API is available")
    else
      vim.health.error("this NvimTree version does not provide the decorator API required by the integration")
    end
  end

  vim.health.start("Integration modules")
  local integration_modules = {
    ["global-bookmarks.integrations.telescope"] = { "open" },
    ["global-bookmarks.integrations.nvim-tree"] = {
      "attach",
      "decorator",
      "refresh",
      "toggle_node",
      "reveal_current_file",
    },
  }

  for module_name, functions in pairs(integration_modules) do
    local module = package.loaded[module_name]
    if module == nil then
      vim.health.info(module_name .. " is not currently loaded and was not force-loaded by the healthcheck")
    elseif type(module) ~= "table" then
      vim.health.error(module_name .. " has an invalid API")
    else
      local valid = true
      for _, name in ipairs(functions) do
        if type(module[name]) ~= "function" then
          valid = false
          break
        end
      end

      if valid then
        vim.health.ok(module_name .. " API is available")
      else
        vim.health.error(module_name .. " has an invalid API")
      end
    end
  end

  vim.health.info("standalone tests: nvim --headless -u tests/minimal_init.lua -i NONE -l tests/bookmarks_spec.lua")
end

return M
