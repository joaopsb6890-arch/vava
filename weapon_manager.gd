extends Node

# ==================================================
# WEAPON MANAGER - Vandal + Faca (Godot 4.x)
# --------------------------------------------------
# Tem de ser FILHO do Jett (CharacterBody3D com o teu script).
# O pearl_map.gd já o adiciona automaticamente.
#
# Controlos:
#   1 ............ Vandal              2 / 3 .... Faca
#   Roda do rato . trocar de arma      R ........ recarregar
#   Esq. ......... disparar / golpe    Dir. ..... (faca) golpe forte
#   F2 ........... modo de AFINAÇÃO dos modelos (ver abaixo)
#
# As armas só ficam ativas quando NENHUMA habilidade do Jett está equipada
# (C / X). Carregar 1, 2 ou na roda do rato guarda a habilidade e saca a arma.
#
# MODO DE AFINAÇÃO (F2) - para acertar posição/rotação/tamanho do FBX:
#   Setas ............ mover X/Y        PageUp/PageDown ... mover Z
#   Shift + teclas ... rodar            Alt + Cima/Baixo ... tamanho
#   Enter ............ inverter a frente (180º)
#   Os valores aparecem na consola "Output": copia-os para o Inspector.
# ==================================================

@export_group("Modelos")
@export_file("*.fbx", "*.glb", "*.gltf", "*.tscn") var vandal_path := "res://source/vandal_v2.fbx"
@export_file("*.fbx", "*.glb", "*.gltf", "*.tscn") var knife_path := "res://source/Toy Knife.fbx"
@export var apply_textures := true
@export var texture_dirs: Array[String] = ["res://textures", "res://source/textures", "res://source"]
@export var vandal_texture_prefix := "DefaultMaterial"
@export var knife_texture_prefix := "ToyKnifeLpSEP_pink"
@export var auto_orient := true         # alinha automaticamente o eixo mais comprido para a frente
@export var use_imported_models := true # false = usa modelos 3D criados pelo script
@export var debug_models := true        # imprime tamanho/escala dos modelos na consola
@export var vandal_axis_correction := Vector3.ZERO # correção extra em graus (X, Y, Z)
@export var knife_axis_correction := Vector3.ZERO  # correção extra em graus (X, Y, Z)

@export_group("Geral")
@export_group("Loja")
@export var primary_id := "vandal"
@export var secondary_id := "classic"
@export var hide_jett_hands := true          # esconde as mãos procedurais do Jett com arma
@export var head_height := 1.45              # y acima dos pés = headshot
@export var leg_height := 0.55               # y abaixo disto = pernas
@export var max_decals := 40

@export_group("Vandal")
@export var vandal_pos := Vector3(0.30, -0.25, -0.72)
@export var vandal_rot := Vector3(0.0, -8.0, -3.0)
@export var vandal_length := 0.95
@export var vandal_flip := false
@export var vandal_muzzle := Vector3(0.2, -0.17, -1.08)
@export var vandal_rate := 9.75
@export var vandal_damage_head := 160.0
@export var vandal_damage_body := 40.0
@export var vandal_damage_leg := 34.0
@export var vandal_mag := 25
@export var vandal_reserve := 50
@export var vandal_reload_time := 2.5
@export var vandal_equip_time := 0.8

@export_group("Faca")
@export var knife_pos := Vector3(0.31, -0.27, -0.72)
@export var knife_rot := Vector3(-8.0, 24.0, -20.0)
@export var knife_length := 0.58
@export var knife_flip := false
@export var knife_damage_light := 50.0
@export var knife_damage_heavy := 150.0
@export var knife_range := 2.4
@export var knife_speed_mult := 1.15         # a faca corre mais depressa (Valorant)

# ==================================================
# DADOS
# ==================================================

class WeaponDef extends RefCounted:
	var id := ""
	var display_name := ""
	var path := ""
	var tex_prefix := ""
	var melee := false
	var auto := true
	var rate := 9.75
	var dmg_head := 160.0
	var dmg_body := 40.0
	var dmg_leg := 34.0
	var dmg_heavy := 150.0
	var range_m := 300.0
	var mag_size := 25
	var reserve_size := 50
	var mag := 25
	var reserve := 50
	var reload_time := 2.5
	var equip_time := 0.8
	var spread_base := 0.0
	var spread_move := 2.6
	var spread_air := 4.0
	var spread_burst := 0.05
	var length := 0.9
	var pos := Vector3.ZERO
	var rot := Vector3.ZERO
	var flip := false
	var price := 0
	var slot_kind := "primary"
	var model_rotation_deg := Vector3.ZERO
	var muzzle := Vector3.ZERO
	var longest := 1.0
	var size := Vector3.ONE
	var auto_basis := Basis()
	var recoil: Array = []
	var holder: Node3D
	var anim: Node3D
	var slot: Node3D
	var orient: Node3D
	var pivot: Node3D
	var muzzle_node: Node3D
	var flash: MeshInstance3D
	var flash_light: OmniLight3D

var jett
var cam: Camera3D
var defs: Array[WeaponDef] = []
var defs_by_id := {}
var slots: Array = []          # índices em defs: primária, secundária, faca
var loadout_primary := ""
var loadout_secondary := "classic"
var cur := 0
var ready_ok := false
var started := false
var root: Node3D

var fire_cd := 0.0
var equip_t := 0.0
var reload_t := 0.0
var reloading := false
var fire_blocked := true
var shot_index := 0
var since_shot := 10.0
var melee_active := false
var melee_heavy := false
var melee_pending := 0.0
var swing_side := 1.0

var vm_kick := 0.0
var vm_equip := 0.0
var bob_t := 0.0
var sway_target := Vector2.ZERO
var sway := Vector2.ZERO
var flash_t := 0.0
var base_run_speed := 7.0

var tune := false
var tune_print_t := 0.0

var anim_tween: Tween
var ammo_label: Label
var name_label: Label
var decals: Array = []
var hole_tex: GradientTexture2D
var soft_tex: GradientTexture2D
var tracer_mat: StandardMaterial3D

var _pts := PackedVector3Array()

# ==================================================
# READY
# ==================================================

func _ready():
	jett = get_parent()
	if jett == null or not ("camera" in jett):
		push_error("WeaponManager tem de ser filho do Jett (script do player).")
		return
	if not jett.is_node_ready():
		await jett.ready
	cam = jett.camera
	base_run_speed = jett.run_speed

	_setup_inputs()
	_make_textures()
	_build_defs()

	root = Node3D.new()
	root.name = "WeaponRoot"
	cam.add_child(root)
	for w in defs:
		_build_viewmodel(w)

	_build_hud()
	if jett.has_signal("died"):
		jett.died.connect(_on_player_died)

	ready_ok = true
	give(primary_id, secondary_id, true)

func _build_defs():
	defs.clear()
	defs_by_id.clear()

	_gun("classic", "CLASSIC", {
		"slot": "secondary", "auto": false, "rate": 6.75, "head": 78.0, "body": 26.0, "leg": 22.0,
		"mag": 12, "reserve": 36, "reload": 1.75, "equip": 0.5, "range": 120.0,
		"spread_base": 0.5, "spread_move": 2.4, "spread_air": 3.0, "spread_burst": 0.2,
		"length": 0.44, "pos": Vector3(0.28, -0.24, -0.62), "rot": Vector3(0.0, -6.0, -2.0),
		"muzzle": Vector3(0.14, -0.13, -0.62), "price": 0,
	})

	_gun("sheriff", "SHERIFF", {
		"slot": "secondary", "auto": false, "rate": 4.0, "head": 159.0, "body": 55.0, "leg": 46.0,
		"mag": 6, "reserve": 24, "reload": 2.25, "equip": 0.6, "range": 200.0,
		"spread_base": 0.25, "spread_move": 2.8, "spread_air": 4.0, "spread_burst": 0.35,
		"length": 0.52, "pos": Vector3(0.28, -0.24, -0.64), "rot": Vector3(0.0, -6.0, -2.0),
		"muzzle": Vector3(0.16, -0.14, -0.70), "price": 800,
	})

	_gun("spectre", "SPECTRE", {
		"slot": "primary", "auto": true, "rate": 13.33, "head": 78.0, "body": 26.0, "leg": 22.0,
		"mag": 30, "reserve": 60, "reload": 2.25, "equip": 0.7, "range": 250.0,
		"spread_base": 0.2, "spread_move": 2.0, "spread_air": 3.0, "spread_burst": 0.06,
		"length": 0.68, "pos": Vector3(0.30, -0.25, -0.70), "rot": Vector3(0.0, -8.0, -3.0),
		"muzzle": Vector3(0.17, -0.15, -0.86), "price": 1600,
	})

	_gun("vandal", "VANDAL", {
		"slot": "primary", "path": vandal_path, "tex": vandal_texture_prefix,
		"auto": true, "rate": vandal_rate, "head": vandal_damage_head, "body": vandal_damage_body,
		"leg": vandal_damage_leg, "mag": vandal_mag, "reserve": vandal_reserve,
		"reload": vandal_reload_time, "equip": vandal_equip_time, "range": 300.0,
		"spread_base": 0.0, "spread_move": 2.6, "spread_air": 4.0, "spread_burst": 0.05,
		"length": vandal_length, "pos": vandal_pos, "rot": vandal_rot, "flip": vandal_flip,
		"muzzle": vandal_muzzle, "price": 2900, "axis": vandal_axis_correction,
	})

	_gun("phantom", "PHANTOM", {
		"slot": "primary", "auto": true, "rate": 11.0, "head": 156.0, "body": 39.0, "leg": 33.0,
		"mag": 30, "reserve": 60, "reload": 2.5, "equip": 0.8, "range": 300.0,
		"spread_base": 0.0, "spread_move": 2.2, "spread_air": 4.0, "spread_burst": 0.04,
		"length": 1.0, "pos": Vector3(0.30, -0.25, -0.72), "rot": Vector3(0.0, -8.0, -3.0),
		"muzzle": Vector3(0.2, -0.17, -1.10), "price": 2900,
	})

	_gun("operator", "OPERATOR", {
		"slot": "primary", "auto": false, "rate": 0.6, "head": 255.0, "body": 150.0, "leg": 120.0,
		"mag": 5, "reserve": 10, "reload": 3.7, "equip": 1.2, "range": 500.0,
		"spread_base": 0.0, "spread_move": 6.0, "spread_air": 9.0, "spread_burst": 0.0,
		"length": 1.35, "pos": Vector3(0.32, -0.26, -0.78), "rot": Vector3(0.0, -8.0, -3.0),
		"muzzle": Vector3(0.2, -0.16, -1.40), "price": 4700,
	})

	var k := WeaponDef.new()
	k.id = "knife"
	k.display_name = "FACA"
	k.path = knife_path
	k.tex_prefix = knife_texture_prefix
	k.melee = true
	k.slot_kind = "melee"
	k.dmg_body = knife_damage_light
	k.dmg_heavy = knife_damage_heavy
	k.equip_time = 0.35
	k.length = knife_length
	k.pos = knife_pos
	k.rot = knife_rot
	k.flip = knife_flip
	k.model_rotation_deg = knife_axis_correction
	defs.append(k)
	defs_by_id["knife"] = k

func _gun(id: String, display: String, cfg: Dictionary) -> WeaponDef:
	var w := WeaponDef.new()
	w.id = id
	w.display_name = display
	w.path = str(cfg.get("path", ""))
	w.tex_prefix = str(cfg.get("tex", ""))
	w.auto = bool(cfg.get("auto", true))
	w.rate = float(cfg.get("rate", 10.0))
	w.dmg_head = float(cfg.get("head", 150.0))
	w.dmg_body = float(cfg.get("body", 40.0))
	w.dmg_leg = float(cfg.get("leg", 34.0))
	w.range_m = float(cfg.get("range", 300.0))
	w.mag_size = int(cfg.get("mag", 25))
	w.mag = w.mag_size
	w.reserve_size = int(cfg.get("reserve", 50))
	w.reserve = w.reserve_size
	w.reload_time = float(cfg.get("reload", 2.5))
	w.equip_time = float(cfg.get("equip", 0.7))
	w.spread_base = float(cfg.get("spread_base", 0.0))
	w.spread_move = float(cfg.get("spread_move", 2.6))
	w.spread_air = float(cfg.get("spread_air", 4.0))
	w.spread_burst = float(cfg.get("spread_burst", 0.05))
	w.length = float(cfg.get("length", 0.9))
	w.pos = cfg.get("pos", Vector3(0.30, -0.25, -0.72))
	w.rot = cfg.get("rot", Vector3(0.0, -8.0, -3.0))
	w.muzzle = cfg.get("muzzle", Vector3(0.2, -0.17, -1.08))
	w.flip = bool(cfg.get("flip", false))
	w.price = int(cfg.get("price", 0))
	w.slot_kind = str(cfg.get("slot", "primary"))
	w.model_rotation_deg = cfg.get("axis", Vector3.ZERO)
	w.recoil = _make_recoil(w.mag_size)
	defs.append(w)
	defs_by_id[id] = w
	return w

# ==================================================
# LOADOUT / LOJA
# ==================================================

func _index_of(id: String) -> int:
	for i in range(defs.size()):
		if defs[i].id == id:
			return i
	return -1

func _current() -> WeaponDef:
	if slots.is_empty():
		return defs[0]
	return defs[slots[clampi(cur, 0, slots.size() - 1)]]

func current_name() -> String:
	return _current().display_name

func current_id() -> String:
	return _current().id

func give(primary: String, secondary: String, refill := true) -> void:
	loadout_primary = primary
	loadout_secondary = secondary
	slots = []
	var p := _index_of(primary)
	if p >= 0:
		slots.append(p)
	var s := _index_of(secondary)
	if s < 0:
		s = _index_of("classic")
	if s >= 0:
		slots.append(s)
	var k := _index_of("knife")
	if k >= 0:
		slots.append(k)
	if refill:
		refill_all()
	select_slot(0, true)

func refill_all() -> void:
	for w in defs:
		w.mag = w.mag_size
		w.reserve = w.reserve_size
	reloading = false
	_cancel_melee()
	fire_blocked = true

func get_buy_list() -> Array:
	var out: Array = []
	for w in defs:
		if w.melee or w.price <= 0:
			continue
		out.append({"id": w.id, "name": w.display_name, "price": w.price, "slot": w.slot_kind})
	return out

func _make_recoil(n: int) -> Array:
	var a := []
	for i in range(maxi(n, 1)):
		var pitch := 0.55 if i < 4 else (0.42 if i < 10 else 0.2)
		var yaw := 0.0
		if i >= 6:
			yaw = sin(float(i - 6) * 0.9) * 0.35
		a.append(Vector2(pitch, yaw))
	return a

# ==================================================
# INPUT MAP
# ==================================================

func _add_keys(action: String, keys: Array):
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	if InputMap.action_get_events(action).is_empty():
		for k in keys:
			var e := InputEventKey.new()
			e.physical_keycode = k
			InputMap.action_add_event(action, e)

func _setup_inputs():
	_add_keys("weapon_1", [KEY_1])
	_add_keys("weapon_2", [KEY_2])
	_add_keys("weapon_3", [KEY_3])
	_add_keys("reload", [KEY_R])
	_add_keys("tune_weapons", [KEY_F2])
	# garantir que existem (o Jett também os cria)
	_add_keys("fire", [])
	_add_keys("alt_fire", [])

func _input(event):
	if not ready_ok:
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED

	if event is InputEventMouseMotion and captured:
		sway_target.x = clampf(sway_target.x + event.relative.x * 0.0006, -0.07, 0.07)
		sway_target.y = clampf(sway_target.y + event.relative.y * 0.0006, -0.07, 0.07)
	elif event is InputEventMouseButton and event.pressed and captured:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			select_slot(cur - 1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			select_slot(cur + 1)

	if event.is_action_pressed("tune_weapons"):
		tune = not tune
		print("[WeaponManager] modo de afinação: ", "LIGADO" if tune else "DESLIGADO")
		if jett.has_method("toast"):
			jett.toast("AFINAÇÃO %s" % ("ON" if tune else "OFF"), Color(1.0, 0.82, 0.3))

	if tune and event is InputEventKey and event.pressed and not event.echo:
		var w := _current()
		if event.keycode == KEY_ENTER:
			w.flip = not w.flip              # inverte frente/trás
			_apply_transform(w)
			_print_tune(w)
		elif event.keycode == KEY_BACKSPACE:
			w.rot.z += 180.0                 # inverte cima/baixo
			_apply_transform(w)
			_print_tune(w)

# ==================================================
# TROCA DE ARMAS
# ==================================================

func select_slot(i: int, force := false):
	if slots.is_empty():
		return
	i = wrapi(i, 0, slots.size())
	var from_ability: bool = jett.equipped != 0
	if from_ability:
		jett.equipped = 0            # Equip.NONE
		jett._refresh_viewmodel()
	if i == cur and not from_ability and not force:
		return

	_cancel_reload()
	_cancel_melee()
	for w in defs:
		if w.anim == null:
			continue
		w.anim.position = Vector3.ZERO
		w.anim.rotation = Vector3.ZERO
	cur = i
	equip_t = _current().equip_time
	vm_equip = 1.0
	shot_index = 0
	fire_blocked = true
	started = true

func _is_active() -> bool:
	return ready_ok and not jett.dead and jett.equipped == 0

# ==================================================
# LÓGICA (physics)
# ==================================================

func _physics_process(delta):
	if not ready_ok:
		return
	if jett.buy_open:
		fire_blocked = true
		return

	if Input.is_action_just_pressed("weapon_1"):
		select_slot(0)
	if Input.is_action_just_pressed("weapon_2"):
		select_slot(1)
	if Input.is_action_just_pressed("weapon_3"):
		select_slot(2)

	var active := _is_active()
	var w := _current()

	# velocidade extra com a faca
	jett.run_speed = base_run_speed * (knife_speed_mult if (active and w.melee) else 1.0)

	if not active:
		_cancel_reload()
		_cancel_melee()
		fire_blocked = true     # tem de largar o botão antes de disparar de novo
		return

	fire_cd = maxf(fire_cd - delta, -delta)
	equip_t = maxf(0.0, equip_t - delta)
	since_shot += delta
	if since_shot > 0.35:
		shot_index = 0

	var lock: float = jett.input_lock
	var captured: bool = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and lock <= 0.0
	if fire_blocked and not Input.is_action_pressed("fire"):
		fire_blocked = false
	var can_fire: bool = captured and not fire_blocked

	if w.melee:
		_process_melee(w, delta, can_fire)
		return

	# ---- arma de fogo ----
	if reloading:
		reload_t -= delta
		if reload_t <= 0.0:
			_finish_reload(w)
		return

	if Input.is_action_just_pressed("reload"):
		start_reload()
		return

	var want := false
	if w.auto:
		want = can_fire and Input.is_action_pressed("fire")
	else:
		want = can_fire and Input.is_action_just_pressed("fire")

	if want and equip_t <= 0.0 and fire_cd <= 0.0:
		if w.mag > 0:
			_shoot(w)
		else:
			start_reload()

func _shoot(w: WeaponDef):
	w.mag -= 1
	fire_cd += 1.0 / w.rate
	since_shot = 0.0

	var dir := _aim_dir(w)
	var from: Vector3 = cam.global_position
	var far: Vector3 = from + dir * w.range_m
	var q := PhysicsRayQueryParameters3D.create(from, far)
	q.exclude = [jett.get_rid()]
	var hit: Dictionary = jett.get_world_3d().direct_space_state.intersect_ray(q)

	var end_pt := far
	if not hit.is_empty():
		end_pt = hit.position
		_apply_gun_hit(w, hit)

	_tracer(w, end_pt)
	_muzzle_flash(w)

	# recuo real na mira
	var r: Vector2 = w.recoil[mini(shot_index, w.recoil.size() - 1)]
	jett.mouse_pitch = clampf(jett.mouse_pitch + deg_to_rad(r.x), -1.5, 1.5)
	jett.rotate_y(deg_to_rad(-r.y))
	shot_index += 1

	vm_kick = minf(vm_kick + 0.05, 0.12)
	jett.add_shake(0.05)

func _aim_dir(w: WeaponDef) -> Vector3:
	var b: Basis = cam.global_transform.basis
	var spread := w.spread_base
	var spd := Vector2(jett.velocity.x, jett.velocity.z).length()
	var slow: float = jett.walk_speed * 0.8
	var mf := clampf((spd - slow) / maxf(base_run_speed - slow, 0.1), 0.0, 1.0)
	spread += w.spread_move * mf
	if not jett.is_on_floor():
		spread += w.spread_air
	spread += minf(float(shot_index), 12.0) * w.spread_burst
	if jett.crouch_t > 0.5:
		spread *= 0.7
	var ang := randf() * TAU
	var rad := tan(deg_to_rad(spread)) * sqrt(randf())
	return (-b.z + b.x * cos(ang) * rad + b.y * sin(ang) * rad).normalized()

func _apply_gun_hit(w: WeaponDef, hit: Dictionary):
	var col = hit.collider
	var is_target: bool = col != null and col.has_method("take_damage")
	var killed := false
	if is_target:
		var rel := 1.0
		if col is Node3D:
			rel = hit.position.y - col.global_position.y
		var dmg := w.dmg_body
		var headshot := false
		if rel >= head_height:
			dmg = w.dmg_head
			headshot = true
		elif rel <= leg_height:
			dmg = w.dmg_leg
		killed = col.take_damage(dmg, jett) == true
		if headshot:
			jett.toast("HEADSHOT", Color(1.0, 0.82, 0.3))
	jett.on_knife_hit(hit.position, hit.normal, is_target, killed, str(col.name) if col else "")
	if not is_target:
		_decal(hit.position, hit.normal)

# ---------- recarregar ----------

func start_reload():
	var w := _current()
	if w.melee or reloading or w.mag >= w.mag_size or w.reserve <= 0:
		return
	reloading = true
	reload_t = w.reload_time
	_kill_tween()
	anim_tween = create_tween()
	anim_tween.set_trans(Tween.TRANS_SINE)
	anim_tween.tween_property(w.anim, "rotation", Vector3(0.7, 0.35, -0.7), 0.3)
	anim_tween.parallel().tween_property(w.anim, "position", Vector3(-0.05, -0.2, 0.05), 0.3)
	anim_tween.tween_interval(maxf(0.0, w.reload_time - 0.65))
	anim_tween.tween_property(w.anim, "rotation", Vector3.ZERO, 0.35)
	anim_tween.parallel().tween_property(w.anim, "position", Vector3.ZERO, 0.35)

func _finish_reload(w: WeaponDef):
	var take := mini(w.mag_size - w.mag, w.reserve)
	w.mag += take
	w.reserve -= take
	reloading = false

func _cancel_reload():
	if reloading:
		reloading = false
		_kill_tween()
		for w in defs:
			w.anim.position = Vector3.ZERO
			w.anim.rotation = Vector3.ZERO

func _kill_tween():
	if anim_tween and anim_tween.is_valid():
		anim_tween.kill()

# ---------- faca ----------

func _process_melee(w: WeaponDef, delta: float, can_fire: bool):
	if melee_active:
		melee_pending -= delta
		if melee_pending <= 0.0:
			melee_active = false
			_melee_hit(w, melee_heavy)
		return
	if equip_t > 0.0 or fire_cd > 0.0 or not can_fire:
		return
	if Input.is_action_just_pressed("fire"):
		_melee_start(w, false)
	elif Input.is_action_just_pressed("alt_fire"):
		_melee_start(w, true)

func _melee_start(w: WeaponDef, heavy: bool):
	melee_active = true
	melee_heavy = heavy
	melee_pending = 0.36 if heavy else 0.12
	fire_cd = 1.0 if heavy else 0.45
	_kill_tween()
	anim_tween = create_tween()
	if heavy:
		# recua e espeta para a frente
		anim_tween.set_trans(Tween.TRANS_SINE)
		anim_tween.tween_property(w.anim, "position", Vector3(0.02, 0.05, 0.16), 0.28)
		anim_tween.parallel().tween_property(w.anim, "rotation", Vector3(0.5, 0.0, 0.0), 0.28)
		anim_tween.tween_property(w.anim, "position", Vector3(-0.04, -0.02, -0.5), 0.08)
		anim_tween.parallel().tween_property(w.anim, "rotation", Vector3(-0.15, 0.0, 0.0), 0.08)
		anim_tween.tween_property(w.anim, "position", Vector3.ZERO, 0.4)
		anim_tween.parallel().tween_property(w.anim, "rotation", Vector3.ZERO, 0.4)
	else:
		# golpe cruzado (alterna esquerda/direita)
		var s := swing_side
		swing_side = -swing_side
		anim_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		anim_tween.tween_property(w.anim, "position", Vector3(-0.28 * s, 0.06, -0.22), 0.12)
		anim_tween.parallel().tween_property(w.anim, "rotation", Vector3(-0.2, 0.9 * s, -0.9 * s), 0.12)
		anim_tween.tween_property(w.anim, "position", Vector3.ZERO, 0.3)
		anim_tween.parallel().tween_property(w.anim, "rotation", Vector3.ZERO, 0.3)

func _melee_hit(w: WeaponDef, heavy: bool):
	var origin: Vector3 = cam.global_position
	var b: Basis = cam.global_transform.basis
	var offsets := [Vector2.ZERO, Vector2(-0.35, 0.0), Vector2(0.35, 0.0), Vector2(0.0, -0.3)]
	var space = jett.get_world_3d().direct_space_state
	for o in offsets:
		var to: Vector3 = origin + (-b.z) * knife_range + b.x * o.x + b.y * o.y
		var q := PhysicsRayQueryParameters3D.create(origin, to)
		q.exclude = [jett.get_rid()]
		var hit: Dictionary = space.intersect_ray(q)
		if hit.is_empty():
			continue
		var col = hit.collider
		var is_target: bool = col != null and col.has_method("take_damage")
		var killed := false
		if is_target:
			killed = col.take_damage(w.dmg_heavy if heavy else w.dmg_body, jett) == true
		jett.on_knife_hit(hit.position, hit.normal, is_target, killed, str(col.name) if col else "")
		jett.add_shake(0.12 if heavy else 0.06)
		return

func _cancel_melee():
	if melee_active:
		melee_active = false
		_kill_tween()
		for w in defs:
			w.anim.position = Vector3.ZERO
			w.anim.rotation = Vector3.ZERO

func _on_player_died():
	await get_tree().create_timer(2.1).timeout
	for w in defs:
		w.mag = w.mag_size
		w.reserve = w.reserve_size
	reloading = false
	fire_blocked = true

# ==================================================
# EFEITOS
# ==================================================

func _make_textures():
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	g.colors = PackedColorArray([Color(0.02, 0.02, 0.02, 0.95), Color(0.05, 0.05, 0.05, 0.8), Color(0, 0, 0, 0)])
	hole_tex = GradientTexture2D.new()
	hole_tex.gradient = g
	hole_tex.fill = GradientTexture2D.FILL_RADIAL
	hole_tex.fill_from = Vector2(0.5, 0.5)
	hole_tex.fill_to = Vector2(1.0, 0.5)
	hole_tex.width = 32
	hole_tex.height = 32

	var g2 := Gradient.new()
	g2.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g2.colors = PackedColorArray([Color(1, 0.95, 0.7, 1.0), Color(1, 0.7, 0.2, 0.55), Color(1, 0.5, 0.1, 0.0)])
	soft_tex = GradientTexture2D.new()
	soft_tex.gradient = g2
	soft_tex.fill = GradientTexture2D.FILL_RADIAL
	soft_tex.fill_from = Vector2(0.5, 0.5)
	soft_tex.fill_to = Vector2(1.0, 0.5)
	soft_tex.width = 64
	soft_tex.height = 64

	tracer_mat = StandardMaterial3D.new()
	tracer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tracer_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tracer_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	tracer_mat.albedo_color = Color(1.0, 0.85, 0.5, 0.7)

func _tracer(w: WeaponDef, end_pt: Vector3):
	var start: Vector3 = w.muzzle_node.global_position
	var dist := start.distance_to(end_pt)
	if dist < 1.5:
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.012, 0.012, dist)
	mi.mesh = bm
	mi.material_override = tracer_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	get_tree().current_scene.add_child(mi)
	mi.global_position = (start + end_pt) * 0.5
	var d := (end_pt - start).normalized()
	var up := Vector3.UP if absf(d.y) < 0.99 else Vector3.RIGHT
	mi.look_at(end_pt, up)
	get_tree().create_timer(0.05).timeout.connect(mi.queue_free)

func _muzzle_flash(w: WeaponDef):
	if w.flash == null:
		return
	w.flash.visible = true
	w.flash.rotation.z = randf() * TAU
	w.flash.scale = Vector3.ONE * randf_range(0.8, 1.3)
	w.flash_light.light_energy = 2.5
	flash_t = 0.04

func _decal(pos: Vector3, normal: Vector3):
	var d := Decal.new()
	d.size = Vector3(0.14, 0.3, 0.14)
	d.texture_albedo = hole_tex
	get_tree().current_scene.add_child(d)
	d.global_position = pos
	var n := normal.normalized()
	var ref := Vector3.UP if absf(n.y) < 0.99 else Vector3.RIGHT
	var x := ref.cross(n).normalized()
	var z := x.cross(n).normalized()
	d.global_transform.basis = Basis(x, n, z)
	d.rotate_object_local(Vector3.UP, randf() * TAU)
	decals.append(d)
	if decals.size() > max_decals:
		var old = decals.pop_front()
		if is_instance_valid(old):
			old.queue_free()

# ==================================================
# VIEWMODEL
# ==================================================

# Recolhe vértices (amostrados) de todas as malhas, no espaço do pivot
func _gather_points(node: Node, xf: Transform3D):
	var cur_xf := xf
	if node is Node3D:
		cur_xf = xf * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var faces: PackedVector3Array = (node as MeshInstance3D).mesh.get_faces()
		var step := maxi(1, int(faces.size() / 20000.0))
		var i := 0
		while i < faces.size():
			_pts.append(cur_xf * faces[i])
			i += step
	for c in node.get_children():
		_gather_points(c, cur_xf)

# Limites robustos (percentis 1%-99%) para ignorar vértices perdidos
func _percentile_bounds(pts: PackedVector3Array) -> AABB:
	var xs := PackedFloat32Array()
	var ys := PackedFloat32Array()
	var zs := PackedFloat32Array()
	for p in pts:
		xs.append(p.x)
		ys.append(p.y)
		zs.append(p.z)
	xs.sort()
	ys.sort()
	zs.sort()
	var lo_i := int(pts.size() * 0.01)
	var hi_i := maxi(lo_i, int(pts.size() * 0.99) - 1)
	var lo := Vector3(xs[lo_i], ys[lo_i], zs[lo_i])
	var hi := Vector3(xs[hi_i], ys[hi_i], zs[hi_i])
	return AABB(lo, hi - lo)

# Descobre a orientação: eixo mais comprido = comprimento da arma;
# a ponta com menor secção (cano / ponta da lâmina) fica para a frente (-Z);
# o lado mais "pesado" (carregador / punho) fica para baixo.
func _compute_basis(pts: PackedVector3Array, bb: AABB) -> Basis:
	# O eixo mais comprido da malha passa a apontar para -Z (frente da câmara).
	# O segundo eixo mais comprido é usado como altura (+Y).
	var ext := [bb.size.x, bb.size.y, bb.size.z]
	var forward_axis := 0
	for i in range(1, 3):
		if ext[i] > ext[forward_axis]:
			forward_axis = i

	var up_axis := -1
	for i in range(3):
		if i == forward_axis:
			continue
		if up_axis == -1 or ext[i] > ext[up_axis]:
			up_axis = i

	if up_axis < 0:
		return Basis.IDENTITY

	# Array tipado para o GDScript conseguir inferir Vector3 ao aceder por índice.
	var units: Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	var forward: Vector3 = units[forward_axis]
	var up: Vector3 = units[up_axis]

	# A ponta mais estreita tende a ser o cano/ponta da lâmina.
	# Compara a secção nas duas extremidades para escolher o sentido da frente.
	var lo: float = bb.position[forward_axis]
	var span: float = ext[forward_axis]
	var band: float = span * 0.12
	var lo_min := Vector2(INF, INF)
	var lo_max := Vector2(-INF, -INF)
	var hi_min := Vector2(INF, INF)
	var hi_max := Vector2(-INF, -INF)
	var lo_n := 0
	var hi_n := 0
	var side_axis := 3 - forward_axis - up_axis
	for p in pts:
		var along: float = p[forward_axis]
		var a: float = p[up_axis]
		var b: float = p[side_axis]
		if along <= lo + band:
			lo_n += 1
			lo_min = Vector2(minf(lo_min.x, a), minf(lo_min.y, b))
			lo_max = Vector2(maxf(lo_max.x, a), maxf(lo_max.y, b))
		elif along >= lo + span - band:
			hi_n += 1
			hi_min = Vector2(minf(hi_min.x, a), minf(hi_min.y, b))
			hi_max = Vector2(maxf(hi_max.x, a), maxf(hi_max.y, b))

	var front_positive := true
	if lo_n >= 3 and hi_n >= 3:
		var area_lo := (lo_max.x - lo_min.x) * (lo_max.y - lo_min.y)
		var area_hi := (hi_max.x - hi_min.x) * (hi_max.y - hi_min.y)
		front_positive = area_hi < area_lo
	if not front_positive:
		forward = -forward

	# Escolhe o lado mais pesado para baixo, mantendo a arma direita.
	var mean_up := 0.0
	for p in pts:
		mean_up += p[up_axis]
	mean_up /= float(maxi(pts.size(), 1))
	var middle_up: float = bb.position[up_axis] + ext[up_axis] * 0.5
	if mean_up > middle_up:
		up = -up

	var right := up.cross(-forward).normalized()
	if right.length_squared() < 0.5:
		return Basis.IDENTITY
	up = (-forward).cross(right).normalized()

	if debug_models:
		print("   eixo frente=%d, direcao=%s, cima=%s" % [forward_axis, str(forward), str(up)])

	# Matriz inversa da base local escolhida: converte os eixos FBX
	# para direita/cima/frente do viewmodel Godot.
	return Basis(right, up, -forward).transposed()

# Mede, centra e normaliza o modelo. Devolve false se não houver geometria.
func _fit_model(model: Node3D, w: WeaponDef) -> bool:
	_pts = PackedVector3Array()
	_gather_points(model, Transform3D.IDENTITY)
	if _pts.size() < 3:
		return false
	var bb := _percentile_bounds(_pts)
	var longest := maxf(bb.size.x, maxf(bb.size.y, bb.size.z))
	if longest < 0.000001:
		return false
	w.size = bb.size
	w.longest = longest
	if debug_models:
		print("[WeaponManager] %s: %d pontos, tamanho %s, escala %.5f" % [w.display_name, _pts.size(), str(bb.size), w.length / longest])
	if model.has_meta("skip_auto_orient") or not auto_orient:
		w.auto_basis = Basis.IDENTITY
	else:
		w.auto_basis = _compute_basis(_pts, bb)
	model.position = -bb.get_center()
	return true

func _no_shadows(node: Node):
	if node is GeometryInstance3D:
		var visual := node as GeometryInstance3D
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visual.visible = true
	for c in node.get_children():
		_no_shadows(c)

func _load_model(w: WeaponDef) -> Node3D:
	if use_imported_models and not w.path.is_empty() and ResourceLoader.exists(w.path):
		var res = load(w.path)
		if res is PackedScene:
			var inst = res.instantiate()
			if inst is Node3D:
				print("[WeaponManager] modelo importado: %s (%s)" % [w.display_name, w.path])
				return inst
		push_warning("WeaponManager: o recurso '%s' existe, mas não foi importado como uma cena 3D." % w.path)
	else:
		if not w.path.is_empty():
			push_warning("WeaponManager: não encontrei '%s'. Vou usar um modelo 3D criado pelo script." % w.path)
	return _placeholder(w)

func _make_vm_material(color: Color, metallic := 0.0, roughness := 0.55, glow := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if glow:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 0.8
	return material

func _add_vm_box(parent: Node3D, size: Vector3, pos: Vector3, material: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.material_override = material
	instance.position = pos
	instance.rotation = rot
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance

func _placeholder(w: WeaponDef) -> Node3D:
	# Modelos provisórios deliberadamente grandes e contrastantes para nunca
	# ficares com o slot da arma vazio quando um FBX falha.
	var model := Node3D.new()
	model.set_meta("skip_auto_orient", true)
	model.set_meta("procedural_viewmodel", true)
	if w.melee:
		var steel := _make_vm_material(Color(0.72, 0.82, 0.9), 0.75, 0.22)
		var edge := _make_vm_material(Color(0.25, 0.9, 1.0), 0.25, 0.2, true)
		var grip := _make_vm_material(Color(0.035, 0.045, 0.065), 0.25, 0.7)
		var guard := _make_vm_material(Color(0.12, 0.16, 0.2), 0.8, 0.3)
		# Lâmina longa apontada para a frente (-Z).
		_add_vm_box(model, Vector3(0.075, 0.025, 0.36), Vector3(0.0, 0.0, -0.20), steel)
		_add_vm_box(model, Vector3(0.012, 0.006, 0.29), Vector3(0.0, 0.016, -0.20), edge)
		# Ponta e gume em dois segmentos para ser visível mesmo sem o FBX.
		_add_vm_box(model, Vector3(0.052, 0.018, 0.09), Vector3(0.0, 0.0, -0.415), steel, Vector3(0.0, 0.0, 0.0))
		_add_vm_box(model, Vector3(0.13, 0.035, 0.045), Vector3(0.0, 0.0, 0.015), guard)
		_add_vm_box(model, Vector3(0.048, 0.045, 0.17), Vector3(0.0, 0.0, 0.12), grip, Vector3(0.0, 0.0, -0.08))
		_add_vm_box(model, Vector3(0.055, 0.012, 0.035), Vector3(0.0, 0.0, 0.225), steel)
	else:
		var dark := _make_vm_material(Color(0.055, 0.07, 0.09), 0.55, 0.35)
		var body := _make_vm_material(Color(0.19, 0.23, 0.28), 0.65, 0.32)
		var metal := _make_vm_material(Color(0.48, 0.55, 0.62), 0.8, 0.25)
		var accent := _make_vm_material(Color(0.18, 0.78, 0.95), 0.25, 0.25, true)
		_add_vm_box(model, Vector3(0.13, 0.13, 0.48), Vector3(0.0, 0.0, -0.12), body)
		_add_vm_box(model, Vector3(0.075, 0.065, 0.28), Vector3(0.0, 0.005, -0.48), metal)
		_add_vm_box(model, Vector3(0.11, 0.09, 0.22), Vector3(0.0, 0.0, 0.23), dark)
		_add_vm_box(model, Vector3(0.075, 0.18, 0.11), Vector3(0.0, -0.13, 0.035), dark, Vector3(-0.16, 0.0, 0.0))
		_add_vm_box(model, Vector3(0.085, 0.17, 0.11), Vector3(0.0, -0.13, -0.12), body)
		_add_vm_box(model, Vector3(0.055, 0.025, 0.42), Vector3(0.0, 0.078, -0.13), metal)
		_add_vm_box(model, Vector3(0.018, 0.018, 0.34), Vector3(0.0, 0.095, -0.16), accent)
		# Detalhes adicionais do receiver e da ergonomia do rifle.
		_add_vm_box(model, Vector3(0.145, 0.075, 0.22), Vector3(0.0, -0.045, -0.12), dark)
		_add_vm_box(model, Vector3(0.145, 0.045, 0.16), Vector3(0.0, 0.075, -0.05), body)
		_add_vm_box(model, Vector3(0.025, 0.018, 0.30), Vector3(-0.078, 0.085, -0.16), metal)
		_add_vm_box(model, Vector3(0.025, 0.018, 0.30), Vector3(0.078, 0.085, -0.16), metal)
		_add_vm_box(model, Vector3(0.11, 0.035, 0.07), Vector3(0.0, 0.145, -0.10), dark)
		_add_vm_box(model, Vector3(0.035, 0.035, 0.045), Vector3(0.0, 0.17, -0.10), accent)
		_add_vm_box(model, Vector3(0.105, 0.025, 0.055), Vector3(0.0, -0.225, 0.10), metal)
		_add_vm_box(model, Vector3(0.14, 0.025, 0.035), Vector3(0.0, 0.0, -0.60), dark)
		_add_vm_box(model, Vector3(0.11, 0.018, 0.025), Vector3(0.0, 0.055, -0.58), accent)
		# Ranhuras laterais do carregador.
		for groove in range(3):
			_add_vm_box(model, Vector3(0.006, 0.018, 0.075), Vector3(-0.041, -0.14, 0.02 + groove * 0.045), metal)
		_add_vm_box(model, Vector3(0.07, 0.055, 0.055), Vector3(0.0, 0.12, -0.04), dark)
	return model

# Procura ficheiros que começam por "prefix" e classifica-os (albedo, normal...)
func _find_textures(prefix: String) -> Dictionary:
	var found := {}
	var exts := ["png", "jpg", "jpeg", "webp", "tga", "bmp"]
	for dir_path in texture_dirs:
		var d := DirAccess.open(dir_path)
		if d == null:
			continue
		for f in d.get_files():
			var fn: String = f
			for suf in [".import", ".remap"]:
				if fn.ends_with(suf):
					fn = fn.trim_suffix(suf)
			var low := fn.to_lower()
			if not low.begins_with(prefix.to_lower()):
				continue
			if not exts.has(fn.get_extension().to_lower()):
				continue
			var kind := ""
			if "normal" in low:
				kind = "normal"
			elif "rough" in low:
				kind = "roughness"
			elif "metal" in low:
				kind = "metallic"
			elif "_ao" in low or "ambient" in low or "occlusion" in low:
				kind = "ao"
			elif "albedo" in low or "basecolor" in low or "base_color" in low or "diffuse" in low or "color" in low:
				kind = "albedo"
			if kind != "" and not found.has(kind):
				found[kind] = dir_path.path_join(fn)
	return found

func _apply_textures(model: Node, w: WeaponDef):
	var t := _find_textures(w.tex_prefix)
	if t.is_empty():
		push_warning("WeaponManager: não encontrei texturas '%s*' em %s" % [w.tex_prefix, str(texture_dirs)])
		return
	print("[WeaponManager] texturas de %s: %s" % [w.display_name, str(t)])

	var m := StandardMaterial3D.new()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color.WHITE if t.has("albedo") else Color(0.5, 0.52, 0.56)
	m.roughness = 1.0 if t.has("roughness") else 0.5
	m.metallic = 0.0

	for kind in t.keys():
		var tex = load(t[kind])
		if not (tex is Texture2D):
			continue
		match kind:
			"albedo":
				m.albedo_texture = tex
			"normal":
				m.normal_enabled = true
				m.normal_texture = tex
			"roughness":
				m.roughness_texture = tex
			"metallic":
				m.metallic = 1.0
				m.metallic_texture = tex
			"ao":
				m.ao_enabled = true
				m.ao_texture = tex
	_set_override(model, m)

func _set_override(node: Node, m: Material):
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).material_override = m
	for c in node.get_children():
		_set_override(c, m)

func _orient_basis(w: WeaponDef) -> Basis:
	var b := w.auto_basis
	if w.flip:
		b = Basis(Vector3.UP, PI) * b
	var correction := Basis.from_euler(Vector3(
		deg_to_rad(w.model_rotation_deg.x),
		deg_to_rad(w.model_rotation_deg.y),
		deg_to_rad(w.model_rotation_deg.z)
	))
	return b * correction

func _apply_transform(w: WeaponDef):
	w.slot.position = w.pos
	w.slot.rotation_degrees = w.rot
	w.orient.basis = _orient_basis(w)
	w.pivot.scale = Vector3.ONE * (w.length / maxf(w.longest, 0.0001))
	w.muzzle_node.position = w.muzzle

func _build_viewmodel(w: WeaponDef):
	w.holder = Node3D.new()
	w.holder.visible = false
	root.add_child(w.holder)
	w.anim = Node3D.new()
	w.holder.add_child(w.anim)
	w.slot = Node3D.new()
	w.anim.add_child(w.slot)
	w.orient = Node3D.new()
	w.slot.add_child(w.orient)
	w.pivot = Node3D.new()
	w.orient.add_child(w.pivot)

	var model := _load_model(w)
	model.position = Vector3.ZERO
	model.visible = true
	w.pivot.add_child(model)
	_no_shadows(model)
	if apply_textures and ResourceLoader.exists(w.path) and not model.has_meta("procedural_viewmodel"):
		_apply_textures(model, w)

	# auto-ajuste: mede o modelo, deteta a orientação, centra-o e normaliza o comprimento
	if not _fit_model(model, w):
		push_warning("WeaponManager: '%s' não tem geometria utilizável - a usar modelo 3D provisório." % w.path)
		model.queue_free()
		model = _placeholder(w)
		w.pivot.add_child(model)
		_no_shadows(model)
		if not _fit_model(model, w):
			push_error("WeaponManager: não foi possível construir o modelo provisório de %s." % w.display_name)

	w.muzzle_node = Node3D.new()
	w.anim.add_child(w.muzzle_node)

	if not w.melee:
		w.flash = MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.22, 0.22)
		w.flash.mesh = qm
		var fm := StandardMaterial3D.new()
		fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		fm.albedo_texture = soft_tex
		fm.cull_mode = BaseMaterial3D.CULL_DISABLED
		w.flash.material_override = fm
		w.flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		w.flash.visible = false
		w.muzzle_node.add_child(w.flash)
		w.flash_light = OmniLight3D.new()
		w.flash_light.light_color = Color(1.0, 0.75, 0.4)
		w.flash_light.omni_range = 6.0
		w.flash_light.light_energy = 0.0
		w.flash_light.shadow_enabled = false
		w.muzzle_node.add_child(w.flash_light)

	_apply_transform(w)
	if debug_models:
		print("[WeaponManager] %s preparado | pos=%s | escala=%s | rotação extra=%s" % [
			w.display_name, str(w.pos), str(w.pivot.scale), str(w.model_rotation_deg)
		])

func _process(delta):
	if not ready_ok:
		return
	var active := _is_active()
	var w := _current()
	var slot_index: int = slots[clampi(cur, 0, slots.size() - 1)] if not slots.is_empty() else -1

	# visibilidade (arma ativa / mãos do Jett)
	for i in range(defs.size()):
		var v: bool = active and i == slot_index
		if defs[i].holder.visible != v:
			defs[i].holder.visible = v
	if hide_jett_hands and jett.hand_l and jett.hand_r:
		jett.hand_l.visible = not active
		jett.hand_r.visible = not active

	_update_hud(w, active)
	if not active:
		return

	# flash do cano
	if flash_t > 0.0:
		flash_t -= delta
		if flash_t <= 0.0 and w.flash:
			w.flash.visible = false
			w.flash_light.light_energy = 0.0

	# balanço, sway e recuo do viewmodel
	vm_kick = lerpf(vm_kick, 0.0, clampf(14.0 * delta, 0.0, 1.0))
	vm_equip = lerpf(vm_equip, 0.0, clampf(8.0 * delta, 0.0, 1.0))
	var spd := Vector2(jett.velocity.x, jett.velocity.z).length()
	var mv := clampf(spd / maxf(base_run_speed, 0.01), 0.0, 1.0)
	if jett.is_on_floor():
		bob_t += delta * (4.0 + spd * 0.9)
	var bob := Vector3(sin(bob_t * 0.5) * 0.006, -absf(sin(bob_t)) * 0.008, 0.0) * mv

	sway_target = sway_target.lerp(Vector2.ZERO, clampf(6.0 * delta, 0.0, 1.0))
	sway = sway.lerp(sway_target, clampf(14.0 * delta, 0.0, 1.0))

	var target := bob + Vector3(-sway.x * 0.4, -sway.y * 0.3, vm_kick * 0.6)
	target += Vector3(0.0, -0.35 * vm_equip, 0.1 * vm_equip)
	if jett.is_dashing:
		target.z += 0.05
	w.holder.position = w.holder.position.lerp(target, clampf(18.0 * delta, 0.0, 1.0))
	w.holder.rotation = Vector3(vm_kick * 1.2 - 0.45 * vm_equip + sway.y, sway.x, 0.0)

	if tune:
		_tune(w, delta)

# ==================================================
# AFINAÇÃO AO VIVO
# ==================================================

func _tune(w: WeaponDef, delta: float):
	var dir := Vector3(
		float(Input.is_key_pressed(KEY_RIGHT)) - float(Input.is_key_pressed(KEY_LEFT)),
		float(Input.is_key_pressed(KEY_UP)) - float(Input.is_key_pressed(KEY_DOWN)),
		float(Input.is_key_pressed(KEY_PAGEDOWN)) - float(Input.is_key_pressed(KEY_PAGEUP)))
	if dir == Vector3.ZERO:
		return
	if Input.is_key_pressed(KEY_ALT):
		w.length = maxf(0.05, w.length + dir.y * 0.4 * delta)
	elif Input.is_key_pressed(KEY_SHIFT):
		w.rot += dir * 45.0 * delta
	else:
		w.pos += dir * 0.3 * delta
		w.muzzle += dir * 0.3 * delta       # o cano acompanha o movimento
	_apply_transform(w)
	tune_print_t -= delta
	if tune_print_t <= 0.0:
		tune_print_t = 0.4
		_print_tune(w)

func _print_tune(w: WeaponDef):
	print("---- %s ----" % w.display_name)
	print("%s_pos = Vector3(%.3f, %.3f, %.3f)" % [w.id, w.pos.x, w.pos.y, w.pos.z])
	print("%s_rot = Vector3(%.1f, %.1f, %.1f)" % [w.id, w.rot.x, w.rot.y, w.rot.z])
	print("%s_length = %.3f" % [w.id, w.length])
	print("%s_flip = %s" % [w.id, str(w.flip)])
	if not w.melee:
		print("%s_muzzle = Vector3(%.3f, %.3f, %.3f)" % [w.id, w.muzzle.x, w.muzzle.y, w.muzzle.z])

# ==================================================
# HUD
# ==================================================

func _build_hud():
	if jett.hud == null:
		return
	ammo_label = jett._label("", 42, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
	ammo_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ammo_label.offset_left = -320
	ammo_label.offset_right = -32
	ammo_label.offset_top = -96
	ammo_label.offset_bottom = -40
	jett.hud.add_child(ammo_label)

	name_label = jett._label("", 16, Color(0.35, 0.88, 1.0), HORIZONTAL_ALIGNMENT_RIGHT)
	name_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	name_label.offset_left = -320
	name_label.offset_right = -32
	name_label.offset_top = -116
	name_label.offset_bottom = -96
	jett.hud.add_child(name_label)

func _update_hud(w: WeaponDef, active: bool):
	if ammo_label == null:
		return
	ammo_label.visible = active
	name_label.visible = active
	if not active:
		return
	name_label.text = w.display_name
	if w.melee:
		ammo_label.text = ""
		return
	if reloading:
		ammo_label.text = "RECARREGANDO"
		ammo_label.add_theme_font_size_override("font_size", 24)
		ammo_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.3))
	else:
		ammo_label.text = "%d / %d" % [w.mag, w.reserve]
		ammo_label.add_theme_font_size_override("font_size", 42)
		ammo_label.add_theme_color_override("font_color", Color(1.0, 0.28, 0.33) if w.mag <= 5 else Color.WHITE)
