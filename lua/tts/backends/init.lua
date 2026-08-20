local M = {}
local current_backend = nil

function M.init()
	local config = require('tts.config').get()

	if config.backend == 'auto' then
		current_backend = M._auto_detect()
	else
		current_backend = M._load_backend(config.backend)
	end

	if not current_backend then
		vim.notify('No TTS backend available', vim.log.levels.ERROR)
	end
end

function M._auto_detect()
	local backends = { 'macos', 'openai' }

	for _, name in ipairs(backends) do
		local backend = M._load_backend(name)
		if backend and backend.is_available() then
			-- Silent auto-detection
			return backend
		end
	end

	return nil
end

function M._load_backend(name)
	local ok, backend = pcall(require, 'tts.backends.' .. name)
	if ok then
		backend.name = name
		return backend
	end
	return nil
end

function M.get_current()
	return current_backend
end

function M.set(name)
	local backend = M._load_backend(name)
	if backend and backend.is_available() then
		current_backend = backend
		-- Silent switch
		return true
	else
		vim.notify('TTS: Backend ' .. name .. ' is not available', vim.log.levels.ERROR)
		return false
	end
end

function M.speak(text, opts)
	if not current_backend then
		vim.notify('No TTS backend available', vim.log.levels.ERROR)
		return nil
	end

	local state = require('tts.state')
	state.transition('playing', { text = text })

	vim.api.nvim_exec_autocmds('User', {
		pattern = 'TTSPlayStart',
		data = { text = text, backend = current_backend.name }
	})

	return current_backend.speak(text, opts)
end

function M.stop(opts)
	if current_backend and current_backend.stop then
		current_backend.stop(opts)

		local state = require('tts.state')
		state.transition('stopped')
	end
end



function M.prefetch(text, opts)
  if not current_backend or not current_backend.prefetch then
    return
  end
  current_backend.prefetch(text, opts)
end

function M.list_voices()
	if current_backend and current_backend.list_voices then
		return current_backend.list_voices()
	end
	return {}
end

function M.get_backend_name()
	return current_backend and current_backend.name or 'none'
end

return M

