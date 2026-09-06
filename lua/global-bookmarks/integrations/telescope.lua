local M = {}

local function open_selection(prompt_bufnr, target_win, actions, action_state, reveal)
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
    if reveal then
      require("global-bookmarks.integrations.nvim-tree").reveal_current_file()
    end
  end)
end

local function delete_bookmark(prompt_bufnr, bookmarks, actions, action_state)
  local selection = action_state.get_selected_entry()

  if not selection or not selection[1] then
    return
  end

  local action = bookmarks.toggle(selection[1])
  if action ~= nil then
    require("global-bookmarks.integrations.nvim-tree").refresh()
  end
  actions.close(prompt_bufnr)
  vim.schedule(M.open)
end

local function should_install_default(prompt_bufnr, mode, lhs, plug)
  return vim.api.nvim_buf_call(prompt_bufnr, function()
    return vim.fn.hasmapto(plug, mode) == 0 and vim.fn.maparg(lhs, mode) == ""
  end)
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
      local open_reveal = "<Plug>(GlobalBookmarksTelescopeOpenReveal)"
      local open = "<Plug>(GlobalBookmarksTelescopeOpen)"
      local delete = "<Plug>(GlobalBookmarksTelescopeDelete)"
      local mapping_options = {
        silent = true,
      }

      map("i", open_reveal, function()
        open_selection(prompt_bufnr, target_win, actions, action_state, true)
      end, vim.tbl_extend("force", mapping_options, {
        desc = "Global Bookmarks: Open and reveal",
      }))
      map("n", open_reveal, function()
        open_selection(prompt_bufnr, target_win, actions, action_state, true)
      end, vim.tbl_extend("force", mapping_options, {
        desc = "Global Bookmarks: Open and reveal",
      }))
      map("i", open, function()
        open_selection(prompt_bufnr, target_win, actions, action_state, false)
      end, vim.tbl_extend("force", mapping_options, {
        desc = "Global Bookmarks: Open",
      }))
      map("n", open, function()
        open_selection(prompt_bufnr, target_win, actions, action_state, false)
      end, vim.tbl_extend("force", mapping_options, {
        desc = "Global Bookmarks: Open",
      }))
      map("i", delete, function()
        delete_bookmark(prompt_bufnr, bookmarks, actions, action_state)
      end, vim.tbl_extend("force", mapping_options, {
        desc = "Global Bookmarks: Delete",
      }))
      map("n", delete, function()
        delete_bookmark(prompt_bufnr, bookmarks, actions, action_state)
      end, vim.tbl_extend("force", mapping_options, {
        desc = "Global Bookmarks: Delete",
      }))

      local defaults = {
        { "i", "<CR>", open_reveal, "Global Bookmarks: Open and reveal" },
        { "i", "<C-o>", open, "Global Bookmarks: Open" },
        { "i", "<C-d>", delete, "Global Bookmarks: Delete" },
        { "n", "<CR>", open_reveal, "Global Bookmarks: Open and reveal" },
        { "n", "<C-o>", open, "Global Bookmarks: Open" },
        { "n", "dd", delete, "Global Bookmarks: Delete" },
      }

      for _, default in ipairs(defaults) do
        local mode, lhs, plug, desc = unpack(default)
        if should_install_default(prompt_bufnr, mode, lhs, plug) then
          map(mode, lhs, {
            plug,
            type = "command",
          }, {
            desc = desc,
            remap = true,
            silent = true,
          })
        end
      end

      return true
    end,
  }):find()
end

return M
