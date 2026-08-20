local M = {}

local ns = vim.api.nvim_create_namespace('tts_segment')
local marked_buf = nil

local function define_highlight()
  vim.api.nvim_set_hl(0, 'TTSSegment', { link = 'Visual', default = true })
end

define_highlight()

vim.api.nvim_create_autocmd('ColorScheme', {
  group = vim.api.nvim_create_augroup('TTSSegmentHighlight', { clear = true }),
  callback = define_highlight,
})

function M.clear()
  if marked_buf and vim.api.nvim_buf_is_valid(marked_buf) then
    vim.api.nvim_buf_clear_namespace(marked_buf, ns, 0, -1)
  end
  marked_buf = nil
end

function M.show(range)
  if not require('tts.config').get().playback.follow then
    return
  end

  M.clear()

  if not range or not range.bufnr or not vim.api.nvim_buf_is_valid(range.bufnr) then
    return
  end

  local bufnr = range.bufnr
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local first = math.max(1, math.min(range.first or 1, line_count))
  local last = math.max(first, math.min(range.last or first, line_count))
  local last_text = vim.api.nvim_buf_get_lines(bufnr, last - 1, last, false)[1] or ''

  vim.api.nvim_buf_set_extmark(bufnr, ns, first - 1, 0, {
    end_row = last - 1,
    end_col = #last_text,
    hl_group = 'TTSSegment',
    hl_eol = true,
  })
  marked_buf = bufnr

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(win) == bufnr then
      vim.api.nvim_win_set_cursor(win, { first, 0 })
      vim.api.nvim_win_call(win, function()
        vim.cmd('normal! zz')
      end)
    end
  end
end

return M
