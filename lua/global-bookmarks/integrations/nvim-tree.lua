local M = {}

local bookmark_cache_generation = 0

local function invalidate_bookmark_cache()
  bookmark_cache_generation = bookmark_cache_generation + 1
end

local function setup_highlights()
  vim.api.nvim_set_hl(0, "GlobalBookmarksNvimTreeHL", { fg = "#fb4934", bold = true, default = true })
  vim.api.nvim_set_hl(0, "GlobalBookmarksNvimTreeIcon", { fg = "#fb4934", bold = true, default = true })
end

function M.attach(bufnr)
  if type(bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  local function opts(desc)
    return { buffer = bufnr, silent = true, nowait = true, desc = "nvim-tree: " .. desc }
  end

  vim.keymap.set("n", "<Plug>(GlobalBookmarksNvimTreeToggle)", M.toggle_node, opts("Toggle Global Bookmark"))
  vim.keymap.set("n", "<Plug>(GlobalBookmarksNvimTreeOpen)", "<Cmd>GlobalBookmarks<CR>", opts("Open Global Bookmarks"))

  vim.api.nvim_buf_call(bufnr, function()
    if vim.fn.hasmapto("<Plug>(GlobalBookmarksNvimTreeToggle)", "n") == 0
      and vim.fn.maparg("gm", "n") == ""
    then
      vim.keymap.set("n", "gm", "<Plug>(GlobalBookmarksNvimTreeToggle)", opts("Toggle Global Bookmark"))
    end

    if vim.fn.hasmapto("<Plug>(GlobalBookmarksNvimTreeOpen)", "n") == 0
      and vim.fn.maparg("gb", "n") == ""
    then
      vim.keymap.set("n", "gb", "<Plug>(GlobalBookmarksNvimTreeOpen)", opts("Open Global Bookmarks"))
    end
  end)

  return true
end

function M.decorator()
  local api = require("nvim-tree.api")
  local bookmarks = require("global-bookmarks")

  setup_highlights()

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
    self.bookmark_cache_generation = bookmark_cache_generation
  end

  function GlobalBookmarkDecorator:is_bookmarked(node)
    if node == nil or node.absolute_path == nil or node.absolute_path == "" then
      return false
    end

    if self.bookmark_cache_generation ~= bookmark_cache_generation then
      self.bookmark_cache = {}
      self.bookmark_cache_generation = bookmark_cache_generation
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
  invalidate_bookmark_cache()

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
