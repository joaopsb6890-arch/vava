extends CanvasLayer

# ==================================================
# HUD DA PARTIDA (desenhado por código)
# --------------------------------------------------
# Placar, cronómetro, barra de plantação/desarme, loja (B), killfeed,
# placar do Tab e ecrã final. O HUD de vida/armas/habilidades fica no player.gd.
# ==================================================

const ACCENT := Color(1.00, 0.30, 0.36)
const GOLD := Color(1.00, 0.83, 0.35)
const CYAN := Color(0.40, 0.88, 1.00)
const TEXT := Color(0.93, 0.96, 0.99)
const DIM := Color(0.58, 0.66, 0.74)
const DARK := Color(0.035, 0.05, 0.07, 0.88)

var match_ref
var root: Control

var score_attack: Label
var score_defense: Label
var timer_label: Label
var round_label: Label
var alive_label: Label
var credit_label: Label
var mode_label: Label

var banner_label: Label
var banner_sub: Label
var banner_t := 0.0

var prompt_label: Label
var plant_bar
var plant_label: Label
var defuse_bar
var defuse_label: Label

var buy_panel: PanelContainer
var buy_rows: VBoxContainer
var buy_credits: Label

var feed: VBoxContainer
var toast_label: Label
var toast_t := 0.0

var scoreboard: PanelContainer
var scoreboard_rows: VBoxContainer
var scoreboard_was_visible := false

var end_panel: Control

# ==================================================
# CONSTRUÇÃO
# ==================================================

func setup(m):
	match_ref = m
	layer = 20
	_build()

func _label(text: String, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 4)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _style(bg: Color, border: Color, bw: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(2)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	return s

func _panel(border: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _style(DARK, border, 2))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p

func _build():
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_build_top_bar()
	_build_banner()
	_build_prompts()
	_build_feed()
	_build_buy()
	_build_scoreboard()
	_build_end_panel()

	toast_label = _label("", 18, GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	toast_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	toast_label.offset_left = -300
	toast_label.offset_right = 300
	toast_label.offset_top = -230
	toast_label.offset_bottom = -200
	toast_label.modulate.a = 0.0
	root.add_child(toast_label)

	credit_label = _label("", 14, GOLD)
	credit_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	credit_label.offset_left = 18
	credit_label.offset_right = 300
	credit_label.offset_top = -176
	credit_label.offset_bottom = -152
	root.add_child(credit_label)

# ---------- BARRA SUPERIOR ----------

func _build_top_bar():
	var box := HBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	box.offset_left = -330
	box.offset_right = 330
	box.offset_top = 8
	box.offset_bottom = 88
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(box)

	var atk := _panel(CYAN)
	atk.custom_minimum_size = Vector2(118, 44)
	atk.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	score_attack = _label("0", 26, CYAN, HORIZONTAL_ALIGNMENT_CENTER)
	score_attack.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	atk.add_child(score_attack)
	box.add_child(atk)

	var mid := VBoxContainer.new()
	mid.custom_minimum_size = Vector2(150, 0)
	mid.add_theme_constant_override("separation", 0)
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	timer_label = _label("1:40", 30, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	mid.add_child(timer_label)
	round_label = _label("RONDA 1", 12, DIM, HORIZONTAL_ALIGNMENT_CENTER)
	mid.add_child(round_label)
	alive_label = _label("", 11, DIM, HORIZONTAL_ALIGNMENT_CENTER)
	mid.add_child(alive_label)
	box.add_child(mid)

	var dfn := _panel(ACCENT)
	dfn.custom_minimum_size = Vector2(118, 44)
	dfn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	score_defense = _label("0", 26, ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	score_defense.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dfn.add_child(score_defense)
	box.add_child(dfn)

	# etiquetas das equipas
	var atk_tag := _label("ATAQUE", 10, CYAN, HORIZONTAL_ALIGNMENT_LEFT)
	atk_tag.position = Vector2(0, 0)
	atk.add_child(atk_tag)

	mode_label = _label("", 11, DIM, HORIZONTAL_ALIGNMENT_CENTER)
	mode_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	mode_label.offset_left = -200
	mode_label.offset_right = 200
	mode_label.offset_top = 90
	mode_label.offset_bottom = 108
	root.add_child(mode_label)

# ---------- BANNER ----------

func _build_banner():
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.offset_left = -360
	box.offset_right = 360
	box.offset_top = -150
	box.offset_bottom = -60
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	root.add_child(box)

	banner_label = _label("", 42, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(banner_label)
	banner_sub = _label("", 15, DIM, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(banner_sub)

func banner(main: String, sub := ""):
	if banner_label == null:
		return
	banner_label.text = main
	banner_sub.text = sub
	banner_t = 3.2
	banner_label.modulate.a = 1.0
	banner_sub.modulate.a = 1.0

# ---------- PROMPTS / BARRAS ----------

func _build_prompts():
	prompt_label = _label("", 16, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	prompt_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_label.offset_left = -360
	prompt_label.offset_right = 360
	prompt_label.offset_top = -172
	prompt_label.offset_bottom = -146
	root.add_child(prompt_label)

	plant_bar = Bar.new()
	plant_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	plant_bar.offset_left = -160
	plant_bar.offset_right = 160
	plant_bar.offset_top = -142
	plant_bar.offset_bottom = -130
	plant_bar.col = GOLD
	root.add_child(plant_bar)

	plant_label = _label("", 12, GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	plant_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	plant_label.offset_left = -200
	plant_label.offset_right = 200
	plant_label.offset_top = -128
	plant_label.offset_bottom = -110
	root.add_child(plant_label)

	defuse_bar = Bar.new()
	defuse_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	defuse_bar.offset_left = -160
	defuse_bar.offset_right = 160
	defuse_bar.offset_top = 112
	defuse_bar.offset_bottom = 124
	defuse_bar.col = ACCENT
	root.add_child(defuse_bar)

	defuse_label = _label("", 12, ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	defuse_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	defuse_label.offset_left = -260
	defuse_label.offset_right = 260
	defuse_label.offset_top = 126
	defuse_label.offset_bottom = 144
	root.add_child(defuse_label)

func set_objective_prompt(text: String, frac := 0.0):
	if prompt_label == null:
		return
	prompt_label.text = text
	plant_bar.frac = clampf(frac, 0.0, 1.0)
	plant_bar.visible = frac > 0.001
	plant_label.text = "A PLANTAR  %d%%" % int(round(frac * 100.0)) if frac > 0.001 else ""

func set_defuse_prompt(frac: float, near: bool):
	if defuse_bar == null:
		return
	defuse_bar.visible = frac > 0.001
	defuse_label.visible = frac > 0.001 or near
	defuse_bar.frac = clampf(frac, 0.0, 1.0)
	defuse_label.text = "A DESARMAR  %d%%" % int(round(clampf(frac, 0.0, 1.0) * 100.0)) if near else ""

# ---------- KILLFEED ----------

func _build_feed():
	var feed_header := _label("REGISTO DE COMBATE", 10, DIM, HORIZONTAL_ALIGNMENT_RIGHT)
	feed_header.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	feed_header.offset_left = -340
	feed_header.offset_right = -18
	feed_header.offset_top = 94
	feed_header.offset_bottom = 112
	root.add_child(feed_header)

	feed = VBoxContainer.new()
	feed.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	feed.offset_left = -340
	feed.offset_right = -18
	feed.offset_top = 116
	feed.offset_bottom = 432
	feed.add_theme_constant_override("separation", 3)
	feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(feed)

func kill_feed(killer: String, victim: String, killer_team: String):
	if feed == null:
		return
	if feed.get_child_count() >= 5:
		feed.get_child(0).queue_free()
	var p := _panel(CYAN if killer_team == "attack" else ACCENT)
	p.size_flags_horizontal = Control.SIZE_SHRINK_END
	var l := _label("%s  ➜  %s" % [killer, victim], 12, TEXT, HORIZONTAL_ALIGNMENT_RIGHT)
	p.add_child(l)
	feed.add_child(p)
	var tw := p.create_tween()
	tw.tween_interval(5.0)
	tw.tween_property(p, "modulate:a", 0.0, 0.6)
	tw.tween_callback(p.queue_free)

func kill_feed_clear():
	if feed == null:
		return
	for c in feed.get_children():
		c.queue_free()

# ---------- LOJA ----------

func _build_buy():
	buy_panel = _panel(GOLD)
	buy_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	buy_panel.offset_left = -450
	buy_panel.offset_right = -32
	buy_panel.offset_top = -250
	buy_panel.offset_bottom = 250
	buy_panel.visible = false
	buy_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(buy_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	buy_panel.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	margin.add_child(col)

	col.add_child(_label("LOJA  //  FASE DE COMPRA", 20, GOLD))
	buy_credits = _label("", 13, TEXT)
	col.add_child(buy_credits)

	var sep := HSeparator.new()
	col.add_child(sep)

	buy_rows = VBoxContainer.new()
	buy_rows.add_theme_constant_override("separation", 4)
	col.add_child(buy_rows)

	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(fill)

	col.add_child(_label("B / ESC fecha a loja", 11, DIM))

func set_buy_open(open: bool):
	buy_panel.visible = open
	if open:
		refresh_buy()

func refresh_buy():
	if buy_rows == null or match_ref == null:
		return
	for c in buy_rows.get_children():
		c.queue_free()
	buy_credits.text = "CRÉDITOS: %d" % int(match_ref.credits)

	var list: Array = match_ref.get_buy_list()
	var i := 0
	for item in list:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.add_child(_label("%d" % (i + 1), 14, GOLD))
		row.add_child(_label(str(item.name), 14, TEXT))
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)
		var price := int(item.price)
		var can: bool = match_ref.credits >= price and match_ref.can_buy()
		row.add_child(_label(("GRÁTIS" if price == 0 else str(price) + " C"), 14, TEXT if can else DIM))
		buy_rows.add_child(row)
		i += 1

# ---------- PLACAR (TAB) ----------

func _build_scoreboard():
	scoreboard = _panel(CYAN)
	scoreboard.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	scoreboard.offset_left = -330
	scoreboard.offset_right = 330
	scoreboard.offset_top = -230
	scoreboard.offset_bottom = 230
	scoreboard.visible = false
	root.add_child(scoreboard)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	scoreboard.add_child(margin)

	scoreboard_rows = VBoxContainer.new()
	scoreboard_rows.add_theme_constant_override("separation", 4)
	margin.add_child(scoreboard_rows)

func _rebuild_scoreboard():
	if scoreboard_rows == null or match_ref == null:
		return
	for c in scoreboard_rows.get_children():
		c.queue_free()
	scoreboard_rows.add_child(_label("PLACAR  //  TAB para fechar", 18, CYAN))
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	head.add_child(_label("JOGADOR", 11, DIM))
	head.add_child(_label("AGENTE", 11, DIM))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	head.add_child(_label("K", 11, DIM))
	head.add_child(_label("D", 11, DIM))
	scoreboard_rows.add_child(head)

	for row in match_ref.get_scoreboard():
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		var team: String = str(row.team)
		var col := CYAN if team == "attack" else ACCENT
		h.add_child(_label(str(row.name), 13, col))
		h.add_child(_label(str(row.agent), 13, TEXT))
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(spacer)
		h.add_child(_label(str(row.kills), 13, TEXT))
		h.add_child(_label(str(row.deaths), 13, DIM))
		scoreboard_rows.add_child(h)

	scoreboard_rows.add_child(_label("", 8, DIM))
	scoreboard_rows.add_child(_label(
		"ATAQUE %d      •      DEFESA %d" % [match_ref.attack_score, match_ref.defense_score],
		14, TEXT))

# ---------- ECRÃ FINAL ----------

func _build_end_panel():
	end_panel = Control.new()
	end_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	end_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	end_panel.visible = false
	root.add_child(end_panel)

	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.03, 0.05, 0.82)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	end_panel.add_child(bg)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.offset_left = -420
	box.offset_right = 420
	box.offset_top = -180
	box.offset_bottom = 180
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	end_panel.add_child(box)

	var title := _label("FIM DA PARTIDA", 46, GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	title.name = "Title"
	box.add_child(title)
	var detail := _label("", 18, TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	detail.name = "Detail"
	box.add_child(detail)
	var hint := _label("ENTER para voltar ao lobby", 14, DIM, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(hint)

func show_match_end(winner: String):
	if end_panel == null or match_ref == null:
		return
	end_panel.visible = true
	var win := winner == "attack"
	var title: Label = end_panel.find_child("Title", true, false)
	var detail: Label = end_panel.find_child("Detail", true, false)
	if title:
		title.text = "VITÓRIA" if win else "DERROTA"
		title.add_theme_color_override("font_color", GOLD if win else ACCENT)
	if detail:
		detail.text = "%d  -  %d     //     %d rondas     //     %d kills / %d mortes\nMODO %s  •  MAPA %s  •  AGENTE %s" % [
			match_ref.attack_score, match_ref.defense_score, int(match_ref.round_no),
			int(match_ref.player_kills), int(match_ref.player_deaths),
			GameState.mode_name(GameState.mode), GameState.get_map(GameState.map_id).name,
			GameState.agent_display(GameState.agent_id),
		]

func toast(text: String):
	if toast_label == null:
		return
	toast_label.text = text
	toast_t = 1.6
	toast_label.modulate.a = 1.0

# ==================================================
# LOOP
# ==================================================

func _process(delta):
	if match_ref == null:
		return

	if banner_t > 0.0:
		banner_t -= delta
		var a := clampf(banner_t / 0.8, 0.0, 1.0)
		banner_label.modulate.a = a
		banner_sub.modulate.a = a

	if toast_t > 0.0:
		toast_t -= delta
		toast_label.modulate.a = clampf(toast_t / 0.5, 0.0, 1.0)

	_update_scores()

	# placar do Tab
	var tab: bool = Input.is_key_pressed(KEY_TAB) and not match_ref.match_over
	if tab and not scoreboard_was_visible:
		_rebuild_scoreboard()
	scoreboard.visible = tab
	scoreboard_was_visible = tab

	buy_panel.visible = match_ref.buy_open

func _update_scores():
	var dm: bool = GameState.mode == "deathmatch"
	if dm:
		score_attack.text = str(match_ref.dm_attack_kills)
		score_defense.text = str(match_ref.dm_defense_kills)
	else:
		score_attack.text = str(match_ref.attack_score)
		score_defense.text = str(match_ref.defense_score)

	var t := ""
	var state: String = match_ref.state
	if dm:
		t = "%d" % int(maxi(0, GameState.deathmatch_kills - maxi(match_ref.dm_attack_kills, match_ref.dm_defense_kills)))
		timer_label.text = "ALVO"
		timer_label.add_theme_color_override("font_color", TEXT)
		round_label.text = "FALTAM %s" % t
	else:
		match state:
			"buy":
				timer_label.text = "COMPRA %d" % int(ceil(maxf(0.0, match_ref.state_time)))
				timer_label.add_theme_color_override("font_color", GOLD)
			"round_end":
				timer_label.text = "%d" % int(ceil(maxf(0.0, match_ref.state_time)))
				timer_label.add_theme_color_override("font_color", TEXT)
			"match_end":
				timer_label.text = "--:--"
				timer_label.add_theme_color_override("font_color", DIM)
			_:
				if match_ref.spike_planted:
					timer_label.text = _fmt(match_ref.spike_timer)
					timer_label.add_theme_color_override("font_color", ACCENT)
				else:
					timer_label.text = _fmt(match_ref.round_time)
					timer_label.add_theme_color_override("font_color", TEXT if match_ref.round_time > 15.0 else ACCENT)
		round_label.text = "RONDA %d   •   %s" % [int(match_ref.round_no), GameState.mode_name(GameState.mode)]

	mode_label.text = "%s  //  %s  //  %s" % [
		GameState.get_map(GameState.map_id).name, GameState.mode_name(GameState.mode),
		GameState.difficulty_name(GameState.difficulty)
	]

	var alive_a: int = match_ref._alive_attackers()
	var alive_d: int = match_ref._alive_enemies()
	alive_label.text = "ATQ %d   •   DEF %d" % [alive_a, alive_d]
	alive_label.add_theme_color_override("font_color", CYAN if alive_a >= alive_d else ACCENT)

	credit_label.text = "CRÉDITOS  %d        %s" % [int(match_ref.credits),
		"  •  B PARA COMPRAR" if match_ref.can_buy() else ""]
	if match_ref.can_buy() and not match_ref.buy_open and match_ref.state != "match_end":
		prompt_label.text = "FASE DE COMPRA  •  B abre a loja  •  prepara-te para atacar o site %s" % str(match_ref.attack_site)
	elif match_ref.state == "round_end":
		prompt_label.text = ""

func _fmt(t: float) -> String:
	var secs := int(ceil(maxf(0.0, t)))
	return "%d:%02d" % [floori(secs / 60.0), secs % 60]

# ==================================================
# INPUT (loja)
# ==================================================

func _unhandled_input(event):
	if match_ref == null:
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key: int = event.keycode
	if key == KEY_B:
		match_ref.toggle_buy()
		get_viewport().set_input_as_handled()
	elif key == KEY_ESCAPE and match_ref.buy_open:
		match_ref.toggle_buy()
		get_viewport().set_input_as_handled()
	elif match_ref.buy_open and key >= KEY_1 and key <= KEY_7:
		match_ref.buy_index(key - KEY_1)
		get_viewport().set_input_as_handled()

# ==================================================
# BARRA DESENHADA
# ==================================================

class Bar extends Control:
	var frac := 0.0
	var col := Color(1.0, 0.83, 0.35)

	func _init():
		custom_minimum_size = Vector2(320, 12)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_d):
		queue_redraw()

	func _draw():
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.05, 0.8))
		var w: float = (size.x - 4.0) * clampf(frac, 0.0, 1.0)
		draw_rect(Rect2(Vector2(2, 2), Vector2(w, size.y - 4.0)), col)
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.28), false, 1.0)
