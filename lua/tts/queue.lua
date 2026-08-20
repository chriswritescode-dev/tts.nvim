local M = {}
local items = {}
local current_index = 0
local active = false
local play_token = 0
local run_text = nil
local finished = false
local pending_advance = false

local function invalidate()
  play_token = play_token + 1
  return play_token
end

local function halt()
  invalidate()
  if active then
    active = false
    require('tts.backends').stop({ keep_prefetch = true })
  end
end

local function push_items(segments, opts)
  for _, seg in ipairs(segments) do
    local text = seg
    local range = nil

    if type(seg) == 'table' then
      text = seg.text
      range = seg.range
    end

    table.insert(items, {
      text = text,
      range = range,
      opts = opts or {},
      status = 'pending',
      id = vim.fn.localtime() .. '_' .. math.random(1000)
    })
  end
end

function M.stop()
  invalidate()
  active = false
  pending_advance = false
  require('tts.utils').progress(nil)
  require('tts.follow').clear()
  require('tts.backends').stop()

  vim.api.nvim_exec_autocmds('User', {
    pattern = 'TTSQueueUpdate',
    data = { action = 'stop', count = #items }
  })
end

function M.clear()
  M.stop()
  items = {}
  current_index = 0
  run_text = nil

  vim.api.nvim_exec_autocmds('User', {
    pattern = 'TTSQueueUpdate',
    data = { action = 'clear', count = 0 }
  })
end

function M.get_current()
  if current_index > 0 and current_index <= #items then
    return items[current_index]
  end
  return nil
end

function M.list()
  local out = {}
  for i, item in ipairs(items) do
    local display_text = item.text
    if #display_text > 50 then
      display_text = display_text:sub(1, 47) .. '...'
    end

    local status_indicator = ''
    if i == current_index then
      if item.status == 'playing' then
        status_indicator = '▶ '
      else
        status_indicator = '→ '
      end
    elseif item.status == 'completed' then
      status_indicator = '✓ '
    elseif item.status == 'error' then
      status_indicator = '✗ '
    else
      status_indicator = '  '
    end

    table.insert(out, {
      index = i,
      text = display_text,
      status = item.status,
      indicator = status_indicator,
      display = string.format('%s%d. %s', status_indicator, i, display_text)
    })
  end

  return out
end

function M.play_index(index)
  if #items == 0 then
    return false
  end
  if index < 1 then
    index = 1
  end
  if index > #items then
    M._finish()
    return false
  end

  halt()
  pending_advance = false
  current_index = index

  require('tts.utils').progress(string.format('%d/%d', index, #items))
  vim.api.nvim_exec_autocmds('User', {
    pattern = 'TTSQueueUpdate',
    data = { action = 'play', index = index, count = #items }
  })

  local item = items[index]
  item.status = 'playing'
  active = true
  finished = false
  local token = play_token

  require('tts.follow').show(item.range)

  local config = require('tts.config').get()
  local hooks = config.hooks
  if hooks and hooks.on_queue_item then
    local ok, err = pcall(hooks.on_queue_item, item, index, #items)
    if not ok then
      vim.notify('TTS: Error in on_queue_item hook: ' .. tostring(err), vim.log.levels.ERROR)
    end
  end

  local settled = false
  local handle = require('tts.backends').speak(item.text, vim.tbl_extend('force', item.opts or {}, {
    on_complete = function(code)
      if token ~= play_token then
        return
      end
      settled = true
      item.status = (code and code ~= 0) and 'error' or 'completed'
      active = false
      M._advance()
    end
  }))

  if not handle and not settled then
    item.status = 'error'
    active = false
    M._advance()
    return false
  end

  if index + 1 <= #items then
    local next_item = items[index + 1]
    require('tts.backends').prefetch(next_item.text, next_item.opts)
  end

  return true
end

function M._advance()
  local pause = require('tts.config').get().playback.pause_between_chunks or 0
  local function advance()
    pending_advance = false
    if current_index >= #items then
      M._finish()
    else
      M.play_index(current_index + 1)
    end
  end

  if pause > 0 then
    local token = play_token
    pending_advance = true
    vim.defer_fn(function()
      if token ~= play_token then
        return
      end
      advance()
    end, pause * 1000)
  else
    advance()
  end
end

function M._finish()
  if finished then
    return
  end
  finished = true
  active = false
  pending_advance = false
  require('tts.utils').progress(nil)
  require('tts.follow').clear()

  local config = require('tts.config').get()
  local hooks = config.hooks
  if hooks and hooks.after_play then
    local ok, err = pcall(hooks.after_play, run_text)
    if not ok then
      vim.notify('TTS: Error in after_play hook: ' .. tostring(err), vim.log.levels.ERROR)
    end
  end

  vim.api.nvim_exec_autocmds('User', {
    pattern = 'TTSQueueUpdate',
    data = { action = 'finish', count = #items }
  })

  if config.playback.auto_clear_queue then
    M.clear()
  end
end

function M.set_segments(segments, run)
  halt()
  items = {}
  push_items(segments, run and run.opts)
  current_index = 0
  run_text = run and run.original_text

  if #items == 0 then
    require('tts.utils').progress(nil)
    require('tts.follow').clear()
  end

  vim.api.nvim_exec_autocmds('User', {
    pattern = 'TTSQueueUpdate',
    data = { action = 'set', count = #items }
  })

  return M.play_index(1)
end

function M.append(segments, run)
  if not segments or #segments == 0 then
    return
  end

  push_items(segments, run and run.opts)

  vim.api.nvim_exec_autocmds('User', {
    pattern = 'TTSQueueUpdate',
    data = { action = 'add', count = #items }
  })

  if not active and not pending_advance then
    run_text = run and run.original_text
    M.play_index(current_index + 1)
  end
end

function M.is_active()
  return active
end

function M.skip(count)
  if #items == 0 then
    return
  end
  count = math.max(1, count or 1)
  if current_index + count > #items then
    halt()
    M._finish()
    return
  end
  M.play_index(current_index + count)
end

function M.previous(count)
  if #items == 0 then
    return
  end
  count = math.max(1, count or 1)
  M.play_index(math.max(1, current_index - count))
end

function M.size()
  return #items
end

function M.is_empty()
  return #items == 0
end

function M.save()
  local state_file = vim.fn.stdpath('data') .. '/tts_queue.json'
  local data = vim.fn.json_encode(items)
  local file = io.open(state_file, 'w')
  if file then
    file:write(data)
    file:close()
    return true
  end
  return false
end

function M.load()
  local state_file = vim.fn.stdpath('data') .. '/tts_queue.json'
  if vim.fn.filereadable(state_file) == 1 then
    local file = io.open(state_file, 'r')
    if file then
      local data = file:read('*all')
      file:close()
      local ok, loaded_queue = pcall(vim.fn.json_decode, data)
      if ok and type(loaded_queue) == 'table' then
        items = loaded_queue
        current_index = 0
        active = false
        return true
      end
    end
  end
  return false
end

function M.remove(index)
  if index > 0 and index <= #items then
    local was_playing = active and current_index == index
    table.remove(items, index)

    if current_index > index then
      current_index = current_index - 1
    elseif current_index == index then
      if current_index > #items then
        current_index = #items
      end
    end

    vim.api.nvim_exec_autocmds('User', {
      pattern = 'TTSQueueUpdate',
      data = { action = 'remove', count = #items }
    })

    if was_playing then
      if current_index >= 1 and current_index <= #items then
        M.play_index(current_index)
      else
        halt()
        M._finish()
      end
    end

    return true
  end
  return false
end

return M
