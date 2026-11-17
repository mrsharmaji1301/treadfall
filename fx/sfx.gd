extends RefCounted
## Sound. Every sound is a file in assets/audio/, as NAME.ogg or NAME.wav
## (ogg wins if both exist). A missing file is simply silent, so sounds can
## be swapped or added one at a time. World sounds are 3D: they come from
## where they happen and fade with distance.

static var _streams: Dictionary = {}
## Where the player's tank is. Loudness is worked out from here, along the
## ground, so it is the same whatever the camera is doing.
static var ears := Vector3.ZERO
const NEAR := 7.0
const FAR := 75.0


## How much quieter (in dB) a sound at `pos` is for the player.
static func fall(pos: Vector3) -> float:
	var d: float = Vector2(pos.x - ears.x, pos.z - ears.z).length()
	if d <= NEAR:
		return 0.0
	if d >= FAR:
		return -80.0
	var db: float = -20.0 * log(d / NEAR) / log(10.0)
	# The last stretch fades right out.
	return db - 40.0 * smoothstep(FAR * 0.7, FAR, d)


static func stream(name: String, looped: bool = false) -> AudioStream:
	if _streams.has(name):
		return _streams[name]
	var found = null
	for ext in ["ogg", "wav", "mp3"]:
		var path := "res://assets/audio/%s.%s" % [name, ext]
		if ResourceLoader.exists(path):
			var res = load(path)
			if res is AudioStream:
				found = res
				break
	if found != null and looped:
		if found is AudioStreamWAV:
			found.loop_mode = AudioStreamWAV.LOOP_FORWARD
			found.loop_begin = 0
			found.loop_end = int(found.get_length() * found.mix_rate)
		elif found is AudioStreamOggVorbis or found is AudioStreamMP3:
			found.loop = true
	_streams[name] = found
	return found


static func _player(name: String, looped: bool, volume_db: float) -> AudioStreamPlayer3D:
	var s := stream(name, looped)
	if s == null:
		return null
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.volume_db = volume_db
	# The engine's own distance falloff goes by the camera, which is far
	# away in the map view. So it is off, and `fall` sets the loudness
	# instead. The player still places the sound left and right.
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	p.max_distance = 0.0
	p.max_db = 0.0
	p.attenuation_filter_db = 0.0
	return p


## One-shot sound at a place in the 3D world.
static func at(view: Node, name: String, pos: Vector3, volume_db: float = 0.0,
		pitch: float = 1.0) -> void:
	if view == null or not view.is_inside_tree():
		return
	var p := _player(name, false, volume_db)
	if p == null:
		return
	p.pitch_scale = pitch * randf_range(0.94, 1.06)
	p.position = pos
	p.volume_db = volume_db + fall(pos)
	if p.volume_db < -70.0:
		p.free()
		return
	view.add_child(p)
	p.play()
	p.finished.connect(p.queue_free)


## Looping sound that travels with `parent`. Returns null if the file is missing.
static func loop(parent: Node3D, name: String, volume_db: float) -> AudioStreamPlayer3D:
	var p := _player(name, true, volume_db)
	if p == null:
		return null
	# A player can only start once it is in the scene. Models are built
	# before they are added, so those start by themselves on entering.
	p.autoplay = not parent.is_inside_tree()
	parent.add_child(p)
	if parent.is_inside_tree():
		p.play(randf() * maxf(p.stream.get_length(), 0.01))
	return p


## Plain sound that is not in the world: alarms, pick-up chimes.
static func flat(owner: Node, name: String, volume_db: float = 0.0) -> void:
	var s := stream(name)
	if s == null or owner == null or not owner.is_inside_tree():
		return
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.volume_db = volume_db
	owner.add_child(p)
	p.play()
	p.finished.connect(p.queue_free)
