class_name ArenaDecor
extends Node3D
## Procedural arena dressing, built once at load: perimeter pillars, torch
## sconces with flickering omni lights, a silhouette ring of spires beyond
## the walls, and a moon. Pure visuals — nothing here has collision, and
## nothing intrudes into the play space beyond a pillar's few cm of relief,
## so enemy steering and the boss charge keep their clear lanes.

const WALL_HALF := 20.0
const PILLAR_SIZE := 1.5
const PILLAR_HEIGHT := 5.4
## Wall-relative pillar offsets: one every 8 m, corners handled separately.
const PILLAR_OFFSETS: Array[float] = [-16.0, -8.0, 0.0, 8.0, 16.0]
const TORCH_HEIGHT := 3.1
const TORCH_INSET := 0.8
const TORCH_LIGHT_COLOR := Color(1.0, 0.62, 0.3)
const TORCH_LIGHT_ENERGY := 1.6
const TORCH_LIGHT_RANGE := 10.0
const SPIRE_COUNT := 26
const SPIRE_COLOR := Color(0.045, 0.045, 0.09)
const MOON_COLOR := Color(0.85, 0.88, 1.0)

var _flames: Array[MeshInstance3D] = []
var _torch_lights: Array[OmniLight3D] = []
var _flicker_phases: PackedFloat32Array = PackedFloat32Array()
var _rng := RandomNumberGenerator.new()
var _time := 0.0


func _ready() -> void:
	# Fixed seed: the backdrop should look identical every run.
	_rng.seed = 0x0F4B13
	_build_pillars()
	_build_torches()
	_build_spires()
	_build_moon()


## Torch flicker: two detuned sines per light so the pool of warm light
## wobbles organically. Eight lights, trivial per-frame cost.
func _process(delta: float) -> void:
	_time += delta
	for i: int in _torch_lights.size():
		var phase := _flicker_phases[i]
		var flicker := 0.86 + 0.1 * sin(_time * 9.0 + phase) \
				+ 0.06 * sin(_time * 23.0 + phase * 1.7)
		_torch_lights[i].light_energy = TORCH_LIGHT_ENERGY * flicker
		_flames[i].scale = Vector3.ONE * (0.92 + 0.1 * sin(_time * 11.0 + phase))


## Square pillars riding the wall line, taller than the walls so the
## silhouette reads as a colosseum rim against the sky.
func _build_pillars() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.22, 0.21, 0.26)
	material.roughness = 0.9
	var mesh := BoxMesh.new()
	mesh.size = Vector3(PILLAR_SIZE, PILLAR_HEIGHT, PILLAR_SIZE)
	mesh.material = material
	var positions: Array[Vector3] = []
	for offset: float in PILLAR_OFFSETS:
		positions.append(Vector3(offset, 0.0, -WALL_HALF))
		positions.append(Vector3(offset, 0.0, WALL_HALF))
		positions.append(Vector3(-WALL_HALF, 0.0, offset))
		positions.append(Vector3(WALL_HALF, 0.0, offset))
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			positions.append(Vector3(sx * WALL_HALF, 0.0, sz * WALL_HALF))
	for pos: Vector3 in positions:
		var pillar := MeshInstance3D.new()
		pillar.mesh = mesh
		add_child(pillar)
		pillar.position = pos + Vector3(0.0, PILLAR_HEIGHT * 0.5, 0.0)


## Eight sconces — wall midpoints + corners — each a bracket, an emissive
## flame blob, and a warm flickering omni light (no shadows: eight shadowed
## omnis would be a Compatibility-renderer perf trap).
func _build_torches() -> void:
	var flame_material := StandardMaterial3D.new()
	flame_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_material.albedo_color = Color(1.0, 0.55, 0.2)
	flame_material.emission_enabled = true
	flame_material.emission = Color(1.0, 0.5, 0.15)
	flame_material.emission_energy_multiplier = 3.5
	var flame_mesh := SphereMesh.new()
	flame_mesh.radius = 0.14
	flame_mesh.height = 0.4
	flame_mesh.material = flame_material
	var bracket_material := StandardMaterial3D.new()
	bracket_material.albedo_color = Color(0.1, 0.09, 0.11)
	bracket_material.roughness = 0.8
	var bracket_mesh := BoxMesh.new()
	bracket_mesh.size = Vector3(0.16, 0.55, 0.16)
	bracket_mesh.material = bracket_material

	var inset := WALL_HALF - TORCH_INSET
	var positions: Array[Vector3] = [
		Vector3(0.0, TORCH_HEIGHT, -inset), Vector3(0.0, TORCH_HEIGHT, inset),
		Vector3(-inset, TORCH_HEIGHT, 0.0), Vector3(inset, TORCH_HEIGHT, 0.0),
		Vector3(-inset, TORCH_HEIGHT, -inset), Vector3(inset, TORCH_HEIGHT, -inset),
		Vector3(-inset, TORCH_HEIGHT, inset), Vector3(inset, TORCH_HEIGHT, inset),
	]
	for pos: Vector3 in positions:
		var torch := Node3D.new()
		add_child(torch)
		torch.position = pos
		var bracket := MeshInstance3D.new()
		bracket.mesh = bracket_mesh
		bracket.position = Vector3(0.0, -0.35, 0.0)
		bracket.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		torch.add_child(bracket)
		var flame := MeshInstance3D.new()
		flame.mesh = flame_mesh
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		torch.add_child(flame)
		_flames.append(flame)
		var light := OmniLight3D.new()
		light.light_color = TORCH_LIGHT_COLOR
		light.light_energy = TORCH_LIGHT_ENERGY
		light.omni_range = TORCH_LIGHT_RANGE
		light.position = Vector3(0.0, 0.25, 0.0)
		torch.add_child(light)
		_torch_lights.append(light)
		_flicker_phases.append(_rng.randf() * TAU)


## Jagged dark monoliths ringing the arena beyond the walls — unshaded so
## they read as pure silhouettes against the dusk sky, hazed by the fog.
func _build_spires() -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = SPIRE_COLOR
	for i: int in SPIRE_COUNT:
		var angle := (float(i) + _rng.randf_range(-0.3, 0.3)) * TAU / float(SPIRE_COUNT)
		var dist := _rng.randf_range(30.0, 48.0)
		var height := _rng.randf_range(7.0, 22.0)
		var width := _rng.randf_range(1.5, 4.0)
		var mesh := BoxMesh.new()
		mesh.size = Vector3(width, height, width)
		mesh.material = material
		var spire := MeshInstance3D.new()
		spire.mesh = mesh
		spire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(spire)
		spire.position = Vector3(
			cos(angle) * dist, height * 0.5 - 1.0, sin(angle) * dist)
		spire.rotation_degrees = Vector3(
			_rng.randf_range(-3.0, 3.0),
			_rng.randf_range(0.0, 360.0),
			_rng.randf_range(-3.0, 3.0))


## An unshaded emissive sphere reads as a flat pale disc from any angle —
## a moon with zero texture assets. Fog is disabled on it so it doesn't
## drown at backdrop distance; placed opposite the sun's yaw.
func _build_moon() -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = MOON_COLOR
	material.emission_enabled = true
	material.emission = MOON_COLOR
	material.emission_energy_multiplier = 1.4
	material.disable_fog = true
	var sphere := SphereMesh.new()
	sphere.radius = 11.0
	sphere.height = 22.0
	sphere.material = material
	var moon := MeshInstance3D.new()
	moon.mesh = sphere
	moon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(moon)
	moon.position = Vector3(-95.0, 62.0, -150.0)
