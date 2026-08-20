local M = {}

local current_request = nil
local prefetch_request = nil

local function cancel_prefetch()
  if not prefetch_request then
    return
  end
  local record = prefetch_request
  prefetch_request = nil
  if record.job then
    vim.fn.jobstop(record.job)
  end
  if record.file then
    vim.fn.delete(record.file)
  end
end

function M.is_available()
  local config = require('tts.config').get()
  
  -- API key is optional for custom endpoints
  local api_url = config.openai.api_url or 'https://api.openai.com/v1/audio/speech'
  if api_url:match('api%.openai%.com') then
    if not config.openai.api_key or config.openai.api_key == '' then
      -- Only log error for OpenAI's official API
      vim.schedule(function()
        vim.notify('TTS: OpenAI API key required for api.openai.com', vim.log.levels.ERROR)
      end)
      return false
    end
  end
  
  -- Check if curl is available
  if vim.fn.executable('curl') ~= 1 then
    vim.schedule(function()
      vim.notify('TTS: curl not found (required for OpenAI backend)', vim.log.levels.ERROR)
    end)
    return false
  end
  
  -- Check for at least one audio player
  local players = {'afplay', 'ffplay', 'mpv', 'mplayer', 'cvlc', 'vlc', 'play'}
  for _, player in ipairs(players) do
    if vim.fn.executable(player) == 1 then
      return true
    end
  end
  
  vim.schedule(function()
    vim.notify('TTS: No audio player found. Install ffplay, mpv, or afplay', vim.log.levels.ERROR)
  end)
  return false
end

local function request_config(config, opts)
  local merged = vim.tbl_extend('force', config, {})

  for _, field in ipairs({ 'model', 'voice', 'speed', 'format' }) do
    if opts and opts[field] ~= nil then
      merged[field] = opts[field]
    end
  end

  merged.format = merged.format or 'mp3'

  return merged
end

local function synthesize(text, config, record)
  -- Create temp file for audio
  local temp_file = vim.fn.tempname() .. '.' .. (config.format or 'mp3')
  record.file = temp_file

  -- Build the API request
  local api_url = config.api_url or 'https://api.openai.com/v1/audio/speech'

  -- Build headers
  local headers = {
    ['Content-Type'] = 'application/json',
  }

  -- Only add Authorization if API key is provided
  if config.api_key and config.api_key ~= '' and config.api_key ~= 'dummy' then
    headers['Authorization'] = 'Bearer ' .. config.api_key
  end

  -- Merge with custom headers
  headers = vim.tbl_extend('force', headers, config.headers or {})

  local data = {
    model = config.model or 'tts-1',
    input = text,
    voice = config.voice or 'alloy',
    speed = config.speed or 1.0,
    response_format = config.format or 'mp3',
  }

  -- Build curl command
  local curl_cmd = {'curl', '-s', '-X', 'POST', api_url}

  -- Add headers
  for key, value in pairs(headers) do
    table.insert(curl_cmd, '-H')
    table.insert(curl_cmd, key .. ': ' .. value)
  end

  -- Add data
  table.insert(curl_cmd, '-d')
  table.insert(curl_cmd, vim.fn.json_encode(data))

  -- Output to file
  table.insert(curl_cmd, '-o')
  table.insert(curl_cmd, temp_file)

  -- Add timeout
  if config.timeout then
    table.insert(curl_cmd, '--max-time')
    table.insert(curl_cmd, tostring(config.timeout))
  end

  -- Debug: Log the curl command for troubleshooting
  -- vim.notify('Debug curl: ' .. table.concat(curl_cmd, ' '), vim.log.levels.DEBUG)

  -- Make the API request
  local stderr_data = {}
  local stdout_data = {}
  local request_job = vim.fn.jobstart(curl_cmd, {
    on_stdout = function(_, data)
      if data and #data > 0 then
        vim.list_extend(stdout_data, data)
      end
    end,
    on_stderr = function(_, data)
      if data and #data > 0 then
        vim.list_extend(stderr_data, data)
      end
    end,
    on_exit = function(_, exit_code)
      if current_request ~= record and prefetch_request ~= record then
        vim.fn.delete(record.file)
        return
      end

      if current_request == record then
        current_request = nil
      elseif prefetch_request == record then
        prefetch_request = nil
      end

      local function fail()
        vim.fn.delete(temp_file)
        if record.on_error then
          record.on_error()
        end
      end

      if exit_code ~= 0 then
        local error_msg = table.concat(stderr_data, '\n')
        local stdout_msg = table.concat(stdout_data, '\n')
        vim.schedule(function()
          if error_msg ~= '' then
            vim.notify('TTS API error: ' .. error_msg, vim.log.levels.ERROR)
          elseif stdout_msg ~= '' then
            vim.notify('TTS API response: ' .. stdout_msg, vim.log.levels.ERROR)
          else
            vim.notify('TTS API failed with exit code: ' .. exit_code, vim.log.levels.ERROR)
          end
        end)
        fail()
        return
      end

      -- Check if file was created and has content
      local file_size = vim.fn.getfsize(temp_file)
      if vim.fn.filereadable(temp_file) ~= 1 or file_size <= 0 then
        vim.schedule(function()
          vim.notify('TTS API returned no audio data', vim.log.levels.ERROR)
        end)
        fail()
        return
      end

      -- Check if response might be JSON error (small file)
      if file_size < 1000 then
        local content = vim.fn.readfile(temp_file)
        local content_str = table.concat(content, '\n')
        if content_str:match('^{') then
          -- Parse and show only actual API errors
          local ok, json = pcall(vim.fn.json_decode, content_str)
          if ok and json.error then
            vim.schedule(function()
              vim.notify('TTS API error: ' .. (json.error.message or json.error), vim.log.levels.ERROR)
            end)
          end
          fail()
          return
        end
      end

      -- Play the audio file
      local cache = require('tts.cache')
      if cache.set(record.key, record.file) and cache.has(record.key, record.format) then
        local cached_path = cache.get_path(record.key, record.format)
        vim.fn.delete(record.file)
        if record.on_ready then
          record.on_ready(cached_path, false)
        end
      else
        if record.on_ready then
          record.on_ready(record.file, true)
        else
          vim.fn.delete(record.file)
        end
      end
    end
  })

  if request_job <= 0 then
    vim.fn.delete(temp_file)
    return nil
  end

  record.job = request_job
  return record
end

local function cache_key(text, config)
  return require('tts.cache').generate_key(text, {
    backend = 'openai',
    api_url = config.api_url,
    model = config.model,
    voice = config.voice,
    speed = config.speed,
    format = config.format,
  })
end

function M.speak(text, opts)
  opts = opts or {}
  local config = request_config(require('tts.config').get().openai, opts)

  -- Validate input text
  if not text or text == '' or text:match('^%s*$') then
    vim.schedule(function()
      vim.notify('TTS: No text to speak', vim.log.levels.WARN)
    end)
    return nil
  end

  -- Stop any current playback
  M._halt_playback()

  local key = cache_key(text, config)
  local cached = require('tts.cache').get(key, config.format)
  if cached then
    M._play_audio(cached, opts, false)
    return {
      stop = function()
        M.stop()
      end
    }
  end

  -- Adopt an in-flight prefetch of the same text instead of requesting again
  if prefetch_request and prefetch_request.key == key then
    local record = prefetch_request
    prefetch_request = nil
    current_request = record
    record.on_ready = function(file, is_temp)
      M._play_audio(file, opts, is_temp)
    end
    record.on_error = function()
      if opts.on_complete then
        opts.on_complete(1)
      end
    end
    return {
      stop = function()
        M.stop()
      end
    }
  end

  local record = {
    text = text,
    key = key,
    format = config.format,
    on_ready = function(file, is_temp)
      M._play_audio(file, opts, is_temp)
    end,
    on_error = function()
      if opts.on_complete then
        opts.on_complete(1)
      end
    end,
  }
  current_request = record

  local ok = synthesize(text, config, record)
  if not ok then
    if current_request == record then
      current_request = nil
    end
    return nil
  end

  return {
    stop = function()
      M.stop()
    end
  }
end

function M.prefetch(text, opts)
  if not text or text == '' or text:match('^%s*$') then
    return
  end

  local config = require('tts.config').get()
  if not config.cache.enabled or not config.cache.prefetch_next then
    return
  end

  local backend = request_config(config.openai, opts)
  local key = cache_key(text, backend)
  if require('tts.cache').has(key, backend.format) then
    return
  end
  if prefetch_request and prefetch_request.key == key then
    return
  end
  if current_request and current_request.key == key then
    return
  end

  cancel_prefetch()

  local record = {
    text = text,
    key = key,
    format = backend.format,
  }
  prefetch_request = record

  local ok = synthesize(text, backend, record)
  if not ok and prefetch_request == record then
    prefetch_request = nil
  end
end

function M._play_audio(file, opts, is_temp)
  opts = opts or {}

  if not file or vim.fn.filereadable(file) ~= 1 then
    if opts.on_complete then
      opts.on_complete(1)
    end
    return
  end

  local player = require('tts.player')
  local handle = player.play(file, vim.tbl_extend('force', opts, {
    on_complete = function(code)
      if is_temp then
        vim.defer_fn(function()
          vim.fn.delete(file)
        end, 100)
      end

      vim.api.nvim_exec_autocmds('User', {
        pattern = 'TTSPlayEnd',
        data = { backend = 'openai' }
      })

      if opts.on_complete then
        opts.on_complete(code)
      end
    end
  }))

  if not handle then
    if is_temp then
      vim.fn.delete(file)
    end
    if opts.on_complete then
      opts.on_complete(1)
    end
  end
end

function M._halt_playback()
  if current_request then
    local record = current_request
    current_request = nil
    if record.job then
      vim.fn.jobstop(record.job)
    end
    if record.file then
      vim.fn.delete(record.file)
    end
  end

  local player = require('tts.player')
  player.stop()
end

function M.stop(opts)
  M._halt_playback()
  if not (opts and opts.keep_prefetch) then
    cancel_prefetch()
  end
end



function M.list_voices()
  return {
    { name = 'alloy', language = 'en', note = 'Neutral and balanced' },
    { name = 'echo', language = 'en', note = 'Warm and engaging' },
    { name = 'fable', language = 'en', note = 'Expressive British accent' },
    { name = 'onyx', language = 'en', note = 'Deep and authoritative' },
    { name = 'nova', language = 'en', note = 'Friendly and upbeat' },
    { name = 'shimmer', language = 'en', note = 'Soft and gentle' },
  }
end

return M
