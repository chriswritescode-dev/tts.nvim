local M = {}
local cache_index = {}
local cache_dir = nil

local function usable(path)
  return vim.fn.filereadable(path) == 1 and vim.fn.getfsize(path) > 0
end

local function cached_files()
  if not cache_dir then
    return {}
  end

  local out = {}
  for _, name in ipairs(vim.fn.readdir(cache_dir)) do
    if name ~= 'index.json' then
      table.insert(out, name)
    end
  end
  return out
end

function M.init()
  local config = require('tts.config').get().cache
  
  if not config.enabled then
    return
  end
  
  cache_dir = config.directory
  
  vim.fn.mkdir(cache_dir, 'p')
  
  M.load_index()
  
  if config.cleanup_on_start then
    M.cleanup()
  end
end

function M.get_path(key, ext)
  if not cache_dir then
    M.init()
  end
  return cache_dir .. '/' .. key .. '.' .. (ext or 'audio')
end

function M.get(key, ext)
  if not cache_dir then
    M.init()
  end
  
  local config = require('tts.config').get().cache
  if not config.enabled then
    return nil
  end
  
  local path = M.get_path(key, ext)
  
  if usable(path) then
    local entry = cache_index[key]
    if entry then
      entry.last_access = os.time()
      entry.hits = (entry.hits or 0) + 1
    else
      cache_index[key] = {
        path = path,
        created = os.time(),
        last_access = os.time(),
        size = vim.fn.getfsize(path),
        hits = 1
      }
    end
    M.save_index()
    return path
  end
  
  return nil
end

function M.has(key, ext)
  if not cache_dir then
    M.init()
  end
  
  local config = require('tts.config').get().cache
  if not config.enabled then
    return false
  end
  
  return usable(M.get_path(key, ext))
end

function M.set(key, file_path)
  if not cache_dir then
    M.init()
  end
  
  local config = require('tts.config').get().cache
  if not config.enabled then
    return false
  end
  
  local ext = file_path:match('%.([%w]+)$')
  local cache_path = M.get_path(key, ext)
  
  if file_path ~= cache_path then
    local copied = vim.loop.fs_copyfile(file_path, cache_path)
    if not copied then
      return false
    end
  end
  
  cache_index[key] = {
    path = cache_path,
    created = os.time(),
    last_access = os.time(),
    size = vim.fn.getfsize(cache_path),
    hits = 0
  }
  
  M.save_index()
  M.check_size()
  
  return true
end

function M.remove(key)
  if cache_index[key] then
    local path = cache_index[key].path
    if vim.fn.filereadable(path) == 1 then
      vim.fn.delete(path)
    end
    cache_index[key] = nil
    M.save_index()
    return true
  end
  return false
end

function M.clear()
  if not cache_dir then
    return
  end
  
  for _, name in ipairs(cached_files()) do
    local path = cache_dir .. '/' .. name
    if vim.fn.filereadable(path) == 1 then
      vim.fn.delete(path)
    end
  end
  
  cache_index = {}
  M.save_index()
  
  vim.notify('TTS cache cleared', vim.log.levels.INFO)
end

function M.cleanup()
  if not cache_dir then
    M.init()
  end
  
  local config = require('tts.config').get().cache
  local max_age_seconds = config.max_age * 24 * 60 * 60
  local current_time = os.time()
  local removed_count = 0
  
  for key, entry in pairs(cache_index) do
    local age = current_time - (entry.created or entry.last_access or 0)
    
    if age > max_age_seconds then
      if vim.fn.filereadable(entry.path) == 1 then
        vim.fn.delete(entry.path)
      end
      cache_index[key] = nil
      removed_count = removed_count + 1
    elseif vim.fn.filereadable(entry.path) ~= 1 then
      cache_index[key] = nil
      removed_count = removed_count + 1
    end
  end
  
  for _, name in ipairs(cached_files()) do
    local path = cache_dir .. '/' .. name
    local indexed = false
    for _, entry in pairs(cache_index) do
      if entry.path == path then
        indexed = true
        break
      end
    end
    
    if not indexed then
      local age = current_time - vim.fn.getftime(path)
      if age > max_age_seconds then
        if vim.fn.filereadable(path) == 1 then
          vim.fn.delete(path)
        end
        removed_count = removed_count + 1
      end
    end
  end
  
  if removed_count > 0 then
    M.save_index()
    vim.notify(string.format('TTS cache: removed %d old entries', removed_count), vim.log.levels.INFO)
  end
end

function M.check_size()
  local config = require('tts.config').get().cache
  local max_size_bytes = config.max_size * 1024 * 1024
  
  local total_size = 0
  local entries = {}
  
  for key, entry in pairs(cache_index) do
    total_size = total_size + (entry.size or 0)
    table.insert(entries, {
      key = key,
      entry = entry,
      score = (entry.last_access or 0) + (entry.hits or 0) * 3600
    })
  end
  
  if total_size <= max_size_bytes then
    return
  end
  
  table.sort(entries, function(a, b)
    return a.score < b.score
  end)
  
  while total_size > max_size_bytes and #entries > 0 do
    local oldest = table.remove(entries, 1)
    total_size = total_size - (oldest.entry.size or 0)
    M.remove(oldest.key)
  end
end

function M.save_index()
  if not cache_dir then
    return
  end
  
  local index_file = cache_dir .. '/index.json'
  local data = vim.fn.json_encode(cache_index)
  
  local file = io.open(index_file, 'w')
  if file then
    file:write(data)
    file:close()
  end
end

function M.load_index()
  if not cache_dir then
    return
  end
  
  local index_file = cache_dir .. '/index.json'
  
  if vim.fn.filereadable(index_file) == 1 then
    local file = io.open(index_file, 'r')
    if file then
      local data = file:read('*all')
      file:close()
      
      local ok, loaded_index = pcall(vim.fn.json_decode, data)
      if ok and type(loaded_index) == 'table' then
        cache_index = loaded_index
      end
    end
  end
end

function M.get_stats()
  local total_size = 0
  local total_files = 0
  local total_hits = 0
  
  for _, entry in pairs(cache_index) do
    total_size = total_size + (entry.size or 0)
    total_files = total_files + 1
    total_hits = total_hits + (entry.hits or 0)
  end
  
  return {
    total_size = total_size,
    total_size_mb = total_size / (1024 * 1024),
    total_files = total_files,
    total_hits = total_hits,
    directory = cache_dir
  }
end

function M.generate_key(text, opts)
  opts = opts or {}
  
  local key_parts = {
    text,
    tostring(opts.backend or 'default'),
    tostring(opts.api_url or 'default'),
    tostring(opts.model or 'default'),
    tostring(opts.voice or 'default'),
    tostring(opts.speed or 'default'),
    tostring(opts.format or 'default'),
    tostring(opts.rate or 'default')
  }
  
  local key_string = table.concat(key_parts, '|')
  
  return vim.fn.sha256(key_string)
end

return M