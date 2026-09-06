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

local function is_valid_state(candidate)
  if type(candidate) ~= "table" then
    return false
  end

  local length = 0
  for index, bookmark_path in pairs(candidate) do
    if type(index) ~= "number" or index < 1 or index % 1 ~= 0 then
      return false
    end

    if type(bookmark_path) ~= "string" or bookmark_path == "" then
      return false
    end

    length = length + 1
  end

  for index = 1, length do
    if candidate[index] == nil then
      return false
    end
  end

  return true
end

local function write_file(path, data)
  local fd, open_err = uv.fs_open(path, "w", 420)
  if not fd then
    return nil, "failed to open bookmarks file: " .. tostring(open_err)
  end

  local offset = 0
  local data_length = #data
  while offset < data_length do
    local written = uv.fs_write(fd, data:sub(offset + 1), offset)
    if type(written) ~= "number" or written <= 0 then
      uv.fs_close(fd)
      return nil, "failed to write bookmarks file"
    end

    offset = offset + written
  end

  uv.fs_close(fd)
  return true
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
  if ok and is_valid_state(decoded) then
    state = decoded
  else
    state = {}
  end

  return state
end

local function save(candidate)
  return write_file(bookmarks_file, vim.json.encode(candidate))
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
      local candidate = vim.deepcopy(bookmarks)
      table.remove(candidate, index)
      local ok, err = save(candidate)
      if not ok then
        return nil, nil, err
      end

      state = candidate
      return "removed", normalized_path
    end
  end

  local candidate = vim.deepcopy(bookmarks)
  table.insert(candidate, normalized_path)
  local ok, err = save(candidate)
  if not ok then
    return nil, nil, err
  end

  state = candidate
  return "added", normalized_path
end

return M
