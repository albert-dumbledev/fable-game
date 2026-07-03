class_name SpitterEnemy
extends EnemyBase
## Ranged enemy: keeps its distance and spits projectiles. Overrides the
## chase/attack behavior; all the state plumbing comes from EnemyBase.

const RETREAT_RANGE := 4.0

@export var projectile_scene: PackedScene


func _chase() -> void:
	var to_target := _target.global_position - global_position
	to_target.y = 0.0
	var dist := to_target.length()
	if dist < RETREAT_RANGE:
		var away := -to_target.normalized()
		velocity.x = away.x * data.move_speed
		velocity.z = away.z * data.move_speed
		return
	if dist <= data.attack_range:
		_begin_windup()
		return
	var toward := to_target.normalized()
	velocity.x = toward.x * data.move_speed
	velocity.z = toward.z * data.move_speed


func _begin_attack() -> void:
	_set_state(State.ATTACK)
	if _material != null:
		_kill_color_tween()
		_material.albedo_color = _base_color
	# Spit animation reuses the fist as a gland recoil.
	_tween_fist(FIST_PUNCH, ATTACK_ACTIVE_TIME * 0.5)
	if projectile_scene == null or _target == null:
		return
	var projectile := projectile_scene.instantiate() as Projectile
	if projectile == null:
		return
	var spawn_pos := global_position + Vector3(0.0, 1.2, 0.0) \
			- global_transform.basis.z * 0.8
	var aim := _target.global_position + Vector3(0.0, 1.0, 0.0) - spawn_pos
	projectile.setup(AttackInfo.new(self, data.damage * _dmg_mult), aim)
	get_tree().current_scene.add_child(projectile)
	projectile.global_position = spawn_pos
