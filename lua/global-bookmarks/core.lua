local uv = vim.uv

local M = {}

local bookmarks_file = vim.fn.stdpath("data") .. "/global-bookmarks.json"
local state = nil

local function normalize(path)
  if path == nil or path == "" then
    return nil
  end

  local realpath = uv.fs_realpath(path)
  if realpath then
    return realpath
  end

  return vim.fn.fnamemodify(path, ":p")
end

local function read_file(path)
  local fd = uv.fs_open(path, "r", 420)
  if not fd then
    return nil
  end

  local stat = uv.fs_fstat(fd)
  if not stat then
    uv.fs_close(fd)
    return nil
  end

  local data = uv.fs_read(fd, stat.size, 0)
  uv.fs_close(fd)
  return data
end

local function write_file(path, data)
  local fd = assert(uv.fs_open(path, "w", 420))
  uv.fs_write(fd, data, 0)
  uv.fs_close(fd)
end

local function load()
  if state ~= nil then
    return state
  end

  local data = read_file(bookmarks_file)
  if not data or data == "" then
    state = {}
    return state
  end

  local ok, decoded = pcall(vim.json.decode, data)
  if ok and type(decoded) == "table" then
    state = decoded
  else
    state = {}
  end

  return state
end

local function save()
  write_file(bookmarks_file, vim.json.encode(load()))
end

local function sort_paths(paths)
  table.sort(paths, function(a, b)
    return a:lower() < b:lower()
  end)
  return paths
end

function M.list()
  return sort_paths(vim.deepcopy(load()))
end

function M.is_bookmarked(path)
  local normalized_path = normalize(path)
  if not normalized_path then
    return false
  end

  for _, bookmarked_path in ipairs(load()) do
    if bookmarked_path == normalized_path then
      return true
    end
  end

  return false
end

function M.toggle(path)
  local normalized_path = normalize(path)
  if not normalized_path then
    return nil, nil
  end

  local bookmarks = load()
  for index, bookmarked_path in ipairs(bookmarks) do
    if bookmarked_path == normalized_path then
      table.remove(bookmarks, index)
      save()
      return "removed", normalized_path
    end
  end

  table.insert(bookmarks, normalized_path)
  save()
  return "added", normalized_path
end

return M
