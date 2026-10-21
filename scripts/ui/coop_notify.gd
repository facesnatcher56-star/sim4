class_name CoopNotify
extends RefCounted
## "Come back" signals for a co-op player who is on autopilot (idle) when something big happens: the window flashes in the task bar, a short
## two-note chime plays (SFX bus, so Mute / volume settings apply) and the alert box pulses. The host marks such alerts with `loud` in the alert data.

const RATE := 22050

## Two soft notes, 0.35 s in all, as an in-memory sound (no asset).
static func chime() -> AudioStreamWAV:
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	var n := int(RATE * 0.35)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		var t := float(i) / RATE
		var hz := 660.0 if t < 0.16 else 880.0
		var local := t if t < 0.16 else t - 0.16
		var env := minf(1.0, local * 80.0) * exp(-local * 9.0)          # quick attack, soft decay
		bytes.encode_s16(i * 2, int(clampf(sin(TAU * hz * t) * env * 0.5, -1.0, 1.0) * 32767.0))
	s.data = bytes
	return s

## Flash the window, chime, and pulse `box` (when given and motion is allowed). Safe in headless / dummy audio.
static func attention(owner: Node, box: Control = null) -> void:
	DisplayServer.window_request_attention()
	if owner != null and is_instance_valid(owner) and owner.is_inside_tree():
		var p := AudioStreamPlayer.new()
		p.stream = chime()
		p.bus = "SFX" if AudioServer.get_bus_index("SFX") >= 0 else "Master"
		p.finished.connect(p.queue_free)
		owner.add_child(p)
		p.play()
	if box != null and is_instance_valid(box) and not GameSettings.reduce_motion():
		var tw := box.create_tween()
		for i in 3:
			tw.tween_property(box, "modulate", Color(1.5, 1.5, 1.5), 0.25)
			tw.tween_property(box, "modulate", Color.WHITE, 0.25)
