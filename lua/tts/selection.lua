local M = {}

local function is_empty_line(line_num)
  local line = vim.api.nvim_buf_get_lines(0, line_num - 1, line_num, false)[1]
  return not line or line:match('^%s*$')
end

function M.get_visual()
  local mode = vim.fn.mode()
  
  if mode == 'v' then
    return M._get_char_visual()
  elseif mode == 'V' then
    return M._get_line_visual()
  elseif mode == '\22' then
    return M._get_block_visual()
  else
    return M._get_last_visual()
  end
end

function M._get_char_visual()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  
  if start_pos[2] == end_pos[2] then
    local line = vim.api.nvim_buf_get_lines(
      0, start_pos[2] - 1, start_pos[2], false
    )[1]
    if line then
      return line:sub(start_pos[3], end_pos[3])
    end
  end
  
  local lines = vim.api.nvim_buf_get_lines(
    0, start_pos[2] - 1, end_pos[2], false
  )
  
  if #lines > 0 then
    lines[1] = lines[1]:sub(start_pos[3])
    if #lines > 1 then
      lines[#lines] = lines[#lines]:sub(1, end_pos[3])
    end
  end
  
  return table.concat(lines, '\n')
end

function M._get_line_visual()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  
  local lines = vim.api.nvim_buf_get_lines(
    0, start_pos[2] - 1, end_pos[2], false
  )
  
  return table.concat(lines, '\n')
end

function M._get_block_visual()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  
  local lines = vim.api.nvim_buf_get_lines(
    0, start_pos[2] - 1, end_pos[2], false
  )
  
  local result = {}
  for _, line in ipairs(lines) do
    local substr = line:sub(start_pos[3], end_pos[3])
    table.insert(result, substr)
  end
  
  return table.concat(result, '\n')
end

function M._get_last_visual()
  local start_pos = vim.fn.getpos("'<")
  local end_pos = vim.fn.getpos("'>")
  
  if start_pos[2] == 0 or end_pos[2] == 0 then
    return ""
  end
  
  local lines = vim.api.nvim_buf_get_lines(
    0, start_pos[2] - 1, end_pos[2], false
  )
  
  if #lines == 0 then
    return ""
  end
  
  if #lines == 1 then
    return lines[1]:sub(start_pos[3], end_pos[3])
  else
    lines[1] = lines[1]:sub(start_pos[3])
    lines[#lines] = lines[#lines]:sub(1, end_pos[3])
    return table.concat(lines, '\n')
  end
end

function M.get_line()
  local line = vim.api.nvim_win_get_cursor(0)[1]
  return vim.api.nvim_get_current_line(), { first = line, last = line }
end

function M.get_buffer()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  return table.concat(lines, '\n'), { first = 1, last = math.max(1, #lines) }
end

function M.get_section()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local current_line = cursor[1]

  if is_empty_line(current_line) then
    return ""
  end

  local start_line = current_line
  local end_line = current_line

  while start_line > 1 do
    local line = vim.api.nvim_buf_get_lines(
      0, start_line - 2, start_line - 1, false
    )[1]
    if not line or line:match('^#+%s') or line:match('^---+$') or line:match('^===+$') then
      break
    end
    start_line = start_line - 1
  end

  local line_count = vim.api.nvim_buf_line_count(0)
  while end_line < line_count do
    local line = vim.api.nvim_buf_get_lines(
      0, end_line, end_line + 1, false
    )[1]
    if not line or line:match('^#+%s') or line:match('^---+$') or line:match('^===+$') then
      break
    end
    end_line = end_line + 1
  end

  local lines = vim.api.nvim_buf_get_lines(
    0, start_line - 1, end_line, false
  )
  local result = table.concat(lines, '\n')

  return result, { first = start_line, last = end_line }
end

function M.get_paragraph()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local current_line = cursor[1]

  if is_empty_line(current_line) then
    return ""
  end

  local start_line = current_line
  local end_line = current_line

  while start_line > 1 do
    local line = vim.api.nvim_buf_get_lines(
      0, start_line - 2, start_line - 1, false
    )[1]
    if not line or line:match('^%s*$') then
      break
    end
    start_line = start_line - 1
  end

  local line_count = vim.api.nvim_buf_line_count(0)
  while end_line < line_count do
    local line = vim.api.nvim_buf_get_lines(
      0, end_line, end_line + 1, false
    )[1]
    if not line or line:match('^%s*$') then
      break
    end
    end_line = end_line + 1
  end

  local lines = vim.api.nvim_buf_get_lines(
    0, start_line - 1, end_line, false
  )
  return table.concat(lines, '\n'), { first = start_line, last = end_line }
end

function M.get_motion(motion)
  local saved_pos = vim.api.nvim_win_get_cursor(0)
  local saved_reg = vim.fn.getreg('"')
  local saved_regtype = vim.fn.getregtype('"')
  
  vim.cmd('normal! m[')
  
  vim.cmd('normal! ' .. motion)
  
  vim.cmd('normal! m]')
  
  local start_pos = vim.fn.getpos("'[")
  local end_pos = vim.fn.getpos("']")
  
  local lines = vim.api.nvim_buf_get_lines(
    0, 
    start_pos[2] - 1, 
    end_pos[2], 
    false
  )
  
  vim.api.nvim_win_set_cursor(0, saved_pos)
  vim.fn.setreg('"', saved_reg, saved_regtype)
  
  return table.concat(lines, '\n')
end

return M
