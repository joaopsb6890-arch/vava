extends CharacterBody3D

# ==================================================
# JETT (VALORANT) - FPS CONTROLLER
# Godot 4  |  Precisa de um filho "Camera3D"
# --------------------------------------------------
# Controlos (criados automaticamente se não existirem no Input Map):
#   WASD ........ mover          Shift ... andar (silencioso)
#   Espaço ...... saltar         Ctrl .... agachar
#   Espaço (no ar, a cair) ...... DRIFT (planar)
#   Q ........... UPDRAFT (impulso para cima)
#   E ........... TAILWIND (1º toque arma, 2º toque dá dash)
#   C ........... CLOUDBURST (equipa) | Botão esq. lança, SEGURAR curva
#   X ........... BLADE STORM (ult)   | Esq. = 1 faca, Dir. = todas
#   F1 .......... mostrar/esconder ajuda
#
# Alvos: qualquer corpo com  take_damage(dano) -> bool  (true = morreu)
# ==================================================

signal died
signal ability_used(ability_name: String)

enum Equip { NONE, SMOKE, KNIVES }

const SLOT_KEYS := {"c": "C", "q": "Q", "e": "E", "x": "X"}
const SLOT_ORDER := ["c", "q", "e", "x"]

const COLOR_CYAN := Color(0.35, 0.88, 1.0)
const COLOR_CYAN_DIM := Color(0.2, 0.5, 0.62)
const COLOR_DIM := Color(0.25, 0.3, 0.36)
const COLOR_GOLD := Color(1.0, 0.82, 0.3)
const COLOR_RED := Color(1.0, 0.28, 0.33)
const VM_BASE := Vector3(0.26, -0.22, -0.55)

const SPEED_SHADER := """
shader_type canvas_item;
uniform float intensity = 0.0;
uniform vec4 tint : source_color = vec4(0.55, 0.92, 1.0, 1.0);
float hash(float n) { return fract(sin(n * 127.1) * 43758.5453); }
void fragment() {
	vec2 p = UV - vec2(0.5);
	float d = length(p) * 1.4142;
	float a = atan(p.y, p.x);
	float idx = floor(a * 48.0);
	float l = step(0.62, hash(idx));
	float flick = hash(idx + floor(TIME * 24.0));
	float edge = smoothstep(0.35, 1.0, d);
	float streak = l * edge * (0.5 + 0.5 * flick);
	float vig = edge * edge * 0.35;
	COLOR = vec4(tint.rgb, (streak * 0.75 + vig) * intensity);
}
"""

# ==================================================
# EXPORTS
# ==================================================

@export_group("Partida")
@export var match_mode := false               # true = HUD de ronda escondido (o match manda)
@export var auto_respawn := true              # false = o match decide quando renascer

@export_group("Gameplay")
@export var practice_mode := true            # true = habilidades recarregam por tempo
@export var max_health := 100.0
@export var start_armor := 50.0
@export var start_ult_points := 7            # começa com a ult pronta (para testar)
@export var ult_cost := 7
@export var ability_recharge_time := 12.0

@export_group("Movement")
@export var run_speed := 7.0
@export var walk_speed := 3.8
@export var crouch_speed := 3.2
@export var acceleration := 55.0
@export var friction := 60.0
@export var air_acceleration := 14.0
@export var gravity := 18.0

@export_group("Jump")
@export var jump_force := 6.2
@export var coyote_time := 0.12
@export var jump_buffer := 0.15

@export_group("Drift (passiva)")
@export var drift_fall_speed := 2.2
@export var drift_brake := 38.0
@export var drift_speed_mult := 1.25
@export var drift_air_acceleration := 18.0

@export_group("Tailwind (E)")
@export var dash_speed := 40.0
@export var dash_duration := 0.2
@export var dash_exit_mult := 1.15
@export var tailwind_prime_time := 12.0
@export var tailwind_cooldown := 12.0         # só no practice_mode
@export var tailwind_kills_needed := 2        # fora do practice_mode

@export_group("Updraft (Q)")
@export var updraft_force := 15.0
@export var updraft_max_charges := 2
@export var updraft_lock_time := 0.6

@export_group("Cloudburst (C)")
@export var smoke_max_charges := 2
@export var smoke_throw_speed := 24.0
@export var smoke_curve_rate := 40.0
@export var smoke_radius := 3.6
@export var smoke_duration := 4.5

@export_group("Blade Storm (X)")
@export var knives_max := 5
@export var knife_speed := 95.0
@export var knife_damage_primary := 100.0
@export var knife_damage_alt := 50.0
@export var knife_fire_delay := 0.25
@export var knife_alt_spread := 4.5

@export_group("Camera")
@export var sensitivity := 0.002
@export var base_fov := 90.0
@export var dash_fov := 103.0
@export var updraft_fov := 98.0
@export var fov_smooth := 9.0
@export var headbob_speed := 11.0
@export var headbob_amount := 0.03
@export var camera_tilt := 0.04
@export var crouch_depth := 0.45

@export_group("Visual Effects")
@export var enable_particles := true
@export var enable_camera_shake := true
@export var enable_landing_effect := true
@export var enable_speed_lines := true
@export var wind_color := Color(0.55, 0.92, 1.0)

# ==================================================
# REFERENCES
# ==================================================

@onready var camera: Camera3D = $Camera3D
@onready var col_shape: CollisionShape3D = get_node_or_null("CollisionShape3D")

# ==================================================
# STATE
# ==================================================

var mouse_pitch := 0.0
var camera_base_position := Vector3.ZERO
var camera_motion_lag := Vector2.ZERO
var spawn_position := Vector3.ZERO
var move_time := 0.0
var trauma := 0.0
var pitch_kick := 0.0
var land_dip := 0.0
var input_lock := 0.0
var fire_cd := 0.0

var health := 100.0
var armor := 0.0
var dead := false

var coyote_timer := 0.0
var jump_buffer_timer := 0.0
var jump_active := false
var was_on_floor := false
var is_drifting := false

var crouch_t := 0.0
var stand_height := 0.0
var stand_col_y := 0.0

var is_dashing := false
var dash_timer := 0.0
var dash_direction := Vector3.ZERO
var tailwind_charged := true
var tailwind_primed := false
var tailwind_prime_timer := 0.0
var tailwind_recharge_t := 0.0
var tailwind_kills := 0

var updraft_charges := 2
var updraft_recharge_t := 0.0
var updraft_lock := 0.0
var updraft_fx_timer := 0.0

var smoke_charges := 2
var smoke_recharge_t := 0.0

var equipped := Equip.NONE
var ult_points := 0
var ult_active := false
var knives := 0
var knives_in_flight := 0

# ---- agente / kit ----
var agent: Dictionary = {}
var kit: Dictionary = {}
var team := "attack"
var buy_open := false
var equipped_slot := "c"
var ability_color := Color(0.55, 0.92, 1.0)

var speed_intensity := 0.0
var soft_texture: GradientTexture2D

# viewmodel
var viewmodel: Node3D
var smoke_vm: Node3D
var knife_vm_root: Node3D
var blades: Array = []
var vm_kick := 0.0
var vm_bob := 0.0
var vm_equip := 0.0
var hand_l: Node3D
var hand_r: Node3D

# fx persistentes
var dash_trail: GPUParticles3D
var air_trail: GPUParticles3D
var drift_puffs: GPUParticles3D

# HUD
var hud: CanvasLayer
var hud_time := 0.0
var speed_overlay: ColorRect
var damage_flash: ColorRect
var toast_label: Label
var toast_tween: Tween
var hint_label: Label
var knife_label: Label
var health_label: Label
var armor_label: Label
var crosshair: Control
var ch_parts: Array = []
var ch_gap := 5.0
var hitmarker: Control
var icon_smoke: AbilityIcon
var icon_updraft: AbilityIcon
var icon_tailwind: AbilityIcon
var icon_ult: AbilityIcon
var shield_icon: AbilityIcon
var timer_label: Label
var blue_score_label: Label
var red_score_label: Label
var killfeed: VBoxContainer
var scorebar: HBoxContainer
var icons: Dictionary = {}
var minimap: Minimap
var round_time_left := 100.0
var blue_score := 0
var red_score := 0

# ==================================================
# READY
# ==================================================

func _ready():
	add_to_group("player")
	_setup_inputs()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	camera_base_position = camera.position
	camera.fov = base_fov
	spawn_position = global_position

	if kit.is_empty():
		configure_agent(GameState.get_agent("jett"))
	health = max_health
	armor = start_armor
	ult_points = mini(start_ult_points, ult_cost)
	_reset_kit()

	if col_shape and col_shape.shape is CapsuleShape3D:
		col_shape.shape = col_shape.shape.duplicate()
		stand_height = (col_shape.shape as CapsuleShape3D).height
		stand_col_y = col_shape.position.y

	soft_texture = _make_soft_texture()
	_build_viewmodel()
	_build_fx_emitters()
	_build_hud()
	_refresh_viewmodel()

# ==================================================
# AGENTE / KIT (4 habilidades por agente)
# ==================================================

func configure_agent(a: Dictionary) -> void:
	agent = a.duplicate(true)
	kit = {}
	for slot in SLOT_ORDER:
		var ab: Dictionary = agent.abilities[slot].duplicate(true)
		ab["slot"] = slot
		var is_ult := bool(ab.get("ult", false)) or str(ab.get("type", "")) in ["knives", "strike"]
		ab["ult"] = is_ult
		ab["max_charges"] = 1 if is_ult else int(ab.get("charges", 1))
		ab["charges"] = int(ab.max_charges)
		ab["recharge_t"] = 0.0
		kit[slot] = ab

	max_health = float(agent.get("hp", 100))
	start_armor = float(agent.get("armor", 50))
	run_speed = float(agent.get("speed", 7.0))
	ult_cost = int(agent.get("ult_cost", 7))
	start_ult_points = 0
	ability_color = agent.get("color", Color(0.55, 0.92, 1.0))
	for slot in kit.keys():
		var ab: Dictionary = kit[slot]
		if str(ab.get("type", "")) == "smoke":
			smoke_radius = float(ab.get("radius", 3.6))
			smoke_duration = float(ab.get("duration", 4.5))
	health = max_health
	armor = start_armor

func _ab(slot: String) -> Dictionary:
	return kit.get(slot, {})

func ab_charges(slot: String) -> int:
	var ab := _ab(slot)
	return int(ab.get("charges", 0))

func ab_ready(slot: String) -> bool:
	var ab := _ab(slot)
	if ab.is_empty():
		return false
	if bool(ab.get("ult", false)):
		return ult_points >= ult_cost
	return int(ab.get("charges", 0)) > 0

func _spend(slot: String) -> void:
	var ab := _ab(slot)
	if ab.is_empty():
		return
	ab.charges = maxi(0, int(ab.get("charges", 1)) - 1)
	if float(ab.get("recharge_t", 0.0)) <= 0.0:
		ab.recharge_t = float(ab.get("recharge", 10.0))

func _reset_kit() -> void:
	for slot in kit.keys():
		var ab: Dictionary = kit[slot]
		ab.charges = int(ab.get("max_charges", 1))
		ab.recharge_t = 0.0

func _slot_with_type(kind: String) -> String:
	for slot in SLOT_ORDER:
		var ab := _ab(slot)
		if not ab.is_empty() and str(ab.get("type", "")) == kind:
			return slot
	return ""

func _icon_kind(t: String) -> String:
	match t:
		"impulse":
			return "updraft"
		"dash":
			return "tailwind"
		"knives":
			return "ult"
		"strike":
			return "strike"
	return t

func _hint_text() -> String:
	var a := _ab("q")
	var b := _ab("e")
	var c := _ab("c")
	var d := _ab("x")
	var line1 := "WASD mover | Shift andar | Ctrl agachar | Espaço saltar (segurar no ar = DRIFT)"
	var line2 := "Q %s | E %s | C %s | X %s" % [
		str(a.get("name", "")), str(b.get("name", "")), str(c.get("name", "")), str(d.get("name", ""))
	]
	var line3 := "Esq. dispara | Dir. alt | R recarrega | 1/2/3 armas | B loja | Tab placar | F plantar | F1 ajuda"
	return line1 + "\n" + line2 + "\n" + line3

func set_armor(value: float) -> void:
	armor = clampf(value, 0.0, 100.0)
	if armor_label:
		armor_label.text = str(ceili(armor))

func is_alive() -> bool:
	return not dead

# ==================================================
# ATIVAÇÃO DE HABILIDADES
# ==================================================

func use_slot(slot: String) -> void:
	if dead:
		return
	var ab := _ab(slot)
	if ab.is_empty():
		return
	if not ab_ready(slot):
		if bool(ab.get("ult", false)):
			toast("%s não está pronta (%d/%d)" % [str(ab.get("name", "ULT")), ult_points, ult_cost], COLOR_RED)
		else:
			toast("Sem cargas de %s" % str(ab.get("name", "habilidade")), COLOR_RED)
		return

	var kind := str(ab.get("type", ""))
	match kind:
		"impulse":
			cast_impulse(slot)
		"dash":
			cast_dash(slot)
		"smoke":
			equipped_slot = slot
			toggle_equip(Equip.SMOKE)
		"flash":
			cast_flash(slot)
		"shock":
			cast_shock(slot)
		"heal":
			cast_heal(slot)
		"mark":
			cast_mark(slot)
		"wall":
			cast_wall(slot)
		"knives":
			toggle_equip(Equip.KNIVES)
		"strike":
			cast_strike(slot)
		_:
			toast("Habilidade desconhecida: " + kind, COLOR_RED)

# ==================================================
# INPUT MAP (auto)
# ==================================================

func _setup_inputs():
	_key_action("move_forward", KEY_W)
	_key_action("move_backward", KEY_S)
	_key_action("move_left", KEY_A)
	_key_action("move_right", KEY_D)
	_key_action("jump", KEY_SPACE)
	_key_action("crouch", KEY_CTRL)
	_key_action("walk", KEY_SHIFT)
	_key_action("updraft", KEY_Q)
	_key_action("dash", KEY_E)
	_key_action("smoke", KEY_C)
	_key_action("ultimate", KEY_X)
	_key_action("toggle_help", KEY_F1)
	_mouse_action("fire", MOUSE_BUTTON_LEFT)
	_mouse_action("alt_fire", MOUSE_BUTTON_RIGHT)

func _key_action(action: String, key: Key):
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	if InputMap.action_get_events(action).is_empty():
		var e := InputEventKey.new()
		e.physical_keycode = key
		InputMap.action_add_event(action, e)

func _mouse_action(action: String, button: MouseButton):
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	if InputMap.action_get_events(action).is_empty():
		var e := InputEventMouseButton.new()
		e.button_index = button
		InputMap.action_add_event(action, e)

func _input(event):
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if dead:
			return
		rotate_y(-event.relative.x * sensitivity)
		mouse_pitch -= event.relative.y * sensitivity
		mouse_pitch = clampf(mouse_pitch, -1.5, 1.5)

	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			input_lock = 0.2   # o clique que captura o rato não dispara

# ==================================================
# MAIN LOOP
# ==================================================

func _physics_process(delta):
	if dead:
		velocity = Vector3.ZERO
		return

	was_on_floor = is_on_floor()
	input_lock = maxf(0.0, input_lock - delta)
	fire_cd = maxf(0.0, fire_cd - delta)

	update_timers(delta)
	handle_ability_input()
	update_crouch(delta)

	if Input.is_action_just_pressed("jump"):
		jump_buffer_timer = jump_buffer

	# GRAVIDADE
	if not is_on_floor() and not is_dashing:
		velocity.y -= gravity * delta

	if is_on_floor() or velocity.y <= 0.0:
		jump_active = false

	# DRIFT: segurar espaço a cair
	is_drifting = (not is_on_floor() and Input.is_action_pressed("jump")
		and velocity.y <= 0.0 and not is_dashing and not jump_active)
	if is_drifting:
		velocity.y = move_toward(velocity.y, -drift_fall_speed, drift_brake * delta)

	if is_dashing:
		process_dash(delta)
	else:
		process_movement(delta)

	# SALTO
	if jump_buffer_timer > 0.0 and coyote_timer > 0.0 and not is_dashing:
		velocity.y = jump_force
		jump_buffer_timer = 0.0
		coyote_timer = 0.0
		jump_active = true
		add_shake(0.06)

	# SALTO CURTO (só salto normal, não o updraft)
	if Input.is_action_just_released("jump") and jump_active and velocity.y > 0.0:
		velocity.y *= 0.5
		jump_active = false

	var fall_speed := velocity.y
	move_and_slide()

	if not was_on_floor and is_on_floor():
		landing_effect(-fall_speed)

	update_camera(delta)
	update_fx(delta)

func _process(delta):
	_update_viewmodel(delta)
	_update_hud(delta)

# ==================================================
# TIMERS & RECARGAS
# ==================================================

func update_timers(delta):
	if is_on_floor():
		coyote_timer = coyote_time
	else:
		coyote_timer = maxf(0.0, coyote_timer - delta)

	jump_buffer_timer = maxf(0.0, jump_buffer_timer - delta)
	updraft_lock = maxf(0.0, updraft_lock - delta)

	# recarga automática de todas as habilidades (a ultimate só com kills)
	for slot in kit.keys():
		var ab: Dictionary = kit[slot]
		if bool(ab.get("ult", false)):
			continue
		if int(ab.get("charges", 0)) >= int(ab.get("max_charges", 1)):
			ab.recharge_t = 0.0
			continue
		ab.recharge_t = maxf(0.0, float(ab.get("recharge_t", 0.0)) - delta)
		if float(ab.recharge_t) <= 0.0:
			ab.charges = int(ab.get("charges", 0)) + 1
			if int(ab.charges) < int(ab.get("max_charges", 1)):
				ab.recharge_t = float(ab.get("recharge", 10.0))

# ==================================================
# ABILITY INPUT
# ==================================================

func handle_ability_input():
	if buy_open:
		return
	if Input.is_action_just_pressed("updraft"):
		use_slot("q")
	if Input.is_action_just_pressed("dash"):
		use_slot("e")
	if Input.is_action_just_pressed("smoke"):
		use_slot("c")
	if Input.is_action_just_pressed("ultimate"):
		use_slot("x")
	if Input.is_action_just_pressed("toggle_help") and hint_label:
		hint_label.visible = not hint_label.visible

	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and input_lock <= 0.0:
		if Input.is_action_just_pressed("fire"):
			on_fire()
		if Input.is_action_just_pressed("alt_fire"):
			on_alt_fire()

func on_fire():
	match equipped:
		Equip.SMOKE:
			throw_smoke()
		Equip.KNIVES:
			if fire_cd <= 0.0 and knives > 0:
				throw_knife()

func on_alt_fire():
	if equipped == Equip.KNIVES and knives > 0 and fire_cd <= 0.0:
		throw_all_knives()

func toggle_equip(which: Equip):
	if equipped == which:
		equipped = Equip.NONE
		_refresh_viewmodel()
		return

	if which == Equip.SMOKE:
		if equipped_slot == "" or ab_charges(equipped_slot) <= 0:
			var found := _slot_with_type("smoke")
			if found == "" or ab_charges(found) <= 0:
				toast("Sem cargas de fumo", COLOR_RED)
				return
			equipped_slot = found
	elif which == Equip.KNIVES:
		if not ult_active:
			if ult_points < ult_cost:
				toast("Ultimate não está pronta (%d/%d)" % [ult_points, ult_cost], COLOR_RED)
				return
			ult_active = true
			ult_points = 0
			knives = knives_max
			toast(str(_ab("x").get("name", "BLADE STORM")), COLOR_GOLD)
			if enable_particles:
				var pos := global_position + Vector3(0, 1.0, 0)
				burst(pos, {"amount": 50, "lifetime": 0.6, "size": 0.5, "additive": true,
					"v_min": 3.0, "v_max": 8.0, "damping": 3.0, "grow": true, "emit_radius": 0.4,
					"color": Color(1.0, 0.9, 0.55, 0.8)})
				spawn_ring(pos, Vector3.UP, COLOR_GOLD, 6.0, 0.5, 0.5)
			add_shake(0.3)
			emit_signal("ability_used", "ultimate")

	equipped = which
	_refresh_viewmodel()

# ==================================================
# MOVEMENT
# ==================================================

func get_move_input() -> Vector2:
	return Input.get_vector("move_left", "move_right", "move_forward", "move_backward")

func process_movement(delta):
	var input_dir := get_move_input()
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	var speed := run_speed
	if Input.is_action_pressed("walk"):
		speed = walk_speed
	if crouch_t > 0.5:
		speed = minf(speed, crouch_speed)
	if is_drifting:
		speed = run_speed * drift_speed_mult

	var target := direction * speed
	var horizontal := Vector3(velocity.x, 0, velocity.z)

	var rate := air_acceleration
	if is_drifting:
		rate = drift_air_acceleration
	if is_on_floor():
		rate = acceleration if direction.length_squared() > 0.0 else friction
	elif direction.length_squared() == 0.0:
		rate = 2.0

	horizontal = horizontal.move_toward(target, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

func update_crouch(delta):
	var want := Input.is_action_pressed("crouch")
	crouch_t = move_toward(crouch_t, 1.0 if want else 0.0, 8.0 * delta)
	if stand_height > 0.0 and col_shape:
		var shape := col_shape.shape as CapsuleShape3D
		var h := lerpf(stand_height, stand_height * 0.65, crouch_t)
		shape.height = h
		col_shape.position.y = stand_col_y - (stand_height - h) * 0.5

# ==================================================
# TAILWIND (E)
# ==================================================

func cast_dash(slot: String) -> void:
	var ab := _ab(slot)
	_spend(slot)
	var input_dir := get_move_input()
	var dir := -transform.basis.z
	if input_dir != Vector2.ZERO:
		dir = (transform.basis * Vector3(input_dir.x, 0, input_dir.y))
	dir.y = 0.0
	if dir.length() < 0.01:
		dir = -transform.basis.z
	dash_direction = dir.normalized()

	dash_speed = float(ab.get("speed", dash_speed))
	is_dashing = true
	dash_timer = float(ab.get("duration", dash_duration))
	jump_active = false
	_dash_fx()
	emit_signal("ability_used", "dash")

# (o dash agora é instantâneo: ver cast_dash)

func process_dash(delta):
	dash_timer -= delta
	velocity.x = dash_direction.x * dash_speed
	velocity.z = dash_direction.z * dash_speed
	velocity.y = 0.0

	if dash_timer <= 0.0:
		is_dashing = false
		velocity.x = dash_direction.x * run_speed * dash_exit_mult
		velocity.z = dash_direction.z * run_speed * dash_exit_mult

func _dash_fx():
	add_shake(0.35)
	speed_intensity = 1.0
	if not enable_particles:
		return
	var pos := global_position + Vector3(0, 1.0, 0)
	(dash_trail.process_material as ParticleProcessMaterial).direction = -dash_direction

	burst(pos, {"amount": 40, "lifetime": 0.5, "size": 0.5, "additive": true, "v_min": 4.0, "v_max": 10.0,
		"damping": 3.0, "grow": true, "emit_radius": 0.4, "color": wind_color})
	burst(pos, {"amount": 36, "lifetime": 0.35, "streak": true, "additive": true, "shrink": true,
		"direction": -dash_direction, "spread": 18.0, "v_min": 10.0, "v_max": 20.0, "emit_radius": 0.5,
		"streak_length": 1.3, "color": Color(0.8, 0.97, 1.0, 0.9)})
	spawn_ring(pos + dash_direction * 0.4, dash_direction, wind_color, 5.5, 0.4, 0.45)
	spawn_ring(pos + dash_direction * 1.4, dash_direction, Color(1, 1, 1, 0.8), 4.0, 0.35, 0.3)

	if is_on_floor():
		burst(global_position + Vector3(0, 0.1, 0), {"amount": 14, "lifetime": 0.6, "size": 0.9,
			"v_min": 1.0, "v_max": 3.0, "spread": 70.0, "damping": 2.5, "grow": true, "emit_radius": 0.3,
			"color": Color(0.8, 0.85, 0.9, 0.45), "fade_start": 0.3})

# ==================================================
# UPDRAFT (Q)
# ==================================================

func cast_impulse(slot: String) -> void:
	if updraft_lock > 0.0:
		return
	var ab := _ab(slot)
	_spend(slot)
	updraft_lock = updraft_lock_time

	velocity.y = float(ab.get("force", updraft_force))
	jump_active = false
	updraft_fx_timer = 0.55

	add_shake(0.45)
	pitch_kick = 0.07
	speed_intensity = maxf(speed_intensity, 0.6)

	if enable_particles:
		var feet := global_position + Vector3(0, 0.1, 0)
		spawn_ring(feet, Vector3.UP, ability_color, 7.0, 0.5, 0.5)
		spawn_ring(feet, Vector3.UP, Color(1, 1, 1, 0.8), 4.5, 0.4, 0.35)
		burst(feet, {"amount": 50, "lifetime": 0.7, "size": 0.7, "additive": true, "v_min": 3.0, "v_max": 9.0,
			"spread": 80.0, "damping": 3.0, "grow": true, "emit_radius": 0.5, "color": ability_color})
		burst(feet, {"amount": 40, "lifetime": 0.45, "streak": true, "additive": true, "shrink": true,
			"direction": Vector3.UP, "spread": 35.0, "v_min": 8.0, "v_max": 16.0, "emit_radius": 0.6,
			"streak_length": 1.4, "color": Color(0.85, 0.98, 1.0, 0.9)})
		burst(feet, {"amount": 16, "lifetime": 0.8, "size": 1.0, "v_min": 1.0, "v_max": 3.5,
			"spread": 85.0, "damping": 2.5, "grow": true, "emit_radius": 0.4,
			"color": Color(0.8, 0.85, 0.9, 0.45), "fade_start": 0.3})
	emit_signal("ability_used", "impulse")

# ==================================================
# CLOUDBURST (C)
# ==================================================

func knife_origin() -> Vector3:
	return camera.global_transform * Vector3(0.22, -0.16, -0.55)

func get_aim_point(max_dist := 200.0) -> Vector3:
	var from := camera.global_position
	var to := from - camera.global_transform.basis.z * max_dist
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return to
	return hit.position

func throw_smoke():
	if equipped_slot == "" or ab_charges(equipped_slot) <= 0:
		equipped = Equip.NONE
		_refresh_viewmodel()
		return
	_spend(equipped_slot)

	var origin := knife_origin()
	var dir := (get_aim_point(60.0) - origin).normalized()

	var ball := SmokeBall.new()
	ball.jett = self
	ball.velocity = dir * smoke_throw_speed + Vector3.UP * 2.0 + velocity * 0.25
	get_tree().current_scene.add_child(ball)
	ball.global_position = origin

	vm_kick = 0.12
	equipped = Equip.NONE
	_refresh_viewmodel()
	emit_signal("ability_used", "smoke")

func spawn_smoke_cloud(pos: Vector3):
	var root := Node3D.new()
	get_tree().current_scene.add_child(root)
	root.global_position = pos

	# núcleo translúcido (dá a sensação de volume / bloqueia a visão)
	var core := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = smoke_radius
	sph.height = smoke_radius * 2.0
	sph.radial_segments = 32
	sph.rings = 16
	core.mesh = sph
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.78, 0.88, 0.94, 0.0)
	core.material_override = mat
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	core.scale = Vector3.ONE * 0.1
	root.add_child(core)

	var tw := root.create_tween()
	tw.set_parallel(true)
	tw.tween_property(core, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.3, 0.45)
	tw.chain().tween_interval(maxf(0.1, smoke_duration - 1.4))
	tw.chain().tween_property(mat, "albedo_color:a", 0.0, 0.9)
	tw.chain().tween_callback(root.queue_free)

	# área para gameplay (inimigos podem consultar o grupo "smoke")
	var area := Area3D.new()
	area.add_to_group("smoke")
	area.collision_layer = 1 << 7
	area.collision_mask = 0
	var cs := CollisionShape3D.new()
	var ss := SphereShape3D.new()
	ss.radius = smoke_radius
	cs.shape = ss
	area.add_child(cs)
	root.add_child(area)

	# partículas de fumo
	var puffs := make_emitter({"amount": 110, "lifetime": smoke_duration, "size": 3.4,
		"scale_min": 0.7, "scale_max": 1.2, "v_min": 0.2, "v_max": 0.9, "damping": 0.5,
		"explosiveness": 1.0, "emit_radius": smoke_radius * 0.65, "grow": true,
		"color": Color(0.82, 0.9, 0.95, 0.55), "fade_start": 0.7})
	root.add_child(puffs)
	puffs.emitting = true

	var wisps := make_emitter({"amount": 30, "lifetime": 1.2, "size": 1.6, "additive": true,
		"v_min": 4.0, "v_max": 9.0, "damping": 3.0, "explosiveness": 1.0, "grow": true,
		"emit_radius": 0.5, "color": Color(0.6, 0.92, 1.0, 0.6)})
	root.add_child(wisps)
	wisps.emitting = true

	spawn_ring(pos, Vector3.UP, wind_color, smoke_radius * 1.6, 0.5, 0.6)
	add_shake(0.1)

# ==================================================
# BLADE STORM (X)
# ==================================================

func throw_knife():
	var origin := knife_origin()
	var dir := (get_aim_point() - origin).normalized()
	spawn_knife(origin, dir, knife_damage_primary)
	knives -= 1
	fire_cd = knife_fire_delay
	vm_kick = 0.1
	_refresh_viewmodel()

func throw_all_knives():
	var origin := knife_origin()
	var b := camera.global_transform.basis
	var count := knives
	for i in range(count):
		var d := (-b.z).rotated(b.y, deg_to_rad(randf_range(-knife_alt_spread, knife_alt_spread)))
		d = d.rotated(b.x, deg_to_rad(randf_range(-knife_alt_spread * 0.6, knife_alt_spread * 0.6)))
		spawn_knife(origin, d.normalized(), knife_damage_alt)
	knives = 0
	fire_cd = knife_fire_delay * 2.0
	vm_kick = 0.16
	add_shake(0.1)
	_refresh_viewmodel()

func spawn_knife(origin: Vector3, dir: Vector3, dmg: float):
	var k := Knife.new()
	k.jett = self
	k.velocity = dir * knife_speed
	k.damage = dmg
	get_tree().current_scene.add_child(k)
	k.global_position = origin
	k.look_at(origin + dir, Vector3.UP)
	knives_in_flight += 1

func on_knife_hit(pos: Vector3, normal: Vector3, hit_target: bool, killed: bool, target_name := ""):
	if enable_particles:
		burst(pos, {"amount": 14, "lifetime": 0.3, "streak": true, "additive": true, "shrink": true,
			"direction": normal, "spread": 40.0, "v_min": 4.0, "v_max": 9.0, "streak_length": 0.5,
			"color": Color(0.85, 0.97, 1.0, 0.95)})
	if hit_target:
		_show_hitmarker(killed)
	if killed:
		add_kill_feed(target_name if target_name != "" else "Inimigo")
		register_kill()

func knife_finished():
	knives_in_flight = maxi(0, knives_in_flight - 1)
	_check_ult_end()

func _check_ult_end():
	if ult_active and knives <= 0 and knives_in_flight <= 0:
		ult_active = false
		equipped = Equip.NONE
		toast("BLADE STORM terminou", COLOR_GOLD)
		_refresh_viewmodel()

# ==================================================
# HABILIDADES GENÉRICAS (usadas pelos 6 agentes)
# ==================================================

func _node_dead(n) -> bool:
	if n == null:
		return true
	var d = n.get("dead")
	return d != null and bool(d)

func _is_enemy(n) -> bool:
	if n == null or not is_instance_valid(n):
		return false
	var t = n.get("team")
	if t == null:
		return true
	return str(t) != team

func _targets_in_radius(center: Vector3, radius: float) -> Array:
	var out: Array = []
	var seen := {}
	for grp in ["bot", "enemy", "ally", "player"]:
		for n in get_tree().get_nodes_in_group(grp):
			if seen.has(n):
				continue
			seen[n] = true
			if not (n is Node3D) or n == self:
				continue
			if _node_dead(n) or not _is_enemy(n):
				continue
			if n.global_position.distance_to(center) <= radius:
				out.append(n)
	return out

func _has_los(from: Vector3, to: Vector3, ignore) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return true
	var col = hit.collider
	if col == ignore:
		return true
	if col is Node and ignore is Node and ignore.is_ancestor_of(col):
		return true
	return false

func _explode(center: Vector3, radius: float, damage: float, col: Color) -> void:
	if not is_inside_tree():
		return
	if enable_particles:
		spawn_ring(center, Vector3.UP, col, radius * 1.4, 0.45, 0.5)
		burst(center, {"amount": 60, "lifetime": 0.6, "size": 1.2, "additive": true,
			"v_min": 4.0, "v_max": 12.0, "spread": 90.0, "damping": 3.0, "grow": true,
			"emit_radius": radius * 0.4, "color": col})
	var targets := _targets_in_radius(center, radius)
	for n in targets:
		if not _has_los(center + Vector3(0, 0.5, 0), n.global_position + Vector3(0, 1.2, 0), n):
			continue
		var d: float = n.global_position.distance_to(center)
		var falloff := clampf(1.0 - d / maxf(radius, 0.1), 0.25, 1.0)
		n.take_damage(damage * falloff, self)
	add_shake(0.35)

func cast_flash(slot: String) -> void:
	var ab := _ab(slot)
	_spend(slot)
	var radius := float(ab.get("radius", 24.0))
	var duration := float(ab.get("blind", 2.2))
	var origin := camera.global_position
	var dir := -camera.global_transform.basis.z
	var blinded := 0
	for n in _targets_in_radius(origin, radius):
		var to: Vector3 = n.global_position + Vector3(0, 1.4, 0) - origin
		if to.normalized().dot(dir) < 0.2:
			continue
		if not _has_los(origin, n.global_position + Vector3(0, 1.2, 0), n):
			continue
		if n.has_method("blind"):
			n.blind(duration)
			blinded += 1
	if enable_particles:
		var p := origin + dir * 1.4
		burst(p, {"amount": 40, "lifetime": 0.35, "size": 2.2, "additive": true,
			"v_min": 6.0, "v_max": 14.0, "spread": 40.0, "damping": 6.0, "grow": true,
			"color": Color(1, 1, 1, 0.95)})
	var light := OmniLight3D.new()
	light.light_color = Color(1, 1, 0.95)
	light.omni_range = 14.0
	light.light_energy = 8.0
	get_tree().current_scene.add_child(light)
	light.global_position = origin + dir * 2.0
	_free_later(light, 0.18)
	if blinded > 0:
		toast("CEGOU %d INIMIGO(S)" % blinded, Color.WHITE)
	else:
		toast("Ninguém foi cegado", COLOR_RED)
	emit_signal("ability_used", "flash")

func cast_shock(slot: String) -> void:
	var ab := _ab(slot)
	_spend(slot)
	var target := get_aim_point(70.0)
	var dmg := float(ab.get("damage", 55.0))
	var radius := float(ab.get("radius", 4.0))
	var orb := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.22
	sph.height = 0.44
	orb.mesh = sph
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = ability_color
	orb.material_override = m
	orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(orb)
	orb.global_position = camera.global_position + (-camera.global_transform.basis.z) * 0.8
	var tw := orb.create_tween()
	tw.tween_property(orb, "global_position", target, 0.32).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		if is_instance_valid(orb):
			orb.queue_free()
		_explode(target, radius, dmg, ability_color)
	)
	emit_signal("ability_used", "shock")

func cast_heal(slot: String) -> void:
	var ab := _ab(slot)
	_spend(slot)
	var amount := float(ab.get("heal", 60.0))
	var radius := float(ab.get("radius", 7.0))
	health = minf(max_health, health + amount)
	for n in get_tree().get_nodes_in_group("ally"):
		if n is Node3D and n.has_method("heal") and n.global_position.distance_to(global_position) <= radius:
			n.heal(amount)
	if enable_particles:
		var c := global_position + Vector3(0, 1.0, 0)
		spawn_ring(c, Vector3.UP, Color(0.5, 1.0, 0.7), radius * 1.2, 0.6, 0.4)
		burst(c, {"amount": 40, "lifetime": 0.8, "size": 0.5, "additive": true, "v_min": 1.0,
			"v_max": 4.0, "spread": 60.0, "grow": true, "emit_radius": 1.2, "color": Color(0.55, 1.0, 0.75, 0.85)})
	toast("CURA +%d" % int(amount), Color(0.6, 1.0, 0.8))
	emit_signal("ability_used", "heal")

func cast_mark(slot: String) -> void:
	var ab := _ab(slot)
	_spend(slot)
	var radius := float(ab.get("radius", 40.0))
	var duration := float(ab.get("duration", 5.0))
	var count := 0
	for n in _targets_in_radius(global_position, radius):
		if n.has_method("mark"):
			n.mark(duration)
			count += 1
	if enable_particles:
		spawn_ring(global_position + Vector3(0, 0.2, 0), Vector3.UP, ability_color, radius * 0.6, 0.7, 0.4)
	toast("RECON: %d INIMIGO(S) MARCADO(S)" % count, ability_color)
	emit_signal("ability_used", "mark")

func cast_wall(slot: String) -> void:
	var ab := _ab(slot)
	_spend(slot)
	var duration := float(ab.get("duration", 22.0))
	var fwd := -camera.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.01:
		fwd = -transform.basis.z
	fwd = fwd.normalized()
	var side := fwd.cross(Vector3.UP).normalized()
	var center := global_position + fwd * 6.0

	var q := PhysicsRayQueryParameters3D.create(center + Vector3(0, 8.0, 0), center + Vector3(0, -6.0, 0))
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var base_y := global_position.y
	if not hit.is_empty():
		base_y = hit.position.y

	var root := Node3D.new()
	get_tree().current_scene.add_child(root)
	root.global_position = Vector3(center.x, base_y, center.z)
	root.rotation.y = atan2(-side.z, side.x)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(ability_color.r, ability_color.g, ability_color.b, 0.7)
	mat.emission_enabled = true
	mat.emission = ability_color
	mat.emission_energy_multiplier = 0.6
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var width := 7.0
	var segments := 5
	var seg_w := width / float(segments)
	for row in range(3):
		for i in range(segments):
			var off := -width * 0.5 + seg_w * (float(i) + 0.5)
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(seg_w, 3.0, 0.5)
			mi.mesh = bm
			mi.material_override = mat
			mi.position = Vector3(off, 1.5 + float(row) * 3.0, 0)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mi)

	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(width, 9.0, 0.6)
	cs.shape = sh
	body.add_child(cs)
	body.position = Vector3(0, 4.5, 0)
	root.add_child(body)

	var tw := root.create_tween()
	tw.tween_interval(maxf(0.5, duration - 1.0))
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.8)
	tw.tween_callback(root.queue_free)
	toast("PAREDE CRIADA", ability_color)
	emit_signal("ability_used", "wall")

func cast_strike(slot: String) -> void:
	var ab := _ab(slot)
	ult_points = 0
	var target := get_aim_point(90.0)
	var dmg := float(ab.get("damage", 150.0))
	var radius := float(ab.get("radius", 6.5))

	if enable_particles:
		spawn_ring(target, Vector3.UP, ability_color, radius * 1.6, 1.1, 0.4)

	var marker := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 0.05
	marker.mesh = cyl
	var mm := StandardMaterial3D.new()
	mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mm.albedo_color = Color(1, 0.2, 0.15, 0.35)
	marker.material_override = mm
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(marker)
	marker.global_position = target + Vector3(0, 0.06, 0)

	get_tree().create_timer(1.1).timeout.connect(func():
		if is_instance_valid(marker):
			marker.queue_free()
		_explode(target, radius, dmg, ability_color)
	)
	toast(str(ab.get("name", "ULTIMATE")), COLOR_GOLD)
	add_shake(0.5)
	emit_signal("ability_used", "strike")

# ==================================================
# KILLS / DANO
# ==================================================

func register_kill():
	if not ult_active:
		ult_points = mini(ult_cost, ult_points + 1)
	if ult_active:
		knives = knives_max
		toast("LÂMINAS RECARREGADAS", COLOR_GOLD)
		_refresh_viewmodel()

func take_damage(amount: float, _source = null) -> bool:
	if dead:
		return false
	if armor > 0.0:
		var absorbed := minf(armor, amount * 0.66)
		armor -= absorbed
		amount -= absorbed
	health -= amount
	add_shake(0.35)
	if damage_flash:
		damage_flash.color.a = 0.35
		var tw := create_tween()
		tw.tween_property(damage_flash, "color:a", 0.0, 0.4)
	if health <= 0.0:
		health = 0.0
		die()
		return true
	return false

func die():
	if dead:
		return
	dead = true
	equipped = Equip.NONE
	ult_active = false
	knives = 0
	knives_in_flight = 0
	_refresh_viewmodel()
	emit_signal("died")
	toast("ELIMINADO", COLOR_RED)
	if auto_respawn:
		await get_tree().create_timer(2.0).timeout
		if is_inside_tree():
			respawn()

func respawn():
	revive_at(spawn_position)

func revive_at(pos: Vector3) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	health = max_health
	armor = start_armor
	is_dashing = false
	dead = false
	ult_active = false
	ult_points = 0
	knives = 0
	knives_in_flight = 0
	equipped = Equip.NONE
	equipped_slot = "c"
	buy_open = false
	_reset_kit()
	_refresh_viewmodel()

# ==================================================
# CAMERA
# ==================================================

func add_shake(amount: float):
	if enable_camera_shake:
		trauma = minf(1.0, trauma + amount)

func update_camera(delta):
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()

	# FOV
	var target_fov := base_fov
	if is_dashing:
		target_fov = dash_fov
	elif updraft_fx_timer > 0.0:
		target_fov = updraft_fov
	elif is_drifting:
		target_fov = base_fov + 3.0
	elif horizontal_speed > run_speed * 1.05:
		target_fov = base_fov + 4.0
	camera.fov = lerpf(camera.fov, target_fov, clampf(fov_smooth * delta, 0.0, 1.0))

	# ALTURA (agachar + headbob + impacto de aterragem)
	land_dip = lerpf(land_dip, 0.0, clampf(9.0 * delta, 0.0, 1.0))
	var target_y := camera_base_position.y - crouch_depth * crouch_t - land_dip
	# Inércia subtil da câmara: acompanha acelerações sem alterar a direção da mira.
	var local_velocity := global_transform.basis.inverse() * Vector3(velocity.x, 0.0, velocity.z)
	var lag_target := Vector2(clampf(-local_velocity.x * 0.0035, -0.035, 0.035),
		clampf(local_velocity.z * 0.0018, -0.025, 0.025))
	camera_motion_lag = camera_motion_lag.lerp(lag_target, clampf(7.0 * delta, 0.0, 1.0))
	var target_x := camera_base_position.x + camera_motion_lag.x
	var target_z := camera_base_position.z + camera_motion_lag.y
	camera.position.x = lerpf(camera.position.x, target_x, clampf(10.0 * delta, 0.0, 1.0))
	camera.position.z = lerpf(camera.position.z, target_z, clampf(10.0 * delta, 0.0, 1.0))
	if is_on_floor() and horizontal_speed > 0.5 and not is_dashing:
		move_time += delta * headbob_speed * (horizontal_speed / run_speed)
		target_y += sin(move_time) * headbob_amount
	else:
		move_time = 0.0
	camera.position.y = lerpf(camera.position.y, target_y, clampf(14.0 * delta, 0.0, 1.0))

	# PITCH (rato + kick)
	pitch_kick = lerpf(pitch_kick, 0.0, clampf(9.0 * delta, 0.0, 1.0))
	camera.rotation.x = mouse_pitch + pitch_kick

	# ROLL (strafe + dash lateral)
	var input_dir := get_move_input()
	var target_roll := -input_dir.x * camera_tilt
	if is_dashing:
		target_roll += -dash_direction.dot(transform.basis.x) * 0.07
	camera.rotation.z = lerpf(camera.rotation.z, target_roll, clampf(10.0 * delta, 0.0, 1.0))

	# SHAKE (trauma)
	if enable_camera_shake and trauma > 0.0:
		trauma = maxf(0.0, trauma - delta * 1.6)
		var s := trauma * trauma
		camera.h_offset = randf_range(-1.0, 1.0) * s * 0.3
		camera.v_offset = randf_range(-1.0, 1.0) * s * 0.3
		camera.rotation.z += randf_range(-1.0, 1.0) * s * 0.04
	else:
		camera.h_offset = lerpf(camera.h_offset, 0.0, clampf(12.0 * delta, 0.0, 1.0))
		camera.v_offset = lerpf(camera.v_offset, 0.0, clampf(12.0 * delta, 0.0, 1.0))

# ==================================================
# FX: PARTÍCULAS PERSISTENTES / LINHAS DE VELOCIDADE
# ==================================================

func update_fx(delta):
	updraft_fx_timer = maxf(0.0, updraft_fx_timer - delta)

	var target := 0.0
	if is_dashing:
		target = 1.0
	elif updraft_fx_timer > 0.0:
		target = 0.55
	if target > speed_intensity:
		speed_intensity = target
	else:
		speed_intensity = lerpf(speed_intensity, 0.0, clampf(6.0 * delta, 0.0, 1.0))

	if speed_overlay:
		var on := enable_speed_lines and speed_intensity > 0.01
		speed_overlay.visible = on
		if on:
			(speed_overlay.material as ShaderMaterial).set_shader_parameter("intensity", speed_intensity)

	if dash_trail:
		dash_trail.emitting = enable_particles and is_dashing
	if air_trail:
		air_trail.emitting = enable_particles and (updraft_fx_timer > 0.0 or is_drifting)
	if drift_puffs:
		drift_puffs.emitting = enable_particles and is_drifting

func landing_effect(impact_speed: float):
	if not enable_landing_effect:
		return
	var impact := clampf((impact_speed - 4.5) / 12.0, 0.0, 1.0)
	if impact <= 0.0:
		return
	add_shake(0.08 + impact * 0.3)
	pitch_kick = -0.03 - impact * 0.05
	land_dip = 0.05 + impact * 0.18
	if enable_particles:
		burst(global_position + Vector3(0, 0.1, 0), {"amount": int(8 + impact * 18), "lifetime": 0.7,
			"size": 0.8, "v_min": 1.5, "v_max": 4.0, "spread": 80.0, "damping": 3.0, "grow": true,
			"emit_radius": 0.3, "color": Color(0.82, 0.87, 0.92, 0.5), "fade_start": 0.3})
		if impact > 0.4:
			spawn_ring(global_position + Vector3(0, 0.05, 0), Vector3.UP, Color(0.8, 0.95, 1.0, 0.6),
				3.0 + impact * 3.0, 0.4, 0.4)

# ==================================================
# FX: GERADORES
# ==================================================

func _make_soft_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.4), Color(1, 1, 1, 0.0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t

func _fade_ramp(color: Color, fade_start := 0.0) -> GradientTexture1D:
	var g := Gradient.new()
	var clear := Color(color.r, color.g, color.b, 0.0)
	if fade_start <= 0.0:
		g.offsets = PackedFloat32Array([0.0, 1.0])
		g.colors = PackedColorArray([color, clear])
	else:
		g.offsets = PackedFloat32Array([0.0, fade_start, 1.0])
		g.colors = PackedColorArray([color, color, clear])
	var t := GradientTexture1D.new()
	t.gradient = g
	return t

# Cria um emissor configurável por dicionário (não adiciona à cena)
func make_emitter(o: Dictionary) -> GPUParticles3D:
	var color: Color = o.get("color", wind_color)
	var p := GPUParticles3D.new()
	p.amount = o.get("amount", 30)
	p.lifetime = o.get("lifetime", 0.6)
	p.one_shot = o.get("one_shot", true)
	p.explosiveness = o.get("explosiveness", 0.9)
	p.local_coords = false
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-25, -25, -25), Vector3(50, 50, 50))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var pm := ParticleProcessMaterial.new()
	pm.direction = o.get("direction", Vector3.UP)
	pm.spread = o.get("spread", 180.0)
	pm.initial_velocity_min = o.get("v_min", 1.0)
	pm.initial_velocity_max = o.get("v_max", 4.0)
	pm.gravity = o.get("gravity", Vector3.ZERO)
	pm.damping_min = o.get("damping", 0.0)
	pm.damping_max = o.get("damping", 0.0)
	pm.scale_min = o.get("scale_min", 0.8)
	pm.scale_max = o.get("scale_max", 1.2)
	pm.color_ramp = _fade_ramp(color, o.get("fade_start", 0.0))
	pm.particle_flag_align_y = o.get("streak", false)

	var radius: float = o.get("emit_radius", 0.0)
	if radius > 0.0:
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = radius

	if o.get("grow", false):
		var c := Curve.new()
		c.add_point(Vector2(0.0, 0.25))
		c.add_point(Vector2(0.2, 1.0))
		c.add_point(Vector2(1.0, 1.15))
		var ct := CurveTexture.new()
		ct.curve = c
		pm.scale_curve = ct
	elif o.get("shrink", false):
		var c2 := Curve.new()
		c2.add_point(Vector2(0.0, 1.0))
		c2.add_point(Vector2(1.0, 0.1))
		var ct2 := CurveTexture.new()
		ct2.curve = c2
		pm.scale_curve = ct2

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if o.get("additive", false):
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD

	if o.get("streak", false):
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.0
		cyl.bottom_radius = o.get("streak_width", 0.012)
		cyl.height = o.get("streak_length", 0.9)
		cyl.radial_segments = 4
		cyl.rings = 1
		cyl.material = mat
		p.draw_pass_1 = cyl
	else:
		mat.albedo_texture = soft_texture
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		mat.billboard_keep_scale = true
		mat.particles_anim_h_frames = 1
		mat.particles_anim_v_frames = 1
		mat.particles_anim_loop = false
		var quad := QuadMesh.new()
		var sz: float = o.get("size", 0.2)
		quad.size = Vector2(sz, sz)
		quad.material = mat
		p.draw_pass_1 = quad

	p.process_material = pm
	return p

# Rajada única na posição (liberta-se sozinha)
func burst(pos: Vector3, o: Dictionary) -> GPUParticles3D:
	var p := make_emitter(o)
	get_tree().current_scene.add_child(p)
	p.global_position = pos
	p.emitting = true
	_free_later(p, p.lifetime + 0.6)
	return p

func _free_later(node: Node, t: float):
	await get_tree().create_timer(t).timeout
	if is_instance_valid(node):
		node.queue_free()

# Anel expansivo (eixo = direção para onde o anel "aponta")
func spawn_ring(pos: Vector3, axis: Vector3, color: Color, final_scale: float, duration: float, radius := 0.4):
	if not enable_particles:
		return
	var holder := Node3D.new()
	get_tree().current_scene.add_child(holder)
	holder.global_position = pos
	holder.quaternion = Quaternion(Vector3.UP, axis.normalized())

	var mesh_i := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius - 0.04
	torus.outer_radius = radius
	torus.rings = 32
	torus.ring_segments = 6
	mesh_i.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = color
	mesh_i.material_override = mat
	mesh_i.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(mesh_i)

	holder.scale = Vector3.ONE * 0.3
	var tw := holder.create_tween()
	tw.set_parallel(true)
	tw.tween_property(holder, "scale", Vector3.ONE * final_scale, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, duration)
	tw.chain().tween_callback(holder.queue_free)

func _build_fx_emitters():
	dash_trail = make_emitter({"amount": 70, "lifetime": 0.4, "one_shot": false, "explosiveness": 0.0,
		"streak": true, "additive": true, "shrink": true, "direction": Vector3.BACK, "spread": 10.0,
		"v_min": 6.0, "v_max": 12.0, "emit_radius": 0.5, "streak_length": 1.4, "streak_width": 0.014,
		"color": Color(0.8, 0.97, 1.0, 0.9)})
	add_child(dash_trail)
	dash_trail.position = Vector3(0, 1.0, 0)

	air_trail = make_emitter({"amount": 45, "lifetime": 0.5, "one_shot": false, "explosiveness": 0.0,
		"streak": true, "additive": true, "shrink": true, "direction": Vector3.DOWN, "spread": 12.0,
		"v_min": 2.0, "v_max": 5.0, "emit_radius": 0.6, "streak_length": 1.2,
		"color": Color(0.8, 0.97, 1.0, 0.8)})
	add_child(air_trail)
	air_trail.position = Vector3(0, 1.0, 0)

	drift_puffs = make_emitter({"amount": 22, "lifetime": 0.7, "one_shot": false, "explosiveness": 0.0,
		"size": 0.5, "additive": true, "direction": Vector3.DOWN, "spread": 60.0, "v_min": 0.3, "v_max": 1.2,
		"damping": 1.0, "emit_radius": 0.3, "grow": true, "color": Color(0.6, 0.92, 1.0, 0.55)})
	add_child(drift_puffs)
	drift_puffs.position = Vector3(0, 0.15, 0)

# ==================================================
# VIEWMODEL (mãos com luvas + kunai, estilo Valorant)
# ==================================================

# [posição, rotação] de cada kunai à volta das mãos (3 na direita, 2 na esquerda)
# Cinco kunais distribuídas pelas laterais do ecrã, como na referência.
# Cada entrada contém [posição, rotação] no espaço da câmara.
const KNIFE_SLOTS := [
	[Vector3(-1.30, 0.30, -1.02), Vector3(0.08, -1.12, 0.22)],
	[Vector3(-1.30, -0.18, -1.00), Vector3(0.12, -1.28, 0.12)],
	[Vector3(1.30, 0.30, -1.02), Vector3(0.08, 1.12, -0.22)],
	[Vector3(1.30, -0.18, -1.00), Vector3(0.12, 1.28, -0.12)],
	[Vector3(0.00, -0.70, -1.04), Vector3(0.05, 0.0, 0.0)],
]

func _mat(color: Color, rough := 0.7, metal := 0.0, emis := Color.BLACK, emis_e := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if emis_e > 0.0:
		m.emission_enabled = true
		m.emission = emis
		m.emission_energy_multiplier = emis_e
	return m

func _mesh_node(mesh: Mesh, mat: Material, pos := Vector3.ZERO, rot := Vector3.ZERO) -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.mesh = mesh
	n.material_override = mat
	n.position = pos
	n.rotation = rot
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return n

# Kunai da Jett: ponta aponta para -Z (também usado nas facas lançadas)
func _make_blade() -> Node3D:
	var root := Node3D.new()
	var steel := _mat(Color(0.72, 0.79, 0.86), 0.22, 0.9)
	var dark := _mat(Color(0.035, 0.055, 0.075), 0.42, 0.65)
	var cyan := _mat(Color(0.35, 0.9, 1.0), 0.22, 0.15, Color(0.25, 0.85, 1.0), 2.6)
	var edge := _mat(Color(0.94, 0.98, 1.0), 0.18, 0.85)

	# Lâmina triangular metálica, mais comprida e legível à distância.
	var blade_mesh := PrismMesh.new()
	blade_mesh.size = Vector3(0.105, 0.285, 0.018)
	blade_mesh.left_to_right = 0.48
	root.add_child(_mesh_node(blade_mesh, steel, Vector3(0, 0, -0.155), Vector3(-PI / 2.0, 0, 0)))

	# Fio claro e núcleo de energia azul.
	var edge_mesh := BoxMesh.new()
	edge_mesh.size = Vector3(0.009, 0.20, 0.006)
	root.add_child(_mesh_node(edge_mesh, edge, Vector3(0.0, 0.005, -0.16), Vector3(-PI / 2.0, 0, 0)))

	var energy_mesh := BoxMesh.new()
	energy_mesh.size = Vector3(0.012, 0.14, 0.009)
	root.add_child(_mesh_node(energy_mesh, cyan, Vector3(0.0, 0.012, -0.16), Vector3(-PI / 2.0, 0, 0)))

	# Guarda e cabo escuros.
	var guard := BoxMesh.new()
	guard.size = Vector3(0.13, 0.018, 0.025)
	root.add_child(_mesh_node(guard, dark, Vector3(0, 0, -0.005)))

	var handle := CylinderMesh.new()
	handle.top_radius = 0.019
	handle.bottom_radius = 0.022
	handle.height = 0.105
	root.add_child(_mesh_node(handle, dark, Vector3(0, 0, 0.065), Vector3(PI / 2.0, 0, 0)))

	var pommel := TorusMesh.new()
	pommel.inner_radius = 0.014
	pommel.outer_radius = 0.022
	root.add_child(_mesh_node(pommel, steel, Vector3(0, 0, 0.13), Vector3(PI / 2.0, 0, 0)))

	# Pequenos brilhos laterais.
	var glint_left := BoxMesh.new()
	glint_left.size = Vector3(0.008, 0.055, 0.008)
	root.add_child(_mesh_node(glint_left, cyan, Vector3(-0.035, 0.012, -0.22), Vector3(0, 0, -0.22)))

	var glint_right := BoxMesh.new()
	glint_right.size = Vector3(0.008, 0.055, 0.008)
	root.add_child(_mesh_node(glint_right, cyan, Vector3(0.035, 0.012, -0.22), Vector3(0, 0, 0.22)))

	return root

func _make_hand(side: float) -> Node3D:
	# Mão procedural inspirada na pose da imagem: antebraço exposto,
	# luva preta sem dedos, punho turquesa e símbolo branco.
	var skin := _mat(Color(0.91, 0.70, 0.60), 0.82)
	var skin_light := _mat(Color(0.98, 0.79, 0.69), 0.78)
	var glove := _mat(Color(0.025, 0.032, 0.043), 0.88)
	var glove_edge := _mat(Color(0.10, 0.13, 0.16), 0.72)
	var cuff := _mat(Color(0.08, 0.55, 0.66), 0.42, 0.1, Color(0.12, 0.72, 0.9), 0.8)
	var white := _mat(Color(0.96, 0.98, 1.0), 0.48, 0.05, Color(0.8, 0.95, 1.0), 0.35)

	var h := Node3D.new()

	# Antebraço em cápsula para evitar o aspeto de cilindro rígido.
	var forearm := CapsuleMesh.new()
	forearm.radius = 0.057
	forearm.height = 0.48
	var forearm_node := _mesh_node(
		forearm,
		skin,
		Vector3(side * 0.08, -0.105, 0.245),
		Vector3(PI / 2.0, side * 0.90, side * 0.06)
	)
	forearm_node.scale = Vector3(1.0, 1.0, 0.92)
	h.add_child(forearm_node)

	# Transição de pele junto ao pulso.
	var wrist := SphereMesh.new()
	wrist.radius = 0.061
	wrist.height = 0.12
	var wrist_node := _mesh_node(wrist, skin_light, Vector3(0, -0.005, 0.115))
	wrist_node.scale = Vector3(1.0, 0.72, 0.9)
	h.add_child(wrist_node)

	# Punho turquesa e duas linhas escuras.
	var cuff_mesh := CylinderMesh.new()
	cuff_mesh.top_radius = 0.064
	cuff_mesh.bottom_radius = 0.064
	cuff_mesh.height = 0.055
	h.add_child(_mesh_node(cuff_mesh, cuff, Vector3(0, 0, 0.075), Vector3(PI / 2.0, 0, 0)))

	var cuff_line := CylinderMesh.new()
	cuff_line.top_radius = 0.066
	cuff_line.bottom_radius = 0.066
	cuff_line.height = 0.012
	h.add_child(_mesh_node(cuff_line, glove_edge, Vector3(0, 0, 0.105), Vector3(PI / 2.0, 0, 0)))

	# Palma e dorso da luva em formas arredondadas.
	var palm := SphereMesh.new()
	palm.radius = 0.125
	palm.height = 0.09
	var palm_node := _mesh_node(palm, skin, Vector3(0, 0, -0.005))
	palm_node.scale = Vector3(1.0, 0.72, 1.0)
	h.add_child(palm_node)

	var glove_back := SphereMesh.new()
	glove_back.radius = 0.12
	glove_back.height = 0.075
	var glove_node := _mesh_node(glove_back, glove, Vector3(0, 0.018, 0.025))
	glove_node.scale = Vector3(1.0, 0.72, 1.0)
	h.add_child(glove_node)

	# Quatro dedos: bases cobertas pela luva e pontas expostas.
	for i in range(4):
		var spread := float(i) - 1.5
		var finger_x := spread * 0.047
		var finger_length: float = 0.105
		if i == 1:
			finger_length = 0.132
		elif i == 2:
			finger_length = 0.125
		elif i == 3:
			finger_length = 0.098
		var finger_angle: float = spread * 0.075

		var glove_segment := CapsuleMesh.new()
		glove_segment.radius = 0.017
		glove_segment.height = 0.072
		h.add_child(_mesh_node(
			glove_segment,
			glove,
			Vector3(finger_x, 0.012, -0.075),
			Vector3(-PI / 2.0, 0, finger_angle)
		))

		var finger_tip := CapsuleMesh.new()
		finger_tip.radius = 0.0125
		finger_tip.height = finger_length
		h.add_child(_mesh_node(
			finger_tip,
			skin_light,
			Vector3(finger_x * 1.08, 0.006, -0.145 - finger_length * 0.34),
			Vector3(-PI / 2.0, 0, finger_angle)
		))

	# Polegar aberto para fora.
	var thumb := CapsuleMesh.new()
	thumb.radius = 0.015
	thumb.height = 0.105
	h.add_child(_mesh_node(
		thumb,
		skin_light,
		Vector3(-side * 0.105, 0.0, -0.025),
		Vector3(-PI / 2.0, 0, side * 0.78)
	))

	var thumb_glove := CapsuleMesh.new()
	thumb_glove.radius = 0.019
	thumb_glove.height = 0.052
	h.add_child(_mesh_node(
		thumb_glove,
		glove,
		Vector3(-side * 0.077, 0.012, 0.025),
		Vector3(-PI / 2.0, 0, side * 0.78)
	))

	# Marca branca em forma de seta no dorso da luva.
	var mark_a := BoxMesh.new()
	mark_a.size = Vector3(0.060, 0.009, 0.008)
	h.add_child(_mesh_node(mark_a, white, Vector3(-0.018, 0.045, 0.108), Vector3(0, 0, 0.52)))

	var mark_b := BoxMesh.new()
	mark_b.size = Vector3(0.052, 0.009, 0.008)
	h.add_child(_mesh_node(mark_b, white, Vector3(0.025, 0.045, 0.105), Vector3(0, 0, -0.52)))

	# Pose ligeiramente aberta e apontada para o centro do ecrã.
	h.rotation = Vector3(deg_to_rad(-7.0), side * deg_to_rad(11.0), -side * deg_to_rad(17.0))
	return h

func _build_viewmodel():
	viewmodel = Node3D.new()
	camera.add_child(viewmodel)

	# Mãos mais afastadas e baixas: deixam o centro livre para apontar.
	hand_l = _make_hand(-1.0)
	hand_l.position = Vector3(-0.39, -0.39, -0.69)
	viewmodel.add_child(hand_l)

	hand_r = _make_hand(1.0)
	hand_r.position = Vector3(0.39, -0.42, -0.69)
	viewmodel.add_child(hand_r)

	# Orbe da Cloudburst, mantido oculto até equipar C.
	smoke_vm = Node3D.new()
	smoke_vm.position = Vector3(0.22, -0.19, -0.54)
	viewmodel.add_child(smoke_vm)

	var orb := SphereMesh.new()
	orb.radius = 0.052
	orb.height = 0.104
	smoke_vm.add_child(_mesh_node(orb, _mat(Color(0.8, 0.95, 1.0), 0.28, 0.0, Color(0.4, 0.9, 1.0), 2.5)))

	var glow := SphereMesh.new()
	glow.radius = 0.09
	glow.height = 0.18
	var glow_mat := StandardMaterial3D.new()
	glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	glow_mat.albedo_color = Color(0.4, 0.9, 1.0, 0.22)
	smoke_vm.add_child(_mesh_node(glow, glow_mat))

	# Cinco kunais flutuantes em redor das mãos.
	knife_vm_root = Node3D.new()
	knife_vm_root.visible = false
	viewmodel.add_child(knife_vm_root)

	for i in range(KNIFE_SLOTS.size()):
		var blade := _make_blade()
		blade.position = KNIFE_SLOTS[i][0]
		blade.rotation = KNIFE_SLOTS[i][1]
		blade.scale = Vector3.ONE * 0.92
		blade.visible = false
		knife_vm_root.add_child(blade)
		blades.append(blade)

	# Garantir que as kunais começam escondidas.
	knife_vm_root.visible = false

func _refresh_viewmodel():
	if viewmodel == null:
		return
	smoke_vm.visible = equipped == Equip.SMOKE

	# Só mostrar as kunais durante a Ultimate, quando estão equipadas
	# e ainda existe pelo menos uma faca disponível.
	var show_knives := ult_active and equipped == Equip.KNIVES and knives > 0
	knife_vm_root.visible = show_knives
	for i in range(blades.size()):
		blades[i].visible = show_knives and i < knives
	vm_equip = 1.0

func _update_viewmodel(delta):
	if viewmodel == null:
		return

	vm_kick = lerpf(vm_kick, 0.0, clampf(13.0 * delta, 0.0, 1.0))
	vm_equip = lerpf(vm_equip, 0.0, clampf(9.0 * delta, 0.0, 1.0))

	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var movement_amount := clampf(horizontal_speed / maxf(run_speed, 0.01), 0.0, 1.0)
	vm_bob += delta * (2.2 + horizontal_speed * 0.95)

	# Movimento discreto das mãos; sem oscilações exageradas.
	var bob_y := sin(vm_bob) * 0.009 * movement_amount
	var bob_x := sin(vm_bob * 0.5) * 0.006 * movement_amount
	var ability_lift := 0.035 if updraft_fx_timer > 0.0 else 0.0
	var dash_push := 0.045 if is_dashing else 0.0

	var target_vm := Vector3(0.0, -0.018 * vm_equip + bob_y, vm_kick + dash_push)
	viewmodel.position = viewmodel.position.lerp(target_vm, clampf(16.0 * delta, 0.0, 1.0))
	viewmodel.rotation.x = lerpf(viewmodel.rotation.x, vm_kick * 0.8, clampf(12.0 * delta, 0.0, 1.0))

	if hand_l and hand_r:
		var left_target := Vector3(-0.39 - bob_x, -0.39 + bob_y + ability_lift, -0.69 - dash_push)
		var right_target := Vector3(0.39 - bob_x, -0.42 + bob_y + ability_lift, -0.69 - dash_push)
		hand_l.position = hand_l.position.lerp(left_target, clampf(14.0 * delta, 0.0, 1.0))
		hand_r.position = hand_r.position.lerp(right_target, clampf(14.0 * delta, 0.0, 1.0))

		var hand_roll := 0.025 if is_dashing else 0.0
		hand_l.rotation.z = lerpf(hand_l.rotation.z, deg_to_rad(17.0) + hand_roll, clampf(10.0 * delta, 0.0, 1.0))
		hand_r.rotation.z = lerpf(hand_r.rotation.z, deg_to_rad(-17.0) - hand_roll, clampf(10.0 * delta, 0.0, 1.0))

	# Kunais flutuam suavemente; cada uma tem uma fase própria.
	for i in range(blades.size()):
		var blade: Node3D = blades[i]
		var base_position: Vector3 = KNIFE_SLOTS[i][0]
		var base_rotation: Vector3 = KNIFE_SLOTS[i][1]
		var phase := hud_time * 1.65 + float(i) * 1.35

		blade.position = base_position + Vector3(
			sin(phase * 0.7) * 0.012,
			sin(phase) * 0.018,
			cos(phase * 0.8) * 0.012
		)
		blade.rotation = base_rotation + Vector3(
			sin(phase) * 0.035,
			cos(phase * 0.8) * 0.045,
			sin(phase * 0.6) * 0.035
		)

# ==================================================
# HUD (estilo Valorant)
# ==================================================

func _label(text: String, size := 14, color := Color.WHITE, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 3)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _rect(parent: Node, pos: Vector2, sz: Vector2, color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.position = pos
	r.size = sz
	r.color = color
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r

func _build_hud():
	hud = CanvasLayer.new()
	hud.layer = 10
	add_child(hud)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(root)

	speed_overlay = ColorRect.new()
	speed_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	speed_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SPEED_SHADER
	var sm := ShaderMaterial.new()
	sm.shader = sh
	speed_overlay.material = sm
	speed_overlay.visible = false
	root.add_child(speed_overlay)

	damage_flash = ColorRect.new()
	damage_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	damage_flash.color = Color(1, 0.1, 0.15, 0.0)
	root.add_child(damage_flash)

	_build_crosshair(root)
	_build_scoreboard(root)
	_build_minimap(root)
	_build_killfeed(root)
	_build_bottom_hud(root)

	toast_label = _label("", 22, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	toast_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast_label.offset_left = -300
	toast_label.offset_right = 300
	toast_label.offset_top = 110
	toast_label.offset_bottom = 150
	toast_label.modulate.a = 0.0
	root.add_child(toast_label)

	knife_label = _label("", 18, COLOR_GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	knife_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	knife_label.offset_left = -150
	knife_label.offset_right = 150
	knife_label.offset_top = -126
	knife_label.offset_bottom = -102
	knife_label.visible = false
	root.add_child(knife_label)

	hint_label = _label(_hint_text(), 12, Color(1, 1, 1, 0.7))
	hint_label.position = Vector2(16, 232)
	root.add_child(hint_label)

# ---------- MIRA ----------

func _build_crosshair(parent: Control):
	crosshair = Control.new()
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(crosshair)

	for kind in range(4):
		var sh := _rect(crosshair, Vector2.ZERO, Vector2(2, 2), Color(0, 0, 0, 0.6))
		var n := _rect(crosshair, Vector2.ZERO, Vector2(2, 2), COLOR_CYAN)
		ch_parts.append({"kind": kind, "node": n, "shadow": sh})
	_rect(crosshair, Vector2(-2, -2), Vector2(4, 4), Color(0, 0, 0, 0.6))
	_rect(crosshair, Vector2(-1, -1), Vector2(2, 2), COLOR_CYAN)
	_layout_crosshair(ch_gap)

	hitmarker = Control.new()
	hitmarker.set_anchors_preset(Control.PRESET_CENTER)
	hitmarker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hitmarker.visible = false
	parent.add_child(hitmarker)
	for ang in [PI / 4.0, -PI / 4.0]:
		var r := _rect(hitmarker, Vector2(-9, -1), Vector2(18, 2), Color.WHITE)
		r.pivot_offset = Vector2(9, 1)
		r.rotation = ang

func _layout_crosshair(gap: float):
	var th := 2.0
	var ln := 7.0
	for p in ch_parts:
		var n: ColorRect = p["node"]
		var s: ColorRect = p["shadow"]
		match p["kind"]:
			0:
				n.position = Vector2(-th / 2.0, -gap - ln)
				n.size = Vector2(th, ln)
			1:
				n.position = Vector2(-th / 2.0, gap)
				n.size = Vector2(th, ln)
			2:
				n.position = Vector2(-gap - ln, -th / 2.0)
				n.size = Vector2(ln, th)
			3:
				n.position = Vector2(gap, -th / 2.0)
				n.size = Vector2(ln, th)
		s.position = n.position - Vector2.ONE
		s.size = n.size + Vector2(2, 2)

func _show_hitmarker(killed: bool):
	if hitmarker == null:
		return
	hitmarker.visible = true
	hitmarker.modulate = COLOR_RED if killed else Color.WHITE
	hitmarker.scale = Vector2.ONE * (1.4 if killed else 1.0)
	var tw := create_tween()
	tw.tween_interval(0.08)
	tw.tween_property(hitmarker, "modulate:a", 0.0, 0.2)
	tw.tween_callback(func(): hitmarker.visible = false)

# ---------- PLACAR NO TOPO ----------

func _score_box(parent: Control, text: String, size_px: Vector2, fsize: int, accent: Color) -> Label:
	var p := Panel.new()
	p.custom_minimum_size = size_px
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.04, 0.07, 0.1, 0.85)
	st.border_width_bottom = 2
	st.border_color = accent
	st.set_corner_radius_all(2)
	p.add_theme_stylebox_override("panel", st)
	parent.add_child(p)
	var l := _label(text, fsize, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	p.add_child(l)
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l

func _build_scoreboard(parent: Control):
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	bar.set_anchors_preset(Control.PRESET_CENTER_TOP)
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.offset_left = -340
	bar.offset_right = 340
	bar.offset_top = 6
	bar.offset_bottom = 50
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bar)
	scorebar = bar
	if match_mode:
		bar.visible = false

	var blue := HBoxContainer.new()
	blue.add_theme_constant_override("separation", 3)
	blue.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(blue)
	for n in ["J", "S", "R", "K", "V"]:
		_score_box(blue, n, Vector2(36, 40), 16, COLOR_CYAN)

	blue_score_label = _score_box(bar, str(blue_score), Vector2(52, 40), 24, COLOR_CYAN)
	timer_label = _score_box(bar, "1:40", Vector2(88, 40), 24, Color(1, 1, 1, 0.5))
	red_score_label = _score_box(bar, str(red_score), Vector2(52, 40), 24, COLOR_RED)

	var red := HBoxContainer.new()
	red.add_theme_constant_override("separation", 3)
	red.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(red)
	for n in ["B", "F", "N", "P", "Z"]:
		_score_box(red, n, Vector2(36, 40), 16, COLOR_RED)

# ---------- MINIMAPA ----------

func _build_minimap(parent: Control):
	minimap = Minimap.new()
	minimap.jett = self
	minimap.position = Vector2(16, 62)
	minimap.size = Vector2(160, 160)
	minimap.custom_minimum_size = Vector2(160, 160)
	minimap.clip_contents = true
	minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(minimap)

# ---------- KILLFEED ----------

func _build_killfeed(parent: Control):
	killfeed = VBoxContainer.new()
	killfeed.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	killfeed.offset_left = -300
	killfeed.offset_right = -16
	killfeed.offset_top = 62
	killfeed.offset_bottom = 300
	killfeed.add_theme_constant_override("separation", 4)
	killfeed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(killfeed)

func add_kill_feed(victim: String):
	if killfeed == null:
		return
	if killfeed.get_child_count() >= 5:
		killfeed.get_child(0).queue_free()
	var p := Panel.new()
	p.custom_minimum_size = Vector2(0, 26)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.04, 0.07, 0.1, 0.8)
	st.border_width_left = 3
	st.border_color = COLOR_RED
	st.set_corner_radius_all(2)
	p.add_theme_stylebox_override("panel", st)
	killfeed.add_child(p)
	var l := _label("Jett  >  %s" % victim, 14, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	p.add_child(l)
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.offset_right = -8
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var tw := p.create_tween()
	tw.tween_interval(4.0)
	tw.tween_property(p, "modulate:a", 0.0, 0.5)
	tw.tween_callback(p.queue_free)

# ---------- BARRA INFERIOR ----------

func _new_icon(parent: Control, kind: String, key: String) -> AbilityIcon:
	var ic := AbilityIcon.new()
	ic.kind = kind
	ic.key = key
	parent.add_child(ic)
	return ic

func _build_bottom_hud(parent: Control):
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.offset_left = -150
	row.offset_right = 150
	row.offset_top = -100
	row.offset_bottom = -20
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)

	icons = {}
	for slot in SLOT_ORDER:
		icons[slot] = _new_icon(row, "smoke", str(SLOT_KEYS[slot]))

	# vida + escudo (à esquerda das habilidades)
	var hp := Control.new()
	hp.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hp.offset_left = -350
	hp.offset_right = -160
	hp.offset_top = -100
	hp.offset_bottom = -20
	hp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(hp)

	shield_icon = AbilityIcon.new()
	shield_icon.kind = "shield"
	shield_icon.custom_minimum_size = Vector2(28, 30)
	shield_icon.glyph_color = COLOR_CYAN
	shield_icon.position = Vector2(0, 40)
	hp.add_child(shield_icon)

	armor_label = _label("50", 16, Color(0.6, 0.88, 1.0))
	armor_label.position = Vector2(32, 42)
	hp.add_child(armor_label)

	health_label = _label("100", 46, Color.WHITE)
	health_label.position = Vector2(74, 16)
	hp.add_child(health_label)

	var line := _rect(parent, Vector2.ZERO, Vector2(1, 1), Color(1, 1, 1, 0.25))
	line.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	line.offset_left = -350
	line.offset_right = 350
	line.offset_top = -14
	line.offset_bottom = -13

func toast(text: String, color := Color.WHITE):
	if toast_label == null:
		return
	toast_label.text = text
	toast_label.modulate = Color(color.r, color.g, color.b, 1.0)
	if toast_tween:
		toast_tween.kill()
	toast_tween = create_tween()
	toast_tween.tween_interval(1.1)
	toast_tween.tween_property(toast_label, "modulate:a", 0.0, 0.5)

func _set_icon(ic: AbilityIcon, glyph: Color, ring: Color, frac: float, txt: String, filled: int, total: int, diamond := false, accent := COLOR_CYAN):
	ic.glyph_color = glyph
	ic.ring_color = ring
	ic.frac = frac
	ic.txt = txt
	ic.pips_filled = filled
	ic.pips_total = total
	ic.pip_diamond = diamond
	ic.accent = accent

func _update_hud(delta):
	if hud == null:
		return
	hud_time += delta
	var pulse := 0.5 + 0.5 * sin(hud_time * 6.0)

	# relógio local (no modo partida quem manda é o HUD do match)
	round_time_left -= delta
	if round_time_left <= 0.0:
		round_time_left = 100.0
	var secs := ceili(round_time_left)
	timer_label.text = "%d:%02d" % [floori(secs / 60.0), secs % 60]
	timer_label.add_theme_color_override("font_color", COLOR_RED if round_time_left < 10.0 else Color.WHITE)
	blue_score_label.text = str(blue_score)
	red_score_label.text = str(red_score)

	var white := Color(0.95, 0.98, 1.0)
	var dim := Color(0.5, 0.55, 0.6)

	for slot in SLOT_ORDER:
		var ic = icons.get(slot, null)
		if ic == null:
			continue
		var ab := _ab(slot)
		if ab.is_empty():
			continue
		ic.kind = _icon_kind(str(ab.get("type", "")))
		ic.accent = ability_color

		var frac := 0.0
		var txt := ""
		var filled := 0
		var total := 0
		var ring := COLOR_DIM
		var glyph := dim
		var is_ult := bool(ab.get("ult", false))

		if is_ult:
			var ready := ult_points >= ult_cost
			filled = ult_points
			total = ult_cost
			if ult_active:
				txt = str(knives)
				ring = COLOR_CYAN if equipped == Equip.KNIVES else COLOR_GOLD
				glyph = COLOR_GOLD
			elif ready:
				ring = COLOR_GOLD.lerp(Color.WHITE, pulse * 0.6)
				glyph = COLOR_GOLD
			else:
				glyph = dim
		else:
			var charges := int(ab.get("charges", 0))
			var maxc := int(ab.get("max_charges", 1))
			filled = charges
			total = maxc
			if charges > 0:
				glyph = white
				ring = white
				if equipped == Equip.SMOKE and slot == equipped_slot:
					ring = ability_color
			else:
				var rec := maxf(float(ab.get("recharge", 10.0)), 0.1)
				frac = clampf(float(ab.get("recharge_t", 0.0)) / rec, 0.0, 1.0)
				txt = str(ceili(float(ab.get("recharge_t", 0.0))))

		_set_icon(ic, glyph, ring, frac, txt, filled, total, is_ult, COLOR_GOLD if is_ult else ability_color)

	knife_label.visible = ult_active
	if ult_active:
		knife_label.text = "FACAS  %d / %d" % [knives, knives_max]

	# VIDA / ESCUDO
	health_label.text = str(ceili(health))
	health_label.add_theme_color_override("font_color", COLOR_RED if health < 30.0 else Color.WHITE)
	armor_label.text = str(ceili(armor))
	shield_icon.visible = armor > 0.0
	armor_label.visible = armor > 0.0

	# MIRA dinâmica
	var spd := Vector2(velocity.x, velocity.z).length()
	var target_gap := 5.0 + spd * 0.35 + (7.0 if is_dashing else 0.0) + (3.0 if not is_on_floor() else 0.0)
	ch_gap = lerpf(ch_gap, target_gap, clampf(14.0 * delta, 0.0, 1.0))
	_layout_crosshair(ch_gap)

# ==================================================
# CLASSES DE UI
# ==================================================

# Ícone de habilidade desenhado por código (sem imagens)
class AbilityIcon extends Control:
	var kind := "smoke"
	var key := ""
	var frac := 0.0
	var txt := ""
	var glyph_color := Color(0.95, 0.98, 1.0)
	var ring_color := Color(0.95, 0.98, 1.0)
	var accent := Color(0.35, 0.88, 1.0)
	var pips_total := 0
	var pips_filled := 0
	var pip_diamond := false

	func _init():
		custom_minimum_size = Vector2(64, 80)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_d):
		queue_redraw()

	func _draw():
		if kind == "shield":
			var pts := PackedVector2Array([Vector2(2, 4), Vector2(14, 0), Vector2(26, 4),
				Vector2(26, 15), Vector2(14, 28), Vector2(2, 15)])
			draw_colored_polygon(pts, glyph_color)
			return

		var c := Vector2(32, 44)
		var r := 20.0

		# pips (cargas / orbes da ult)
		if pips_total > 0:
			var step := 10.0 if pip_diamond else 14.0
			var x0 := 32.0 - float(pips_total - 1) * step * 0.5
			for i in range(pips_total):
				var pc := accent if i < pips_filled else Color(0.3, 0.35, 0.4, 0.8)
				var p := Vector2(x0 + float(i) * step, 10.0)
				if pip_diamond:
					draw_colored_polygon(PackedVector2Array([p + Vector2(0, -4), p + Vector2(4, 0),
						p + Vector2(0, 4), p + Vector2(-4, 0)]), pc)
				else:
					draw_rect(Rect2(p - Vector2(5, 1.5), Vector2(10, 3)), pc)

		draw_circle(c, r, Color(0.04, 0.07, 0.1, 0.8))
		draw_arc(c, r, 0.0, TAU, 40, ring_color, 2.0, true)
		_glyph(c, glyph_color)

		if frac > 0.01:
			var pts2 := PackedVector2Array([c])
			var n := 32
			for i in range(n + 1):
				var a := -PI / 2.0 + TAU * minf(frac, 1.0) * float(i) / float(n)
				pts2.append(c + Vector2(cos(a), sin(a)) * (r - 1.0))
			draw_colored_polygon(pts2, Color(0, 0, 0, 0.62))

		var font := ThemeDB.fallback_font
		if txt != "":
			draw_string(font, Vector2(0, c.y + 7), txt, HORIZONTAL_ALIGNMENT_CENTER, 64, 20, Color.WHITE)
		draw_string(font, Vector2(0, 76), key, HORIZONTAL_ALIGNMENT_CENTER, 64, 13, Color(1, 1, 1, 0.9))

	func _glyph(c: Vector2, col: Color):
		match kind:
			"smoke":
				draw_arc(c + Vector2(-6, 3), 7.0, 0.0, TAU, 20, col, 2.0, true)
				draw_arc(c + Vector2(6, 3), 7.0, 0.0, TAU, 20, col, 2.0, true)
				draw_arc(c + Vector2(0, -5), 8.0, 0.0, TAU, 20, col, 2.0, true)
			"updraft":
				for k in range(2):
					var o := Vector2(0, float(k) * 9.0 - 6.0)
					draw_polyline(PackedVector2Array([c + o + Vector2(-9, 5), c + o + Vector2(0, -4),
						c + o + Vector2(9, 5)]), col, 2.5, true)
			"tailwind":
				draw_line(c + Vector2(-12, -6), c + Vector2(3, -6), col, 2.0, true)
				draw_line(c + Vector2(-14, 0), c + Vector2(8, 0), col, 2.0, true)
				draw_line(c + Vector2(-12, 6), c + Vector2(3, 6), col, 2.0, true)
				draw_polyline(PackedVector2Array([c + Vector2(5, -7), c + Vector2(13, 0), c + Vector2(5, 7)]),
					col, 2.5, true)
			"flash":
				for k in range(8):
					var a := TAU * float(k) / 8.0
					draw_line(c, c + Vector2(cos(a), sin(a)) * 12.0, col, 2.0, true)
				draw_circle(c, 3.0, col)
			"shock":
				draw_arc(c, 9.0, 0.0, TAU, 24, col, 2.0, true)
				draw_line(c + Vector2(-5, 5), c + Vector2(5, -5), col, 2.0, true)
				draw_line(c + Vector2(5, -5), c + Vector2(2, -9), col, 2.0, true)
			"heal":
				draw_rect(Rect2(c + Vector2(-3, -11), Vector2(6, 22)), col)
				draw_rect(Rect2(c + Vector2(-11, -3), Vector2(22, 6)), col)
			"mark":
				draw_arc(c, 10.0, -PI * 0.75, PI * 0.75, 20, col, 2.0, true)
				draw_arc(c, 6.0, -PI * 0.75, PI * 0.75, 20, col, 2.0, true)
				draw_circle(c + Vector2(2, 0), 2.5, col)
			"wall":
				for k in range(3):
					draw_rect(Rect2(c + Vector2(-11 + k * 8, -10), Vector2(6, 20)), col)
			"strike":
				draw_line(c + Vector2(0, -12), c + Vector2(0, 6), col, 2.5, true)
				draw_polyline(PackedVector2Array([c + Vector2(-8, 2), c + Vector2(0, 12), c + Vector2(8, 2)]), col, 2.5, true)
				draw_line(c + Vector2(-11, -12), c + Vector2(11, -12), col, 2.0, true)
			"ult":
				draw_colored_polygon(PackedVector2Array([c + Vector2(0, -14), c + Vector2(6, 0),
					c + Vector2(0, 7), c + Vector2(-6, 0)]), col)
				draw_line(c + Vector2(0, 7), c + Vector2(0, 12), col, 3.0, true)
				draw_arc(c + Vector2(0, 14), 3.0, 0.0, TAU, 12, col, 1.5, true)

# Radar: jogador ao centro, "frente" = cima. Inimigos = grupo "enemy", fumo = grupo "smoke"
class Minimap extends Control:
	var jett
	const MAP_SCALE := 3.2

	func _process(_d):
		queue_redraw()

	func _to_map(pos: Vector3) -> Vector2:
		var local: Vector3 = jett.global_transform.affine_inverse() * pos
		return size * 0.5 + Vector2(local.x, local.z) * MAP_SCALE

	func _draw():
		var c := size * 0.5
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.07, 0.1, 0.78))
		var g := 20.0
		var x := 0.0
		while x <= size.x:
			draw_line(Vector2(x, 0), Vector2(x, size.y), Color(1, 1, 1, 0.05), 1.0)
			draw_line(Vector2(0, x), Vector2(size.x, x), Color(1, 1, 1, 0.05), 1.0)
			x += g

		if jett:
			for n in get_tree().get_nodes_in_group("smoke"):
				if n is Node3D:
					draw_circle(_to_map(n.global_position), jett.smoke_radius * MAP_SCALE, Color(0.8, 0.9, 0.95, 0.35))
			for n in get_tree().get_nodes_in_group("enemy"):
				if not (n is Node3D):
					continue
				var dd = n.get("dead")
				if dd != null and bool(dd):
					continue
				var mt = n.get("mark_t")
				var marked: bool = mt != null and float(mt) > 0.0
				if not marked and n.global_position.distance_to(jett.global_position) > 20.0:
					continue
				var p: Vector2 = _to_map(n.global_position)
				draw_circle(p, 5.0 if marked else 4.0, Color(1.0, 0.28, 0.33))
			for n in get_tree().get_nodes_in_group("ally"):
				if n is Node3D:
					var ad = n.get("dead")
					if ad == null or not bool(ad):
						draw_circle(_to_map(n.global_position), 3.5, Color(0.4, 0.88, 1.0))

		var r := 70.0
		var t := tan(0.7)
		draw_colored_polygon(PackedVector2Array([c, c + Vector2(-r * t, -r), c + Vector2(r * t, -r)]),
			Color(0.35, 0.88, 1.0, 0.16))
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -7), c + Vector2(-5, 5), c + Vector2(5, 5)]),
			Color(0.35, 0.88, 1.0))
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.35, 0.88, 1.0, 0.5), false, 2.0)

# ==================================================
# PROJÉTEIS
# ==================================================

class SmokeBall extends Node3D:
	var jett
	var velocity := Vector3.ZERO
	var life := 2.5
	var done := false

	func _ready():
		var m := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.09
		s.height = 0.18
		m.mesh = s
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.8, 0.95, 1.0)
		mat.emission_enabled = true
		mat.emission = Color(0.4, 0.9, 1.0)
		mat.emission_energy_multiplier = 3.0
		m.material_override = mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(m)

		var trail = jett.make_emitter({"amount": 40, "lifetime": 0.45, "one_shot": false,
			"explosiveness": 0.0, "size": 0.35, "additive": true, "v_min": 0.0, "v_max": 0.4,
			"grow": true, "color": Color(0.55, 0.92, 1.0, 0.7)})
		add_child(trail)
		trail.emitting = true

	func _physics_process(delta):
		if done:
			return
		life -= delta

		if Input.is_action_pressed("fire"):
			# segurar = curvar na direção da mira
			var want = -jett.camera.global_transform.basis.z * velocity.length()
			velocity = velocity.move_toward(want, jett.smoke_curve_rate * delta)
			velocity.y -= jett.gravity * 0.25 * delta
		else:
			velocity.y -= jett.gravity * 0.8 * delta

		var from := global_position
		var to: Vector3 = from + velocity * delta
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.exclude = [jett.get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(q)

		if not hit.is_empty():
			_detonate(hit.position + hit.normal * (jett.smoke_radius * 0.45))
			return

		global_position = to
		if life <= 0.0:
			_detonate(global_position)

	func _detonate(pos: Vector3):
		done = true
		jett.spawn_smoke_cloud(pos)
		queue_free()

class Knife extends Node3D:
	var jett
	var velocity := Vector3.ZERO
	var damage := 50.0
	var life := 1.2
	var done := false

	func _ready():
		var m: Node3D = jett._make_blade()
		m.scale = Vector3(1.0, 1.0, 1.3)
		add_child(m)
		var trail = jett.make_emitter({"amount": 36, "lifetime": 0.25, "one_shot": false,
			"explosiveness": 0.0, "size": 0.22, "additive": true, "v_min": 0.0, "v_max": 0.3,
			"color": Color(0.55, 0.92, 1.0, 0.8)})
		add_child(trail)
		trail.emitting = true

	func _physics_process(delta):
		if done:
			return
		life -= delta
		var from := global_position
		var to: Vector3 = from + velocity * delta
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.exclude = [jett.get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(q)

		if not hit.is_empty():
			global_position = hit.position
			var collider = hit.collider
			var hit_target := false
			var killed := false
			if collider and collider.has_method("take_damage"):
				hit_target = true
				killed = collider.take_damage(damage) == true
			jett.on_knife_hit(hit.position, hit.normal, hit_target, killed, str(collider.name) if collider else "")
			_finish()
			return

		global_position = to
		if life <= 0.0:
			_finish()

	func _finish():
		done = true
		jett.knife_finished()
		queue_free()
