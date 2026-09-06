local function test(name, fn)
  local ok, err = xpcall(fn, debug.traceback)
  if not ok then error(name .. "\n" .. err, 0) end
end

local real_vim = vim
local repo_root = real_vim.fn.getcwd()

local function repo_file(path)
  return repo_root .. "/" .. path
end
local module_names = {
  "global-bookmarks", "global-bookmarks.core",
  "global-bookmarks.integrations.telescope",
  "global-bookmarks.integrations.nvim-tree", "telescope.pickers",
  "telescope.finders", "telescope.config", "telescope.actions",
  "telescope.actions.state", "nvim-tree.api",
}
local saved_loaded, saved_preload = {}, {}
for _, name in ipairs(module_names) do
  saved_loaded[name], saved_preload[name] = package.loaded[name], package.preload[name]
end

local files, realpaths, descriptors = {}, {}, {}
local counters = { successful_opens = 0, closes = 0, read_attempts = 0 }
local next_fd, fstat_fails = 0, false
local fake = {}

local function reset_io()
  files, realpaths, descriptors = {}, {}, {}
  counters.successful_opens, counters.closes, counters.read_attempts = 0, 0, 0
  next_fd, fstat_fails = 0, false
end

local function fs_open(path, flags)
  if flags == "r" then counters.read_attempts = counters.read_attempts + 1 end
  if flags == "r" and files[path] == nil then return nil end
  next_fd = next_fd + 1; descriptors[next_fd] = { path = path, flags = flags }
  counters.successful_opens = counters.successful_opens + 1; return next_fd
end
local uv = {
  fs_open = fs_open,
  fs_close = function(fd) if descriptors[fd] then descriptors[fd] = nil; counters.closes = counters.closes + 1 end end,
  fs_read = function(fd, size, offset) local d = descriptors[fd]; return d and files[d.path]:sub(offset + 1, offset + size) end,
  fs_write = function(fd, data) local d = descriptors[fd]; files[d.path] = data; return #data end,
  fs_fstat = function(fd) if fstat_fails then return nil end; local d = descriptors[fd]; return d and { size = #(files[d.path] or "") } end,
  fs_realpath = function(path) return realpaths[path] end,
}

fake.vim = fake; setmetatable(fake, { __index = _G })
fake.fn = { stdpath = function() return "/real/user/data" end, fnamemodify = function(p) return "/fallback/" .. p:gsub("^/", "") end, fnameescape = function(p) return p end }
fake.json, fake.uv, fake.loop = real_vim.json, uv, uv
fake.deepcopy = real_vim.deepcopy
fake.schedule, fake.wait = function(fn) fn() end, function() return true end
fake.notify, fake.log = function() end, { levels = { INFO = 1, WARN = 2 } }
fake.cmd = function(command)
  fake.last_cmd = command
end
fake.api = { nvim_get_current_win = function() return 1 end, nvim_get_current_buf = function() return 1 end, nvim_buf_get_name = function() return "/test/current.php" end, nvim_win_is_valid = function() return true end, nvim_set_current_win = function() end, nvim_win_set_buf = function() end }

local storage_path = "/real/user/data/global-bookmarks.json"
local function json(v) return real_vim.json.encode(v) end
local function clear_modules() for _, n in ipairs(module_names) do package.loaded[n], package.preload[n] = nil, nil end end
local function load_core()
  local chunk = assert(loadfile(repo_file("lua/global-bookmarks/core.lua"))); setfenv(chunk, fake); return chunk()
end
local function load_with_fake_vim(path)
  local chunk = assert(loadfile(path))
  setfenv(chunk, fake)
  return chunk()
end
local function with_fake_vim(fn)
  local ok, err = xpcall(fn, debug.traceback)
  if not ok then
    error(err, 0)
  end
end
local function public(c)
  clear_modules()
  package.loaded["global-bookmarks.core"] = c
  return load_with_fake_vim(repo_file("lua/global-bookmarks/init.lua"))
end

test("core lazy loading and cached missing state", function()
  reset_io(); local c = load_core(); assert(counters.read_attempts == 0); assert(#c.list() == 0 and counters.read_attempts == 1); files[storage_path] = json({ "/changed" }); assert(#c.list() == 0 and counters.read_attempts == 1); assert(counters.successful_opens == counters.closes)
end)
test("core fstat failure closes opened descriptor", function()
  reset_io(); files[storage_path] = json({ "/x" }); fstat_fails = true; local c = load_core(); assert(#c.list() == 0 and counters.successful_opens == 1 and counters.closes == 1)
end)
test("core invalid JSON is not rewritten", function()
  reset_io(); files[storage_path] = "malformed"; local c = load_core(); assert(#c.list() == 0 and files[storage_path] == "malformed"); assert(counters.successful_opens == counters.closes)
end)
test("core sorting and independent copies", function()
  reset_io(); files[storage_path] = json({ "/Z", "/a", "/B", "/c" }); local c = load_core(); local first = c.list(); assert(first[1] == "/a" and first[2] == "/B" and first[3] == "/c" and first[4] == "/Z"); first[1] = "/mutated"; assert(c.list()[1] == "/a")
end)
test("core invalid toggles do not write", function()
  reset_io(); local c = load_core(); local action, path = c.toggle(nil); assert(action == nil and path == nil); action, path = c.toggle(""); assert(action == nil and path == nil); assert(c.is_bookmarked(nil) == false and c.is_bookmarked("") == false); assert(counters.successful_opens == 0 and counters.closes == 0)
end)
test("core realpath add remove and fallback", function()
  reset_io(); realpaths.input = "/canonical/input"; local c = load_core(); local a, p = c.toggle("input"); assert(a == "added" and p == "/canonical/input" and files[storage_path]:find("/canonical/input", 1, true)); assert(c.is_bookmarked("input")); a, p = c.toggle("input"); assert(a == "removed" and p == "/canonical/input" and not files[storage_path]:find("/canonical/input", 1, true)); reset_io(); c = load_core(); a, p = c.toggle("fallback.php"); assert(a == "added" and p == "/fallback/fallback.php"); assert(counters.successful_opens == counters.closes)
end)

test("public API delegates and isolates notifications", function()
  with_fake_vim(function()
    local calls, notes, result = {}, {}, {}; local c = { list = function() calls.list = true; return result end, is_bookmarked = function(p) calls.path = p; return "result" end, toggle = function(p) calls.toggle = p; return calls.action, p end }; local old = fake.notify; fake.notify = function(...) notes[#notes + 1] = {...} end; local M = public(c); assert(M.list() == result and calls.list); assert(M.is_bookmarked("exact") == "result" and calls.path == "exact"); local a, p = M.toggle(); assert(a == nil and p == nil and notes[#notes][1] == "Path not found" and notes[#notes][2] == fake.log.levels.WARN and notes[#notes][3].title == "global-bookmarks"); calls.action = "added"; a, p = M.toggle("/test/file.php"); assert(a == "added" and p == "/test/file.php" and notes[#notes][1] == "Added bookmark: /test/file.php" and notes[#notes][2] == fake.log.levels.INFO and notes[#notes][3].title == "global-bookmarks"); calls.action = "removed"; a, p = M.toggle("/test/file.php"); assert(a == "removed" and notes[#notes][1] == "Removed bookmark: /test/file.php" and notes[#notes][2] == fake.log.levels.INFO); fake.notify = old
  end)
end)
test("public current file delegates exact buffer name", function() with_fake_vim(function() local got; local M = public({ list = function() return {} end, is_bookmarked = function() return false end, toggle = function(p) got = p; return "added", p end }); M.toggle_current_file(); assert(got == "/test/current.php") end) end)

local function telescope_deps(state)
  local loaded = {}; local function provide(n, v) package.preload[n] = function() loaded[n] = true; return v end end
  provide("telescope.pickers", { new = function(_, o) state.opts = o; return { find = function(self) state.picker = self end } end }); provide("telescope.finders", { new_table = function(o) state.finder = o.results; return o end }); provide("telescope.config", { values = { generic_sorter = function() state.sorter = true; return "sorter" end, file_previewer = function() state.previewer = true; return "previewer" end } }); provide("telescope.actions", { close = function() state.closed = (state.closed or 0) + 1 end }); provide("telescope.actions.state", { get_selected_entry = function() return { state.selected } end }); return loaded
end
test("telescope is lazy and handles empty list", function() with_fake_vim(function()
  clear_modules()
  local dependency_state = {}
  local loaded = telescope_deps(dependency_state)
  local listed = false
  package.loaded["global-bookmarks"] = { list = function() listed = true; return {} end }
  local lazy_module = require("global-bookmarks.integrations.telescope")
  assert(lazy_module and not listed)
  for _, n in ipairs({"telescope.pickers", "telescope.finders", "telescope.config", "telescope.actions", "telescope.actions.state"}) do assert(not loaded[n]) end
  package.loaded["global-bookmarks.integrations.telescope"] = nil
  local M = load_with_fake_vim(repo_file("lua/global-bookmarks/integrations/telescope.lua"))
  local notes, old = {}, fake.notify
  fake.notify = function(...) notes[#notes + 1] = {...} end
  listed = false
  M.open()
  assert(listed and #notes == 1 and notes[1][1] == "No global bookmarks" and notes[1][2] == fake.log.levels.INFO and notes[1][3].title == "global-bookmarks")
  for _, n in ipairs({"telescope.pickers", "telescope.finders", "telescope.config", "telescope.actions", "telescope.actions.state"}) do assert(not loaded[n]) end
  fake.notify = old
end) end)
test("telescope picker construction and delete reopen", function() with_fake_vim(function() clear_modules(); local state = { selected = "/test/file.php" }; local loaded = telescope_deps(state); local deleted, refreshes = false, 0; package.loaded["global-bookmarks"] = { list = function() return deleted and {} or { state.selected } end, toggle = function(p) assert(p == state.selected); deleted = true; return "removed", p end }; package.preload["global-bookmarks.integrations.nvim-tree"] = function() return { refresh = function() refreshes = refreshes + 1 end } end; local notes, old = {}, fake.notify; fake.notify = function(...) notes[#notes + 1] = {...} end; local M = load_with_fake_vim(repo_file("lua/global-bookmarks/integrations/telescope.lua")); M.open(); assert(state.opts.prompt_title == "Global Bookmarks" and state.finder[1] == state.selected and state.sorter and state.previewer and state.picker); local maps = {}; local map = function(mode, key, fn) maps[mode .. key] = fn end; assert(state.opts.attach_mappings(1, map) == true); for _, k in ipairs({"i<CR>", "n<CR>", "i<C-o>", "n<C-o>", "i<C-d>", "ndd"}) do assert(maps[k]) end; maps["i<C-d>"](); fake.wait(10); assert(refreshes == 1 and notes[#notes][1] == "No global bookmarks"); fake.notify = old end) end)
test("telescope CR and C-o behavior", function() with_fake_vim(function()
  clear_modules(); local state = { selected = "/test/file.php" }; telescope_deps(state)
  package.loaded["global-bookmarks"] = { list = function() return { state.selected } end }
  local revealed = 0
  package.preload["global-bookmarks.integrations.nvim-tree"] = function() return { reveal_current_file = function() revealed = revealed + 1 end } end
  local M = load_with_fake_vim(repo_file("lua/global-bookmarks/integrations/telescope.lua")); local maps = {}
  local map = function(mode, key, fn) maps[mode .. key] = fn end
  local function run(key, should_reveal)
    M.open(); state.opts.attach_mappings(1, map); fake.last_cmd = nil; local before_reveals = revealed; state.closed = 0; maps[key](); assert(state.closed == 1 and fake.last_cmd == "edit /test/file.php" and revealed == before_reveals + (should_reveal and 1 or 0)); maps = {}
  end
  run("i<CR>", true); run("n<CR>", true); run("i<C-o>", false); run("n<C-o>", false)
end) end)

test("nvim-tree lazy loading refresh toggle reveal and decorator contract", function() with_fake_vim(function()
  local api
  clear_modules(); local loader, reloads, visible, toggled, lookups = 0, 0, false, nil, 0; local node = { absolute_path = "/test/node.php" }; api = { tree = { is_visible = function() return visible end, reload = function() reloads = reloads + 1 end, get_node_under_cursor = function() return node end, find_file = function(o) api.find_opts = o end } }; package.preload["nvim-tree.api"] = function() loader = loader + 1; return api end; package.loaded["global-bookmarks"] = { is_bookmarked = function(p) lookups = lookups + 1; return p == node.absolute_path end, toggle = function(p) toggled = p; return "added", p end }; local M = require("global-bookmarks.integrations.nvim-tree"); assert(loader == 0); package.loaded["nvim-tree.api"] = nil; assert(M.refresh() == false and loader == 0); package.loaded["nvim-tree.api"] = api; assert(M.refresh() == false); visible = true; assert(M.refresh() == true and reloads == 1); local a, p = M.toggle_node(); assert(a == "added" and p == node.absolute_path and toggled == node.absolute_path and reloads == 2); for _, bad in ipairs({ {}, { absolute_path = "" } }) do api.tree.get_node_under_cursor = function() return bad end; a, p = M.toggle_node(); assert(a == nil and p == nil and toggled == node.absolute_path) end; api.tree.get_node_under_cursor = function() return nil end; a, p = M.toggle_node(); assert(a == nil and p == nil); assert(M.reveal_current_file() and api.find_opts.open and api.find_opts.focus == false and api.find_opts.update_root and not api.marks)
  api.Decorator = {}
  function api.Decorator:extend()
    local parent = self
    local class = {}
    class.__index = class
    setmetatable(class, { __index = parent, __call = function(cls, ...)
      local instance = setmetatable({}, cls)
      if instance.new then instance:new(...) end
      return instance
    end })
    return class
  end
  local D = M.decorator(); local one = D(); assert(one.enabled and one.highlight_range == "all" and one.icon_placement == "after"); local icons = one:icons(node); assert(icons[1].str == " " and icons[1].hl[1] == "GlobalBookmarksNvimTreeIcon" and one:highlight_group(node) == "GlobalBookmarksNvimTreeHL"); local before = lookups; one:icons(node); one:highlight_group(node); assert(lookups == before); local unmarked = { absolute_path = "/none" }; local before_unmarked = lookups; assert(one:icons(unmarked) == nil); assert(lookups == before_unmarked + 1); assert(one:highlight_group(unmarked) == nil and one:icons(unmarked) == nil and lookups == before_unmarked + 1); local before_invalid = lookups; assert(one:icons(nil) == nil and one:highlight_group({ absolute_path = "" }) == nil and lookups == before_invalid); local before_second = lookups; local two = D(); two:icons(node); assert(lookups == before_second + 1)
end) end)

local function isolated_nvim_tree_test(fn)
  local loaded, preload = {}, {}
  for _, n in ipairs(module_names) do
    loaded[n], preload[n] = package.loaded[n], package.preload[n]
  end
  local old_vim, old_api, old_fn, old_keymap = _G.vim, fake.api, fake.fn, fake.keymap
  clear_modules()
  _G.vim = fake
  local ok, err = xpcall(fn, debug.traceback)
  _G.vim, fake.api, fake.fn, fake.keymap = old_vim, old_api, old_fn, old_keymap
  for _, n in ipairs(module_names) do
    package.loaded[n], package.preload[n] = loaded[n], preload[n]
  end
  if not ok then error(err, 0) end
end

test("nvim-tree attach, mappings, highlights, and cache invalidation are standalone", function()
  isolated_nvim_tree_test(function()
    local maps, highlights, valid_checks, buf_calls, hasmapto_calls, maparg_calls = {}, {}, {}, {}, 0, 0
    local active_buffer, api_loads, lookups, reloads, visible = nil, 0, 0, 0, false
    local remapped, occupied = {}, {}
    local tree_api
    tree_api = {
      tree = {
        is_visible = function() return visible end,
        reload = function() reloads = reloads + 1 end,
        find_file = function(opts) tree_api.find_opts = opts end,
      },
      Decorator = {},
    }
    function tree_api.Decorator:extend()
      local parent, class = self, {}
      class.__index = class
      setmetatable(class, { __index = parent, __call = function(cls, ...)
        local instance = setmetatable({}, cls)
        if instance.new then instance:new(...) end
        return instance
      end })
      return class
    end
    fake.api = {
      nvim_buf_is_valid = function(bufnr) valid_checks[#valid_checks + 1] = bufnr; return bufnr == 42 end,
      nvim_buf_call = function(bufnr, callback)
        buf_calls[#buf_calls + 1] = bufnr
        local previous = active_buffer; active_buffer = bufnr; callback(); active_buffer = previous
      end,
      nvim_set_hl = function(namespace, name, opts)
        highlights[#highlights + 1] = { namespace = namespace, name = name, opts = opts }
      end,
    }
    fake.keymap = { set = function(mode, lhs, rhs, opts)
      maps[#maps + 1] = { mode = mode, lhs = lhs, rhs = rhs, opts = opts }
    end }
    fake.fn = {
      hasmapto = function(target, mode)
        hasmapto_calls = hasmapto_calls + 1
        assert(active_buffer == 42 and mode == "n")
        return remapped[target] or 0
      end,
      maparg = function(lhs, mode)
        maparg_calls = maparg_calls + 1
        assert(active_buffer == 42 and mode == "n")
        return occupied[lhs] or ""
      end,
    }
    package.preload["nvim-tree.api"] = function() api_loads = api_loads + 1; return tree_api end
    package.loaded["global-bookmarks"] = {
      is_bookmarked = function(path) lookups = lookups + 1; return path == "/marked" end,
    }

    local M = load_with_fake_vim(repo_file("lua/global-bookmarks/integrations/nvim-tree.lua"))
    assert(api_loads == 0)
    local before_valid, before_calls, before_maps = #valid_checks, #buf_calls, #maps
    assert(M.attach(nil) == false)
    assert(#valid_checks == before_valid and #buf_calls == before_calls and #maps == before_maps)
    for _, value in ipairs({ false, "1", {} }) do
      before_valid, before_calls, before_maps = #valid_checks, #buf_calls, #maps
      assert(M.attach(value) == false)
      assert(#valid_checks == before_valid and #buf_calls == before_calls and #maps == before_maps)
    end
    assert(M.attach(99) == false and valid_checks[#valid_checks] == 99 and #maps == 0)

    assert(M.attach(42) == true and api_loads == 0)
    assert(#buf_calls == 1 and buf_calls[1] == 42)
    local by_lhs = {}
    for _, map in ipairs(maps) do by_lhs[map.lhs] = map end
    local function assert_map(lhs, rhs, desc)
      local map = assert(by_lhs[lhs])
      assert(map.mode == "n" and map.rhs == rhs)
      assert(map.opts.buffer == 42 and map.opts.silent == true and map.opts.nowait == true and map.opts.desc == desc)
    end
    assert_map("<Plug>(GlobalBookmarksNvimTreeToggle)", M.toggle_node, "nvim-tree: Toggle Global Bookmark")
    assert_map("<Plug>(GlobalBookmarksNvimTreeOpen)", "<Cmd>GlobalBookmarks<CR>", "nvim-tree: Open Global Bookmarks")
    assert_map("gm", "<Plug>(GlobalBookmarksNvimTreeToggle)", "nvim-tree: Toggle Global Bookmark")
    assert_map("gb", "<Plug>(GlobalBookmarksNvimTreeOpen)", "nvim-tree: Open Global Bookmarks")

    local function attach_with(remap, existing)
      maps, remapped, occupied = {}, remap, existing
      hasmapto_calls, maparg_calls = 0, 0
      assert(M.attach(42) == true)
      local result = {}; for _, map in ipairs(maps) do result[map.lhs] = map end
      assert(result["<Plug>(GlobalBookmarksNvimTreeToggle)"] and result["<Plug>(GlobalBookmarksNvimTreeOpen)"])
      return result
    end
    local result = attach_with({ ["<Plug>(GlobalBookmarksNvimTreeToggle)"] = 1 }, {})
    assert(result.gm == nil and result.gb and hasmapto_calls == 2 and maparg_calls == 1)
    result = attach_with({ ["<Plug>(GlobalBookmarksNvimTreeOpen)"] = 1 }, {})
    assert(result.gm and result.gb == nil and hasmapto_calls == 2 and maparg_calls == 1)
    result = attach_with({}, { gm = "existing-gm" })
    assert(result.gm == nil and result.gb)
    result = attach_with({}, { gb = "existing-gb" })
    assert(result.gm and result.gb == nil)

    local D = M.decorator()
    assert(#highlights == 2)
    local expected_highlights = { GlobalBookmarksNvimTreeHL = true, GlobalBookmarksNvimTreeIcon = true }
    for _, highlight in ipairs(highlights) do
      assert(expected_highlights[highlight.name] and highlight.namespace == 0)
      local opts, count = highlight.opts, 0; for _ in pairs(opts) do count = count + 1 end
      assert(count == 3 and opts.fg == "#fb4934" and opts.bold == true and opts.default == true)
    end
    local recorded_highlights = {}
    for _, highlight in ipairs(highlights) do recorded_highlights[highlight.name] = true end
    assert(recorded_highlights.GlobalBookmarksNvimTreeHL and recorded_highlights.GlobalBookmarksNvimTreeIcon)
    assert(not recorded_highlights.NvimTreeBookmarkHL and not recorded_highlights.NvimTreeBookmarkIcon)
    local decorator, marked, unmarked = D(), { absolute_path = "/marked" }, { absolute_path = "/unmarked" }
    assert(decorator.enabled == true and decorator.highlight_range == "all" and decorator.icon_placement == "after")
    assert(decorator:icons(marked)[1].str == " " and decorator:icons(marked)[1].hl[1] == "GlobalBookmarksNvimTreeIcon")
    assert(decorator:highlight_group(marked) == "GlobalBookmarksNvimTreeHL" and lookups == 1)
    assert(decorator:icons(unmarked) == nil and decorator:highlight_group(unmarked) == nil and lookups == 2)
    assert(decorator:icons(unmarked) == nil and lookups == 2)
    local before_invalid = lookups
    assert(decorator:icons(nil) == nil and decorator:highlight_group({}) == nil and decorator:icons({ absolute_path = "" }) == nil and lookups == before_invalid)

    package.loaded["nvim-tree.api"] = nil
    assert(M.refresh() == false and api_loads == 1)
    decorator:icons(marked); assert(lookups == 3)
    package.loaded["nvim-tree.api"] = tree_api
    visible = false; assert(M.refresh() == false and reloads == 0)
    decorator:icons(marked); assert(lookups == 4)
    visible = true; assert(M.refresh() == true and reloads == 1)
    decorator:icons(marked); assert(lookups == 5)

    assert(M.reveal_current_file() == true)
    local find_opts, count = tree_api.find_opts, 0; for _ in pairs(find_opts) do count = count + 1 end
    assert(count == 3 and find_opts.open == true and find_opts.focus == false and find_opts.update_root == true)
  end)
end)

local function isolated_plugin_test(fn)
  local loaded, preload = {}, {}
  for _, n in ipairs(module_names) do
    loaded[n], preload[n] = package.loaded[n], package.preload[n]
  end
  local old_g, old_api, old_fn, old_keymap = fake.g, fake.api, fake.fn, fake.keymap
  clear_modules()
  for _, n in ipairs(module_names) do
    local name = n
    package.preload[name] = function() error("Unexpected require: " .. name) end
  end
  local ok, err = xpcall(fn, debug.traceback)
  fake.g, fake.api, fake.fn, fake.keymap = old_g, old_api, old_fn, old_keymap
  for _, n in ipairs(module_names) do
    package.loaded[n], package.preload[n] = loaded[n], preload[n]
  end
  if not ok then error(err, 0) end
end

test("public open lazily delegates and returns the integration result", function()
  isolated_plugin_test(function()
    local loads, calls, sentinel = 0, 0, {}
    local integration = { open = function() calls = calls + 1; return sentinel end }
    package.loaded["global-bookmarks.core"] = {}
    package.preload["global-bookmarks"] = function()
      return load_with_fake_vim(repo_file("lua/global-bookmarks/init.lua"))
    end
    package.preload["global-bookmarks.integrations.telescope"] = function()
      loads = loads + 1
      return integration
    end
    local M = require("global-bookmarks")
    assert(type(M.open) == "function" and loads == 0 and calls == 0)
    assert(package.loaded["global-bookmarks.integrations.telescope"] == nil)
    assert(require("global-bookmarks").open() == sentinel)
    assert(loads == 1 and calls == 1)
    assert(package.loaded["global-bookmarks.integrations.telescope"] == integration)
  end)
end)

local function plugin_commands()
  local commands, registrations = {}, 0
  fake.g = {}
  fake.api = { nvim_create_user_command = function(name, callback, opts)
    registrations = registrations + 1
    assert(commands[name] == nil)
    assert(type(callback) == "function" and type(opts) == "table")
    commands[name] = callback
  end }
  assert(fake.g.loaded_global_bookmarks == nil)
  load_with_fake_vim(repo_file("plugin/global-bookmarks.lua"))
  assert(fake.g.loaded_global_bookmarks == true and registrations == 2)
  assert(commands.GlobalBookmarks and commands.GlobalBookmarkToggle)
  return commands, function() return registrations end
end

test("real plugin registers exactly two commands and respects its loaded guard", function()
  isolated_plugin_test(function()
    local commands, count = plugin_commands()
    load_with_fake_vim(repo_file("plugin/global-bookmarks.lua"))
    assert(count() == 2)
    local names = 0
    for name in pairs(commands) do
      assert(name == "GlobalBookmarks" or name == "GlobalBookmarkToggle")
      names = names + 1
    end
    assert(names == 2)
    fake.g.loaded_global_bookmarks = nil
  end)
end)

test("GlobalBookmarks command uses only the public open API", function()
  isolated_plugin_test(function()
    local commands = plugin_commands()
    local calls = 0
    package.loaded["global-bookmarks"] = { open = function() calls = calls + 1 end }
    commands.GlobalBookmarks()
    assert(calls == 1)
    assert(package.loaded["global-bookmarks.integrations.telescope"] == nil)
  end)
end)

test("GlobalBookmarkToggle refreshes only after a successful public toggle", function()
  isolated_plugin_test(function()
    local commands = plugin_commands()
    local calls, loads, refreshes, returned = 0, 0, 0, false
    package.loaded["global-bookmarks"] = { toggle_current_file = function()
      calls = calls + 1
      assert(loads == 0 and refreshes == 0)
      assert(package.loaded["global-bookmarks.integrations.nvim-tree"] == nil)
      returned = true
      return "added", "/test/current.php"
    end }
    package.preload["global-bookmarks.integrations.nvim-tree"] = function()
      assert(returned and calls == 1)
      loads = loads + 1
      return { refresh = function() refreshes = refreshes + 1 end }
    end
    commands.GlobalBookmarkToggle()
    assert(calls == 1 and loads == 1 and refreshes == 1)
  end)
end)

test("GlobalBookmarkToggle does not load or refresh an integration without an action", function()
  isolated_plugin_test(function()
    local commands = plugin_commands()
    local calls, loads, refreshes = 0, 0, 0
    package.loaded["global-bookmarks"] = { toggle_current_file = function()
      calls = calls + 1
      return nil, nil
    end }
    package.preload["global-bookmarks.integrations.nvim-tree"] = function()
      loads = loads + 1
      return { refresh = function() refreshes = refreshes + 1 end }
    end
    commands.GlobalBookmarkToggle()
    assert(calls == 1 and loads == 0 and refreshes == 0)
    assert(package.loaded["global-bookmarks.integrations.nvim-tree"] == nil)
  end)
end)

local function lazy_scenario(remapped, occupied, expect_open, expect_toggle)
  isolated_plugin_test(function()
    local maps, autocmds, hasmapto_calls, maparg_calls = {}, {}, {}, {}
    fake.keymap = { set = function(mode, lhs, rhs, opts)
      maps[#maps + 1] = { mode = mode, lhs = lhs, rhs = rhs, opts = opts }
    end }
    fake.api = { nvim_create_autocmd = function(event, opts)
      autocmds[#autocmds + 1] = { event = event, opts = opts }
    end }
    fake.fn = {
      hasmapto = function(...)
        local args = { ... }; hasmapto_calls[#hasmapto_calls + 1] = args
        return remapped[args[1]] or 0
      end,
      maparg = function(...)
        local args = { ... }; maparg_calls[#maparg_calls + 1] = args
        return occupied[args[1]] or ""
      end,
    }
    local package_specs = load_with_fake_vim(repo_file("lazy.lua"))
    assert(type(package_specs) == "table" and #package_specs == 1)
    for key in pairs(package_specs) do assert(key == 1) end
    local spec = package_specs[1]
    assert(type(spec) == "table" and spec[1] == "Oleg4cy/global-bookmarks.nvim")
    assert(type(spec.cmd) == "table" and #spec.cmd == 2)
    for key in pairs(spec.cmd) do assert(key == 1 or key == 2) end
    assert(spec.cmd[1] == "GlobalBookmarks" and spec.cmd[2] == "GlobalBookmarkToggle")
    assert(type(spec.init) == "function")
    spec.init()
    local function assert_mapping(mapping, lhs, rhs, desc)
      assert(mapping and mapping.mode == "n" and mapping.lhs == lhs and mapping.rhs == rhs)
      assert(mapping.opts.silent == true and mapping.opts.desc == desc)
    end
    assert(#maps == 2)
    assert_mapping(maps[1], "<Plug>(GlobalBookmarksOpen)", "<Cmd>GlobalBookmarks<CR>", "Global Bookmarks: Open")
    assert_mapping(maps[2], "<Plug>(GlobalBookmarksToggleCurrent)", "<Cmd>GlobalBookmarkToggle<CR>", "Global Bookmarks: Toggle current file")
    assert(#hasmapto_calls == 0 and #maparg_calls == 0)
    assert(#autocmds == 1 and autocmds[1].event == "VimEnter")
    assert(autocmds[1].opts.once == true and type(autocmds[1].opts.callback) == "function")
    local function assert_unloaded()
      for _, name in ipairs({ "global-bookmarks", "global-bookmarks.core", "global-bookmarks.integrations.telescope", "global-bookmarks.integrations.nvim-tree" }) do
        assert(package.loaded[name] == nil)
      end
    end
    assert_unloaded()
    autocmds[1].opts.callback()
    assert_unloaded()
    local defaults = {}
    for i = 3, #maps do
      local mapping = maps[i]
      assert(defaults[mapping.lhs] == nil)
      defaults[mapping.lhs] = mapping
    end
    assert(#maps == 2 + (expect_open and 1 or 0) + (expect_toggle and 1 or 0))
    if expect_open then
      assert_mapping(defaults["<leader>m"], "<leader>m", "<Plug>(GlobalBookmarksOpen)", "Global Bookmarks: Open")
    else
      assert(defaults["<leader>m"] == nil)
    end
    if expect_toggle then
      assert_mapping(defaults["<leader>M"], "<leader>M", "<Plug>(GlobalBookmarksToggleCurrent)", "Global Bookmarks: Toggle current file")
    else
      assert(defaults["<leader>M"] == nil)
    end
    assert(#hasmapto_calls == 2)
    local targets = { "<Plug>(GlobalBookmarksOpen)", "<Plug>(GlobalBookmarksToggleCurrent)" }
    local lhs_values, maparg_index = { "<leader>m", "<leader>M" }, 0
    for i, target in ipairs(targets) do
      local args = hasmapto_calls[i]
      assert(#args == 2 and args[1] == target and args[2] == "n")
      if (remapped[target] or 0) == 0 then
        maparg_index = maparg_index + 1
        args = maparg_calls[maparg_index]
        assert(args and #args == 2 and args[1] == lhs_values[i] and args[2] == "n")
      end
    end
    assert(#maparg_calls == maparg_index)
  end)
end

test("lazy spec installs stable actions and defers free defaults to VimEnter", function()
  lazy_scenario({}, {}, true, true)
end)
test("lazy Open remapping suppresses only the Open default", function()
  lazy_scenario({ ["<Plug>(GlobalBookmarksOpen)"] = 1 }, {}, false, true)
end)
test("lazy Toggle remapping suppresses only the Toggle default", function()
  lazy_scenario({ ["<Plug>(GlobalBookmarksToggleCurrent)"] = 1 }, {}, true, false)
end)
test("lazy occupied Open lhs preserves the independent Toggle default", function()
  lazy_scenario({}, { ["<leader>m"] = "existing-open" }, false, true)
end)
test("lazy occupied Toggle lhs preserves the independent Open default", function()
  lazy_scenario({}, { ["<leader>M"] = "existing-toggle" }, true, false)
end)

for _, n in ipairs(module_names) do package.loaded[n], package.preload[n] = saved_loaded[n], saved_preload[n] end
print("global-bookmarks tests: OK")
