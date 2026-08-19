local M = {}

M.defaults = {
	backend = 'auto',

	macos = {
		voice = 'Alex',
		rate = 200,
		volume = 0.5,
		audio_device = nil,
		pitch = nil,
		modulation = nil,
	},

	openai = {
		api_key = vim.env.OPENAI_API_KEY,
		api_url = 'https://api.openai.com/v1/audio/speech',
		model = 'tts-1',
		voice = 'alloy',
		speed = 1.0,
		format = 'mp3',
		headers = {},
		timeout = 30,
	},

	playback = {
		auto_clear_queue = false,
		show_progress = true,
		chunk_size = 500,
		pause_between_chunks = 0,
		player = 'auto',
		player_args = {},
		default_selection = 'buffer',
		follow = true,
		segmentation = 'line',
		lines_per_segment = 5,
	},

	cache = {
		enabled = true,
		directory = vim.fn.stdpath('cache') .. '/tts',
		max_size = 100,
		max_age = 7,
		cleanup_on_start = true,
		prefetch_next = true,
	},

	keymaps = {
		play = '<leader>tp',
		stop = '<leader>ts',
		queue = '<leader>tq',
		clear = '<leader>tc',
		next = '<leader>tn',
		prev = '<leader>tN',
		visual_play = '<leader>tp',
	},

	preprocessing = {
		clean_markdown = true, -- Remove markdown syntax
		clean_code = false, -- Convert code symbols to spoken words for better TTS readability
		filtering_level = 'moderate', -- Content filtering level: 'none', 'minimal', 'moderate', 'aggressive'
		expand_abbreviations = true,
		skip_code_blocks = false, -- Read code blocks by default
		remove_emoji = true, -- Remove emoji and symbols for TTS compatibility
		add_line_breaks = false, -- Add periods at end of lines for natural pauses
		replacements = {
			['TODO:?'] = 'todo item',
			['FIXME:?'] = 'fix me item',
			['NOTE:?'] = 'note',
			['WARNING:?'] = 'warning',
			['TIP:?'] = 'tip',
			['==='] = ' equals ',
			['=='] = ' equals ',
			['='] = ' equals ',
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
				['==='] = 'strictly equals',
				['!=='] = 'not strictly equal',
			},
		},
	},

	hooks = {
		before_play = nil,
		after_play = nil,
		on_error = function(err)
			vim.notify('TTS Error: ' .. err, vim.log.levels.ERROR)
		end,
		on_queue_item = nil,
	},

	notifications = {
		level = vim.log.levels.INFO,
		use_notify = false,
	},

}

local config = vim.deepcopy(M.defaults)

function M.setup(opts)
	local previous = config
	config = vim.tbl_deep_extend('force', M.defaults, opts or {})
	local ok, err = pcall(M.validate)
	if not ok then
		config = previous
		error(err, 0)
	end
end

function M.get()
	return config
end

function M.validate()
	vim.validate({
		backend = { config.backend, 'string' },
		macos = { config.macos, 'table' },
		openai = { config.openai, 'table' },
		playback = { config.playback, 'table' },
		cache = { config.cache, 'table' },
		keymaps = { config.keymaps, 'table' },
		preprocessing = { config.preprocessing, 'table' },
		hooks = { config.hooks, 'table' },
		notifications = { config.notifications, 'table' },
	})

	if config.backend ~= 'auto' and config.backend ~= 'macos' and config.backend ~= 'openai' then
		error("backend must be 'auto', 'macos', or 'openai'")
	end

	if config.playback.segmentation ~= 'sentence' and config.playback.segmentation ~= 'line' and config.playback.segmentation ~= 'none' then
		error("playback.segmentation must be 'sentence', 'line', or 'none'")
	end

	if config.playback.chunk_size and (type(config.playback.chunk_size) ~= 'number' or config.playback.chunk_size < 1) then
		error("playback.chunk_size must be a positive number")
	end

	if config.playback.lines_per_segment and (type(config.playback.lines_per_segment) ~= 'number' or config.playback.lines_per_segment < 1) then
		error("playback.lines_per_segment must be a positive number")
	end

	if config.openai.speed and (config.openai.speed < 0.25 or config.openai.speed > 4.0) then
		error("openai.speed must be between 0.25 and 4.0")
	end

	if config.cache.max_size and config.cache.max_size < 0 then
		error("cache.max_size must be positive")
	end
end

return M
