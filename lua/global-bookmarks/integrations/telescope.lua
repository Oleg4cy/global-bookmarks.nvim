local M = {}

local function open_selection(prompt_bufnr, target_win, actions, action_state)
  local selection = action_state.get_selected_entry()

  actions.close(prompt_bufnr)

  if not selection or not selection[1] then
    return
  end

  local path = selection[1]

  vim.schedule(function()
    if not vim.api.nvim_win_is_valid(target_win) then
      return
    end

    vim.api.nvim_set_current_win(target_win)
    vim.cmd("edit " .. vim.fn.fnameescape(path))
  end)
end

local function delete_bookmark(prompt_bufnr, bookmarks, actions, action_state)
  local selection = action_state.get_selected_entry()

  if not selection or not selection[1] then
    return
  end

  bookmarks.toggle(selection[1])
  actions.close(prompt_bufnr)
  vim.schedule(M.open)
end

function M.open()
  local bookmarks = require("global-bookmarks")
  local items = bookmarks.list()

  if #items == 0 then
    vim.notify("No global bookmarks", vim.log.levels.INFO, {
      title = "global-bookmarks",
    })
    return
  end

  local target_win = vim.api.nvim_get_current_win()
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  return pickers.new({}, {
    prompt_title = "Global Bookmarks",
    finder = finders.new_table({
      results = items,
    }),
    sorter = conf.generic_sorter({}),
    previewer = conf.file_previewer({}),
    attach_mappings = function(prompt_bufnr, map)
      map("i", "<CR>", function()
        open_selection(prompt_bufnr, target_win, actions, action_state)
      end)
      map("n", "<CR>", function()
        open_selection(prompt_bufnr, target_win, actions, action_state)
      end)
      map("i", "<C-o>", function()
        open_selection(prompt_bufnr, target_win, actions, action_state)
      end)
      map("n", "<C-o>", function()
        open_selection(prompt_bufnr, target_win, actions, action_state)
      end)
      map("i", "<C-d>", function()
        delete_bookmark(prompt_bufnr, bookmarks, actions, action_state)
      end)
      map("n", "dd", function()
        delete_bookmark(prompt_bufnr, bookmarks, actions, action_state)
      end)

      return true
    end,
  }):find()
end

return M
