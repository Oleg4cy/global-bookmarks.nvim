if vim.g.loaded_global_bookmarks then
  return
end
vim.g.loaded_global_bookmarks = true

vim.api.nvim_create_user_command("GlobalBookmarks", function()
  require("global-bookmarks").open()
end, {})

vim.api.nvim_create_user_command("GlobalBookmarkToggle", function()
  local action = require("global-bookmarks").toggle_current_file()
  if action ~= nil then
    require("global-bookmarks.integrations.nvim-tree").refresh()
  end
end, {})
