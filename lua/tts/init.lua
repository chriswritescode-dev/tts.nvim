local M = {}

M.version = "1.0.0"

local initialized = false

function M.setup(opts)
  if initialized then
    return
  end

  local config = require('tts.config')
  config.setup(opts)

  local backends = require('tts.backends')
  backends.init()

  local cache = require('tts.cache')
  cache.init()

  M._setup_commands()
  M._setup_keymaps()

  initialized = true
end

function M._setup_commands()
  vim.api.nvim_create_user_command('TTS', function(cmd)
    if cmd.args and cmd.args ~= '' then
      M.play(cmd.args)
    elseif cmd.range and cmd.range > 0 then
      M.play_range(cmd.line1, cmd.line2)
    else
      M.play_selection()
    end
  end, { nargs = '*', range = true })
  
  vim.api.nvim_create_user_command('TTSPlay', function(cmd)
    if cmd.range and cmd.range > 0 then
      M.play_range(cmd.line1, cmd.line2)
    else
      M.play_selection()
    end
  end, { range = true })
  
  vim.api.nvim_create_user_command('TTSStop', function()
    M.stop()
  end, {})
  
  vim.api.nvim_create_user_command('TTSQueue', function(cmd)
    if cmd.args == '' then
      M.queue_list()
    else
      M.queue_add(cmd.args)
    end
  end, { nargs = '*' })
  
  vim.api.nvim_create_user_command('TTSClear', function()
    M.queue_clear()
  end, {})
  
  vim.api.nvim_create_user_command('TTSNext', function(cmd)
    M.queue_next(math.max(cmd.count, vim.v.count1))
  end, { count = true })
  
  vim.api.nvim_create_user_command('TTSPrev', function(cmd)
    M.queue_prev(math.max(cmd.count, vim.v.count1))
  end, { count = true })
  
  vim.api.nvim_create_user_command('TTSBackend', function(cmd)
    M.set_backend(cmd.args)
  end, { 
    nargs = 1,
    complete = function()
      return { 'auto', 'macos', 'openai' }
    end
  })
  
  vim.api.nvim_create_user_command('TTSVoices', function()
    M.list_voices()
  end, {})
  
  vim.api.nvim_create_user_command('TTSSetVoice', function(cmd)
    M.set_voice(cmd.args)
  end, { nargs = 1 })
  
  vim.api.nvim_create_user_command('TTSClearCache', function()
    M.clear_cache()
  end, {})
  
  vim.api.nvim_create_user_command('TTSMotion', function(cmd)
    M.play_motion(cmd.args)
  end, { nargs = 1 })
end

function M._setup_keymaps()
  local config = require('tts.config').get()
  local keymaps = config.keymaps
  
  if not keymaps then
    return
  end
  
  local function map(mode, lhs, rhs, opts)
    opts = opts or {}
    opts.silent = opts.silent ~= false
    vim.keymap.set(mode, lhs, rhs, opts)
  end
  
  if keymaps.play then
    map('n', keymaps.play, '<cmd>TTSPlay<cr>', { desc = 'TTS: Play current selection/section' })
    map('v', keymaps.visual_play or keymaps.play, ':TTSPlay<cr>', { desc = 'TTS: Play selection' })
  end
  
  if keymaps.stop then
    map('n', keymaps.stop, '<cmd>TTSStop<cr>', { desc = 'TTS: Stop playback' })
  end
  
  if keymaps.queue then
    map('n', keymaps.queue, '<cmd>TTSQueue<cr>', { desc = 'TTS: Show queue' })
    map('v', keymaps.queue, ':TTSQueue<cr>', { desc = 'TTS: Add to queue' })
  end
  
  if keymaps.clear then
    map('n', keymaps.clear, '<cmd>TTSClear<cr>', { desc = 'TTS: Clear queue' })
  end
  
  if keymaps.next then
    map('n', keymaps.next, '<cmd>TTSNext<cr>', { desc = 'TTS: Skip N segments forward' })
  end
  
  if keymaps.prev then
    map('n', keymaps.prev, '<cmd>TTSPrev<cr>', { desc = 'TTS: Skip N segments back' })
  end
end

function M._prepare_segments(text)
  local utils = require('tts.utils')
  text = utils.preprocess_text(text)

  if not text or text == '' then
    return {}
  end

  local hooks = require('tts.config').get().hooks
  if hooks and hooks.before_play then
    local modified = hooks.before_play(text)
    if modified then
      text = modified
    end
  end

  return utils.split_segments(text)
end

function M.play(text, opts)
  opts = opts or {}
  if not text or text == '' then
    vim.notify('No text provided to play', vim.log.levels.WARN)
    return
  end

  local segments = M._prepare_segments(text)
  if #segments == 0 then
    vim.notify('Text became empty after preprocessing', vim.log.levels.WARN)
    return
  end

  require('tts.queue').set_segments(segments, { opts = opts, original_text = text })
end

function M.play_lines(first, last, opts)
  local bufnr = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, first - 1, last, false)

  if #lines == 0 then
    vim.notify('No text selected', vim.log.levels.WARN)
    return
  end

  local segments = {}
  for _, group in ipairs(require('tts.utils').group_source_lines(lines, first)) do
    for _, piece in ipairs(M._prepare_segments(group.text)) do
      table.insert(segments, {
        text = piece,
        range = { bufnr = bufnr, first = group.first, last = group.last },
      })
    end
  end

  if #segments == 0 then
    vim.notify('Text became empty after preprocessing', vim.log.levels.WARN)
    return
  end

  require('tts.queue').set_segments(segments, {
    opts = opts or {},
    original_text = table.concat(lines, '\n'),
  })
end

function M.play_range(line1, line2)
  M.play_lines(line1, line2)
end

function M.play_selection()
  if not initialized then
    M.setup({})
  end

  local selection = require('tts.selection')
  local mode = vim.fn.mode()

  if mode == 'v' or mode == 'V' or mode == '\22' then
    vim.cmd('normal! "vy')
    local selected = vim.fn.getreg('v')
    if selected and selected ~= '' then
      M.play(selected)
    else
      vim.notify('No text selected', vim.log.levels.WARN)
    end
    return
  end

  local config = require('tts.config').get()
  local default = config.playback and config.playback.default_selection
  local text, range

  if default == 'line' then
    text, range = selection.get_line()
  elseif default == 'section' then
    text, range = selection.get_section()
  elseif default == 'buffer' then
    text, range = selection.get_buffer()
  else
    text, range = selection.get_paragraph()
  end

  if not text or text == '' then
    text, range = selection.get_line()
  end

  if not text or text == '' then
    vim.notify('No text selected', vim.log.levels.WARN)
    return
  end

  if range then
    M.play_lines(range.first, range.last)
  else
    M.play(text)
  end
end

function M.play_motion(motion)
  local selection = require('tts.selection')
  local text = selection.get_motion(motion)
  
  if text and text ~= '' then
    M.play(text)
  end
end

function M.stop()
  require('tts.queue').stop()
end

function M.queue_add(text)
  if not text or text == '' then
    local selection = require('tts.selection')
    local mode = vim.fn.mode()
    
    if mode == 'v' or mode == 'V' or mode == '\22' then
      text = selection.get_visual()
    else
      text = selection.get_line()
    end
  end
  
  if text and text ~= '' then
    local segments = M._prepare_segments(text)
    if #segments > 0 then
      require('tts.queue').append(segments, { original_text = text })
    end
    -- Silent add - no notification needed
  end
end

function M.queue_clear()
  local queue = require('tts.queue')
  queue.clear()
  -- Silent clear - no notification needed
end

function M.queue_list()
  local queue = require('tts.queue')
  local items = queue.list()
  
  if #items == 0 then
    vim.notify('Queue is empty', vim.log.levels.INFO)
    return
  end
  
  local lines = { 'TTS Queue:' }
  for _, item in ipairs(items) do
    table.insert(lines, item.display)
  end

  require('tts.utils').echo_lines(lines)
end

function M.queue_next(count)
  local queue = require('tts.queue')
  queue.skip(count)
end

function M.queue_prev(count)
  local queue = require('tts.queue')
  queue.previous(count)
end

function M.set_backend(name)
  local backends = require('tts.backends')
  backends.set(name)
  -- Backend module already handles success/failure notifications
end

function M.get_backend()
  local backends = require('tts.backends')
  return backends.get_backend_name()
end

function M.list_voices()
  local backends = require('tts.backends')
  local voices = backends.list_voices()
  
  if #voices == 0 then
    vim.notify('No voices available', vim.log.levels.INFO)
    return
  end
  
  local lines = { 'Available voices:' }
  for _, voice in ipairs(voices) do
    local line = string.format('  %s (%s)', voice.name, voice.language or 'unknown')
    if voice.note and voice.note ~= '' then
      line = line .. ' - ' .. voice.note
    end
    table.insert(lines, line)
  end

  require('tts.utils').echo_lines(lines)
end

function M.set_voice(voice)
  local config = require('tts.config').get()
  local backend = require('tts.backends').get_backend_name()
  
  if backend == 'macos' then
    config.macos.voice = voice
  elseif backend == 'openai' then
    config.openai.voice = voice
  end
  -- Silent voice change
end

function M.get_state()
  local state = require('tts.state')
  return state.get_state()
end

function M.clear_cache()
  local cache = require('tts.cache')
  cache.clear()
end

function M.get_cache_stats()
  local cache = require('tts.cache')
  return cache.get_stats()
end

return M
