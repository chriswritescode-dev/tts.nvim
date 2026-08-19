# tts.nvim

A comprehensive text-to-speech plugin for Neovim with support for macOS native speech synthesis and OpenAI-compatible TTS endpoints. This plugin allows you to have your text read aloud directly within Neovim. I created it for use with [obsidian.nvim](https://github.com/epwalsh/obsidian.nvim). I did not find anything else like it.

## TL;DR

```lua
-- Quick setup with auto-detection
require('tts').setup()

-- Or specific backend
require('tts').setup({
  backend = 'macos',  -- or 'openai'
  macos = { voice = 'Samantha', rate = 200 }
})

```

## Features

- **Multi-backend Support**: Native macOS `say` command and OpenAI API
- **Smart Text Selection**: Visual mode, line/paragraph/section/buffer, and motion-based selection
- **Intelligent Content Filtering**: Removes paths, URLs, and technical content for better TTS
- **Playback Control**: Play and stop with basic state management
- **Segment Playback**: A selection is split into segments and played in order, with next/prev navigation between them. In `line` mode a segment is a group of `lines_per_segment` lines (5 by default), so next/prev jumps a whole group rather than a single line
- **Segment Following**: When playing from a buffer, the cursor jumps to the current segment and its lines are highlighted with the `TTSSegment` group (linked to `Visual` by default). Disable with `playback.follow = false`
- **Audio Caching**: The OpenAI-compatible backend caches each segment's audio (keyed by text, endpoint, model, voice, speed and format), so replaying a segment costs no HTTP request
- **Text Preprocessing**: Clean code comments, expand abbreviations, language-specific replacements

- **Customizable**: Extensive configuration options, hooks, and keymaps

## Requirements

- Neovim 0.7+
- macOS (for native TTS) or OpenAI API key (for OpenAI TTS)

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  'yourusername/tts.nvim',
  config = function()
    require('tts').setup({
      -- Backend selection: 'auto', 'macos', 'openai'
      backend = 'auto',

      -- macOS configuration
      macos = {
        voice = 'Alex',
        rate = 200,              -- 75-720 words per minute
        volume = 0.5,            -- 0.0-1.0
        audio_device = nil,      -- Custom audio device
        pitch = nil,             -- Voice pitch
        modulation = nil,        -- Voice modulation
      },

      -- OpenAI configuration
      openai = {
        api_key = vim.env.OPENAI_API_KEY,
        api_url = 'https://api.openai.com/v1/audio/speech',
        model = 'tts-1',         -- or 'tts-1-hd'
        voice = 'alloy',         -- alloy, echo, fable, onyx, nova, shimmer
        speed = 1.0,             -- 0.25-4.0
        format = 'mp3',          -- mp3, opus, aac, flac
        headers = {},            -- Custom headers
        timeout = 30,            -- Request timeout in seconds
      },

      -- Playback behavior
      playback = {
        auto_clear_queue = false,
        show_progress = true,
        segmentation = 'line',               -- Split text into segments: 'line', 'sentence', or 'none'
        lines_per_segment = 5,               -- 'line' mode only: how many lines make up one segment
        chunk_size = 500,                    -- Max segment length before a segment is split further ('sentence' mode only)
        pause_between_chunks = 0,            -- Delay between segments on natural advance only (seconds)
        player = 'auto',                     -- Audio player: 'auto', 'mpv', 'ffplay', etc.
        player_args = {},                    -- Custom player arguments
        default_selection = 'buffer',       -- Default text selection: 'line', 'paragraph', 'section', 'buffer'
        follow = true,                       -- Move the cursor to the playing segment and highlight its lines
      },

      -- Cache settings
      cache = {
        enabled = true,
        directory = vim.fn.stdpath('cache') .. '/tts',
        max_size = 100,          -- MB
        max_age = 7,             -- days
        cleanup_on_start = true,
        prefetch_next = true,    -- Warm the next segment while the current one plays
      },

      -- Custom keymaps
      keymaps = {
        play = '<leader>tp',
        stop = '<leader>ts',
        queue = '<leader>tq',
        clear = '<leader>tc',
        next = '<leader>tn',
        prev = '<leader>tN',
        visual_play = '<leader>tp',
      },

      -- Text preprocessing
      preprocessing = {
        clean_markdown = true,           -- Remove markdown syntax
        clean_code = false,              -- Remove code comments
        filtering_level = 'moderate',    -- 'none', 'minimal', 'moderate', 'aggressive'
        expand_abbreviations = true,
        skip_code_blocks = true,         -- Skip code blocks entirely
        replacements = {
          -- Task markers
          ['TODO:?'] = 'todo item',
          ['FIXME:?'] = 'fix me item',
          ['NOTE:?'] = 'note',
          ['WARNING:?'] = 'warning',
          ['TIP:?'] = 'tip',

          -- Technical acronyms
          ['API'] = 'A P I',
          ['URL'] = 'U R L',
          ['HTTP'] = 'H T T P',
          ['JSON'] = 'J son',
          ['SQL'] = 'S Q L',
          ['CSS'] = 'C S S',
          ['HTML'] = 'H T M L',
          ['JS'] = 'javascript',
          ['TS'] = 'TypeScript',
          ['AI'] = 'artificial intelligence',
          ['TL;DR'] = 'too long did not read',

          -- Common abbreviations
          ['etc.'] = 'etcetera',
          ['i.e.'] = 'that is',
          ['e.g.'] = 'for example',

          -- Custom identifiers
          -- ['MyApp'] = 'my app',
          -- ['BigCorp'] = 'big corp',
        },
        languages = {
          lua = {
            ['~='] = 'not equal',
            ['%.%.'] = 'concatenate',
          },
          python = {
            ['!='] = 'not equal',
            ['//'] = 'integer divide',
          },
          javascript = {
            ['=>'] = 'arrow function',
            ['==='] = 'strict equals',
            ['!=='] = 'strict not equals',
          },
          rust = {
            ['fn '] = 'function ',
            ['mut '] = 'mutable ',
            ['impl '] = 'implementation ',
          },
        },
      },

      -- Hooks
      hooks = {
        before_play = nil,              -- function(text) return modified_text end
        after_play = nil,               -- function(text) end; fires once when the whole run finishes
        on_state_change = nil,          -- function(new_state, old_state) end
        on_error = function(err)
          vim.notify('TTS Error: ' .. err, vim.log.levels.ERROR)
        end,
        on_queue_item = nil,            -- function(item, index, total) end; fires per segment
      },

      -- Notifications
      notifications = {
        level = vim.log.levels.INFO,
        use_notify = false,             -- Use vim.notify for notifications
      },
    })
  end
}
```

Cached audio files live in `cache.directory` (default `vim.fn.stdpath('cache') .. '/tts'`), one file per segment named `<sha256>.<format>`, alongside an `index.json` manifest. When `cache.cleanup_on_start` is true, entries older than `cache.max_age` days are deleted on the next startup sweep, and the total size is capped at `cache.max_size` MB with least-recently-used eviction. `:TTSClearCache` (`tts.clear_cache()`) empties the cache immediately, and `tts.get_cache_stats()` reports size, file count and hits. Setting `cache.enabled = false` disables storage entirely and falls back to per-play temp files.

Using [packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
use {
  'yourusername/tts.nvim',
  config = function()
    require('tts').setup({
      -- Same configuration as above
    })
  end
}
```

## Quick Start

### Basic Setup

```lua
require('tts').setup()  -- Uses defaults with auto-detection
```

### macOS Setup

```lua
require('tts').setup({
  backend = 'macos',
  macos = {
    voice = 'Samantha',  -- or 'Alex', 'Victoria', etc.
    rate = 200           -- words per minute
  }
})
```

### Content Filtering Levels

- **`none`**: No additional filtering
- **`minimal`**: Remove paths and URLs only
- **`moderate`**: Remove paths, URLs, UUIDs, versions, emails, IPs (default)
- **`aggressive`**: All of the above plus code-specific content

## Usage

### Commands

- `:TTS [text]` - Speak the provided text or current selection
- `:TTSPlay` - Play current selection, or the whole file when nothing is selected
- `:TTSStop` - Stop current playback

- `:TTSQueue [text]` - Append extra text to the current run, or show the queue when called without text
- `:TTSClear` - Clear the queue
- `:TTSNext` - Skip to the next segment (accepts a count, e.g. `3:TTSNext`)
- `:TTSPrev` - Go to the previous segment (accepts a count, e.g. `3:TTSPrev`)
- `:TTSBackend <name>` - Switch backend (macos/openai)
- `:TTSVoices` - List available voices
- `:TTSSetVoice <voice>` - Set voice for current backend
- `:TTSClearCache` - Clear audio cache
- `:TTSMotion <motion>` - Speak text based on vim motion

### Default Keymaps

- `<leader>tp` - Play selection, or the whole file when nothing is selected
- `<leader>ts` - Stop playback

- `<leader>tq` - Add to queue / show queue
- `<leader>tc` - Clear queue
- `<leader>tn` - Skip N segments forward (`3<leader>tn` jumps 3 segments)
- `<leader>tN` - Skip N segments back (`3<leader>tN` jumps back 3 segments)

### Usage Examples

#### Visual Mode

1. Select text in visual mode
2. Press `<leader>tp` or run `:TTSPlay`

#### Current Line

1. Place cursor on a line
2. Press `<leader>tp` or run `:TTSPlay`

#### Current Paragraph

```lua
-- Configure to use paragraph by default
require('tts').setup({
  playback = {
    default_selection = 'paragraph'
  }
})
```

#### With Motions

```vim
:TTSMotion w    " Speak word
:TTSMotion }    " Speak to next paragraph
:TTSMotion G    " Speak to end of file
```

#### Queue Management

```vim
" Play the current selection as a new run (replaces any previous run)
:TTSPlay

" Append extra text to the current run; starts playing when idle
:TTSQueue First paragraph
:TTSQueue Second paragraph

" Show the queue
:TTSQueue
```

## Advanced Features

### Content Processing

The plugin intelligently processes text before speaking:

#### Pattern Replacement System

The `replacements` configuration can replace any identifiers or patterns with spoken alternatives:

```lua
replacements = {
  -- Technical acronyms
  ["API"] = "A P I",
  ["URL"] = "U R L",
  ["HTTP"] = "H T T P",
  ["JSON"] = "J son",

  -- Project-specific identifiers
  ["MyApp"] = "my app",
  ["BigCorp"] = "big corp",

  -- Custom terminology
  ["foobar"] = "foo bar",
  ["widget"] = "wid get",
}
```

#### Markdown Processing

- Code blocks: ` ```code...``` ` → `" code block "`
- Inline code: `` `code` `` → `" code "`
- Links: `[text](url)` → `"text"`
- Headers: `# Header` → `"Header"`
- Emphasis: `**bold**`, `*italic*` → plain text

#### Smart Content Filtering

- **Paths**: `/path/to/file`, `C:\Windows` → `" file path "`
- **URLs**: `https://example.com` → `" url "`
- **Git references**: `HEAD~1`, commit hashes → `" git reference "`
- **UUIDs**: `550e8400-e29b-41d4-a716-446655440000` → `" uuid "`
- **Versions**: `v1.2.3` → `" version "`
- **Emails**: `user@example.com` → `" email address "`
- **IPs**: `192.168.1.1` → `" ip address "`

#### Code-Specific Filtering (aggressive level)

- **JavaScript**: npm packages, imports
- **Python**: pip packages, imports
- **Lua**: require statements, variables
- **Rust**: cargo commands, use statements
- **Go**: go commands, imports
- **Java**: Maven commands, imports

### Backend Details

#### macOS Backend

Uses the built-in `say` command:

- Requires macOS
- No API key needed
- Multiple system voices available
- Fast, local processing
- Caching and prefetching are inert: audio is synthesized locally by `say`, so nothing is stored on disk or warmed ahead

#### OpenAI-Compatible Backend

Uses OpenAI-compatible TTS API (official OpenAI, Kokoro FastAPI, etc.):

- API key required for official OpenAI, optional for self-hosted services
- High-quality voices (varies by service)
- Multiple voice options (alloy, echo, fable, onyx, nova, shimmer for OpenAI)
- Audio caching: each segment's audio is cached, keyed by text plus endpoint, model, voice, speed and format, so replaying a segment costs no HTTP request
- Supports custom endpoints and self-hosted services

### User Autocmds

The plugin fires `User` autocmds you can listen to with `vim.api.nvim_create_autocmd('User', { pattern = ..., callback = ... })`:

- `TTSPlayStart` / `TTSPlayEnd` fire once **per segment** — the current text and backend are passed as `data` on start, the backend name on end.
- `TTSQueueUpdate` fires for run-level UI: its `data` carries `action` (`set`, `add`, `play`, `stop`, `finish`, `clear`, `remove`) plus `index` and `count` when relevant (a `play` event includes both).

### API Reference

```lua
local tts = require("tts")

-- Basic usage
tts.play("Hello world")
tts.play_selection()
tts.stop()


-- Queue management
tts.queue_add("Text to queue")
tts.queue_clear()
tts.queue_list()

-- Backend control
tts.set_backend("openai")
tts.get_backend()
tts.list_voices()
tts.set_voice("alloy")

-- Cache management
tts.clear_cache()
tts.get_cache_stats()
```
