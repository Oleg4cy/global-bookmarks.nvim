# global-bookmarks.nvim

A small persistent global bookmark plugin for Neovim. Bookmarks are global rather than project-local, persist between Neovim sessions, and are stored as normalized absolute file paths in a JSON array at:

```lua
vim.fn.stdpath("data") .. "/global-bookmarks.json"
```

Storage is loaded lazily on the first bookmark storage operation and remains cached in memory afterward. The plugin has no polling, timers, or background filesystem watchers. It does not provide multi-instance file locking or automatic cross-process synchronization.

## Public API

```lua
require("global-bookmarks").list()
require("global-bookmarks").is_bookmarked(path)
require("global-bookmarks").toggle(path)
require("global-bookmarks").toggle_current_file()
```

`toggle(path)` and `toggle_current_file()` return `"added", normalized_path` or `"removed", normalized_path`. For invalid or empty paths they return `nil, nil`. Toggle operations emit user notifications.

## Telescope integration

Telescope is optional and is loaded only when the picker is opened with a non-empty bookmark list.

```lua
require("global-bookmarks.integrations.telescope").open()
```

Picker-local mappings:

- `<CR>` opens the selected file and reveals it in NvimTree.
- `<C-o>` opens the selected file without NvimTree reveal.
- `<C-d>` deletes the selected bookmark in insert mode.
- `dd` deletes the selected bookmark in normal mode.

The plugin does not automatically create a global keymap for opening the picker.

## NvimTree integration

```lua
require("global-bookmarks.integrations.nvim-tree")
```

The integration exposes `.decorator()`, `.toggle_node()`, `.refresh()`, and `.reveal_current_file()`.

Global bookmarks are independent from NvimTree's native bookmarks. This integration does not use or synchronize through `api.marks`; native NvimTree bookmarks may coexist with global bookmarks. The custom decorator reads global bookmark state directly. It uses the dedicated highlight groups `GlobalBookmarksNvimTreeIcon` and `GlobalBookmarksNvimTreeHL`.

Register the decorator in the user's NvimTree configuration alongside every built-in decorator that should remain active. Specifying `renderer.decorators` replaces NvimTree's decorator list; it does not automatically merge with the defaults.

```lua
local global_bookmarks_tree = require("global-bookmarks.integrations.nvim-tree")

require("nvim-tree").setup({
  renderer = {
    decorators = {
      "Git",
      "Open",
      "Hidden",
      "Modified",
      "Bookmark",
      "Diagnostics",
      "Copied",
      "Cut",
      global_bookmarks_tree.decorator(),
    },
  },
})
```

The native NvimTree bookmark is controlled by NvimTree, may use its native `m` mapping, and uses NvimTree's own bookmark state. A global bookmark is controlled by global-bookmarks.nvim, persists in `global-bookmarks.json`, and may be mapped separately, for example to `gm`. The plugin itself defines neither `m` nor `gm`.

## Installation

With [Lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "Oleg4cy/global-bookmarks.nvim",
  lazy = true,
}
```

Telescope and NvimTree are optional integrations and must be available in the user's configuration when used; they are not mandatory core dependencies.

For example, a user may configure commands and mappings for the integrations:

```lua
-- User configuration examples; these are not created automatically.
vim.api.nvim_create_user_command("GlobalBookmarks", function()
  require("global-bookmarks.integrations.telescope").open()
end, {})

vim.api.nvim_create_user_command("GlobalBookmarkToggle", function()
  require("global-bookmarks").toggle_current_file()
end, {})

vim.keymap.set("n", "<leader>gb", "<cmd>GlobalBookmarks<cr>")
vim.keymap.set("n", "gm", "<cmd>GlobalBookmarkToggle<cr>")
```

## Performance

Requiring the public module does not read bookmark storage. Telescope and NvimTree are not loaded merely by requiring their integration modules. The plugin uses no timers, polling, or background loops.

## Tests

Run the standalone tests with:

```sh
nvim --headless -u tests/minimal_init.lua -i NONE -l tests/bookmarks_spec.lua
```

The tests use plain Neovim/Lua and fake Telescope, NvimTree, and filesystem integrations rather than requiring those third-party plugins.

## Healthcheck

Run:

```vim
:checkhealth global-bookmarks
```

## License

MIT
