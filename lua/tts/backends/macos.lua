local M = {}

M.voices = {
  'Alex', 'Samantha', 'Victoria', 'Karen', 
  'Daniel', 'Moira', 'Rishi', 'Tessa'
}

local current_job = nil
local job_token = 0

function M.is_available()
  return vim.fn.has('mac') == 1 and vim.fn.executable('say') == 1
end

function M.speak(text, opts)
  opts = opts or {}
  local config = require('tts.config').get().macos
  
  local args = {}
  
  if opts.voice or config.voice then
    table.insert(args, '-v')
    table.insert(args, opts.voice or config.voice)
  end
  
  if opts.rate or config.rate then
    table.insert(args, '-r')
    table.insert(args, tostring(opts.rate or config.rate))
  end
  
  if opts.output_file then
    table.insert(args, '-o')
    table.insert(args, opts.output_file)
  end
  
  table.insert(args, vim.fn.shellescape(text))
  
  local cmd = 'say ' .. table.concat(args, ' ')
  
  if opts.async ~= false then
    return M._execute_async(cmd, opts)
  else
    return vim.fn.system(cmd)
  end
end

function M._execute_async(cmd, opts)
  opts = opts or {}
  if current_job then
    M.stop()
  end

  local stdout = vim.loop.new_pipe(false)
  local stderr = vim.loop.new_pipe(false)

  job_token = job_token + 1
  local token = job_token

  current_job = vim.loop.spawn('sh', {
    args = { '-c', cmd },
    stdio = { nil, stdout, stderr }
  }, function(code, signal)
    if stdout then
      stdout:close()
    end
    if stderr then
      stderr:close()
    end
    if token ~= job_token then
      return
    end
    if current_job then
      current_job:close()
      current_job = nil
    end

    vim.schedule(function()
      local state = require('tts.state')
      if state then
        state.transition('idle')
      end

      vim.api.nvim_exec_autocmds('User', {
        pattern = 'TTSPlayEnd',
        data = { backend = 'macos' }
      })

      if opts.on_complete then
        opts.on_complete(code)
      end
    end)
  end)

  return {
    stop = function()
      M.stop()
    end
  }
end

function M.stop()
  if current_job and not current_job:is_closing() then
    current_job:kill('sigterm')
    current_job = nil
  end
  
  vim.fn.system('pkill -x say')
end



function M.list_voices()
  local output = vim.fn.system('say -v ?')
  local voices = {}
  
  for line in output:gmatch('[^\n]+') do
    local voice, lang, note = line:match('(%S+)%s+(%S+)%s*(.*)')
    if voice and lang then
      table.insert(voices, {
        name = voice,
        language = lang,
        note = note and note:gsub('%s*#.*', '') or ''
      })
    end
  end
  
  return voices
end

return M