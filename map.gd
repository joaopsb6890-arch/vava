extends Node3D

# ==================================================
# PEARL MAP GENERATOR  (Godot 4.x)
# --------------------------------------------------
# Como usar:
#   1. Cria uma cena nova com um Node3D na raiz e anexa este script.
#   2. Em "Player Script Path" põe o caminho do teu script do Jett.
#      (Se já tiveres o Jett na cena, ele é só teletransportado para o spawn.)
#   3. Corre. Tudo é gerado por código, com colisões.
#
# Compatível com o player: grupo "enemy" (minimapa), take_damage() -> bool,
# morrer ao cair ao mar (y < -20).
# ==================================================

@export_group("Mapa")
@export var map_seed := 7
@export var map_half := 70.0
@export var map_id := ""          # vazio = usa o mapa escolhido no lobby (GameState)

var theme: Dictionary = {}

@export_group("Jogador")
@export var spawn_player := true
@export_file("*.gd") var player_script_path := "res://jett.gd"
@export var spawn_point := Vector3(0, 0.15, 20)
@export_file("*.gd") var weapon_script_path := "res://weapon_manager.gd"   # vazio = sem armas

@export_group("Extras")
@export var spawn_dummies := true
@export var enable_shadows := true

const FLOOR_H := 3.2
const CELL_W := 3.0

var C_ROAD := Color(0.15, 0.17, 0.19)
var C_PAVE := Color(0.64, 0.62, 0.58)
var C_GROUND := Color(0.5, 0.5, 0.48)
var C_GRASS := Color(0.36, 0.62, 0.3)
const C_LINE := Color(0.92, 0.92, 0.88)
const C_YELLOW := Color(0.95, 0.78, 0.2)
var C_DECK := Color(0.32, 0.34, 0.37)
var C_RAIL := Color(0.55, 0.58, 0.6)
const C_ORANGE := Color(0.92, 0.46, 0.14)
const C_PINK := Color(0.86, 0.55, 0.52)
const C_CREAM := Color(0.93, 0.86, 0.78)
const C_METAL := Color(0.62, 0.66, 0.7)

var rng := RandomNumberGenerator.new()
var _mats := {}
var world: Node3D

# ==================================================
# READY
# ==================================================

func _ready():
	_apply_theme()
	rng.seed = map_seed
	world = Node3D.new()
	world.name = "Map"
	add_child(world)

	_build_environment()
	_build_ground()
	_build_roads()
	_build_houses()
	_build_pink_tower()
	_build_scaffold()
	_build_angular_tower()
	_build_white_buildings()
	_build_shops()
	_build_elevated_road()
	_build_park()
	_build_plaza_props()
	_build_extra_cover()
	_build_tactical_details()
	_build_border()
	if spawn_dummies:
		_spawn_dummies()
	call_deferred("_place_player")

# Paleta + dimensões vêm do mapa escolhido no lobby (GameState.MAPS).
func _apply_theme() -> void:
	var id := map_id
	if id == "" and GameState != null:
		id = GameState.map_id
	theme = GameState.get_map(id)
	if theme.is_empty():
		return
	map_seed = int(theme.get("seed", map_seed))
	map_half = float(theme.get("half", map_half))
	C_ROAD = theme.get("road", C_ROAD)
	C_PAVE = theme.get("pave", C_PAVE)
	C_GROUND = theme.get("ground", C_GROUND)
	C_GRASS = theme.get("grass", C_GRASS)
	C_DECK = C_GROUND.darkened(0.35)
	C_RAIL = C_PAVE.darkened(0.18)

func _physics_process(_delta):
	# quem cair ao mar morre
	for p in get_tree().get_nodes_in_group("player"):
		if p is Node3D and p.global_position.y < -20.0 and p.has_method("take_damage"):
			p.take_damage(9999.0)

# ==================================================
# HELPERS
# ==================================================

func mat(c: Color, rough := 0.85, emis := 0.0) -> StandardMaterial3D:
	var key := "m%s_%s_%s" % [c.to_html(true), rough, emis]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if emis > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emis
	_mats[key] = m
	return m

# Fachada com janelas (textura gerada por código, triplanar -> serve em qualquer tamanho)
func facade_mat(wall: Color, glass: Color, frame: Color, odd: bool) -> StandardMaterial3D:
	var key := "f%s%s%s%s" % [wall.to_html(), glass.to_html(), frame.to_html(), odd]
	if _mats.has(key):
		return _mats[key]
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(wall)
	img.fill_rect(Rect2i(12, 10, 40, 44), frame)
	img.fill_rect(Rect2i(15, 13, 34, 38), glass)
	img.fill_rect(Rect2i(31, 13, 2, 38), frame)
	img.fill_rect(Rect2i(15, 30, 34, 2), frame)
	img.fill_rect(Rect2i(10, 54, 44, 3), wall.darkened(0.3))
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.uv1_triplanar = true
	m.uv1_triplanar_sharpness = 8.0
	m.uv1_scale = Vector3(1.0 / CELL_W, 1.0 / FLOOR_H, 1.0 / CELL_W)
	if odd:
		m.uv1_offset = Vector3(0.0, 0.5, 0.0)
	m.roughness = 0.8
	_mats[key] = m
	return m

# Pavimento com juntas (lajes de 4 m)
func tile_mat(base: Color) -> StandardMaterial3D:
	var key := "t%s" % base.to_html()
	if _mats.has(key):
		return _mats[key]
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	img.fill(base)
	img.fill_rect(Rect2i(0, 0, 64, 2), base.darkened(0.22))
	img.fill_rect(Rect2i(0, 0, 2, 64), base.darkened(0.22))
	img.generate_mipmaps()
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.25, 0.25, 0.25)
	m.roughness = 0.95
	_mats[key] = m
	return m

# Caixa (pos = centro). solid = cria StaticBody3D com colisão.
func box(pos: Vector3, size: Vector3, material: Material, solid := true, rot := Vector3.ZERO, parent: Node = null) -> Node3D:
	var holder: Node3D
	if solid:
		var b := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		b.add_child(cs)
		holder = b
	else:
		holder = Node3D.new()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if solid else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(mi)
	(parent if parent else world).add_child(holder)
	holder.position = pos
	holder.rotation = rot
	return holder

func cyl(pos: Vector3, radius: float, height: float, material: Material, solid := true, top_r := -1.0) -> Node3D:
	var holder: Node3D
	if solid:
		var b := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = radius
		sh.height = height
		cs.shape = sh
		b.add_child(cs)
		holder = b
	else:
		holder = Node3D.new()
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.bottom_radius = radius
	cm.top_radius = radius if top_r < 0.0 else top_r
	cm.height = height
	cm.radial_segments = 16
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = material
	holder.add_child(mi)
	world.add_child(holder)
	holder.position = pos
	return holder

# Laje fina sem colisão (estradas, passeios, relva)
func slab(x0: float, z0: float, x1: float, z1: float, y: float, h: float, material: Material) -> void:
	box(Vector3((x0 + x1) * 0.5, y + h * 0.5, (z0 + z1) * 0.5), Vector3(absf(x1 - x0), h, absf(z1 - z0)), material, false)

func invisible_wall(pos: Vector3, size: Vector3) -> void:
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	b.add_child(cs)
	world.add_child(b)
	b.position = pos

# Prédio com fachada, cobertura e props de telhado. Devolve y do topo.
func building(cx: float, cz: float, w: float, d: float, floors: int, wall: Color, glass: Color, frame: Color,
		roof := Color(0.35, 0.37, 0.4), y0 := 0.0, props := true) -> float:
	var h := floors * FLOOR_H
	box(Vector3(cx, y0 + h * 0.5, cz), Vector3(w, h, d), facade_mat(wall, glass, frame, floors % 2 == 1))
	box(Vector3(cx, y0 + h + 0.15, cz), Vector3(w + 0.5, 0.3, d + 0.5), mat(roof))
	box(Vector3(cx, y0 + 0.4, cz), Vector3(w + 0.2, 0.8, d + 0.2), mat(wall.darkened(0.3)), false)
	var top := y0 + h + 0.3
	if props:
		rooftop_props(cx, cz, w, d, top)
	return top

func rooftop_props(cx: float, cz: float, w: float, d: float, y: float) -> void:
	for i in range(rng.randi_range(2, 4)):
		var px := cx + rng.randf_range(-w * 0.35, w * 0.35)
		var pz := cz + rng.randf_range(-d * 0.35, d * 0.35)
		match rng.randi() % 3:
			0:
				box(Vector3(px, y + 0.5, pz), Vector3(1.6, 1.0, 1.2), mat(Color(0.72, 0.74, 0.76)))
				cyl(Vector3(px, y + 1.05, pz), 0.4, 0.1, mat(Color(0.3, 0.32, 0.34)), false)
			1:
				cyl(Vector3(px, y + 0.8, pz), 0.9, 1.6, mat(Color(0.5, 0.6, 0.66)))
				cyl(Vector3(px, y + 1.9, pz), 0.95, 0.6, mat(Color(0.4, 0.45, 0.5)), false, 0.0)
			2:
				cyl(Vector3(px, y + 2.0, pz), 0.04, 4.0, mat(C_METAL), false)
				box(Vector3(px, y + 3.2, pz), Vector3(1.4, 0.05, 0.05), mat(C_METAL), false)
				box(Vector3(px, y + 2.5, pz), Vector3(1.0, 0.05, 0.05), mat(C_METAL), false)

func crate(pos: Vector3, s: float, color := Color(0.66, 0.5, 0.32)) -> void:
	box(pos + Vector3(0, s * 0.5, 0), Vector3(s, s, s), mat(color, 0.9), true, Vector3(0, rng.randf() * 0.8, 0))

func lamp(pos: Vector3) -> void:
	cyl(pos + Vector3(0, 2.6, 0), 0.07, 5.2, mat(Color(0.25, 0.28, 0.3)))
	box(pos + Vector3(0.5, 5.1, 0), Vector3(1.1, 0.1, 0.12), mat(Color(0.25, 0.28, 0.3)), false)
	box(pos + Vector3(0.95, 5.02, 0), Vector3(0.4, 0.06, 0.25), mat(Color(1.0, 0.92, 0.7), 0.4, 2.5), false)

func tree(pos: Vector3, s: float, leaf: Color) -> void:
	cyl(pos + Vector3(0, 1.2 * s, 0), 0.25 * s, 2.4 * s, mat(Color(0.36, 0.26, 0.18)))
	var f := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 2.0 * s
	sp.height = 3.6 * s
	f.mesh = sp
	f.material_override = mat(leaf, 0.9)
	world.add_child(f)
	f.position = pos + Vector3(0, 3.5 * s, 0)

# ==================================================
# AMBIENTE
# ==================================================

func _build_environment():
	var sky_top: Color = theme.get("sky_top", Color(0.28, 0.45, 0.52))
	var horizon: Color = theme.get("sky_horizon", Color(0.58, 0.74, 0.75))
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = sky_top
	sky_mat.sky_horizon_color = horizon
	sky_mat.ground_horizon_color = horizon
	sky_mat.ground_bottom_color = sky_top.darkened(0.45)
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = theme.get("fog", Color(0.5, 0.68, 0.7))
	env.fog_density = 0.004
	env.ssao_enabled = true
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_energy = 1.3
	sun.light_color = theme.get("sun", Color(1.0, 0.95, 0.85))
	sun.shadow_enabled = enable_shadows
	sun.directional_shadow_max_distance = 130.0
	add_child(sun)

	# mar à volta da ilha
	var wm := mat(Color(0.2, 0.46, 0.52), 0.15)
	wm.metallic = 0.2
	box(Vector3(0, -5.0, 0), Vector3(900, 0.2, 900), wm, false)

# ==================================================
# CHÃO, ESTRADAS
# ==================================================

func _build_ground():
	var h := map_half
	# bloco da ilha (topo em y = 0)
	box(Vector3(0, -3.0, 0), Vector3(h * 2.0, 6.0, h * 2.0), tile_mat(C_GROUND))

func _build_roads():
	var h := map_half
	var road := mat(C_ROAD, 0.95)
	var pave := tile_mat(C_PAVE)

	# Estrada A (E-W, z = 30) e passeios
	slab(-h, 25, h, 35, 0.0, 0.04, road)
	slab(-h, 22, -25, 25, 0.0, 0.05, pave)
	slab(-11, 22, h, 25, 0.0, 0.05, pave)
	slab(-h, 35, h, 38, 0.0, 0.05, pave)

	# Estrada B (N-S, x = -18) e passeios
	slab(-22, -h, -14, 25, 0.0, 0.045, road)
	slab(-25, -h, -22, 22, 0.0, 0.05, pave)
	slab(-14, -h, -11, 22, 0.0, 0.05, pave)

	# linhas tracejadas
	var x := -h + 3.0
	while x < h:
		if absf(x + 18.0) > 7.0:
			box(Vector3(x, 0.055, 30), Vector3(3.0, 0.01, 0.2), mat(C_YELLOW, 0.9), false)
		x += 6.0
	var z := -h + 3.0
	while z < 20.0:
		box(Vector3(-18, 0.06, z), Vector3(0.2, 0.01, 3.0), mat(C_YELLOW, 0.9), false)
		z += 6.0

	# passadeiras
	for i in range(8):
		box(Vector3(-6, 0.06, 25.8 + i * 1.2), Vector3(3.0, 0.01, 0.6), mat(C_LINE, 0.9), false)
		box(Vector3(-21.2 + i * 1.2, 0.065, 12), Vector3(0.6, 0.01, 3.0), mat(C_LINE, 0.9), false)

	# candeeiros ao longo da estrada A
	var lx := -h + 8.0
	while lx < h - 4.0:
		if absf(lx + 18.0) > 8.0:
			lamp(Vector3(lx, 0, 23.5))
		lx += 16.0

# ==================================================
# CASAS DE TELHADO VERDE (oeste)
# ==================================================

func _build_houses():
	var cols := [-59.0, -49.0, -39.0, -30.0]
	var rows := [-16.0, -5.0, 6.0, 16.0]
	var walls := [Color(0.88, 0.78, 0.62), Color(0.82, 0.74, 0.66), Color(0.9, 0.83, 0.7)]
	var roofs := [Color(0.42, 0.62, 0.45), Color(0.52, 0.7, 0.5), Color(0.36, 0.56, 0.42)]

	for cx in cols:
		for cz in rows:
			if rng.randf() < 0.1:
				continue
			var w := 7.0
			var d := 8.0
			var floors := rng.randi_range(1, 2)
			var wall: Color = walls[rng.randi() % walls.size()]
			var top := floors * FLOOR_H
			box(Vector3(cx, top * 0.5, cz), Vector3(w, top, d), facade_mat(wall, Color(0.25, 0.33, 0.4), Color(0.6, 0.5, 0.4), floors % 2 == 1))

			# telhado de duas águas
			var rot90 := rng.randf() < 0.5
			var pm := PrismMesh.new()
			pm.size = Vector3(d + 1.0, 2.2, w + 1.0) if rot90 else Vector3(w + 1.0, 2.2, d + 1.0)
			var rb := StaticBody3D.new()
			var rc := CollisionShape3D.new()
			rc.shape = pm.create_convex_shape()
			rb.add_child(rc)
			var rm := MeshInstance3D.new()
			rm.mesh = pm
			rm.material_override = mat(roofs[rng.randi() % roofs.size()], 0.75)
			rb.add_child(rm)
			world.add_child(rb)
			rb.position = Vector3(cx, top + 1.1, cz)
			if rot90:
				rb.rotation.y = PI * 0.5

			# pormenores
			if rng.randf() < 0.6:
				box(Vector3(cx + 2.0, 0.6, cz + d * 0.5 + 0.5), Vector3(1.2, 1.2, 0.8), mat(Color(0.7, 0.72, 0.74)))
			if rng.randf() < 0.4:
				crate(Vector3(cx - 2.5, 0.0, cz - d * 0.5 - 1.0), 1.0)
			if rng.randf() < 0.5:
				cyl(Vector3(cx + 2.5, top + 2.4, cz - 1.0), 0.3, 1.2, mat(Color(0.45, 0.38, 0.35)), false)

	# caixas de água e árvore entre as casas
	cyl(Vector3(-44.0, 1.5, -10.5), 0.9, 3.0, mat(Color(0.5, 0.6, 0.66)))
	tree(Vector3(-24.5, 0, 6), 0.9, Color(0.3, 0.58, 0.32))

# ==================================================
# TORRE ROSA (centro)
# ==================================================

func _build_pink_tower():
	var cx := 0.0
	var cz := -28.0
	var w := 14.0
	var d := 12.0
	var floors := 14
	var glass := Color(0.3, 0.4, 0.46)
	var top := building(cx, cz, w, d, floors, C_PINK, glass, C_CREAM, Color(0.5, 0.35, 0.34), 0.0, false)

	# andar recuado no topo
	var top2 := building(cx + 1.0, cz, 8.0, 8.0, 2, C_PINK.darkened(0.06), glass, C_CREAM, Color(0.5, 0.35, 0.34), top, false)

	# varandas na fachada virada ao plaza (+z)
	var fz := cz + d * 0.5
	var f := 2
	while f < floors - 1:
		var y := f * FLOOR_H + 0.1
		for bx in [-3.2, 3.2]:
			box(Vector3(cx + bx, y, fz + 0.6), Vector3(4.0, 0.2, 1.2), mat(C_CREAM))
			box(Vector3(cx + bx, y + 0.55, fz + 1.15), Vector3(4.0, 0.9, 0.06), mat(Color(0.25, 0.3, 0.34), 0.5), false)
			if rng.randf() < 0.7:
				box(Vector3(cx + bx + 1.0, y + 0.5, fz + 0.5), Vector3(1.0, 0.8, 0.7), mat(Color(0.75, 0.77, 0.78)), false)
		f += 2

	# placa verde vertical (lado oeste) + faixa néon
	box(Vector3(cx - w * 0.5 - 0.2, floors * FLOOR_H * 0.6, cz + 1.0), Vector3(0.3, 10.0, 2.4), mat(Color(0.2, 0.7, 0.45), 0.5, 0.8), false)
	box(Vector3(cx + w * 0.5 + 0.15, floors * FLOOR_H * 0.45, cz - 2.0), Vector3(0.2, 7.0, 0.5), mat(Color(1.0, 0.45, 0.6), 0.5, 1.6), false)

	# telhado: antena parabólica, depósito, mastro
	var ry := top2
	var dish := MeshInstance3D.new()
	var dm := SphereMesh.new()
	dm.radius = 1.3
	dm.height = 2.6
	dish.mesh = dm
	dish.material_override = mat(Color(0.88, 0.9, 0.92), 0.4)
	dish.scale = Vector3(1, 0.3, 1)
	world.add_child(dish)
	dish.position = Vector3(cx + 2.5, ry + 2.6, cz + 1.0)
	dish.rotation_degrees = Vector3(-50, 20, 0)
	cyl(Vector3(cx + 2.5, ry + 1.3, cz + 1.0), 0.08, 2.6, mat(C_METAL), false)
	cyl(Vector3(cx - 2.0, ry + 1.0, cz - 1.5), 1.1, 2.0, mat(Color(0.5, 0.6, 0.66)))
	cyl(Vector3(cx - 2.0, ry + 2.35, cz - 1.5), 1.15, 0.7, mat(Color(0.4, 0.45, 0.5)), false, 0.0)
	cyl(Vector3(cx + 1.5, ry + 4.0, cz - 2.0), 0.06, 8.0, mat(C_METAL), false)
	rooftop_props(cx, cz, w, d, top)

# ==================================================
# ANDAIME LARANJA (ao lado da torre rosa)
# ==================================================

func _build_scaffold():
	var orange := mat(C_ORANGE, 0.6)
	var plank := mat(Color(0.7, 0.62, 0.5), 0.9)

	# plataforma 1 (y = 3.2)
	var p1 := Vector3(16, 3.2, -29.5)
	box(p1, Vector3(8, 0.25, 7), plank)
	# plataforma 2 (y = 6.4)
	var p2 := Vector3(16, 6.4, -47)
	box(p2, Vector3(8, 0.25, 7), plank)

	# rampa 1: do chão (x=28) até à plataforma 1 (x=20)
	var a1 := atan(3.2 / 8.0)
	box(Vector3(24, 1.6, -29.5), Vector3(sqrt(64.0 + 10.24), 0.2, 2.6), plank, true, Vector3(0, 0, -a1))
	# rampa 2: da plataforma 1 (z=-33) até à plataforma 2 (z=-43.5)
	var a2 := atan(3.2 / 10.5)
	box(Vector3(16, 4.8, -38.25), Vector3(2.6, 0.2, sqrt(110.25 + 10.24)), plank, true, Vector3(a2, 0, 0))

	# postes e vigas
	for p in [p1, p2]:
		for sx in [-3.8, 3.8]:
			for sz in [-3.3, 3.3]:
				cyl(Vector3(p.x + sx, p.y * 0.5, p.z + sz), 0.07, p.y, orange, false)
		box(p + Vector3(0, 0.6, 3.4), Vector3(8, 0.06, 0.06), orange, false)
		box(p + Vector3(0, 0.6, -3.4), Vector3(8, 0.06, 0.06), orange, false)
		box(p + Vector3(-3.9, 0.6, 0), Vector3(0.06, 0.06, 7), orange, false)
		box(p + Vector3(3.9, 0.6, 0), Vector3(0.06, 0.06, 7), orange, false)
	for k in range(3):
		box(Vector3(11.8, 1.6 + k * 1.6, -29.5), Vector3(0.06, 0.06, 7), orange, false)

	# cobertura (caixas) e canos até à torre
	crate(Vector3(18, 3.325, -31), 1.0)
	crate(Vector3(14, 6.525, -47), 1.2)
	cyl(Vector3(7.4, 8.0, -24), 0.09, 16.0, mat(Color(0.7, 0.7, 0.72)), false)

# ==================================================
# TORRE ANGULAR (fundo, lado direito)
# ==================================================

func _build_angular_tower():
	var r := 11.0
	var hgt := 75.0
	var cm := CylinderMesh.new()
	cm.bottom_radius = r
	cm.top_radius = r * 0.5
	cm.height = hgt
	cm.radial_segments = 5
	cm.rings = 1
	var b := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = cm.create_convex_shape()
	b.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	var m := mat(Color(0.82, 0.84, 0.86), 0.35)
	m.metallic = 0.3
	mi.material_override = m
	b.add_child(mi)
	world.add_child(b)
	b.position = Vector3(42, hgt * 0.5 - 3.0, -42)
	b.rotation = Vector3(0.0, 0.5, deg_to_rad(3.5))

	# base de betão com degraus de cobertura
	box(Vector3(30, 0.75, -26), Vector3(10, 1.5, 6), mat(Color(0.7, 0.7, 0.68)))
	crate(Vector3(30, 1.5, -26), 1.5, Color(0.55, 0.58, 0.6))

# ==================================================
# PRÉDIOS BRANCOS (este) + LOJAS
# ==================================================

func _build_white_buildings():
	var wall := Color(0.93, 0.94, 0.95)
	var glass := Color(0.32, 0.42, 0.48)
	var frame := Color(0.75, 0.77, 0.8)
	building(32, 6, 16, 14, 5, wall, glass, frame, Color(0.6, 0.62, 0.65))
	building(50, 15, 12, 14, 4, wall, glass, frame, Color(0.6, 0.62, 0.65))
	# degraus/cobertura para subir ao prédio mais baixo
	box(Vector3(43.5, 0.8, 22), Vector3(3, 1.6, 3), mat(Color(0.75, 0.75, 0.73)))
	box(Vector3(43.5, 2.4, 25), Vector3(3, 0.2, 3), mat(Color(0.75, 0.75, 0.73)), false)

func _build_shops():
	var palettes := [
		[Color(0.72, 0.45, 0.35), Color(0.3, 0.38, 0.44), Color(0.9, 0.85, 0.78)],
		[C_PINK, Color(0.3, 0.4, 0.46), C_CREAM],
		[Color(0.85, 0.75, 0.55), Color(0.28, 0.36, 0.42), Color(0.55, 0.45, 0.35)],
	]
	var xs := [-6.0, 6.0, 18.0]
	for i in range(xs.size()):
		var p: Array = palettes[i]
		building(xs[i], 17, 11, 9, rng.randi_range(3, 4), p[0], p[1], p[2], Color(0.4, 0.4, 0.42))
		# toldo
		box(Vector3(xs[i], 3.0, 17 + 5.2), Vector3(8, 0.1, 1.6), mat(Color(0.2, 0.62, 0.5), 0.8), false, Vector3(0.2, 0, 0))

# ==================================================
# VIADUTO CURVO (oeste/norte)
# ==================================================

func _build_elevated_road():
	var p0 := Vector2(-68, 30)
	var p1 := Vector2(-68, -60)
	var p2 := Vector2(10, -62)
	var segs := 18
	var prev := p0
	for i in range(1, segs + 1):
		var t := float(i) / float(segs)
		var q: Vector2 = (1.0 - t) * (1.0 - t) * p0 + 2.0 * t * (1.0 - t) * p1 + t * t * p2
		var dir := q - prev
		var seg_len := dir.length()
		var mid := (q + prev) * 0.5
		var ang := atan2(-dir.y, dir.x)
		var side := Vector2(-dir.y, dir.x).normalized()
		box(Vector3(mid.x, 6.7, mid.y), Vector3(seg_len + 0.15, 0.6, 8.0), mat(C_DECK, 0.9), true, Vector3(0, ang, 0))
		box(Vector3(mid.x, 7.02, mid.y), Vector3(seg_len * 0.5, 0.02, 0.2), mat(C_LINE), false, Vector3(0, ang, 0))
		for s in [-1.0, 1.0]:
			var rp: Vector2 = mid + side * s * 3.9
			box(Vector3(rp.x, 7.5, rp.y), Vector3(seg_len + 0.15, 1.0, 0.2), mat(C_RAIL), true, Vector3(0, ang, 0))
		if i % 2 == 0:
			cyl(Vector3(mid.x, 3.35, mid.y), 0.7, 6.7, mat(Color(0.6, 0.6, 0.58)))
		prev = q

	# placas verdes de sinalização no viaduto
	box(Vector3(-62, 9.0, -20), Vector3(0.2, 2.0, 5.0), mat(Color(0.15, 0.55, 0.4), 0.5, 0.6), false)

# ==================================================
# PARQUE (sul)
# ==================================================

func _build_park():
	var h := map_half
	slab(-h, 38, h, h, 0.0, 0.03, mat(C_GRASS, 1.0))
	# caminho de pedra
	slab(-2.5, 38, 2.5, h, 0.03, 0.02, tile_mat(Color(0.7, 0.68, 0.62)))

	for i in range(32):
		var x := rng.randf_range(-h + 6, h - 6)
		var z := rng.randf_range(41, h - 4)
		if absf(x) < 5.0 or Vector2(x - 24, z - 52).length() < 8.0:
			continue
		tree(Vector3(x, 0, z), rng.randf_range(0.8, 1.2), Color(0.27, 0.55, 0.3).lerp(Color(0.4, 0.68, 0.32), rng.randf()))

	# árvore roxa de destaque
	tree(Vector3(24, 0, 52), 1.7, Color(0.62, 0.3, 0.7))

	# sebes e bancos (cobertura)
	for i in range(6):
		var hx := -50.0 + i * 20.0 + rng.randf_range(-3, 3)
		box(Vector3(hx, 0.6, 46 + rng.randf_range(-3, 3)), Vector3(6, 1.2, 1.2), mat(Color(0.2, 0.46, 0.25)))
	for bx in [-8.0, 8.0]:
		box(Vector3(bx, 0.45, 48), Vector3(2.2, 0.15, 0.6), mat(Color(0.5, 0.35, 0.22)))
		box(Vector3(bx, 0.22, 48), Vector3(2.0, 0.3, 0.4), mat(Color(0.5, 0.5, 0.5)))

# ==================================================
# PLAZA CENTRAL: COBERTURA
# ==================================================

func _build_plaza_props():
	var concrete := mat(Color(0.7, 0.7, 0.68), 0.95)
	# barreiras de betão
	box(Vector3(-8, 0.6, -6), Vector3(5, 1.2, 0.8), concrete)
	box(Vector3(10, 0.6, -2), Vector3(0.8, 1.2, 5), concrete)
	box(Vector3(-2, 0.6, 6), Vector3(4, 1.2, 0.8), concrete)
	box(Vector3(24, 0.6, 24), Vector3(5, 1.2, 0.8), concrete)
	# caixotes
	crate(Vector3(-14, 0, -12), 1.4)
	crate(Vector3(-12.6, 0, -12), 1.4)
	crate(Vector3(-13.3, 1.4, -12), 1.2)
	crate(Vector3(4, 0, -16), 1.2)
	crate(Vector3(22, 0, -12), 1.5)
	# máquinas de venda
	for p in [Vector3(-9, 0, 22.4), Vector3(14, 0, 22.4), Vector3(-30, 0, 20.5)]:
		box(p + Vector3(0, 0.95, 0), Vector3(1.0, 1.9, 0.8), mat(Color(0.2, 0.45, 0.8), 0.5, 0.0))
		box(p + Vector3(0, 1.2, 0.41), Vector3(0.7, 1.0, 0.02), mat(Color(0.9, 0.95, 1.0), 0.4, 2.0), false)
	# candeeiros na plaza
	for p in [Vector3(-10, 0, -14), Vector3(10, 0, -14), Vector3(0, 0, 8)]:
		lamp(p)

# Cobertura extra: cada mapa tem uma quantidade própria de barreiras/caixotes
# espalhados pelas duas avenidas principais (zonas garantidamente abertas).
func _build_extra_cover() -> void:
	var count := int(theme.get("cover", 0))
	if count <= 0:
		return
	var accent: Color = theme.get("accent", C_ORANGE)
	var concrete := mat(C_PAVE.darkened(0.35), 0.95)
	for i in range(count):
		var pos: Vector3
		if rng.randf() < 0.55:
			pos = Vector3(rng.randf_range(-map_half + 10.0, map_half - 10.0), 0.0, rng.randf_range(27.0, 33.0))
		else:
			pos = Vector3(rng.randf_range(-20.5, -15.5), 0.0, rng.randf_range(-map_half + 10.0, 19.0))
		match i % 3:
			0:
				box(pos + Vector3(0, 0.6, 0), Vector3(4.0, 1.2, 0.9), concrete, true)
			1:
				crate(pos, 1.3)
			_:
				box(pos + Vector3(0, 0.9, 0), Vector3(1.0, 1.8, 1.0), mat(accent.darkened(0.15), 0.6), true)

# ==================================================
# DETALHES TÁTICOS / AMBIENTAÇÃO
# ==================================================

func _build_tactical_details() -> void:
	var accent: Color = theme.get("accent", C_ORANGE)
	var metal := mat(Color(0.12, 0.16, 0.19), 0.55)
	var trim := mat(accent, 0.55, 0.18)
	var concrete := mat(C_PAVE.darkened(0.18), 0.92)
	var glass := mat(Color(0.22, 0.48, 0.58), 0.22, 0.35)

	# Marcos de orientação e pequenos painéis luminosos nas entradas das rotas.
	for i in range(6):
		var z := -42.0 + float(i) * 16.0
		box(Vector3(-25.4, 1.15, z), Vector3(0.18, 2.3, 0.18), metal, false)
		box(Vector3(-25.28, 1.75, z), Vector3(0.08, 0.48, 0.34), trim, false)
		box(Vector3(-25.27, 1.12, z), Vector3(0.07, 0.08, 0.28), glass, false)

	# Caixas de utilidade e ventilação junto a paredes (sem colisões extras).
	for i in range(8):
		var side := -1.0 if i % 2 == 0 else 1.0
		var x := side * (38.0 + float(i % 3) * 5.0)
		var z := -48.0 + float(i) * 13.0
		box(Vector3(x, 0.65, z), Vector3(1.25, 1.3, 0.9), concrete, false)
		box(Vector3(x, 1.34, z), Vector3(1.30, 0.08, 0.94), trim, false)
		for vent in range(3):
			box(Vector3(x - 0.36 + float(vent) * 0.36, 0.70, z - 0.47),
				Vector3(0.035, 0.48, 0.025), metal, false)

	# Balizadores baixos nas esquinas e nas aproximações aos dois sites.
	for site_key in ["site_a", "site_b"]:
		var site: Vector3 = theme.get(site_key, Vector3.ZERO)
		for i in range(4):
			var ang := TAU * float(i) / 4.0 + PI * 0.25
			var p := site + Vector3(cos(ang) * 7.0, 0.0, sin(ang) * 7.0)
			cyl(p + Vector3(0, 0.42, 0), 0.12, 0.84, metal, false)
			cyl(p + Vector3(0, 0.78, 0), 0.13, 0.12, trim, false)

	# Faixas de tinta e numeração visual para leitura rápida das rotas.
	for i in range(5):
		var x := -9.0 + float(i) * 4.5
		box(Vector3(x, 0.065, 40.0), Vector3(2.2, 0.012, 0.12), trim, false)
	box(Vector3(-29.0, 0.065, 8.0), Vector3(0.12, 0.012, 5.0), trim, false)

# ==================================================
# PRÉDIOS DE FUNDO + PAREDES INVISÍVEIS
# ==================================================

func _build_border():
	var step := 24.0
	var n := int(ceil(map_half * 2.0 / step))
	var off := map_half + 12.0
	var dark := Color(0.2, 0.27, 0.33)
	var glass := Color(0.38, 0.58, 0.66)
	for i in range(n + 1):
		var t := -map_half + i * step
		for side in range(4):
			var p := Vector2.ZERO
			match side:
				0: p = Vector2(t, -off)
				1: p = Vector2(t, off)
				2: p = Vector2(-off, t)
				3: p = Vector2(off, t)
			# deixa o lado noroeste aberto para o mar
			if (side == 0 and t < -10.0) or (side == 2 and t < -10.0):
				continue
			building(p.x, p.y, 21.0, 18.0, rng.randi_range(8, 22), dark, glass, Color(0.55, 0.65, 0.7), Color(0.18, 0.2, 0.24), 0.0, false)

	# paredes invisíveis
	var e := map_half + 1.0
	invisible_wall(Vector3(0, 30, -e), Vector3(map_half * 2 + 6, 80, 2))
	invisible_wall(Vector3(0, 30, e), Vector3(map_half * 2 + 6, 80, 2))
	invisible_wall(Vector3(-e, 30, 0), Vector3(2, 80, map_half * 2 + 6))
	invisible_wall(Vector3(e, 30, 0), Vector3(2, 80, map_half * 2 + 6))

# ==================================================
# JOGADOR E ALVOS
# ==================================================

func _place_player():
	var existing := get_tree().get_nodes_in_group("player")
	if existing.size() > 0:
		var ep: Node3D = existing[0]
		ep.global_position = spawn_point
		if "spawn_position" in ep:
			ep.spawn_position = spawn_point
		_attach_weapons(ep)
		return
	if not spawn_player:
		return
	if not ResourceLoader.exists(player_script_path):
		push_warning("PearlMap: não encontrei o script do jogador em '%s'. Ajusta 'Player Script Path'." % player_script_path)
		return

	var p := CharacterBody3D.new()
	p.name = "Jett"
	var cs := CollisionShape3D.new()
	cs.name = "CollisionShape3D"
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	cs.shape = cap
	cs.position.y = 0.9
	p.add_child(cs)
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.position = Vector3(0, 1.6, 0)
	cam.current = true
	p.add_child(cam)
	p.set_script(load(player_script_path))
	p.position = spawn_point
	add_child(p)
	_attach_weapons(p)

func _attach_weapons(p: Node):
	if weapon_script_path == "" or p.has_node("WeaponManager"):
		return
	if not ResourceLoader.exists(weapon_script_path):
		push_warning("PearlMap: não encontrei o weapon manager em '%s'." % weapon_script_path)
		return
	var wm := Node.new()
	wm.name = "WeaponManager"
	wm.set_script(load(weapon_script_path))
	p.add_child(wm)

func _spawn_dummies():
	var spots := [
		Vector3(6, 0, -10), Vector3(-10, 0, 0), Vector3(20, 0, 20), Vector3(-44, 0, -10.5),
		Vector3(0, 0, 55), Vector3(16, 3.33, -29.5), Vector3(16, 6.53, -47), Vector3(52, 0, 30),
	]
	for i in range(spots.size()):
		var dmy := Dummy.new()
		dmy.name = "Bot%d" % (i + 1)
		add_child(dmy)
		dmy.position = spots[i]

# Alvo de treino: leva dano, morre e volta ao fim de 3 s
class Dummy extends StaticBody3D:
	var health := 100.0
	var max_health := 100.0

	func _ready():
		add_to_group("enemy")
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.4
		cap.height = 1.8
		cs.shape = cap
		cs.position.y = 0.9
		add_child(cs)

		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.95, 0.3, 0.35)
		m.emission_enabled = true
		m.emission = Color(1.0, 0.2, 0.25)
		m.emission_energy_multiplier = 0.5

		var body := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.38
		cm.height = 1.5
		body.mesh = cm
		body.material_override = m
		body.position.y = 0.75
		add_child(body)

		var head := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.22
		sm.height = 0.44
		head.mesh = sm
		head.material_override = m
		head.position.y = 1.65
		add_child(head)

	func take_damage(amount: float, _source = null) -> bool:
		if health <= 0.0:
			return false
		health -= amount
		if health <= 0.0:
			_die()
			return true
		return false

	func _die():
		visible = false
		set_deferred("collision_layer", 0)
		remove_from_group("enemy")
		await get_tree().create_timer(3.0).timeout
		health = max_health
		visible = true
		collision_layer = 1
		add_to_group("enemy")
