local M = {}

function M.decorator()
  local api = require("nvim-tree.api")
  local bookmarks = require("global-bookmarks")

  local GlobalBookmarkDecorator = api.Decorator:extend()

  function GlobalBookmarkDecorator:new()
    self.enabled = true
    self.highlight_range = "all"
    self.icon_placement = "after"
    self.icon = {
      str = " ",
      hl = { "GlobalBookmarksNvimTreeIcon" },
    }
    self.bookmark_cache = {}
  end

  function GlobalBookmarkDecorator:is_bookmarked(node)
    if node == nil or node.absolute_path == nil or node.absolute_path == "" then
      return false
    end

    local path = node.absolute_path
    if self.bookmark_cache[path] ~= nil then
      return self.bookmark_cache[path]
    end

    local bookmarked = bookmarks.is_bookmarked(path)
    self.bookmark_cache[path] = bookmarked
    return bookmarked
  end

  function GlobalBookmarkDecorator:icons(node)
    if not self:is_bookmarked(node) then
      return nil
    end

    return { self.icon }
  end

  function GlobalBookmarkDecorator:highlight_group(node)
    if self:is_bookmarked(node) then
      return "GlobalBookmarksNvimTreeHL"
    end

    return nil
  end

  return GlobalBookmarkDecorator
end

function M.refresh()
  local api = package.loaded["nvim-tree.api"]
  if type(api) ~= "table" or not api.tree.is_visible() then
    return false
  end

  api.tree.reload()
  return true
end

function M.toggle_node()
  local api = require("nvim-tree.api")
  local node = api.tree.get_node_under_cursor()
  if node == nil or node.absolute_path == nil or node.absolute_path == "" then
    return nil, nil
  end

  local action, normalized_path = require("global-bookmarks").toggle(node.absolute_path)
  if action ~= nil then
    M.refresh()
  end

  return action, normalized_path
end

function M.reveal_current_file()
  local api = require("nvim-tree.api")
  api.tree.find_file({
    open = true,
    focus = false,
    update_root = true,
  })
  return true
end

return M
