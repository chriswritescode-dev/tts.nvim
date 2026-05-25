local M = {}
local current_job = nil
local current_player = nil

local function detect_player()
	local config = require('tts.config').get().playback

	if config.player ~= 'auto' then
		if vim.fn.executable(config.player) == 1 then
			return config.player
		end
	end

	local players = { 'afplay', 'mpv', 'ffplay', 'play' }

	for _, player in ipairs(players) do
		if vim.fn.executable(player) == 1 then
			return player
		end
	end

	return nil
end

function M.play(audio_source, opts)
	opts = opts or {}
	local state = require('tts.state')

	if not state.can_play() and not opts.force then
		M.stop()
	end

	local player = detect_player()
	if not player then
		vim.notify('No audio player found', vim.log.levels.ERROR)
		return nil
	end

	current_player = player

	if player == 'afplay' then
		return M._play_with_afplay(audio_source, opts)
	elseif player == 'mpv' then
		return M._play_with_mpv(audio_source, opts)
	elseif player == 'ffplay' then
		return M._play_with_ffplay(audio_source, opts)
	elseif player == 'play' then
		return M._play_with_sox(audio_source, opts)
	end
end

function M._play_with_afplay(file, opts)
	local args = { file }

	if opts.volume then
		table.insert(args, '-v')
		table.insert(args, tostring(opts.volume))
	end

	current_job = vim.loop.spawn('afplay', {
		args = args
	}, function(code)
		current_job = nil
		vim.schedule(function()
			if code == 0 then
				local state = require('tts.state')
				state.transition('idle')
			end
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

function M._play_with_mpv(file, opts)
	local args = {
		'--no-video',
		'--no-terminal',
		'--force-window=no'
	}

	if opts.volume then
		table.insert(args, '--volume=' .. tostring(opts.volume * 100))
	end

	if opts.speed then
		table.insert(args, '--speed=' .. tostring(opts.speed))
	end

	table.insert(args, file)

	current_job = vim.loop.spawn('mpv', {
		args = args
	}, function(code)
		current_job = nil
		vim.schedule(function()
			if code == 0 then
				local state = require('tts.state')
				state.transition('idle')
			end
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

function M._play_with_ffplay(file, opts)
	local args = {
		'-nodisp',
		'-autoexit',
		'-loglevel', 'quiet'
	}

	if opts.volume then
		table.insert(args, '-volume')
		table.insert(args, tostring(math.floor(opts.volume * 100)))
	end

	table.insert(args, file)

	current_job = vim.loop.spawn('ffplay', {
		args = args
	}, function(code)
		current_job = nil
		vim.schedule(function()
			if code == 0 then
				local state = require('tts.state')
				state.transition('idle')
			end
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

function M._play_with_sox(file, opts)
	local args = { file }

	if opts.volume then
		table.insert(args, 'vol')
		table.insert(args, tostring(opts.volume))
	end

	current_job = vim.loop.spawn('play', {
		args = args
	}, function(code)
		current_job = nil
		vim.schedule(function()
			if code == 0 then
				local state = require('tts.state')
				state.transition('idle')
			end
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
	if current_job then
		if not current_job:is_closing() then
			current_job:kill('sigterm')
		end
		current_job = nil
	end
	local state = require('tts.state')
	state.transition('stopped')

	return true
end

function M.is_playing()
	return current_job ~= nil
end

function M.get_current_player()
	return current_player
end

return M
