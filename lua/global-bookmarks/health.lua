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
  local telescope_ok, telescope = pcall(require, "telescope")
  if telescope_ok then
    vim.health.ok("Telescope is available")
  else
    vim.health.warn("Telescope is unavailable; Telescope integration is optional and the core plugin works without it")
  end

  vim.health.start("NvimTree integration")
  local nvim_tree_ok, api = pcall(require, "nvim-tree.api")
  if not nvim_tree_ok then
    vim.health.warn("NvimTree is unavailable; NvimTree integration is optional and the core plugin works without it")
  else
    vim.health.ok("NvimTree API is available")
    if type(api.Decorator) == "table" and type(api.Decorator.extend) == "function" then
      vim.health.ok("NvimTree decorator API is available")
    else
      vim.health.error("this NvimTree version does not provide the decorator API required by the integration")
    end
  end

  vim.health.start("Integration modules")
  for _, module_name in ipairs({
    "global-bookmarks.integrations.telescope",
    "global-bookmarks.integrations.nvim-tree",
  }) do
    local module_ok, module_or_error = pcall(require, module_name)
    if module_ok then
      vim.health.ok(module_name .. " loaded")
    else
      vim.health.error(module_name .. " failed to load: " .. tostring(module_or_error))
    end
  end

  vim.health.info("standalone tests: nvim --headless -u tests/minimal_init.lua -i NONE -l tests/bookmarks_spec.lua")
end

return M
