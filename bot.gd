extends CharacterBody3D

# ==================================================
# BOT / NPC DE COMBATE
# --------------------------------------------------
# Inimigos e aliados controlados por IA:
#   - patrulham um objetivo (site, spike ou zona de deathmatch)
#   - veem o alvo por raycast (não veem através de paredes)
#   - disparam em rajadas com precisão dependente da dificuldade
#   - reagem a flash (cegueira) e a recon (marcados)
#   - desviam de obstáculos e destravam-se sozinhos
# Tudo modelado por código, com cores do agente escolhido.
# ==================================================

signal died(bot, killer)
signal damaged(bot, amount, attacker)

const GRAVITY := 18.0
const ACCEL := 26.0
const UP := Vector3.UP

# Identidade / equipa
var team := "defense"
var display_name := "BOT"
var agent: Dictionary = {}
var difficulty := 1
var profile: Dictionary = {}
var frozen := true
var dead := false
var kills := 0
var deaths := 0

# Stats
var max_hp := 100.0
var hp := 100.0
var max_armor := 50.0
var armor := 50.0
var move_speed := 4.7
var accuracy := 0.76
var reaction_time := 0.42
var shot_damage := 26.0
var fire_interval := 0.30

# Navegação
var roam_center := Vector3.ZERO
var roam_radius := 14.0
var waypoint := Vector3.ZERO
var has_waypoint := false
var wait_t := 0.0
var stuck_t := 0.0
var last_pos := Vector3.ZERO
var spawned_at := Vector3.ZERO

# Combate
var target = null
var bot_brain: RefCounted
var target_visible := false
var think_t := 0.0
var reaction_t := 0.0
var fire_t := 0.0
var burst_left := 0
var burst_pause := 0.0
var strafe_dir := 1.0
var strafe_t := 0.0
var blind_t := 0.0
var mark_t := 0.0
var aim_pitch := 0.0

# Visual
var body_root: Node3D
var head_node: Node3D
var gun_root: Node3D
var muzzle_light: OmniLight3D
var hp_bg: MeshInstance3D
var hp_fill: MeshInstance3D
var hp_fill_mat: StandardMaterial3D
var beacon: Node3D
var blind_dome: MeshInstance3D
var tag: Label3D
var tracer_mat: StandardMaterial3D
var flash_mesh: MeshInstance3D

# ==================================================
# CONFIGURAÇÃO (chamada antes de add_child)
# ==================================================

func setup(cfg: Dictionary) -> void:
	team = str(cfg.get("team", "defense"))
	display_name = str(cfg.get("name", "BOT"))
	agent = cfg.get("agent", {})
	if agent.is_empty():
		agent = GameState.get_agent("jett")
	difficulty = int(cfg.get("difficulty", 1))
	profile = GameState.difficulty_profile(difficulty)

	max_hp = float(profile.get("hp", 100.0))
	hp = max_hp
	max_armor = float(agent.get("armor", 50))
	armor = max_armor
	move_speed = float(profile.get("speed", 4.7))
	accuracy = float(profile.get("accuracy", 0.76))
	reaction_time = float(profile.get("reaction", 0.42))
	shot_damage = 26.0 * float(profile.get("damage", 1.0))

	roam_center = cfg.get("roam_center", Vector3.ZERO)
	roam_radius = float(cfg.get("roam_radius", 14.0))

# ==================================================
# READY
# ==================================================

func _ready():
	add_to_group("bot")
	add_to_group("enemy" if team == "defense" else "ally")
	_setup_csharp_brain()
	collision_layer = 1
	collision_mask = 1

	var cs := CollisionShape3D.new()
	cs.name = "Body"
	var cap := CapsuleShape3D.new()
	cap.radius = 0.40
	cap.height = 1.80
	cs.shape = cap
	cs.position = Vector3(0, 0.9, 0)
	add_child(cs)

	_build_visuals()
	spawned_at = global_position
	if roam_center == Vector3.ZERO:
		roam_center = global_position
	last_pos = global_position
	_pick_waypoint()
	_update_hp_bar()

# ==================================================
# VISUAL PROCEDURAL
# ==================================================

func _mat(color: Color, emission := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.6
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	return m

func _mesh(mesh: Mesh, mat: Material, pos: Vector3, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi

func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b

func _build_visuals():
	body_root = Node3D.new()
	add_child(body_root)

	var suit: Color = agent.get("color", Color(0.4, 0.8, 1.0))
	var accent: Color = agent.get("accent", Color(0.9, 0.95, 1.0))
	var dark := Color(0.06, 0.08, 0.10)

	# tronco
	var torso := CapsuleMesh.new()
	torso.radius = 0.33
	torso.height = 1.30
	torso.radial_segments = 12
	_mesh(torso, _mat(suit.darkened(0.15), 0.15), Vector3(0, 0.98, 0), body_root)

	# faixa de equipa no peito
	_mesh(_box(Vector3(0.42, 0.10, 0.30)), _mat(GameState.team_color(team), 1.2), Vector3(0, 1.18, -0.14), body_root)

	# pernas
	_mesh(_box(Vector3(0.17, 0.72, 0.20)), _mat(dark), Vector3(-0.13, 0.36, 0), body_root)
	_mesh(_box(Vector3(0.17, 0.72, 0.20)), _mat(dark), Vector3(0.13, 0.36, 0), body_root)

	# braços
	_mesh(_box(Vector3(0.14, 0.58, 0.16)), _mat(suit.darkened(0.25)), Vector3(-0.38, 1.05, 0), body_root)
	_mesh(_box(Vector3(0.14, 0.58, 0.16)), _mat(suit.darkened(0.25)), Vector3(0.38, 1.05, 0), body_root)

	# Camadas táticas adicionais: placas, bolsos, joelheiras e equipamento.
	_build_agent_armor(suit, accent, dark)

	# cabeça
	head_node = Node3D.new()
	head_node.position = Vector3(0, 1.66, 0)
	body_root.add_child(head_node)
	var sph := SphereMesh.new()
	sph.radius = 0.19
	sph.height = 0.38
	_mesh(sph, _mat(accent, 0.25), Vector3.ZERO, head_node)
	# viseira
	_mesh(_box(Vector3(0.30, 0.09, 0.05)), _mat(dark), Vector3(0, 0.02, -0.17), head_node)

	# arma
	gun_root = Node3D.new()
	gun_root.position = Vector3(0.26, 1.28, -0.32)
	body_root.add_child(gun_root)
	_mesh(_box(Vector3(0.08, 0.10, 0.52)), _mat(Color(0.12, 0.14, 0.17)), Vector3.ZERO, gun_root)
	_mesh(_box(Vector3(0.05, 0.05, 0.26)), _mat(Color(0.32, 0.36, 0.42)), Vector3(0, 0.01, -0.34), gun_root)
	_mesh(_box(Vector3(0.06, 0.14, 0.10)), _mat(Color(0.09, 0.10, 0.12)), Vector3(0, -0.10, 0.10), gun_root)

	# Componentes visíveis da arma: carregador, mira, guarda-mão e cano.
	_mesh(_box(Vector3(0.055, 0.17, 0.12)), _mat(Color(0.075, 0.085, 0.10)), Vector3(0, -0.12, -0.02), gun_root)
	_mesh(_box(Vector3(0.075, 0.045, 0.11)), _mat(Color(0.24, 0.28, 0.32), 0.08), Vector3(0, 0.075, -0.10), gun_root)
	_mesh(_box(Vector3(0.045, 0.045, 0.12)), _mat(Color(0.08, 0.09, 0.11)), Vector3(0, 0.085, -0.13), gun_root)
	_mesh(_box(Vector3(0.095, 0.065, 0.20)), _mat(Color(0.16, 0.19, 0.22)), Vector3(0, 0.0, -0.29), gun_root)
	_mesh(_box(Vector3(0.035, 0.035, 0.18)), _mat(accent.darkened(0.2), 0.12), Vector3(0, 0.055, -0.29), gun_root)

	muzzle_light = OmniLight3D.new()
	muzzle_light.light_color = Color(1.0, 0.78, 0.4)
	muzzle_light.omni_range = 7.0
	muzzle_light.light_energy = 0.0
	muzzle_light.shadow_enabled = false
	muzzle_light.position = Vector3(0, 0.01, -0.48)
	gun_root.add_child(muzzle_light)

	var quad := QuadMesh.new()
	quad.size = Vector2(0.26, 0.26)
	flash_mesh = _mesh(quad, _flash_material(), Vector3(0, 0.01, -0.50), gun_root)
	flash_mesh.visible = false

	# barra de vida
	var bg_quad := QuadMesh.new()
	bg_quad.size = Vector2(0.78, 0.09)
	hp_bg = _mesh(bg_quad, _billboard_mat(Color(0.02, 0.03, 0.04, 0.85)), Vector3(0, 2.02, 0), body_root)
	var fill_quad := QuadMesh.new()
	fill_quad.size = Vector2(0.74, 0.06)
	hp_fill_mat = _billboard_mat(GameState.team_color(team))
	hp_fill = _mesh(fill_quad, hp_fill_mat, Vector3(0, 2.02, 0.001), body_root)

	# nome
	tag = Label3D.new()
	tag.text = "%s\n%s" % [display_name, str(agent.get("name", ""))]
	tag.font_size = 44
	tag.pixel_size = 0.0042
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.modulate = GameState.team_color(team)
	tag.outline_size = 10
	tag.outline_modulate = Color(0, 0, 0, 0.85)
	tag.position = Vector3(0, 2.24, 0)
	tag.no_depth_test = false
	body_root.add_child(tag)

	# marcador de recon (visível quando marcado)
	beacon = Node3D.new()
	beacon.position = Vector3(0, 2.55, 0)
	beacon.visible = false
	body_root.add_child(beacon)
	var cone := CylinderMesh.new()
	cone.bottom_radius = 0.16
	cone.top_radius = 0.0
	cone.height = 0.34
	_mesh(cone, _mat(Color(1.0, 0.25, 0.3), 2.5), Vector3.ZERO, beacon)

	# cúpula de cegueira
	var dome := SphereMesh.new()
	dome.radius = 0.34
	dome.height = 0.68
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.albedo_color = Color(1, 1, 1, 0.55)
	blind_dome = _mesh(dome, dm, Vector3(0, 1.68, 0), body_root)
	blind_dome.visible = false

	tracer_mat = StandardMaterial3D.new()
	tracer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tracer_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tracer_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	tracer_mat.albedo_color = Color(1.0, 0.85, 0.55, 0.85)


func _build_agent_armor(suit: Color, accent: Color, dark: Color) -> void:
	# Peitoral em duas camadas e placas laterais.
	var armor_mat := _mat(suit.darkened(0.32))
	var trim_mat := _mat(accent.darkened(0.18), 0.12)
	var fabric_mat := _mat(suit.darkened(0.08))
	_mesh(_box(Vector3(0.48, 0.46, 0.12)), armor_mat, Vector3(0, 1.12, -0.205), body_root)
	_mesh(_box(Vector3(0.30, 0.12, 0.035)), trim_mat, Vector3(0, 1.22, -0.274), body_root)
	_mesh(_box(Vector3(0.12, 0.30, 0.10)), armor_mat, Vector3(-0.25, 1.05, -0.02), body_root)
	_mesh(_box(Vector3(0.12, 0.30, 0.10)), armor_mat, Vector3(0.25, 1.05, -0.02), body_root)

	# Ombreiras, proteções dos antebraços e luvas.
	_mesh(_box(Vector3(0.23, 0.18, 0.22)), trim_mat, Vector3(-0.39, 1.31, 0), body_root)
	_mesh(_box(Vector3(0.23, 0.18, 0.22)), trim_mat, Vector3(0.39, 1.31, 0), body_root)
	_mesh(_box(Vector3(0.18, 0.25, 0.19)), armor_mat, Vector3(-0.43, 0.91, -0.01), body_root)
	_mesh(_box(Vector3(0.18, 0.25, 0.19)), armor_mat, Vector3(0.43, 0.91, -0.01), body_root)
	_mesh(_box(Vector3(0.17, 0.13, 0.18)), _mat(dark), Vector3(-0.43, 0.72, -0.01), body_root)
	_mesh(_box(Vector3(0.17, 0.13, 0.18)), _mat(dark), Vector3(0.43, 0.72, -0.01), body_root)

	# Cinto modular e bolsas laterais.
	_mesh(_box(Vector3(0.48, 0.12, 0.28)), _mat(dark), Vector3(0, 0.73, 0), body_root)
	_mesh(_box(Vector3(0.11, 0.16, 0.12)), fabric_mat, Vector3(-0.29, 0.72, -0.015), body_root)
	_mesh(_box(Vector3(0.11, 0.16, 0.12)), fabric_mat, Vector3(0.29, 0.72, -0.015), body_root)
	_mesh(_box(Vector3(0.10, 0.11, 0.035)), trim_mat, Vector3(0, 0.73, -0.15), body_root)

	# Joelheiras e botas reforçadas.
	_mesh(_box(Vector3(0.20, 0.18, 0.24)), trim_mat, Vector3(-0.13, 0.28, -0.045), body_root)
	_mesh(_box(Vector3(0.20, 0.18, 0.24)), trim_mat, Vector3(0.13, 0.28, -0.045), body_root)
	_mesh(_box(Vector3(0.22, 0.16, 0.34)), _mat(dark), Vector3(-0.13, 0.09, -0.055), body_root)
	_mesh(_box(Vector3(0.22, 0.16, 0.34)), _mat(dark), Vector3(0.13, 0.09, -0.055), body_root)

	# Mochila compacta e antena de comunicação.
	_mesh(_box(Vector3(0.34, 0.48, 0.17)), fabric_mat, Vector3(0, 1.08, 0.205), body_root)
	_mesh(_box(Vector3(0.25, 0.12, 0.06)), armor_mat, Vector3(0, 1.28, 0.30), body_root)
	_mesh(_box(Vector3(0.035, 0.28, 0.035)), trim_mat, Vector3(0.17, 1.48, 0.23), body_root)


func _billboard_mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = color
	m.no_depth_test = false
	return m

func _flash_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = Color(1.0, 0.8, 0.4, 1.0)
	return m

# ==================================================
# LOOP
# ==================================================

func _physics_process(delta):
	if dead:
		return

	if frozen:
		velocity = Vector3.ZERO
		return

	blind_t = maxf(0.0, blind_t - delta)
	mark_t = maxf(0.0, mark_t - delta)
	if blind_dome:
		blind_dome.visible = blind_t > 0.0
	if beacon:
		beacon.visible = mark_t > 0.0
		beacon.rotate_y(delta * 2.5)

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif velocity.y < 0.0:
		velocity.y = -0.1

	_think(delta)
	_move(delta)
	_try_fire(delta)

	move_and_slide()

	if muzzle_light and muzzle_light.light_energy > 0.0:
		muzzle_light.light_energy = maxf(0.0, muzzle_light.light_energy - delta * 40.0)
		if muzzle_light.light_energy <= 0.0 and flash_mesh:
			flash_mesh.visible = false

# ---------- PERCEÇÃO ----------

func _candidates() -> Array:
	var out: Array = []
	out.append_array(get_tree().get_nodes_in_group("bot"))
	out.append_array(get_tree().get_nodes_in_group("player"))
	return out

func _team_of(n) -> String:
	if n == null:
		return ""
	var t = n.get("team")
	return str(t) if t != null else ""

func _setup_csharp_brain() -> void:
	# Classes C# [GlobalClass] ficam registadas no ClassDB depois da
	# compilação da assembly pelo editor Godot .NET.
	if not ClassDB.class_exists("BotBrain"):
		push_warning("BotBrain C# não está compilado. A IA vai usar o fallback GDScript.")
		return

	var instance: Object = ClassDB.instantiate("BotBrain")
	if instance is RefCounted:
		bot_brain = instance as RefCounted
	else:
		push_warning("Não foi possível criar BotBrain. A IA vai usar o fallback GDScript.")
		if is_instance_valid(instance):
			instance.free()


func _acquire_target():
	var best = null
	var best_score := -1.0e20
	for n in _candidates():
		if n == self or not is_instance_valid(n) or not (n is Node3D):
			continue
		var dd = n.get("dead")
		if dd != null and bool(dd):
			continue
		if _team_of(n) == team:
			continue
		var d: float = global_position.distance_to(n.global_position)
		if d > 62.0:
			continue
		if not _can_see(n):
			continue

		# O C# combina distância, estabilidade do alvo, marcação e vida restante.
		# A perceção/linha de visão continua a ser validada em GDScript antes daqui.
		var score := -d
		if bot_brain != null:
			var marked_value = n.get("mark_t")
			var is_marked := marked_value != null and float(marked_value) > 0.0
			var hp_value = n.get("hp")
			var max_hp_value = n.get("max_hp")
			if hp_value == null:
				hp_value = n.get("health")
			if max_hp_value == null:
				max_hp_value = n.get("max_health")
			var health_ratio := 1.0
			if hp_value != null and max_hp_value != null and float(max_hp_value) > 0.0:
				health_ratio = clampf(float(hp_value) / float(max_hp_value), 0.0, 1.0)
			score = float(bot_brain.call("ScoreCandidate", d, n == target, is_marked, health_ratio))
		if score > best_score:
			best = n
			best_score = score

	if best != target:
		target = best
		reaction_t = reaction_time + randf() * 0.18
		burst_left = randi_range(3, 6)
		fire_t = 0.0
		if best != null:
			strafe_dir = 1.0 if randf() < 0.5 else -1.0

func _can_see(n) -> bool:
	if n == null or not is_instance_valid(n):
		return false
	var from := global_position + UP * 1.55
	var to: Vector3 = n.global_position + UP * 1.25
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [get_rid()]
	q.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return true
	var col = hit.collider
	if col == n:
		return true
	if col is Node and n is Node and n.is_ancestor_of(col):
		return true
	return false

# ---------- IA ----------

func _think(delta):
	think_t -= delta
	if think_t <= 0.0:
		think_t = 0.22
		_acquire_target()

	if target != null and (not is_instance_valid(target) or bool(target.get("dead"))):
		target = null

	if target != null and blind_t <= 0.0:
		target_visible = _can_see(target)
	else:
		target_visible = false

	if target_visible:
		reaction_t = maxf(0.0, reaction_t - delta)
		aim_pitch = 0.0
	else:
		reaction_t = maxf(reaction_t, reaction_time * 0.5) if target != null else 0.0

func _move(delta):
	var desired := Vector3.ZERO
	var focus: Vector3 = Vector3.ZERO
	var has_focus := false

	if target != null and is_instance_valid(target):
		var to: Vector3 = target.global_position - global_position
		to.y = 0.0
		var dist := to.length()
		focus = to.normalized()
		has_focus = dist > 0.05
		if not target_visible:
			# avança para a última posição conhecida
			desired = to.normalized() * 0.85
		elif dist > 16.0:
			desired = to.normalized()
		elif dist < 4.5:
			desired = -to.normalized()
		else:
			var side := to.normalized().cross(UP).normalized()
			desired = side * strafe_dir * 0.8
			strafe_t -= delta
			if strafe_t <= 0.0:
				strafe_dir = -strafe_dir
				strafe_t = randf_range(0.7, 1.7)
	elif has_waypoint:
		var wp: Vector3 = waypoint - global_position
		wp.y = 0.0
		if wp.length() < 1.6:
			has_waypoint = false
			wait_t = randf_range(0.2, 1.0)
		else:
			desired = wp.normalized() * 0.75
			focus = wp.normalized()
			has_focus = true
		if blind_t > 0.0:
			desired *= 0.3

	# pausa antes de escolher novo ponto
	if not has_waypoint and target == null:
		wait_t -= delta
		if wait_t <= 0.0:
			_pick_waypoint()

	# desvio de obstáculos
	if desired.length() > 0.05:
		desired = desired.normalized()
		if _blocked(desired):
			var right := desired.rotated(UP, deg_to_rad(58.0))
			var left := desired.rotated(UP, deg_to_rad(-58.0))
			if not _blocked(right):
				desired = right
			elif not _blocked(left):
				desired = left

	var target_vel := desired * move_speed
	velocity.x = move_toward(velocity.x, target_vel.x, ACCEL * delta)
	velocity.z = move_toward(velocity.z, target_vel.z, ACCEL * delta)

	# olhar
	var face := focus if has_focus else Vector3(velocity.x, 0, velocity.z)
	if face.length() > 0.1:
		var want_yaw := atan2(-face.x, -face.z)
		rotation.y = lerp_angle(rotation.y, want_yaw, clampf(7.0 * delta, 0.0, 1.0))

	# destravar
	if global_position.distance_to(last_pos) < 0.02:
		stuck_t += delta
	else:
		stuck_t = 0.0
	last_pos = global_position
	if stuck_t > 0.7:
		stuck_t = 0.0
		has_waypoint = false
		strafe_dir = -strafe_dir
		_pick_waypoint()
		if is_on_floor():
			velocity.y = 4.2

func _blocked(dir: Vector3) -> bool:
	var from := global_position + UP * 0.95
	var to := from + dir * 1.25
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [get_rid()]
	q.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return not hit.is_empty()

func _pick_waypoint():
	var ang := randf() * TAU
	var r := roam_radius * sqrt(randf())
	waypoint = roam_center + Vector3(cos(ang) * r, 0.0, sin(ang) * r)
	has_waypoint = true

# ---------- DISPARO ----------

func _try_fire(delta):
	if target == null or not is_instance_valid(target):
		return
	if not target_visible or blind_t > 0.0 or reaction_t > 0.0:
		return
	var dist: float = global_position.distance_to(target.global_position)
	if dist > 58.0:
		return

	if burst_pause > 0.0:
		burst_pause -= delta
		return

	fire_t -= delta
	if fire_t > 0.0:
		return

	_fire_at(target)
	fire_t = fire_interval
	burst_left -= 1
	if burst_left <= 0:
		burst_left = randi_range(3, 7)
		burst_pause = randf_range(0.30, 0.85)

func _fire_at(t):
	var from: Vector3 = gun_root.global_position + (-global_transform.basis.z) * 0.45
	var aim: Vector3 = t.global_position + UP * randf_range(0.95, 1.45)
	var dist := from.distance_to(aim)
	var err := (1.0 - accuracy) * dist * 0.055
	if blind_t > 0.0:
		err *= 3.0
	var dir := (aim - from).normalized()
	if err > 0.001:
		dir = (dir + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * (err / maxf(dist, 1.0))).normalized()

	var far := from + dir * 220.0
	var q := PhysicsRayQueryParameters3D.create(from, far)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var end_pt := far
	if not hit.is_empty():
		end_pt = hit.position
		var col = hit.collider
		if col != null and col.has_method("take_damage") and _team_of(col) != team:
			var falloff := clampf(1.0 - dist / 90.0, 0.55, 1.0)
			var amount := shot_damage * falloff
			if randf() < 0.07:
				amount *= 2.2
			col.take_damage(amount, self)

	_tracer(from, end_pt)
	muzzle_light.light_energy = 3.0
	if flash_mesh:
		flash_mesh.visible = true
		flash_mesh.rotation.z = randf() * TAU

func _tracer(from: Vector3, to: Vector3):
	var dist := from.distance_to(to)
	if dist < 1.0:
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.02, 0.02, dist)
	mi.mesh = bm
	mi.material_override = tracer_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(mi)
	mi.global_position = (from + to) * 0.5
	var d := (to - from).normalized()
	var up := UP if absf(d.y) < 0.98 else Vector3.RIGHT
	mi.look_at(to, up)
	get_tree().create_timer(0.05).timeout.connect(mi.queue_free)

# ==================================================
# DANO / ESTADO
# ==================================================

func take_damage(amount: float, attacker = null) -> bool:
	if dead:
		return false
	var dmg := amount
	if armor > 0.0:
		var absorbed := minf(armor, dmg * 0.66)
		armor -= absorbed
		dmg -= absorbed
	hp -= dmg
	_update_hp_bar()
	emit_signal("damaged", self, amount, attacker)
	if hp <= 0.0:
		_die(attacker)
		return true
	# reage a quem lhe bateu
	if target == null and attacker != null and is_instance_valid(attacker) and attacker != self:
		target = attacker
		reaction_t = reaction_time * 0.6
		burst_left = randi_range(3, 6)
	return false

func _update_hp_bar():
	if hp_fill == null:
		return
	var frac := clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)
	hp_fill.scale = Vector3(maxf(frac, 0.001), 1.0, 1.0)
	hp_fill.position.x = -(0.74 * (1.0 - frac)) * 0.5
	if hp_fill_mat:
		hp_fill_mat.albedo_color = Color(0.35, 0.9, 0.45) if frac > 0.5 else (Color(1.0, 0.8, 0.25) if frac > 0.25 else Color(1.0, 0.3, 0.3))
	hp_bg.visible = frac < 1.0
	hp_fill.visible = frac < 1.0

func _die(killer):
	if dead:
		return
	dead = true
	hp = 0.0
	deaths += 1
	emit_signal("died", self, killer)
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	if body_root:
		body_root.visible = false
	if tag:
		tag.visible = false
	blind_t = 0.0
	mark_t = 0.0

func reset_for_round(pos: Vector3, facing := Vector3.FORWARD) -> void:
	dead = false
	hp = max_hp
	armor = max_armor
	blind_t = 0.0
	mark_t = 0.0
	target = null
	target_visible = false
	reaction_t = 0.0
	fire_t = 0.0
	burst_pause = 0.0
	velocity = Vector3.ZERO
	global_position = pos
	if facing.length() > 0.01:
		rotation.y = atan2(-facing.x, -facing.z)
	set_deferred("collision_layer", 1)
	set_deferred("collision_mask", 1)
	if body_root:
		body_root.visible = true
	if tag:
		tag.visible = true
	has_waypoint = false
	_update_hp_bar()

func heal(amount: float) -> void:
	if dead:
		return
	hp = minf(max_hp, hp + amount)
	_update_hp_bar()

func blind(seconds: float) -> void:
	if dead:
		return
	blind_t = maxf(blind_t, seconds)

func mark(seconds: float) -> void:
	if dead:
		return
	mark_t = maxf(mark_t, seconds)

func set_objective(pos: Vector3, radius := 6.0) -> void:
	roam_center = pos
	roam_radius = radius
	has_waypoint = false
	_pick_waypoint()

func is_alive() -> bool:
	return not dead
