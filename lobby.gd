extends Control

# ==================================================
# LOBBY (100% construído por código)
# --------------------------------------------------
# Ecrã inicial do VAVA: escolha de agente, mapa, modo e dificuldade.
# Não existe uma única imagem: cards, painéis e ícones são desenhados aqui.
# ==================================================

const SLOT_KEYS := {"c": "C", "q": "Q", "e": "E", "x": "X"}
const SLOT_ORDER := ["c", "q", "e", "x"]
const MODES := ["spike", "deathmatch"]

const BG := Color(0.035, 0.05, 0.07)
const PANEL := Color(0.065, 0.09, 0.12)
const PANEL_HI := Color(0.10, 0.14, 0.18)
const LINE := Color(1, 1, 1, 0.09)
const TEXT := Color(0.92, 0.95, 0.98)
const DIM := Color(0.55, 0.63, 0.71)
const ACCENT := Color(1.0, 0.30, 0.36)
const GOLD := Color(1.0, 0.83, 0.35)

var agent_index := 0
var map_index := 0
var mode_index := 0
var diff_index := 1

var agent_buttons: Array = []
var map_buttons: Array = []
var mode_buttons: Array = []
var diff_buttons: Array = []

var detail_panel: PanelContainer
var detail_name: Label
var detail_role: Label
var detail_desc: Label
var detail_abilities: VBoxContainer
var detail_stats: Label
var detail_tag: Label
var help_panel: PanelContainer

# ==================================================
# READY
# ==================================================

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_sync_from_state()
	_build()
	_refresh()

func _sync_from_state():
	agent_index = _index_of_id(GameState.AGENTS, GameState.agent_id)
	map_index = _index_of_id(GameState.MAPS, GameState.map_id)
	mode_index = maxi(0, MODES.find(GameState.mode))
	diff_index = clampi(GameState.difficulty, 0, 2)

func _index_of_id(list: Array, id: String) -> int:
	for i in range(list.size()):
		if list[i].id == id:
			return i
	return 0

# ==================================================
# CONSTRUÇÃO DA UI
# ==================================================

func _build():
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# barra de destaque no topo e à esquerda
	var top_bar := ColorRect.new()
	top_bar.color = ACCENT
	top_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_bottom = 3
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_bar)

	var left_bar := ColorRect.new()
	left_bar.color = ACCENT
	left_bar.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	left_bar.offset_right = 3
	left_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(left_bar)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 36)
	margin.add_theme_constant_override("margin_right", 36)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_bottom", 26)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	margin.add_child(col)

	col.add_child(_build_header())

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 24)
	col.add_child(body)
	body.add_child(_build_left())
	body.add_child(_build_detail())

	col.add_child(_build_footer())

	_build_help()

# ---------- CABEÇALHO ----------

func _build_header() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)

	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.add_child(_label("VAVA", 46, TEXT))
	titles.add_child(_label("PROTOCOLO TÁTICO  //  BOTS  //  TUDO GERADO POR CÓDIGO", 12, ACCENT))
	row.add_child(titles)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 0)
	var info := _label("AGENTE  •  MAPA  •  MODO", 12, DIM)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(info)
	var help_hint := _label("ENTER inicia o jogo", 12, DIM)
	help_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(help_hint)
	row.add_child(right)
	return row

# ---------- COLUNA ESQUERDA: AGENTES + MAPAS ----------

func _build_left() -> Control:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 10)

	col.add_child(_section("ESCOLHE O TEU AGENTE"))

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	col.add_child(grid)

	for i in range(GameState.AGENTS.size()):
		var a: Dictionary = GameState.AGENTS[i]
		var b := _button("%s\n%s" % [a.name, a.role], Vector2(178, 82))
		b.add_theme_font_size_override("font_size", 16)
		b.pressed.connect(_select_agent.bind(i))
		grid.add_child(b)
		agent_buttons.append(b)

	col.add_child(_section("MAPA"))

	var maps_row := HBoxContainer.new()
	maps_row.add_theme_constant_override("separation", 8)
	col.add_child(maps_row)
	for i in range(GameState.MAPS.size()):
		var m: Dictionary = GameState.MAPS[i]
		var b := _button("%s\n%s" % [m.name, m.subtitle], Vector2(0, 62))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 15)
		b.pressed.connect(_select_map.bind(i))
		maps_row.add_child(b)
		map_buttons.append(b)

	var note := _label("Todos os mapas têm sites A e B, cobertura tática e são gerados por código a cada partida.", 12, DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 420
	col.add_child(note)

	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(filler)
	return col

# ---------- COLUNA DIREITA: DETALHE DO AGENTE ----------

func _build_detail() -> Control:
	detail_panel = PanelContainer.new()
	detail_panel.custom_minimum_size.x = 430
	detail_panel.add_theme_stylebox_override("panel", _style(PANEL, LINE, 1))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	detail_panel.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	margin.add_child(col)

	detail_tag = _label("", 11, DIM)
	col.add_child(detail_tag)

	detail_name = _label("", 34, TEXT)
	col.add_child(detail_name)

	detail_role = _label("", 13, ACCENT)
	col.add_child(detail_role)

	detail_desc = _label("", 13, TEXT)
	detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_desc.custom_minimum_size.x = 380
	col.add_child(detail_desc)

	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 12)
	col.add_child(sep)

	col.add_child(_section("HABILIDADES"))

	detail_abilities = VBoxContainer.new()
	detail_abilities.add_theme_constant_override("separation", 8)
	col.add_child(detail_abilities)

	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(fill)

	detail_stats = _label("", 13, TEXT)
	col.add_child(detail_stats)

	return detail_panel

# ---------- RODAPÉ ----------

func _build_footer() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)

	row.add_child(_option_group("MODO", ["SPIKE RUSH", "DEATHMATCH"], mode_buttons, _select_mode))
	row.add_child(_option_group("DIFICULDADE", ["FÁCIL", "NORMAL", "DIFÍCIL"], diff_buttons, _select_diff))

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var help := _button("COMO JOGAR", Vector2(150, 52))
	help.pressed.connect(_toggle_help)
	row.add_child(help)

	var play := _button("JOGAR", Vector2(220, 52))
	play.add_theme_font_size_override("font_size", 20)
	play.add_theme_stylebox_override("normal", _style(ACCENT, ACCENT, 0))
	play.add_theme_stylebox_override("hover", _style(ACCENT.lightened(0.12), ACCENT, 0))
	play.add_theme_stylebox_override("pressed", _style(ACCENT.darkened(0.2), ACCENT, 0))
	play.add_theme_color_override("font_color", Color(1, 1, 1))
	play.pressed.connect(_start)
	row.add_child(play)

	return row

func _option_group(title: String, options: Array, store: Array, cb: Callable) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.add_child(_section(title))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for i in range(options.size()):
		var b := _button(str(options[i]), Vector2(104, 32))
		b.add_theme_font_size_override("font_size", 12)
		b.pressed.connect(cb.bind(i))
		row.add_child(b)
		store.append(b)
	col.add_child(row)
	return col

# ---------- AJUDA ----------

func _build_help():
	help_panel = PanelContainer.new()
	help_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	help_panel.offset_left = 120
	help_panel.offset_right = -120
	help_panel.offset_top = 70
	help_panel.offset_bottom = -70
	help_panel.add_theme_stylebox_override("panel", _style(PANEL, ACCENT, 2))
	help_panel.visible = false
	add_child(help_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 26)
	margin.add_theme_constant_override("margin_right", 26)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 22)
	help_panel.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)

	col.add_child(_label("COMO JOGAR", 26, ACCENT))
	var body := _label(
		"OBJETIVO (SPIKE RUSH)\n" +
		"Estás no ataque com 2 aliados contra 3 defensores. Chega a um dos sites (A ou B),\n" +
		"segura F durante 4 segundos para plantar o spike e defende-o até explodir.\n" +
		"A ronda termina se o spike explodir, se a defesa toda cair ou se o tempo acabar.\n" +
		"Primeira equipa a 5 rondas ganha. No DEATHMATCH é só eliminar: 20 kills.\n\n" +
		"CONTROLOS\n" +
		"WASD mover  •  Shift andar  •  Ctrl agachar  •  Espaço saltar (segura no ar = drift)\n" +
		"Q / E / C habilidades  •  X ultimate  •  Esq/Dir dispara  •  1 / 2 / 3 armas\n" +
		"R recarregar  •  B loja (fase de compra)  •  Tab placar  •  F plantar  •  F1 ajuda\n\n" +
		"AGENTES\n" +
		"Cada agente tem 4 habilidades diferentes (C, Q, E e X). Q/E/C recarregam com o tempo;\n" +
		"a X (ultimate) carrega com eliminações. Testa-os todos: o kit muda mesmo o jogo.",
		13, TEXT)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size.x = 760
	col.add_child(body)

	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(fill)

	var close := _button("FECHAR  (ESC)", Vector2(170, 38))
	close.pressed.connect(_toggle_help)
	col.add_child(close)

# ==================================================
# HELPERS VISUAIS
# ==================================================

func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _section(text: String) -> Label:
	return _label(text, 12, ACCENT)

func _style(bg: Color, border: Color, bw: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(3)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s

func _button(text: String, min_size: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	b.clip_text = false
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", DIM)
	b.add_theme_stylebox_override("normal", _style(PANEL, LINE, 1))
	b.add_theme_stylebox_override("hover", _style(PANEL_HI, LINE, 1))
	b.add_theme_stylebox_override("pressed", _style(PANEL.darkened(0.25), LINE, 1))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b

func _paint(b: Button, active: bool, tint: Color) -> void:
	var bg := PANEL.lerp(tint, 0.18) if active else PANEL
	b.add_theme_stylebox_override("normal", _style(bg, tint if active else LINE, 2 if active else 1))
	b.add_theme_stylebox_override("hover", _style(bg.lightened(0.08), tint, 1))
	b.add_theme_stylebox_override("pressed", _style(bg.darkened(0.2), tint, 2))
	b.add_theme_color_override("font_color", TEXT if active else DIM)

# ==================================================
# ATUALIZAÇÃO DO ESTADO
# ==================================================

func _refresh():
	for i in range(agent_buttons.size()):
		var a: Dictionary = GameState.AGENTS[i]
		_paint(agent_buttons[i], i == agent_index, a.color)

	for i in range(map_buttons.size()):
		var m: Dictionary = GameState.MAPS[i]
		_paint(map_buttons[i], i == map_index, m.accent)

	for i in range(mode_buttons.size()):
		_paint(mode_buttons[i], i == mode_index, ACCENT)
	for i in range(diff_buttons.size()):
		_paint(diff_buttons[i], i == diff_index, GOLD)

	var agent: Dictionary = GameState.AGENTS[agent_index]
	var map: Dictionary = GameState.MAPS[map_index]
	detail_name.text = agent.name
	detail_name.add_theme_color_override("font_color", agent.color)
	detail_role.text = "%s   •   %s" % [agent.role, agent.country]
	detail_desc.text = agent.desc
	detail_tag.text = "AGENTE SELECIONADO  //  %s" % GameState.mode_name(MODES[mode_index])
	detail_stats.text = "VIDA %d     ESCUDO %d     VELOCIDADE %.1f     //     MAPA %s" % [
		int(agent.hp), int(agent.armor), float(agent.speed), str(map.name)
	]

	for c in detail_abilities.get_children():
		c.queue_free()
	for slot in SLOT_ORDER:
		var ab: Dictionary = agent.abilities[slot]
		detail_abilities.add_child(_ability_row(slot, ab, agent.color))

func _ability_row(slot: String, ab: Dictionary, tint: Color) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var badge := PanelContainer.new()
	badge.custom_minimum_size = Vector2(32, 30)
	badge.add_theme_stylebox_override("panel", _style(PANEL_HI, tint, 1))
	var key := _label(str(SLOT_KEYS[slot]), 14, tint)
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_child(key)
	row.add_child(badge)

	var texts := VBoxContainer.new()
	texts.add_theme_constant_override("separation", 0)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var is_ult: bool = ab.get("ult", false) or str(ab.type) in ["knives", "strike"]
	var name_label := _label(str(ab.name), 14, GOLD if is_ult else TEXT)
	texts.add_child(name_label)
	var cost := "  •  ultimate" if is_ult else "  •  %d carga(s)" % int(ab.get("charges", 1))
	var desc := _label("%s%s" % [str(ab.desc), cost], 12, DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size.x = 330
	texts.add_child(desc)
	row.add_child(texts)
	return row

# ==================================================
# AÇÕES
# ==================================================

func _select_agent(i: int):
	agent_index = i
	_refresh()

func _select_map(i: int):
	map_index = i
	_refresh()

func _select_mode(i: int):
	mode_index = i
	_refresh()

func _select_diff(i: int):
	diff_index = i
	_refresh()

func _toggle_help():
	help_panel.visible = not help_panel.visible

func _start():
	GameState.agent_id = GameState.AGENTS[agent_index].id
	GameState.map_id = GameState.MAPS[map_index].id
	GameState.mode = MODES[mode_index]
	GameState.difficulty = diff_index
	GameState.last_result = {}
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_tree().change_scene_to_file("res://match.tscn")

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			help_panel.visible = not help_panel.visible
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			if not help_panel.visible:
				_start()
				get_viewport().set_input_as_handled()
