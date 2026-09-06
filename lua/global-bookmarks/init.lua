local core = require("global-bookmarks.core")

local M = {}

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, {
    title = "global-bookmarks",
  })
end

function M.list()
  return core.list()
end

function M.is_bookmarked(path)
  return core.is_bookmarked(path)
end

function M.toggle(path)
  local action, normalized_path, err = core.toggle(path)

  if err then
    notify("Failed to save bookmarks: " .. err, vim.log.levels.ERROR)
    return nil, nil
  end

  if action == nil then
    notify("Path not found", vim.log.levels.WARN)
    return nil, nil
  end

  if action == "removed" then
    notify("Removed bookmark: " .. normalized_path)
  elseif action == "added" then
    notify("Added bookmark: " .. normalized_path)
  end

  return action, normalized_path
end

function M.toggle_current_file()
  local path = vim.api.nvim_buf_get_name(0)

  return M.toggle(path)
end

function M.open()
  return require("global-bookmarks.integrations.telescope").open()
end

return M
