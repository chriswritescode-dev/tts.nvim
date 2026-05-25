local M = {}
local queue = {}
local current_index = 0
local is_processing = false

function M.add(text, opts)
  table.insert(queue, {
    text = text,
    opts = opts or {},
    status = 'pending',
    id = vim.fn.localtime() .. '_' .. math.random(1000)
  })
  
  vim.api.nvim_exec_autocmds('User', {
    pattern = 'TTSQueueUpdate',
    data = { action = 'add', count = #queue }
  })
  
  if not is_processing then
    M.process_next()
  end
end

function M.clear()
  queue = {}
  current_index = 0
  is_processing = false

  vim.api.nvim_exec_autocmds('User', {
    pattern = 'TTSQueueUpdate',
    data = { action = 'clear', count = 0 }
  })
end

function M.reset_state()
  is_processing = false
  current_index = 0
end

function M.get_next()
  if current_index < #queue then
    current_index = current_index + 1
    return queue[current_index]
  end
  return nil
end

function M.get_previous()
  if current_index > 1 then
    current_index = current_index - 1
    return queue[current_index]
  end
  return nil
end

function M.get_current()
  if current_index > 0 and current_index <= #queue then
    return queue[current_index]
  end
  return nil
end

function M.list()
  local items = {}
  for i, item in ipairs(queue) do
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
    
    table.insert(items, {
      index = i,
      text = display_text,
      status = item.status,
      indicator = status_indicator,
      display = string.format('%s%d. %s', status_indicator, i, display_text)
    })
  end
  
  return items
end

function M.process_next()
  if is_processing then
    return
  end

  local item = M.get_next()
  if not item then
    is_processing = false

    local config = require('tts.config').get()
    if config.playback.auto_clear_queue then
      M.clear()
    end

    return
  end

  is_processing = true
  item.status = 'playing'

  local config = require('tts.config').get()
  local hooks = config.hooks

  if hooks and hooks.on_queue_item then
    local ok, err = pcall(hooks.on_queue_item, item, current_index, #queue)
    if not ok then
      vim.notify('TTS: Error in on_queue_item hook: ' .. tostring(err), vim.log.levels.ERROR)
    end
  end

  local backends = require('tts.backends')
  
  local opts_with_callback = vim.tbl_extend('force', item.opts or {}, {
    on_complete = function()
      vim.schedule(function()
        item.status = 'completed'
        is_processing = false
        M.process_next()
      end)
    end
  })

  local handle = backends.speak(item.text, opts_with_callback)

  if not handle then
    item.status = 'error'
    is_processing = false
  end
end

function M.process()
  if not is_processing and #queue > 0 then
    current_index = 0
    M.process_next()
  end
end

function M.skip()
  if is_processing then
    local backends = require('tts.backends')
    backends.stop()

    is_processing = false
    M.process_next()
  end
end

function M.previous()
  if current_index > 1 then
    local backends = require('tts.backends')
    backends.stop()

    current_index = current_index - 2
    is_processing = false
    M.process_next()
  end
end

function M.size()
  return #queue
end

function M.is_empty()
  return #queue == 0
end

function M.save()
  local state_file = vim.fn.stdpath('data') .. '/tts_queue.json'
  local data = vim.fn.json_encode(queue)
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
        queue = loaded_queue
        current_index = 0
        is_processing = false
        return true
      end
    end
  end
  return false
end

function M.remove(index)
  if index > 0 and index <= #queue then
    table.remove(queue, index)
    
    if current_index > index then
      current_index = current_index - 1
    elseif current_index == index then
      if current_index > #queue then
        current_index = #queue
      end
    end
    
    vim.api.nvim_exec_autocmds('User', {
      pattern = 'TTSQueueUpdate',
      data = { action = 'remove', count = #queue }
    })
    
    return true
  end
  return false
end

return M
