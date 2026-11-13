extends AudioStreamPlayer

const SAMPLE_RATE := 44100
var clips := {}
var pellet_voice := AudioStreamPlayer.new()

func _ready() -> void:
	volume_db = -10
	pellet_voice.volume_db = -15
	add_child(pellet_voice)
	# Each note has a starting frequency, ending frequency and duration in seconds.
	clips["dot"] = chip_sound([[570, 230, 0.075]], 0.38)
	clips["dot2"] = chip_sound([[255, 490, 0.068]], 0.38)
	clips["item"] = chip_sound([[660, 660, 0.065], [880, 880, 0.10]], 0.56)
	clips["reward"] = chip_sound([[523, 523, 0.07], [784, 784, 0.07], [988, 988, 0.08], [1175, 1175, 0.18]], 0.60)
	clips["power"] = chip_sound([[196, 196, 0.09], [294, 294, 0.08], [392, 392, 0.08], [587, 784, 0.17]], 0.78)
	clips["capture"] = chip_sound([[440, 690, 0.055], [660, 990, 0.065], [880, 1320, 0.13]], 0.64)
	clips["death"] = chip_sound([[622, 523, 0.11], [494, 392, 0.12], [370, 277, 0.14], [247, 92, 0.34]], 0.58)
	clips["clear"] = chip_sound([[523, 523, 0.09], [659, 659, 0.09], [784, 784, 0.09], [1047, 1047, 0.24]], 0.74)

func chip_sound(notes: Array, brightness: float) -> AudioStreamWAV:
	var samples := PackedByteArray()
	for note: Array in notes:
		var count := roundi(SAMPLE_RATE * float(note[2]))
		var offset := samples.size()
		samples.resize(offset + count * 2)
		var phase := 0.0
		for i in count:
			var t := float(i) / (count - 1)
			var frequency := float(note[0]) * pow(float(note[1]) / float(note[0]), t)
			phase += TAU * frequency / SAMPLE_RATE
			# Blend rounded triangle and hollow square tones using their first odd harmonics.
			var third := sin(3 * phase)
			var fifth := sin(5 * phase)
			var triangle := sin(phase) - third / 9.0 + fifth / 25.0
			var square := sin(phase) + third / 3.0 + fifth / 5.0 + sin(7 * phase) / 7.0
			var tone := lerpf(triangle, square, brightness * (1.0 - 0.55 * t))
			var attack := minf(1.0, i / (0.003 * SAMPLE_RATE))
			var release := minf(1.0, (count - 1 - i) / (0.014 * SAMPLE_RATE))
			samples.encode_s16(offset + i * 2, roundi(23000 * tone * attack * release * (1.0 - 0.32 * t)))
	var clip := AudioStreamWAV.new()
	clip.format = AudioStreamWAV.FORMAT_16_BITS
	clip.mix_rate = SAMPLE_RATE
	clip.data = samples
	return clip

func cue(key: String) -> void:
	var voice := pellet_voice if key in ["dot", "dot2"] else self
	voice.stream = clips[key]
	voice.play()
