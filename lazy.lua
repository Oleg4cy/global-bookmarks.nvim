return {
  {
    "Oleg4cy/global-bookmarks.nvim",
    cmd = {
      "GlobalBookmarks",
      "GlobalBookmarkToggle",
    },
    init = function()
      vim.keymap.set("n", "<Plug>(GlobalBookmarksOpen)", "<Cmd>GlobalBookmarks<CR>", {
        silent = true,
        desc = "Global Bookmarks: Open",
      })
      vim.keymap.set("n", "<Plug>(GlobalBookmarksToggleCurrent)", "<Cmd>GlobalBookmarkToggle<CR>", {
        silent = true,
        desc = "Global Bookmarks: Toggle current file",
      })

      vim.api.nvim_create_autocmd("VimEnter", {
        once = true,
        callback = function()
          if vim.fn.hasmapto("<Plug>(GlobalBookmarksOpen)", "n") == 0
            and vim.fn.maparg("<leader>m", "n") == ""
          then
            vim.keymap.set("n", "<leader>m", "<Plug>(GlobalBookmarksOpen)", {
              silent = true,
              desc = "Global Bookmarks: Open",
            })
          end

          if vim.fn.hasmapto("<Plug>(GlobalBookmarksToggleCurrent)", "n") == 0
            and vim.fn.maparg("<leader>M", "n") == ""
          then
            vim.keymap.set("n", "<leader>M", "<Plug>(GlobalBookmarksToggleCurrent)", {
              silent = true,
              desc = "Global Bookmarks: Toggle current file",
            })
          end
        end,
      })
    end,
  },
}
