# global-bookmarks.nvim

Persistent global file bookmarks for Neovim. Bookmark paths are shared across projects and persisted between sessions. Operations are explicit and manual: the plugin has no background watcher, polling process, or automatic synchronization.

## Features

- Persistent bookmarks stored globally rather than per project.
- Optional Telescope picker and NvimTree integration.
- Manual add/remove, open, and delete operations.

## Requirements

Neovim must provide the `vim.uv`, `vim.json`, and `vim.health` APIs used by the plugin. Telescope is required only for the bookmark picker. NvimTree is required only for the tree integration, which requires an NvimTree API providing `Decorator.extend`.

## Installation

The repository supplies its own lazy.nvim package metadata, so the normal lazy.nvim specification is intentionally small:

```lua
{
  "Oleg4cy/global-bookmarks.nvim",
}
```

No `setup()` call is required.

## Public API

```lua
require("global-bookmarks").list()
require("global-bookmarks").is_bookmarked(path)
require("global-bookmarks").toggle(path)
require("global-bookmarks").toggle_current_file()
require("global-bookmarks").open()
```

- `list()` returns an independent, case-insensitively sorted bookmark list.
- `is_bookmarked(path)` checks a normalized path.
- `toggle(path)` adds or removes a bookmark. On success it returns `"added", normalized_path` or `"removed", normalized_path`; for an invalid path or persistence failure it returns `nil, nil`. A persistence failure is reported with an `ERROR` notification.
- `toggle_current_file()` delegates to `toggle()` for the current buffer.
- `open()` opens the Telescope bookmark picker without requiring callers to use the Telescope integration module directly.

## Commands

- `:GlobalBookmarks` opens the bookmark picker.
- `:GlobalBookmarkToggle` toggles the current file bookmark.

## Default mappings

Global normal-mode defaults are:

- `<leader>m` — open Global Bookmarks (`<Plug>(GlobalBookmarksOpen)`).
- `<leader>M` — toggle the current-file bookmark (`<Plug>(GlobalBookmarksToggleCurrent)`).

### Remapping

Define replacement mappings before `VimEnter`, targeting the stable `<Plug>` action:

```lua
vim.keymap.set(
  "n",
  "<leader>b",
  "<Plug>(GlobalBookmarksOpen)",
  { desc = "Global Bookmarks: Open" }
)

vim.keymap.set(
  "n",
  "<leader>B",
  "<Plug>(GlobalBookmarksToggleCurrent)",
  { desc = "Global Bookmarks: Toggle current file" }
)
```

If another left-hand side already maps to a stable target, the plugin does not create that action's original default. An occupied original left-hand side is never overwritten. Open and Toggle are handled independently. This is replacement semantics, not an extra alias.

## NvimTree integration

Add the integration to your existing NvimTree `on_attach(bufnr)`:

```lua
local function on_attach(bufnr)
  require("nvim-tree.api").config.mappings.default_on_attach(bufnr)
  require("global-bookmarks.integrations.nvim-tree").attach(bufnr)
end
```

Specifying `renderer.decorators` replaces NvimTree's decorator list; it does not automatically merge with the existing/default decorators. Preserve whichever existing NvimTree decorators you want and append `global_bookmarks_tree.decorator()` to that list. This list is illustrative:

```lua
local global_bookmarks_tree = require("global-bookmarks.integrations.nvim-tree")

require("nvim-tree").setup({
  on_attach = on_attach,
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

The plugin does not call `nvim-tree.setup()` or monkey-patch NvimTree.

### NvimTree mappings

These normal-mode mappings are buffer-local to NvimTree:

- `gm` — toggle the Global Bookmark for the node (`<Plug>(GlobalBookmarksNvimTreeToggle)`).
- `gb` — open the Global Bookmarks picker (`<Plug>(GlobalBookmarksNvimTreeOpen)`).

They use the same replacement semantics as the global defaults: mapping another key to the stable `<Plug>` target suppresses that original default, occupied `gm` and `gb` mappings are not overwritten, and Toggle and Open are independent.

### NvimTree highlights

The plugin defines `GlobalBookmarksNvimTreeHL` and `GlobalBookmarksNvimTreeIcon` with `default = true`; users and colorschemes may override them.

## Telescope picker

Picker defaults are:

| Mode | Mapping | Action |
| --- | --- | --- |
| Insert | `<CR>` | Open the selected bookmark and reveal it in NvimTree. |
| Insert | `<C-o>` | Open the selected bookmark without revealing it. |
| Insert | `<C-d>` | Delete the selected bookmark. |
| Normal | `<CR>` | Open the selected bookmark and reveal it in NvimTree. |
| Normal | `<C-o>` | Open the selected bookmark without revealing it. |
| Normal | `dd` | Delete the selected bookmark. |

The stable picker-local actions exist in both insert and normal modes:

- `<Plug>(GlobalBookmarksTelescopeOpenReveal)`
- `<Plug>(GlobalBookmarksTelescopeOpen)`
- `<Plug>(GlobalBookmarksTelescopeDelete)`

The plugin currently exposes the stable picker-local `<Plug>` targets, but does not provide a separate setup/keymap configuration table or a public prompt-buffer configuration hook.

The picker checks mappings in its prompt buffer: if a mode already maps to a stable action, it does not install that action's default; an occupied default left-hand side is also preserved. Remapping/default suppression is mode-specific internally, so replacing Delete in insert mode does not replace normal-mode `dd`.

## Storage

Bookmarks are stored in:

```lua
vim.fn.stdpath("data") .. "/global-bookmarks.json"
```

The file contains an array of bookmark-path strings. Invalid or malformed persisted data fails closed to an empty in-memory state; reading it does not rewrite or repair the file automatically. Bookmark state changes in memory only after persistence succeeds.

Filesystem write failures do not crash the plugin, do not falsely report a bookmark as added or removed, and leave cached state unchanged. The public API reports the failure with an `ERROR` notification.

## Healthcheck

Run:

```vim
:checkhealth global-bookmarks
```

The healthcheck is passive. It may validate the top-level public API, expected storage path, already-loaded Telescope, already-loaded NvimTree and its decorator API, and the API shape of already-loaded integration modules. It does not force-load Telescope, NvimTree, the Telescope integration, or the NvimTree integration. Unloaded optional lazy integrations are informational rather than failures. It does not read or write bookmark storage.

If lazy.nvim has not loaded the plugin yet, load it first:

```vim
:Lazy load global-bookmarks.nvim
:checkhealth global-bookmarks
```

## Tests

```sh
nvim --headless -u tests/minimal_init.lua -i NONE -l tests/bookmarks_spec.lua
```

The standalone tests use plain Neovim/Lua with no external testing framework, and use controlled fake integrations and storage where appropriate.

## License

MIT
