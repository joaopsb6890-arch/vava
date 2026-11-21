extends Node3D

# ==================================================
# MATCH - GESTOR DA PARTIDA
# --------------------------------------------------
# Monta o mapa escolhido, cria o jogador com o agente escolhido, cria as
# equipas de bots, controla rondas / compras / spike / placar e volta ao lobby.
#
# Modos:
#   spike       -> ataque (tu + aliados) contra defesa; planta o spike num site
#   deathmatch  -> respawns infinitos, primeira equipa a 20 eliminações
# ==================================================

const STATE_BUY := "buy"
const STATE_LIVE := "live"
const STATE_ROUND_END := "round_end"
const STATE_MATCH_END := "match_end"

const ROUND_TIME := 100.0
const SPIKE_TIME := 45.0
const PLANT_TIME := 4.0
const DEFUSE_TIME := 6.0
const BUY_TIME := 9.0
const ROUND_END_TIME := 5.0
const SITE_RADIUS := 6.0

var map_node: Node3D
var hud
var player

var allies: Array = []
var enemies: Array = []
var bots: Array = []

var state := STATE_BUY
var round_no := 1
var attack_score := 0
var defense_score := 0
var credits := 800
var round_time := ROUND_TIME
var state_time := BUY_TIME

var spike_planted := false
var spike_pos := Vector3.ZERO
var spike_node: Node3D
var spike_light: OmniLight3D
var spike_timer := SPIKE_TIME
var plant_progress := 0.0
var defuse_progress := 0.0

var attack_spawn := Vector3.ZERO
var defense_spawn := Vector3.ZERO
var sites: Dictionary = {}
var attack_site := "A"

var primary_id := ""
var secondary_id := "classic"

var dm_attack_kills := 0
var dm_defense_kills := 0
var player_kills := 0
var player_deaths := 0
var match_over := false

var respawns: Array = []          # [{bot, t, pos}]
var player_respawn_t := -1.0
var buy_open := false
var blink := 0.0

# ==================================================
# READY
# ==================================================

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_setup_map()
	await get_tree().physics_frame
	await get_tree().physics_frame
	if not is_inside_tree():
		return

	attack_spawn = _find_ground(GameState.get_map(GameState.map_id).attack_spawn)
	defense_spawn = _find_ground(GameState.get_map(GameState.map_id).defense_spawn)
	sites = {
		"A": _find_ground(GameState.get_map(GameState.map_id).site_a),
		"B": _find_ground(GameState.get_map(GameState.map_id).site_b),
	}

	_build_site_markers()
	_build_spike()
	print("[Match] mapa=%s agente=%s ataque=%s defesa=%s siteA=%s siteB=%s" % [
		GameState.map_id, GameState.agent_id, str(attack_spawn), str(defense_spawn),
		str(sites["A"]), str(sites["B"])])
	_spawn_player()
	_spawn_bots()

	hud = load("res://match_hud.gd").new()
	hud.name = "MatchHUD"
	add_child(hud)
	hud.setup(self)

	credits = GameState.credits_start
	if GameState.mode == "deathmatch":
		_start_deathmatch()
	else:
		_start_round()

func _setup_map():
	map_node = Node3D.new()
	map_node.name = "Map"
	map_node.set_script(load("res://map.gd"))
	map_node.set("map_id", GameState.map_id)
	map_node.set("spawn_player", false)
	map_node.set("spawn_dummies", false)
	add_child(map_node)

# ==================================================
# SPAWNS
# ==================================================

func _find_ground(hint: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	for attempt in range(30):
		var off := Vector3.ZERO
		if attempt > 0:
			var ang := float(attempt) * 2.399963
			var r := 1.6 * sqrt(float(attempt))
			off = Vector3(cos(ang) * r, 0.0, sin(ang) * r)
		var x := hint.x + off.x
		var z := hint.z + off.z
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 42.0, z), Vector3(x, -12.0, z))
		q.collision_mask = 1
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			continue
		var y: float = hit.position.y
		if y < -1.0 or y > 0.9:
			continue
		var probe := PhysicsShapeQueryParameters3D.new()
		var shape := CapsuleShape3D.new()
		shape.radius = 0.45
		shape.height = 1.8
		probe.shape = shape
		probe.transform = Transform3D(Basis(), Vector3(x, y + 1.15, z))
		probe.collision_mask = 1
		if not space.intersect_shape(probe, 1).is_empty():
			continue
		return Vector3(x, y + 0.25, z)
	return hint

func _random_point_around(center: Vector3, radius: float) -> Vector3:
	for i in range(10):
		var ang := randf() * TAU
		var r := radius * sqrt(randf())
		var p := center + Vector3(cos(ang) * r, 0.0, sin(ang) * r)
		var g := _find_ground(p)
		if g.distance_to(p) < radius + 8.0:
			return g
	return center

# ==================================================
# JOGADOR
# ==================================================

func _spawn_player():
	var p := CharacterBody3D.new()
	p.name = "Player"
	var cs := CollisionShape3D.new()
	cs.name = "CollisionShape3D"
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	cs.shape = cap
	cs.position = Vector3(0, 0.9, 0)
	p.add_child(cs)

	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.position = Vector3(0, 1.6, 0)
	cam.current = true
	p.add_child(cam)

	p.set_script(load("res://player.gd"))
	p.set("match_mode", true)
	p.set("auto_respawn", false)
	p.set("team", "attack")
	p.configure_agent(GameState.get_agent(GameState.agent_id))
	p.position = attack_spawn
	add_child(p)

	var wm := Node.new()
	wm.name = "WeaponManager"
	wm.set_script(load("res://weapon_manager.gd"))
	p.add_child(wm)

	player = p
	player.died.connect(_on_player_died)

# ==================================================
# BOTS
# ==================================================

var ally_names := ["ALIADO VEX", "ALIADO NOVA", "ALIADO KILO"]
var enemy_names := ["INIMIGO ECHO", "INIMIGO TANGO", "INIMIGO SIERRA", "INIMIGO OMEGA"]

func _spawn_bots():
	var used: Array = [GameState.agent_id]
	for i in range(GameState.bot_allies):
		var agent_id := GameState.random_agent_id(used)
		used.append(agent_id)
		var b = _make_bot("attack", ally_names[i % ally_names.size()], agent_id,
			_random_point_around(attack_spawn, 5.0))
		allies.append(b)
		bots.append(b)

	for i in range(GameState.bot_enemies):
		var agent_id := GameState.random_agent_id(used)
		used.append(agent_id)
		var b = _make_bot("defense", enemy_names[i % enemy_names.size()], agent_id,
			_random_point_around(defense_spawn, 6.0))
		enemies.append(b)
		bots.append(b)

func _make_bot(team: String, name: String, agent_id: String, pos: Vector3):
	var b := CharacterBody3D.new()
	b.name = name.replace(" ", "_")
	b.set_script(load("res://bot.gd"))
	b.setup({
		"team": team,
		"name": name,
		"agent": GameState.get_agent(agent_id),
		"difficulty": GameState.difficulty,
		"roam_center": pos,
		"roam_radius": 12.0,
	})
	b.position = pos
	add_child(b)
	b.died.connect(_on_bot_died)
	return b

# ==================================================
# MARCADORES 3D (SITES + SPIKE)
# ==================================================

func _build_site_markers():
	for letter in ["A", "B"]:
		var pos: Vector3 = sites[letter]
		var root := Node3D.new()
		root.name = "Site" + letter
		add_child(root)
		root.global_position = pos

		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = SITE_RADIUS - 0.25
		torus.outer_radius = SITE_RADIUS
		torus.rings = 48
		ring.mesh = torus
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(1.0, 0.82, 0.35, 0.85)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ring.material_override = m
		ring.position = Vector3(0, 0.06, 0)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(ring)

		var beam := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.06
		cyl.bottom_radius = 0.06
		cyl.height = 14.0
		beam.mesh = cyl
		var bm := StandardMaterial3D.new()
		bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bm.albedo_color = Color(1.0, 0.82, 0.35, 0.20)
		bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		beam.material_override = bm
		beam.position = Vector3(0, 7.0, 0)
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(beam)

		var label := Label3D.new()
		label.text = letter
		label.font_size = 220
		label.pixel_size = 0.012
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = Color(1.0, 0.85, 0.4)
		label.outline_size = 26
		label.outline_modulate = Color(0, 0, 0, 0.7)
		label.position = Vector3(0, 3.4, 0)
		root.add_child(label)

func _build_spike():
	spike_node = Node3D.new()
	spike_node.name = "Spike"
	add_child(spike_node)
	spike_node.visible = false

	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.5, 0.34, 0.34)
	body.mesh = box
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.16, 0.18, 0.2)
	m.metallic = 0.6
	m.roughness = 0.35
	body.material_override = m
	body.position.y = 0.18
	spike_node.add_child(body)

	var core := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.13
	sph.height = 0.26
	core.mesh = sph
	var cm := StandardMaterial3D.new()
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.albedo_color = Color(1.0, 0.25, 0.2)
	core.material_override = cm
	core.position.y = 0.42
	spike_node.add_child(core)

	spike_light = OmniLight3D.new()
	spike_light.light_color = Color(1.0, 0.3, 0.2)
	spike_light.omni_range = 8.0
	spike_light.light_energy = 1.5
	spike_light.shadow_enabled = false
	spike_node.add_child(spike_light)

# ==================================================
# RONDAS (SPIKE)
# ==================================================

func _start_round():
	print("[Match] ronda %d (ataque %d - defesa %d)" % [round_no, attack_score, defense_score])
	state = STATE_BUY
	state_time = BUY_TIME
	round_time = ROUND_TIME
	spike_timer = SPIKE_TIME
	plant_progress = 0.0
	defuse_progress = 0.0
	spike_planted = false
	attack_site = "A" if randf() < 0.5 else "B"
	if spike_node:
		spike_node.visible = false

	if player:
		player.revive_at(attack_spawn)
		player.buy_open = false
		buy_open = false

	var i := 0
	for b in allies:
		b.reset_for_round(_random_point_around(attack_spawn, 4.0))
		b.frozen = true
		b.set_objective(sites[attack_site], 8.0)
		i += 1
	i = 0
	for b in enemies:
		var letter := "A" if i % 2 == 0 else "B"
		b.reset_for_round(_random_point_around(defense_spawn, 4.0))
		b.frozen = true
		b.set_objective(sites[letter], 9.0)
		i += 1

	_refill_weapons()
	if hud:
		hud.banner("RONDA %d" % round_no, "FASE DE COMPRA  •  B para abrir a loja")
		hud.kill_feed_clear()

func _begin_live():
	print("[Match] combate! site alvo=%s" % attack_site)
	state = STATE_LIVE
	if buy_open:
		buy_open = false
		if player:
			player.buy_open = false
		if hud:
			hud.set_buy_open(false)
	for b in bots:
		b.frozen = false
	if hud:
		hud.banner("COMBATE", "Planta o spike no site A ou B")

func _refill_weapons():
	var wm = player.get_node_or_null("WeaponManager")
	if wm and wm.has_method("give"):
		wm.give(primary_id, secondary_id, true)

func _process(delta):
	if match_over:
		return

	blink += delta
	if spike_light and spike_planted:
		spike_light.light_energy = 1.2 + sin(blink * 7.0) * 0.9

	if GameState.mode == "deathmatch":
		_process_deathmatch(delta)
		return

	match state:
		STATE_BUY:
			state_time -= delta
			if state_time <= 0.0:
				_begin_live()
		STATE_LIVE:
			if spike_planted:
				spike_timer -= delta
				if spike_timer <= 0.0:
					_end_round("attack", "O spike explodiu")
					return
				_update_defuse(delta)
			else:
				round_time -= delta
				if round_time <= 0.0:
					_end_round("defense", "Tempo esgotado sem plantação")
					return
				_update_plant(delta)
			_check_alive()
		STATE_ROUND_END:
			state_time -= delta
			if state_time <= 0.0:
				round_no += 1
				_start_round()

func _update_plant(delta):
	if player == null or player.dead:
		plant_progress = 0.0
		if hud:
			hud.set_objective_prompt("")
		return

	var site := _nearest_site(player.global_position)
	var in_site := site != ""
	var holding: bool = Input.is_key_pressed(KEY_F) and player.is_on_floor()

	if in_site and holding:
		plant_progress += delta
		if plant_progress >= PLANT_TIME:
			_plant_spike(sites[site])
			return
	elif plant_progress > 0.0:
		plant_progress = maxf(0.0, plant_progress - delta * 1.6)

	if hud:
		if in_site:
			hud.set_objective_prompt("SEGURA  F  PARA PLANTAR O SPIKE", plant_progress / PLANT_TIME)
		else:
			hud.set_objective_prompt("VAI PARA O SITE A OU B E PLANTA O SPIKE")

func _nearest_site(pos: Vector3) -> String:
	var best := ""
	var best_d := SITE_RADIUS
	for letter in sites.keys():
		var d: float = pos.distance_to(sites[letter])
		if d < best_d:
			best_d = d
			best = letter
	return best

func _plant_spike(pos: Vector3):
	spike_planted = true
	spike_pos = pos
	spike_timer = SPIKE_TIME
	plant_progress = 0.0
	for b in allies:
		b.set_objective(pos, 5.0)
	for b in enemies:
		b.set_objective(pos, 3.5)
	if spike_node:
		spike_node.visible = true
		spike_node.global_position = pos
	print("[Match] spike plantado em %s" % str(pos))
	if hud:
		hud.banner("SPIKE PLANTADO", "Defende durante 45 segundos")
		hud.set_objective_prompt("")

func _update_defuse(delta):
	var near := false
	for b in enemies:
		if b.dead:
			continue
		if b.global_position.distance_to(spike_pos) < 2.6:
			near = true
			break
	if near:
		defuse_progress += delta
		if defuse_progress >= DEFUSE_TIME:
			_end_round("defense", "Spike desarmado")
			return
	else:
		defuse_progress = maxf(0.0, defuse_progress - delta * 0.4)
	if hud:
		hud.set_defuse_prompt(defuse_progress / DEFUSE_TIME, near)

func _check_alive():
	if spike_planted:
		if _alive_enemies() == 0:
			_end_round("attack", "Defesa eliminada")
		return
	if _alive_attackers() == 0:
		_end_round("defense", "Ataque eliminado")
	elif _alive_enemies() == 0:
		_end_round("attack", "Defesa eliminada")

func _alive_attackers() -> int:
	var n := 0
	if player and not player.dead:
		n += 1
	for b in allies:
		if not b.dead:
			n += 1
	return n

func _alive_enemies() -> int:
	var n := 0
	for b in enemies:
		if not b.dead:
			n += 1
	return n

func _end_round(winner: String, reason: String):
	if state == STATE_ROUND_END or state == STATE_MATCH_END:
		return
	state = STATE_ROUND_END
	state_time = ROUND_END_TIME
	for b in bots:
		b.frozen = true
	print("[Match] fim da ronda %d: %s (%s)" % [round_no, winner, reason])
	if winner == "attack":
		attack_score += 1
		credits += 3000
	else:
		defense_score += 1
		credits += 1900
	if hud:
		hud.banner("RONDA %d  •  %s" % [round_no, GameState.team_label(winner)], reason)
		hud.set_objective_prompt("")
		hud.set_defuse_prompt(0.0, false)
	if attack_score >= GameState.rounds_to_win or defense_score >= GameState.rounds_to_win:
		_end_match(winner)

func _end_match(winner: String):
	print("[Match] FIM: vencedor=%s ataque=%d defesa=%d" % [winner, attack_score, defense_score])
	match_over = true
	state = STATE_MATCH_END
	GameState.last_result = {
		"winner": winner,
		"attack": attack_score,
		"defense": defense_score,
		"rounds": round_no,
		"kills": player_kills,
		"deaths": player_deaths,
		"mode": GameState.mode,
	}
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if player:
		player.buy_open = false
	buy_open = false
	for b in bots:
		b.frozen = true
	if hud:
		hud.show_match_end(winner)

# ==================================================
# DEATHMATCH
# ==================================================

func _start_deathmatch():
	state = STATE_LIVE
	spike_planted = false
	if spike_node:
		spike_node.visible = false
	for b in bots:
		b.frozen = false
		b.set_objective(_random_point_around(Vector3.ZERO, 40.0), 14.0)
	if player:
		player.revive_at(attack_spawn)
	_refill_weapons()
	if hud:
		hud.banner("DEATHMATCH", "Primeira equipa a %d eliminações" % GameState.deathmatch_kills)

func _process_deathmatch(delta):
	# respawns de bots
	var i := respawns.size() - 1
	while i >= 0:
		var r: Dictionary = respawns[i]
		r.t -= delta
		if r.t <= 0.0:
			var b = r.bot
			if is_instance_valid(b):
				var pos: Vector3 = _random_point_around(Vector3.ZERO, 40.0)
				b.reset_for_round(pos)
				b.frozen = false
				b.set_objective(_random_point_around(Vector3.ZERO, 36.0), 16.0)
			respawns.remove_at(i)
		i -= 1

	# respawn do jogador
	if player_respawn_t > 0.0:
		player_respawn_t -= delta
		if player_respawn_t <= 0.0:
			player_respawn_t = -1.0
			if player:
				player.revive_at(_random_point_around(Vector3.ZERO, 34.0))
				_refill_weapons()

# ==================================================
# COMBATE / EVENTOS
# ==================================================

func _on_bot_died(bot, killer):
	var killer_name := "?"
	var killer_team := ""
	if killer != null and is_instance_valid(killer):
		killer_name = str(killer.get("display_name")) if killer.get("display_name") != null else str(killer.name)
		killer_team = str(killer.get("team")) if killer.get("team") != null else ""
		if killer == player:
			killer_name = "TU"
			player_kills += 1
			credits += 200

	if hud:
		var agent_name: String = str(bot.agent.get("name", "BOT")) if bot.agent is Dictionary else "BOT"
		hud.kill_feed(killer_name, "%s (%s)" % [str(bot.display_name), agent_name], killer_team)

	print("[Match] %s eliminado por %s" % [str(bot.display_name), killer_name])
	if GameState.mode == "deathmatch":
		if killer_team == "attack":
			dm_attack_kills += 1
		else:
			dm_defense_kills += 1
		respawns.append({"bot": bot, "t": 3.0})
		if dm_attack_kills >= GameState.deathmatch_kills:
			attack_score = dm_attack_kills
			_end_match("attack")
		elif dm_defense_kills >= GameState.deathmatch_kills:
			defense_score = dm_defense_kills
			_end_match("defense")
	else:
		_check_alive()

func _on_player_died():
	player_deaths += 1
	if hud:
		hud.kill_feed("DEFESA", "TU (%s)" % GameState.agent_display(GameState.agent_id), "defense")
	if GameState.mode == "deathmatch":
		dm_defense_kills += 1
		player_respawn_t = 3.0
		if dm_defense_kills >= GameState.deathmatch_kills:
			_end_match("defense")
	else:
		if hud:
			hud.banner("ELIMINADO", "A ronda continua com os teus aliados")

# ==================================================
# LOJA
# ==================================================

func can_buy() -> bool:
	return state == STATE_BUY and player != null

func get_buy_list() -> Array:
	var wm = player.get_node_or_null("WeaponManager") if player else null
	if wm and wm.has_method("get_buy_list"):
		return wm.get_buy_list()
	return []

func buy_index(index: int) -> bool:
	var list := get_buy_list()
	if index < 0 or index >= list.size():
		return false
	var item: Dictionary = list[index]
	if not can_buy():
		if hud:
			hud.toast("Só podes comprar na fase de compra")
		return false
	var price := int(item.price)
	if credits < price:
		if hud:
			hud.toast("Créditos insuficientes")
		return false
	credits -= price
	match str(item.slot):
		"primary":
			primary_id = str(item.id)
		"secondary":
			secondary_id = str(item.id)
		"armor":
			if player:
				player.set_armor(50.0)
	_refill_weapons()
	if hud:
		hud.toast("COMPRADO: " + str(item.name))
		hud.refresh_buy()
	return true

func toggle_buy() -> void:
	if not can_buy() and not buy_open:
		if hud:
			hud.toast("A loja abre na fase de compra")
		return
	buy_open = not buy_open
	if player:
		player.buy_open = buy_open
	if hud:
		hud.set_buy_open(buy_open)

# ==================================================
# PLACAR / INPUT
# ==================================================

func get_scoreboard() -> Array:
	var rows: Array = []
	rows.append({
		"name": "TU",
		"agent": GameState.agent_display(GameState.agent_id),
		"team": "attack",
		"kills": player_kills,
		"deaths": player_deaths,
	})
	var wm = player.get_node_or_null("WeaponManager") if player else null
	if wm and player:
		rows[0]["weapon"] = str(wm.current_name()) if wm.has_method("current_name") else ""
	for b in bots:
		rows.append({
			"name": str(b.display_name),
			"agent": str(b.agent.get("name", "BOT")) if b.agent is Dictionary else "BOT",
			"team": str(b.team),
			"kills": int(b.kills),
			"deaths": int(b.deaths),
			"weapon": "",
		})
	return rows

func _unhandled_input(event):
	if match_over and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER or event.keycode == KEY_ESCAPE:
			get_tree().change_scene_to_file("res://lobby.tscn")
			get_viewport().set_input_as_handled()
