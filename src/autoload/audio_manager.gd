extends Node
## "Audio" autoload. play_sfx("shoot") looks for res://assets/audio/sfx/shoot.wav
## (or .ogg). play_music("odd_duck_theme") for res://assets/audio/music/<name>.*
## Missing files are silently ignored so placeholder audio can be swapped freely.

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"
const EXTENSIONS := ["ogg", "wav", "mp3"]
const POOL_SIZE := 10

var music_volume_db := -8.0
var sfx_volume_db := -4.0

var _music: AudioStreamPlayer
var _music_name := ""
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _cache: Dictionary = {}  # path -> AudioStream (or null if missing)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_music = AudioStreamPlayer.new()
	_music.volume_db = music_volume_db
	_music.finished.connect(func(): _music.play())  # loop fallback for non-looping streams
	add_child(_music)
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.volume_db = sfx_volume_db
		add_child(p)
		_pool.append(p)
	apply_volumes()


## Reads volumes from Game.settings (Game autoloads before Audio).
func apply_volumes() -> void:
	music_volume_db = float(Game.settings.get("music_db", music_volume_db))
	sfx_volume_db = float(Game.settings.get("sfx_db", sfx_volume_db))
	if _music:
		_music.volume_db = music_volume_db


func play_sfx(sfx_name: String, pitch_jitter: float = 0.08, volume_offset: float = 0.0) -> void:
	var stream := _find(SFX_DIR, sfx_name)
	if stream == null:
		return
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = stream
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.volume_db = sfx_volume_db + volume_offset
	p.play()


func play_music(music_name: String, fade_time: float = 0.8) -> void:
	if music_name == _music_name and _music.playing:
		return
	var stream := _find(MUSIC_DIR, music_name)
	_music_name = music_name
	if stream == null:
		_music.stop()
		return
	if stream is AudioStreamWAV:
		var wav: AudioStreamWAV = stream
		if wav.loop_mode == AudioStreamWAV.LOOP_DISABLED:
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			wav.loop_end = roundi(wav.get_length() * wav.mix_rate)
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	var tw := create_tween()
	if _music.playing:
		tw.tween_property(_music, "volume_db", -40.0, fade_time * 0.5)
	tw.tween_callback(func():
		_music.stream = stream
		_music.play())
	tw.tween_property(_music, "volume_db", music_volume_db, fade_time * 0.5)


func stop_music() -> void:
	_music.stop()
	_music_name = ""


func _find(dir: String, base_name: String) -> AudioStream:
	var key := dir + base_name
	if _cache.has(key):
		return _cache[key]
	var found: AudioStream = null
	for ext in EXTENSIONS:
		var path := "%s%s.%s" % [dir, base_name, ext]
		if ResourceLoader.exists(path):
			found = load(path) as AudioStream
			break
	_cache[key] = found
	return found
