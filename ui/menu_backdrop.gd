class_name MenuBackdrop
extends Node3D
## Main-menu diorama: a lean copy of the arena look (twilight environment,
## shader floor, walls, and the shared ArenaDecor dressing) with a slow
## orbiting camera. Lives inside a SubViewport behind the menu UI — the
## theme sells itself before the first run. No gameplay nodes, no collision.

const FLOOR_SHADER := preload("res://levels/floor.gdshader")
const ORBIT_RADIUS := 13.0
const ORBIT_HEIGHT := 5.5
const ORBIT_SPEED := 0.06
const LOOK_TARGET := Vector3(0.0, 1.2, 0.0)

var _camera: Camera3D
var _angle := 0.0
var _environment: Environment
var _sun: DirectionalLight3D


func _ready() -> void:
	_build_environment()
	_build_arena_shell()
	add_child(ArenaDecor.new())
	_camera = Camera3D.new()
	_camera.fov = 70.0
	add_child(_camera)
	_update_camera()
	Settings.changed.connect(_apply_graphics)
	_apply_graphics()


## The backdrop renders in its own SubViewport, which the root viewport's
## render scale doesn't reach — mirror the graphics settings here.
func _apply_graphics() -> void:
	_environment.glow_enabled = Settings.glow_enabled
	_sun.shadow_enabled = Settings.shadows_enabled
	var viewport := get_viewport()
	if viewport != null:
		viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		viewport.scaling_3d_scale = Settings.render_scale


func _process(delta: float) -> void:
	_angle += ORBIT_SPEED * delta
	_update_camera()


func _update_camera() -> void:
	_camera.position = Vector3(
		cos(_angle) * ORBIT_RADIUS, ORBIT_HEIGHT, sin(_angle) * ORBIT_RADIUS)
	_camera.look_at(LOOK_TARGET)


## Same dusk-colosseum settings as Arena.tscn's WorldEnvironment; kept in
## sync by hand — if the arena look changes, change this too.
func _build_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.05, 0.06, 0.15)
	sky_material.sky_horizon_color = Color(0.58, 0.29, 0.17)
	sky_material.sky_curve = 0.09
	sky_material.ground_bottom_color = Color(0.02, 0.02, 0.04)
	sky_material.ground_horizon_color = Color(0.42, 0.21, 0.13)
	var sky := Sky.new()
	sky.sky_material = sky_material
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.31, 0.29, 0.4)
	environment.ambient_light_energy = 1.1
	environment.glow_enabled = true
	environment.glow_intensity = 0.7
	environment.glow_bloom = 0.04
	environment.glow_hdr_threshold = 1.05
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.23, 0.17, 0.27)
	environment.fog_density = 0.01
	environment.fog_sky_affect = 0.15
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	_environment = environment
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.72, 0.5)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-28.0, 35.0, 0.0)
	add_child(sun)
	_sun = sun


## Floor + walls as meshes only (the decor node brings the rest).
func _build_arena_shell() -> void:
	var floor_material := ShaderMaterial.new()
	floor_material.shader = FLOOR_SHADER
	var floor_plane := PlaneMesh.new()
	floor_plane.size = Vector2(40.0, 40.0)
	floor_plane.material = floor_material
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = floor_plane
	add_child(floor_mesh)
	var wall_material := StandardMaterial3D.new()
	wall_material.albedo_color = Color(0.19, 0.18, 0.23)
	wall_material.roughness = 0.95
	for i: int in 4:
		var along_x := i < 2
		var wall_box := BoxMesh.new()
		wall_box.size = Vector3(41.0, 4.0, 1.0) if along_x else Vector3(1.0, 4.0, 41.0)
		wall_box.material = wall_material
		var wall := MeshInstance3D.new()
		wall.mesh = wall_box
		add_child(wall)
		var sign_dir := -1.0 if i % 2 == 0 else 1.0
		wall.position = Vector3(0.0, 2.0, sign_dir * 20.0) if along_x \
				else Vector3(sign_dir * 20.0, 2.0, 0.0)
