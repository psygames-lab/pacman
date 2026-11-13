extends AudioStreamPlayer

var clips := {}

func _ready() -> void:
	volume_db = -17
	for spec in [["dot", 520, 270, 0.055], ["dot2", 270, 520, 0.055], ["power", 200, 750, 0.3],
			["capture", 480, 1350, 0.24], ["death", 700, 80, 0.55], ["clear", 330, 1120, 0.5]]:
		var count := int(22050 * float(spec[3]))
		var samples := PackedByteArray()
		samples.resize(count * 2)
		var phase := 0.0
		for i in count:
			var t := float(i) / count
			phase += TAU * lerpf(spec[1], spec[2], t) / 22050.0
			var envelope := minf(1, t * 35) * minf(1, (1 - t) * 10)
			samples.encode_s16(i * 2, int(20000 * sin(phase) * envelope))
		var clip := AudioStreamWAV.new()
		clip.format = AudioStreamWAV.FORMAT_16_BITS
		clip.mix_rate = 22050
		clip.data = samples
		clips[spec[0]] = clip

func cue(key: String) -> void:
	stream = clips[key]
	play()
