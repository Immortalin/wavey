
localforage = require "localforage"

module.exports =
class AudioClipStorage
	
	@audio_buffers = {}
	@recordings = {}
	@loading = {}
	@errors = {}
	
	throttle = 0
	
	@load_clip = (clip, InfoBar)=>
		return if AudioClipStorage.audio_buffers[clip.audio_id]?
		return if AudioClipStorage.loading[clip.audio_id]?
		
		AudioClipStorage.loading[clip.audio_id] = yes
		
		fail_warn = (error_message)->
			AudioClipStorage.errors[clip.audio_id] = error_message
			InfoBar.warn error_message
			# TODO: button on infobar to remove broken clips
			# including when showing errors via AudioClipStorage.errors[clip.audio_id]
			# maybe that should be a map of clip ids to functions that show infobars
			# maybe internal, with API like has_error(clip) show_error(clip)
			# load_clip would probably take a callback for removing broken clips
			# (not just the one clip) and it would be undoable
		
		if clip.recording_id?
			localforage.getItem "recording:#{clip.recording_id}", (err, recording)=>
				if err
					InfoBar.error "Failed to load recording.\n#{err.message}"
					throw err
				else if recording
					AudioClipStorage.recordings[clip.recording_id] = recording
					chunks = [[], []]
					total_loaded_chunks = 0
					for channel_chunk_ids, channel_index in recording.chunk_ids
						for chunk_id, chunk_index in channel_chunk_ids
							do (channel_chunk_ids, channel_index, chunk_id, chunk_index)=>
								# timeout because of DOMException: The transaction was aborted, so the request cannot be fulfilled.
								# Internal error: Too many transactions queued.
								# https://code.google.com/p/chromium/issues/detail?id=338800
								setTimeout ->
									localforage.getItem "recording:#{clip.recording_id}:chunk:#{chunk_id}", (err, typed_array)=>
										if err
											InfoBar.error "Failed to load part of a recording.\n#{err.message}"
											throw err
										else if typed_array
											chunks[channel_index][chunk_index] = typed_array
											total_loaded_chunks += 1
											throttle -= 1 # this will not unthrottle anything during the document load
											if total_loaded_chunks is recording.chunk_ids.length * channel_chunk_ids.length
												recording.chunks = chunks
												render()
										else
											fail_warn "Part of a recording is missing from storage."
											console.warn "A chunk of a recording (chunk_id: #{chunk_id}) is missing from storage.", clip, recording
								, throttle += 1
						if channel_chunk_ids.length is 0 and channel_index is recording.chunk_ids.length - 1
							recording.chunks = chunks
							render()
				else
					fail_warn "A recording is missing from storage."
					console.warn "A recording is missing from storage. clip:", clip
		else
			localforage.getItem "audio:#{clip.audio_id}", (err, array_buffer)=>
				if err
					InfoBar.error "Failed to load audio data.\n#{err.message}"
					throw err
				else if array_buffer
					actx.decodeAudioData array_buffer, (buffer)=>
						AudioClipStorage.audio_buffers[clip.audio_id] = buffer
						InfoBar.hide "Not all tracks have finished loading."
						render()
				else
					fail_warn "An audio clip is missing from storage."
					console.warn "An audio clip is missing from storage. clip:", clip
	
	@load_clips = (tracks, InfoBar)->
		for track in tracks when track.type is "audio"
			for clip in track.clips
				@load_clip clip, InfoBar
