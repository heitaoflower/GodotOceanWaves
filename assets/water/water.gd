@tool
extends MeshInstance3D
## Handles updating the displacement/normal maps for the water material as well as
## managing wave generation pipelines.

const WATER_MAT := preload('res://assets/water/mat_water.tres')
const WATER_MESH_HIGH := preload('res://assets/water/clipmap_high.obj')
const WATER_MESH_LOW := preload('res://assets/water/clipmap_low.obj')

enum MeshQuality { LOW, HIGH }

@export_group('Wave Parameters')
@export_color_no_alpha var water_color : Color = Color(0.1, 0.15, 0.18) :
	set(value): water_color = value; WATER_MAT.set_shader_parameter('water_color', water_color)

@export_color_no_alpha var foam_color : Color = Color(0.73, 0.67, 0.62) :
	set(value): foam_color = value; WATER_MAT.set_shader_parameter('foam_color', foam_color)

## The parameters for wave cascades. Each parameter set represents one cascade.
@export var parameters : Array[WaveCascadeParameters] :
	set(value):
		var new_size := len(value)
		# All below logic is basically just required for using in the editor!
		for i in range(new_size):
			# Ensure all values in the array have an associated cascade
			if not value[i]: value[i] = WaveCascadeParameters.new()
			value[i].spectrum_seed = Vector2i(rng.randi_range(-10000, 10000), rng.randi_range(-10000, 10000))
			value[i].time = 120.0 + PI*i # We make sure to choose a time offset such that cascades don't interfere!
		parameters = value
		map_scales.resize(new_size)
		_setup_wave_generator()

@export_group('Performance Parameters')
@export_enum('128x128:128', '256x256:256', '512x512:512', '1024x1024:1024') var map_size := 1024 :
	set(value):
		map_size = value
		_setup_wave_generator()

@export var mesh_quality := MeshQuality.HIGH :
	set(value):
		mesh_quality = value
		mesh = WATER_MESH_HIGH if mesh_quality == MeshQuality.HIGH else WATER_MESH_LOW

## How many times the wave simulation should update per second.
## Note: This doesn't reduce the frame stutter caused by FFT calculation, only
##       minimizes GPU time taken by it!
@export_range(0, 60) var updates_per_second := 50.0 :
	set(value):
		next_update_time = next_update_time - (1.0/(updates_per_second + 1e-10) - 1.0/(value + 1e-10))
		updates_per_second = value

var wave_generator : WaveGenerator :
	set(value):
		if wave_generator: wave_generator.queue_free()
		wave_generator = value
		add_child(wave_generator)
var displacement_maps := Texture2DArrayRD.new()
var normal_maps := Texture2DArrayRD.new()
var map_scales : PackedVector2Array
var rng = RandomNumberGenerator.new()
var time := 0.0
var next_update_time := 0.0

func _init() -> void:
	rng.set_seed(1234)

func _process(delta : float) -> void:
	# Update waves once every 1.0/updates_per_second.
	if updates_per_second == 0 or time >= next_update_time:
		var target_update_delta := 1.0 / (updates_per_second + 1e-10)
		var update_delta := delta if updates_per_second == 0 else target_update_delta + (time - next_update_time)
		next_update_time = time + target_update_delta
		_update_water(update_delta)
	time += delta

func _setup_wave_generator() -> void:
	if parameters.size() <= 0: return
	for param in parameters:
		param.should_generate_spectrum = true

	wave_generator = WaveGenerator.new()
	wave_generator.map_size = map_size
	wave_generator.init_gpu(maxi(2, parameters.size())) # FIXME: This is needed because my RenderContext API sucks...

	displacement_maps.texture_rd_rid = RID()
	normal_maps.texture_rd_rid = RID()
	displacement_maps.texture_rd_rid = wave_generator.descriptors['displacement_map'].rid
	normal_maps.texture_rd_rid = wave_generator.descriptors['normal_map'].rid

	WATER_MAT.set_shader_parameter('num_cascades', parameters.size())
	WATER_MAT.set_shader_parameter('displacements', displacement_maps)
	WATER_MAT.set_shader_parameter('normals', normal_maps)

func _update_water(delta : float) -> void:
	if wave_generator == null: _setup_wave_generator()
	wave_generator.update(delta, parameters)

	for i in len(parameters):
		map_scales[i] = Vector2.ONE / parameters[i].tile_length
	WATER_MAT.set_shader_parameter('map_scales', map_scales)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		displacement_maps.texture_rd_rid = RID()
		normal_maps.texture_rd_rid = RID()