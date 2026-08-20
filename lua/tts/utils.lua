local M = {}

local function apply_replacements(text, replacements)
  local ordered_replacements = {}

  for pattern, replacement in pairs(replacements) do
    table.insert(ordered_replacements, {
      pattern = pattern,
      replacement = replacement,
    })
  end

  table.sort(ordered_replacements, function(a, b)
    if #a.pattern == #b.pattern then
      return a.pattern < b.pattern
    end

    return #a.pattern > #b.pattern
  end)

  for _, item in ipairs(ordered_replacements) do
    text = text:gsub(item.pattern, item.replacement)
  end

  return text
end

function M.preprocess_text(text)
  local config = require('tts.config').get()
  local preprocessing = config.preprocessing
  
  if not preprocessing or not text then
    return text
  end
  
  -- Clean markdown first (before code cleaning)
  if preprocessing.clean_markdown then
    text = M.clean_markdown_text(text)
  end
  
  -- Apply content filtering based on filtering level
  if preprocessing.filtering_level and preprocessing.filtering_level ~= 'none' then
    local level = preprocessing.filtering_level
    
    -- Always clean paths and URLs for minimal level and above
    if level == 'minimal' or level == 'moderate' or level == 'aggressive' then
      text = M.clean_paths_and_urls(text)
    end
    
    -- Clean smart content for moderate and aggressive levels
    if level == 'moderate' or level == 'aggressive' then
      text = M.clean_smart_content(text)
    end
    
    -- Clean code-specific content for aggressive level
    if level == 'aggressive' then
      local filetype = vim.bo.filetype
      text = M.clean_code_specific_content(text, filetype)
    end
  end
  
  if preprocessing.clean_code then
    text = M.clean_code_text(text)
  end
  
  if preprocessing.expand_abbreviations then
    text = M.expand_abbreviations(text)
  end
  
  if preprocessing.replacements then
    text = apply_replacements(text, preprocessing.replacements)
  end
  
  local filetype = vim.bo.filetype
  if preprocessing.languages and preprocessing.languages[filetype] then
    text = apply_replacements(text, preprocessing.languages[filetype])
  end
  
  -- Add periods at end of lines for natural pauses (before normalizing whitespace)
  if preprocessing.add_line_breaks then
    -- Add period at end of lines that don't already end with punctuation
    text = text:gsub('([^%.!?:,;])[ \t]*\n', '%1.\n')
  end
  
  -- Strip problematic characters that TTS engines struggle with
  text = text:gsub('#', '')
  text = text:gsub('/', '')

  -- Final cleanup
  text = text:gsub('[ \t\r]+', ' ')  -- Normalize whitespace (preserve newlines)
  text = text:gsub(' *\n *', '\n')  -- Trim spaces around newlines
  text = text:gsub('\n+', '\n')  -- Collapse blank lines
  text = text:gsub('^%s*[%-%*%+]%s+', '')  -- Remove leading list markers
  text = text:gsub('\n%s*[%-%*%+]%s+', '\n')  -- Remove list markers on later lines
  text = text:gsub('%.%s*[%-%*%+]%s+', '. ')  -- Clean up ". -" to ". "
  text = vim.trim(text)
  
  return text
end

function M.clean_markdown_text(text)
  -- Preserve original text for fallback
  local original = text
  
  local config = require('tts.config').get()
  local preprocessing = config.preprocessing
  
  -- Handle code blocks based on configuration
  if preprocessing.skip_code_blocks then
    text = text:gsub('```[^\n]*\n.-\n```', ' ')
    text = text:gsub('~~~[^\n]*\n.-\n~~~', ' ')
  else
    text = text:gsub('```[^\n]*\n(.-)\n```', ' %1 ')
    text = text:gsub('~~~[^\n]*\n(.-)\n~~~', ' %1 ')
  end
  text = text:gsub('`([^`\n]+)`', '%1')
  
  -- Remove images
  text = text:gsub('!%[.-%]%(.-%)', '')
  
  -- Convert links to just the link text
  text = text:gsub('%[([^%]]+)%]%([^%)]+%)', '%1')
  
  -- Remove reference-style links
  text = text:gsub('%[([^%]]+)%]%[[^%]]*%]', '%1')
  text = text:gsub('^%[[^%]]+%]:%s*.*$', '')
  
  -- Remove HTML tags
  text = text:gsub('<[^>]+>', '')
  
  -- Remove footnote references [^1] and footnote definitions [^1]:
  text = text:gsub('%[%^[%w_%-]+%]', '')
  text = text:gsub('%[%^[%w_%-]+%]:', '')
  
  -- Remove math blocks (LaTeX-style)
  text = text:gsub('%$%$.-%$%$', ' math expression ')
  text = text:gsub('%$([^%$\n]+)%$', ' math ')
  
  -- Remove markdown tables (pipes and alignment markers)
  text = text:gsub('|', ' ')
  text = text:gsub(':?%-%-+:?', '')
  
  -- Remove markdown headers (keep the text)
  -- Handle headers at start of lines only, preserving # in other contexts
  text = text:gsub('^(#+)%s+(.-)$', '%2')
  text = text:gsub('\n(#+)%s+', '\n')
  text = text:gsub('#+', '')
  
  -- Remove horizontal rules (handle multiline by processing each line)
  text = text:gsub('\n%-%-%-+%s*\n', '\n')
  text = text:gsub('\n%*%*%*+%s*\n', '\n')
  text = text:gsub('\n___+%s*\n', '\n')
  text = text:gsub('\n%s*\n+', '\n')
  text = text:gsub('^%-%-%-+%s*\n', '')
  text = text:gsub('^%*%*%*+%s*\n', '')
  text = text:gsub('^___+%s*\n', '')
  text = text:gsub('\n%-%-%-+%s*$', '')
  text = text:gsub('\n%*%*%*+%s*$', '')
  text = text:gsub('\n___+%s*$', '')
  
  -- Remove blockquotes
  text = text:gsub('^>+%s*', '')
  text = text:gsub('\n>+%s*', '\n')
  
  -- Remove list markers but add pauses between items for better speech flow
  text = text:gsub('^%s*[-*+]%s+', '')
  text = text:gsub('\n%s*[-*+]%s+', '. ')  -- Add period for pause between list items
  text = text:gsub('(%S)[^%S\n]+[-*+][^%S\n]+', '%1. ')  -- Add period for pause in single-line lists
  
  -- Remove numbered list markers and add pauses
  text = text:gsub('^%s*%d+%.%s+', '')
  text = text:gsub('\n%s*%d+%.%s+', '. ')  -- Add period for pause between numbered items
  text = text:gsub('(%S)[^%S\n]+%d+%.[^%S\n]+', '%1. ')  -- Add period for pause in single-line numbered lists
  
  -- Remove emphasis markers (bold, italic) - non-greedy matching
  text = text:gsub('%*%*%*(.-)%*%*%*', '%1')  -- Bold + italic
  text = text:gsub('%*%*(.-)%*%*', '%1')  -- Bold  
  text = text:gsub('__(.-)__', '%1')  -- Bold
  text = text:gsub('%*([^%*]+)%*', '%1')  -- Italic (non-greedy)
  text = text:gsub('_([^_]+)_', '%1')  -- Italic (non-greedy)
  text = text:gsub('~~(.-)~~', '%1')  -- Strikethrough
  
  -- Remove any remaining markdown characters anywhere in text
  text = text:gsub('[*_~`]+', '')  -- Remove *, _, ~, ` characters
  -- Only remove empty brackets/parentheses, not ones with content
  text = text:gsub('%[%]', '')  -- Empty brackets
  text = text:gsub('%(%)' , '')  -- Empty parentheses
  
  -- Remove task list markers (case-insensitive for [x] and [X])
  text = text:gsub('%[[ xX]%]%s*', '')
  
  -- Remove emoji shortcodes
  text = text:gsub(':[%w_%-]+:', '')
  
  -- Remove all Unicode emoji characters using comprehensive ranges (if enabled)
  if preprocessing.remove_emoji then
    text = M.remove_emoji(text)
  end
  
  -- Clean up URLs but keep surrounding text
  text = text:gsub('https?://[%w%-%._~:/%?#%[%]@!%$&\'%(%)%*%+,;=]+', ' url ')
  text = text:gsub('www%.[%w%-%._~:/%?#%[%]@!%$&\'%(%)%*%+,;=]+', ' url ')
  text = text:gsub('ftp://[%w%-%._~:/%?#%[%]@!%$&\'%(%)%*%+,;=]+', ' url ')
  
  -- Final safety check - if we've removed everything, return the original
  if text:match('^%s*$') then
    return original
  end
  
  return text
end

function M.clean_code_text(text)
  text = text:gsub('===', ' strictly equals ')
  text = text:gsub('!==', ' not strictly equal ')
  text = text:gsub('==', ' equals ')
  text = text:gsub('~=', ' not equal ')
  text = text:gsub('!=', ' not equal ')
  text = text:gsub('<=', ' less than or equal ')
  text = text:gsub('>=', ' greater than or equal ')
  text = text:gsub('&&', ' and ')
  text = text:gsub('||', ' or ')
  text = text:gsub('%.%.', ' concatenate ')
  
  text = text:gsub('=>', ' ')
  text = text:gsub('%->', ' ')
  text = text:gsub('::', ' ')
  text = text:gsub('<<', ' ')
  text = text:gsub('>>', ' ')
  
  text = text:gsub('%+', ' plus ')
  text = text:gsub('%-', ' minus ')
  text = text:gsub('%*', ' times ')
  text = text:gsub('%%', ' modulo ')
  text = text:gsub('=', ' equals ')
  text = text:gsub('<', ' less than ')
  text = text:gsub('>', ' greater than ')
  text = text:gsub('&', ' and ')
  text = text:gsub('|', ' or ')
  text = text:gsub('!', ' not ')
  text = text:gsub('%^', ' to the power of ')
  text = text:gsub('~', ' tilde ')
  text = text:gsub('@', ' at ')
  text = text:gsub('#', ' hash ')
  text = text:gsub('%$', ' dollar ')
  
  text = text:gsub('/', ' ')
  text = text:gsub('\\', ' ')
  
  text = text:gsub(';', '.')
  
  text = text:gsub('%s+', ' ')
  text = vim.trim(text)

  return text
end

function M.clean_paths_and_urls(text)
  text = text:gsub('%.%.?/[%w%-%._~]+[%w%-%._~/]*', ' file path ')
  text = text:gsub('/[%w%-%._~]+/[%w%-%._~%.]+[%w%-%._~/]*', ' file path ')
  text = text:gsub('[A-Za-z]:\\[%w%-%._~\\]+', ' file path ')

  text = text:gsub('https?://[%w%-%._~:/?%#[%]@!%$&\'%(%)*%+,;=]+', ' url ')
  text = text:gsub('www%.[%w%-%._~:/?%#[%]@!%$&\'%(%)*%+,;=]+', ' url ')
  text = text:gsub('ftp://[%w%-%._~:/?%#[%]@!%$&\'%(%)*%+,;=]+', ' url ')

  text = text:gsub('[%w%-%._]+@{%w+}', ' git reference ')
  text = text:gsub('HEAD[~^]%d+', ' git reference ')

  text = text:gsub('\\\\[%w%-%._$]+\\[%w%-%._$]+', ' network path ')
  text = text:gsub('smb://[%w%-%._~:/?%#[%]@!%$&\'%(%)*%+,;=]+', ' network path ')

  return text
end

function M.clean_smart_content(text)
  -- Remove UUIDs (8-4-4-4-12 hex pattern)
  text = text:gsub('[a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9]%-[a-f0-9][a-f0-9][a-f0-9][a-f0-9]%-[a-f0-9][a-f0-9][a-f0-9][a-f0-9]%-[a-f0-9][a-f0-9][a-f0-9][a-f0-9]%-[a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9][a-f0-9]', ' uuid ')
  
  -- Remove binary/hex data
  text = text:gsub('0[xX][a-fA-F0-9]+', ' hex value ')
  text = text:gsub('U%+[a-fA-F0-9]+', ' unicode character ')
  
  -- Remove version numbers and semver
  text = text:gsub('v%d+%.%d+%.%d+', ' version ')
  text = text:gsub('[~^]%d+%.%d+%.%d+', ' version range ')
  
  -- Remove email addresses
  text = text:gsub('[%w%-%._]+@[%w%-%._]+%.%w+', ' email address ')
  
  -- Remove IP addresses
  text = text:gsub('%d+%.%d+%.%d+%.%d+', ' ip address ')
  
  return text
end

function M.clean_code_specific_content(text, filetype)
  if not filetype then
    return text
  end
  
  -- File-specific cleaning
  if filetype == 'javascript' or filetype == 'typescript' then
    -- Remove npm package references
    text = text:gsub('npm%s+install%s+[%w%-%._@/]+', ' package installation ')
    text = text:gsub('require%(["\'][^"\']+["\']%)', ' module import ')
    text = text:gsub('import.*from.*["\'][^"\']+["\']', ' module import ')
    
  elseif filetype == 'python' then
    -- Remove pip references
    text = text:gsub('pip%s+install%s+[%w%-%._=]+', ' package installation ')
    text = text:gsub('from%s+[%w%.]+%s+import', ' import ')
    text = text:gsub('import%s+[%w%.]+', ' import ')
    
  elseif filetype == 'lua' then
    -- Remove Lua-specific patterns
    text = text:gsub('local%s+[%w_]+%s*=', ' variable ')
    text = text:gsub('require%(["\'][^"\']+["\']%)', ' module ')
    
  elseif filetype == 'rust' then
    -- Remove Cargo/crates references
    text = text:gsub('cargo%s+[%w]+', ' cargo command ')
    text = text:gsub('use%s+[%w:]+;', ' import ')
    text = text:gsub('extern%s+crate%s+[%w]+;', ' external crate ')
    
  elseif filetype == 'go' then
    -- Remove Go-specific patterns
    text = text:gsub('go%s+[%w]+', ' go command ')
    text = text:gsub('import%s+%(["\'][^"\']+["\']%)', ' import ')
    
  elseif filetype == 'java' then
    -- Remove Java/Maven references
    text = text:gsub('import%s+[%w%.]+;', ' import ')
    text = text:gsub('package%s+[%w%.]+;', ' package ')
    text = text:gsub('mvn%s+[%w]+', ' maven command ')
  end
  
  return text
end

function M.remove_emoji(text)
  -- Remove emoji and emoji-like symbols that are problematic for TTS.
  --
  -- NOTE: LuaJIT pattern ranges work on individual bytes, not Unicode code
  -- points. Using \\u{} escapes inside character ranges like [\\u{1F600}-\\u{1F64F}]
  -- creates broken ranges because multi-byte characters place the hyphen
  -- boundary at an arbitrary byte position (e.g. \\x80-\\xF0), catching ALL
  -- continuation bytes. We avoid this by using explicit UTF-8 byte sequences
  -- for each emoji block instead.
  
  -- Emoticons / Ornamental Dingbats (U+1F600-U+1F67F)
  text = text:gsub('\xF0\x9F[\x98-\x99][\x80-\xBF]', '')
  -- Misc Symbols and Pictographs (U+1F300-U+1F5FF)
  text = text:gsub('\xF0\x9F[\x8C-\x97][\x80-\xBF]', '')
  -- Transport and Map (U+1F680-U+1F6FF)
  text = text:gsub('\xF0\x9F[\x9A-\x9B][\x80-\xBF]', '')
  -- Dingbats (U+2700-U+27BF) — hearts, stars, check marks, crosses, etc.
  text = text:gsub('\xE2[\x9C-\x9E][\x80-\xBF]', '')
  -- Misc Symbols (U+2600-U+26FF) — weather, zodiac, chess, etc.
  text = text:gsub('\xE2[\x98-\x9B][\x80-\xBF]', '')
  -- Regional Indicators (U+1F1E0-U+1F1FF)
  text = text:gsub('\xF0\x9F\x87[\xA0-\xBF]', '')
  -- Supplemental Symbols and Pictographs (U+1F900-U+1F9FF)
  text = text:gsub('\xF0\x9F[\xA4-\xA7][\x80-\xBF]', '')
  -- Symbols Extended-A (U+1FA70-U+1FAFF)
  text = text:gsub('\xF0\x9F[\xA9-\xAB][\x80-\xBF]', '')
  
  -- Skin tone modifiers (U+1F3FB-U+1F3FF)
  text = text:gsub('\xF0\x9F\x8F[\xBB-\xBF]', '')
  -- Zero-width joiner (U+200D)
  text = text:gsub('\xE2\x80\x8D', '')
  -- Variation selector-16 (U+FE0F)
  text = text:gsub('\xEF\xB8\x8F', '')
  
  return text
end

function M.expand_abbreviations(text)
  local abbreviations = {
    ['e%.g%.'] = 'for example',
    ['i%.e%.'] = 'that is',
    ['etc%.'] = 'etcetera',
    ['vs%.'] = 'versus',
    ['Dr%.'] = 'Doctor',
    ['Mr%.'] = 'Mister',
    ['Mrs%.'] = 'Missus',
    ['Ms%.'] = 'Miss',
    ['Prof%.'] = 'Professor',
    ['Sr%.'] = 'Senior',
    ['Jr%.'] = 'Junior',
  }
  
  for pattern, replacement in pairs(abbreviations) do
    text = text:gsub(pattern, replacement)
  end
  
  return text
end

function M.chunk_text(text, chunk_size)
  chunk_size = chunk_size or 500
  local chunks = {}
  local current_pos = 1
  local text_len = #text
  
  while current_pos <= text_len do
    local chunk_end = math.min(current_pos + chunk_size - 1, text_len)
    
    if chunk_end < text_len then
      local space_pos = text:find('%s', chunk_end)
      if space_pos and space_pos - chunk_end < 50 then
        chunk_end = space_pos - 1
      elseif chunk_end > current_pos then
        for i = chunk_end, current_pos, -1 do
          if text:sub(i, i):match('%s') then
            chunk_end = i - 1
            break
          end
        end
      end
    end
    
    if chunk_end < current_pos then
      chunk_end = current_pos
    end

    chunk_end = chunk_end + vim.str_utf_end(text, chunk_end)
    
    local chunk = text:sub(current_pos, chunk_end)
    table.insert(chunks, vim.trim(chunk))
    current_pos = chunk_end + 1
    
    while current_pos <= text_len and text:sub(current_pos, current_pos):match('%s') do
      current_pos = current_pos + 1
    end
  end
  
  return chunks
end

local function is_speakable(piece)
  return piece:match('[^%s%p]') ~= nil
end

local function group_lines(text, lines_per_segment)
  local group_size = math.max(1, math.floor(tonumber(lines_per_segment) or 1))
  local segments = {}
  local group = {}

  for line in text:gmatch('[^\n]+') do
    line = vim.trim(line)
    if is_speakable(line) then
      table.insert(group, line)
      if #group == group_size then
        table.insert(segments, table.concat(group, '\n'))
        group = {}
      end
    end
  end

  if #group > 0 then
    table.insert(segments, table.concat(group, '\n'))
  end

  return segments
end

function M.split_segments(text)
  if not text or text:match('^%s*$') then
    return {}
  end

  local playback = require('tts.config').get().playback
  local mode = playback.segmentation or 'sentence'

  if mode == 'none' then
    return { vim.trim(text) }
  end

  if mode == 'line' then
    return group_lines(text, playback.lines_per_segment)
  end

  local segments = {}
  for line in text:gmatch('[^\n]+') do
    local pos = 1
    while true do
      local s, e = line:find('[%.!%?]["%)%]]*%s+', pos)
      if not s then
        break
      end
      table.insert(segments, vim.trim(line:sub(pos, e)))
      pos = e + 1
    end
    table.insert(segments, vim.trim(line:sub(pos)))
  end

  local result = {}
  for _, piece in ipairs(segments) do
    if is_speakable(piece) then
      if #piece > playback.chunk_size then
        for _, chunk in ipairs(M.chunk_text(piece, playback.chunk_size)) do
          if is_speakable(chunk) then
            table.insert(result, chunk)
          end
        end
      else
        table.insert(result, piece)
      end
    end
  end

  return result
end

function M.group_source_lines(lines, start_line)
  local config = require('tts.config').get()
  local playback = config.playback
  local mode = playback.segmentation or 'sentence'

  local group_size
  if mode == 'line' then
    group_size = math.max(1, math.floor(tonumber(playback.lines_per_segment) or 1))
  elseif mode == 'none' then
    group_size = math.huge
  else
    group_size = 1
  end

  local skip_code = config.preprocessing and config.preprocessing.skip_code_blocks
  local groups = {}
  local group, first, last = {}, nil, nil
  local in_fence = false

  local function flush()
    if #group > 0 then
      table.insert(groups, {
        text = table.concat(group, '\n'),
        first = first,
        last = last,
      })
    end
    group, first, last = {}, nil, nil
  end

  for i, line in ipairs(lines) do
    local buf_line = start_line + i - 1
    local skip = false

    if skip_code then
      if line:match('^%s*```') or line:match('^%s*~~~') then
        in_fence = not in_fence
        skip = true
      elseif in_fence then
        skip = true
      end
    end

    if not skip and is_speakable(line) then
      if not first then
        first = buf_line
      end
      last = buf_line
      table.insert(group, line)
      if #group >= group_size then
        flush()
      end
    end
  end

  flush()

  return groups
end

function M.notify(message, level)
  level = level or vim.log.levels.INFO
  local config = require('tts.config').get().notifications
  
  if level < config.level then
    return
  end
  
  if config.use_notify then
    local ok, notify = pcall(require, 'notify')
    if ok then
      notify(message, level, {
        title = 'TTS',
        timeout = 3000,
        render = 'default'
      })
      return
    end
  end
  
  vim.notify('[TTS] ' .. message, level)
end

function M.echo_lines(lines)
  vim.api.nvim_echo({ { table.concat(lines, '\n') } }, true, {})
end

function M.progress(message, percentage)
  local config = require('tts.config').get().playback
  
  if not config.show_progress then
    return
  end
  
  if percentage then
    message = string.format('%s (%.0f%%)', message, percentage)
  end
  
  vim.g.tts_progress = message or ''
  vim.cmd('redrawstatus')
end



return M
