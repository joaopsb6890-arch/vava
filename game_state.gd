extends Node

# ==================================================
# VAVA - ESTADO GLOBAL (autoload "GameState")
# --------------------------------------------------
# Guarda o que o jogador escolheu no lobby (agente, mapa, modo, dificuldade)
# e o elenco de agentes / catálogo de mapas que o resto do jogo lê.
# Tudo definido por código: nada aqui depende de ficheiros externos.
# ==================================================

# ---------- SLOTS DE HABILIDADE ----------
# C = habilidade barata, Q = habilidade secundária, E = assinatura, X = ultimate.
const SLOTS := ["c", "q", "e", "x"]
const SLOT_KEYS := {"c": "C", "q": "Q", "e": "E", "x": "X"}
const ULT_TYPES := ["knives", "strike"]

# ---------- AGENTES ----------
# type define a implementação usada pelo player.gd:
#   impulse  -> salto vertical
#   dash     -> avanço rápido
#   smoke    -> nuvem de fumo arremessada
#   flash    -> cega inimigos à frente
#   shock    -> explosão em área na mira
#   heal     -> cura própria e aliados próximos
#   mark     -> revela inimigos próximos
#   wall     -> parede sólida temporária
#   knives   -> ultimate de lâminas (Jett)
#   strike   -> ultimate de impacto em área na mira
var AGENTS: Array = [
	{
		"id": "jett", "name": "JETT", "role": "Duelista", "country": "Coreia do Sul",
		"color": Color(0.44, 0.90, 1.00), "accent": Color(0.86, 0.97, 1.00),
		"hp": 100, "armor": 50, "speed": 7.0, "ult_cost": 7,
		"desc": "Vento em pessoa. Entra primeiro, cria espaço com mobilidade e sai antes de ser apanhada.",
		"abilities": {
			"q": {"type": "impulse", "name": "UPDRAFT", "desc": "Impulso vertical instantâneo.", "charges": 2, "recharge": 9.0, "force": 15.0},
			"e": {"type": "dash", "name": "TAILWIND", "desc": "Avança rapidamente na direção do movimento.", "charges": 1, "recharge": 8.0, "speed": 40.0, "duration": 0.2},
			"c": {"type": "smoke", "name": "CLOUDBURST", "desc": "Lança uma nuvem de fumo que corta a visão.", "charges": 2, "recharge": 12.0, "radius": 3.6, "duration": 4.5},
			"x": {"type": "knives", "name": "BLADE STORM", "desc": "5 lâminas letais. Esq. lança uma, Dir. lança todas.", "ult": true},
		},
	},
	{
		"id": "phoenix", "name": "PHOENIX", "role": "Duelista", "country": "Reino Unido",
		"color": Color(1.00, 0.55, 0.22), "accent": Color(1.00, 0.85, 0.45),
		"hp": 100, "armor": 50, "speed": 6.9, "ult_cost": 6,
		"desc": "Fogo e pressão. Cega, queima e bloqueia a passagem enquanto avança para o objetivo.",
		"abilities": {
			"q": {"type": "flash", "name": "CURVEBALL", "desc": "Cega os inimigos que estiverem à frente.", "charges": 2, "recharge": 10.0, "radius": 24.0, "blind": 2.4},
			"e": {"type": "shock", "name": "FIREBALL", "desc": "Bola de fogo que explode e causa dano em área.", "charges": 1, "recharge": 12.0, "damage": 60.0, "radius": 4.0},
			"c": {"type": "wall", "name": "BLAZE", "desc": "Parede de fogo que bloqueia a passagem.", "charges": 1, "recharge": 20.0, "duration": 22.0},
			"x": {"type": "strike", "name": "SOL", "desc": "Chama um impacto solar devastador na mira.", "ult": true, "damage": 150.0, "radius": 6.5},
		},
	},
	{
		"id": "sova", "name": "SOVA", "role": "Iniciador", "country": "Rússia",
		"color": Color(0.36, 0.66, 1.00), "accent": Color(0.72, 0.90, 1.00),
		"hp": 100, "armor": 50, "speed": 6.7, "ult_cost": 7,
		"desc": "Olhos da equipa. Revela posições, abre caminho com dardos e fecha rondas com fogo orbital.",
		"abilities": {
			"q": {"type": "shock", "name": "SHOCK DART", "desc": "Dardo explosivo de longo alcance.", "charges": 2, "recharge": 10.0, "damage": 45.0, "radius": 3.0},
			"e": {"type": "mark", "name": "RECON BOLT", "desc": "Revela inimigos próximos durante 6 segundos.", "charges": 1, "recharge": 14.0, "radius": 48.0, "duration": 6.0},
			"c": {"type": "flash", "name": "OWL DRONE", "desc": "Pulso ótico que cega os inimigos à frente.", "charges": 1, "recharge": 14.0, "radius": 26.0, "blind": 2.0},
			"x": {"type": "strike", "name": "FÚRIA DO CAÇADOR", "desc": "Impacto orbital na mira.", "ult": true, "damage": 140.0, "radius": 6.0},
		},
	},
	{
		"id": "sage", "name": "SAGE", "role": "Sentinela", "country": "China",
		"color": Color(0.52, 0.95, 0.76), "accent": Color(0.86, 1.00, 0.94),
		"hp": 100, "armor": 50, "speed": 6.6, "ult_cost": 6,
		"desc": "A âncora da equipa. Cura, levanta paredes e mantém o site fechado.",
		"abilities": {
			"q": {"type": "heal", "name": "ORBE DE CURA", "desc": "Cura-te e cura aliados próximos.", "charges": 1, "recharge": 16.0, "heal": 60.0, "radius": 7.0},
			"e": {"type": "wall", "name": "MURO DE GELO", "desc": "Cria uma parede sólida à frente.", "charges": 1, "recharge": 18.0, "duration": 26.0},
			"c": {"type": "mark", "name": "ORBE DE VIGILÂNCIA", "desc": "Marca inimigos próximos.", "charges": 2, "recharge": 14.0, "radius": 40.0, "duration": 5.0},
			"x": {"type": "strike", "name": "JULGAMENTO", "desc": "Esfera de gelo colossal na mira.", "ult": true, "damage": 130.0, "radius": 6.0},
		},
	},
	{
		"id": "raze", "name": "RAZE", "role": "Duelista", "country": "Brasil",
		"color": Color(1.00, 0.70, 0.22), "accent": Color(1.00, 0.92, 0.55),
		"hp": 100, "armor": 50, "speed": 6.9, "ult_cost": 7,
		"desc": "Explosivos em tudo. Limpa cantos fechados e entra no site com um foguete na mão.",
		"abilities": {
			"q": {"type": "impulse", "name": "CARGA DE IMPULSO", "desc": "Propulsão vertical para ganhar altura.", "charges": 2, "recharge": 9.0, "force": 16.0},
			"e": {"type": "shock", "name": "GRANADA", "desc": "Granada que explode e causa dano em área.", "charges": 2, "recharge": 11.0, "damage": 70.0, "radius": 4.5},
			"c": {"type": "dash", "name": "PROPULSÃO", "desc": "Avanço rápido para entrar em combate.", "charges": 1, "recharge": 9.0, "speed": 36.0, "duration": 0.22},
			"x": {"type": "strike", "name": "FOGUETE", "desc": "Foguete devastador na mira.", "ult": true, "damage": 160.0, "radius": 7.0},
		},
	},
	{
		"id": "omen", "name": "OMEN", "role": "Controlador", "country": "Desconhecido",
		"color": Color(0.58, 0.44, 0.95), "accent": Color(0.88, 0.78, 1.00),
		"hp": 100, "armor": 50, "speed": 6.8, "ult_cost": 7,
		"desc": "Sombras e medo. Corta a visão do inimigo e aparece onde ninguém espera.",
		"abilities": {
			"q": {"type": "smoke", "name": "MANTO SOMBRIO", "desc": "Nuvem de escuridão que bloqueia a visão.", "charges": 2, "recharge": 12.0, "radius": 3.8, "duration": 5.0},
			"e": {"type": "flash", "name": "PARANOIA", "desc": "Cega quem estiver à frente.", "charges": 2, "recharge": 11.0, "radius": 24.0, "blind": 2.2},
			"c": {"type": "dash", "name": "PASSOS SOMBRIOS", "desc": "Desloca-te rapidamente na direção da mira.", "charges": 1, "recharge": 10.0, "speed": 38.0, "duration": 0.2},
			"x": {"type": "strike", "name": "SALTO SOMBRIO", "desc": "Impacto sombrio em área na mira.", "ult": true, "damage": 150.0, "radius": 6.5},
		},
	},
]

# ---------- MAPAS ----------
# Todos gerados por código a partir do mesmo gerador (map.gd), com paleta,
# dimensão, seed e cobertura próprias.
var MAPS: Array = [
	{
		"id": "pearl", "name": "PEARL", "subtitle": "Cidade submersa", "half": 70.0, "seed": 7, "cover": 8,
		"sky_top": Color(0.28, 0.45, 0.52), "sky_horizon": Color(0.58, 0.74, 0.75),
		"fog": Color(0.50, 0.68, 0.70), "sun": Color(1.00, 0.95, 0.85),
		"ground": Color(0.50, 0.50, 0.48), "pave": Color(0.64, 0.62, 0.58),
		"road": Color(0.15, 0.17, 0.19), "grass": Color(0.36, 0.62, 0.30),
		"accent": Color(0.86, 0.55, 0.52),
		"attack_spawn": Vector3(0, 0.35, 58), "defense_spawn": Vector3(-40, 0.35, 28),
		"site_a": Vector3(30, 0.35, 30), "site_b": Vector3(-18, 0.35, 4),
	},
	{
		"id": "ascent", "name": "ASCENT", "subtitle": "Vale alpino", "half": 76.0, "seed": 21, "cover": 12,
		"sky_top": Color(0.30, 0.55, 0.82), "sky_horizon": Color(0.76, 0.87, 0.95),
		"fog": Color(0.80, 0.88, 0.95), "sun": Color(1.00, 0.98, 0.93),
		"ground": Color(0.62, 0.62, 0.60), "pave": Color(0.79, 0.78, 0.73),
		"road": Color(0.28, 0.30, 0.34), "grass": Color(0.45, 0.60, 0.38),
		"accent": Color(0.95, 0.76, 0.30),
		"attack_spawn": Vector3(0, 0.35, 64), "defense_spawn": Vector3(44, 0.35, 27),
		"site_a": Vector3(14, 0.35, 31), "site_b": Vector3(-18, 0.35, 10),
	},
	{
		"id": "bind", "name": "BIND", "subtitle": "Deserto ao pôr do sol", "half": 66.0, "seed": 44, "cover": 16,
		"sky_top": Color(0.45, 0.25, 0.35), "sky_horizon": Color(0.98, 0.60, 0.35),
		"fog": Color(0.90, 0.60, 0.42), "sun": Color(1.00, 0.72, 0.45),
		"ground": Color(0.72, 0.60, 0.45), "pave": Color(0.80, 0.70, 0.55),
		"road": Color(0.30, 0.25, 0.22), "grass": Color(0.60, 0.55, 0.30),
		"accent": Color(0.95, 0.45, 0.20),
		"attack_spawn": Vector3(-24, 0.35, 54), "defense_spawn": Vector3(0, 0.35, -52),
		"site_a": Vector3(24, 0.35, 30), "site_b": Vector3(-18, 0.35, 2),
	},
]

# ---------- ESCOLHAS ATUAIS ----------
var agent_id := "jett"
var map_id := "pearl"
var mode := "spike"          # "spike" | "deathmatch"
var difficulty := 1          # 0 fácil | 1 normal | 2 difícil
var bot_allies := 2
var bot_enemies := 3
var rounds_to_win := 5
var deathmatch_kills := 20
var credits_start := 3200

# Resultado da última partida (preenchido pelo match.gd)
var last_result: Dictionary = {}

# ==================================================
# CONSULTAS
# ==================================================

func get_agent(id: String) -> Dictionary:
	for a in AGENTS:
		if a.id == id:
			return a
	return AGENTS[0]

func get_map(id: String) -> Dictionary:
	for m in MAPS:
		if m.id == id:
			return m
	return MAPS[0]

func agent_display(id: String) -> String:
	return str(get_agent(id).name)

func random_agent_id(exclude: Array = []) -> String:
	var pool: Array = []
	for a in AGENTS:
		if not exclude.has(a.id):
			pool.append(a.id)
	if pool.is_empty():
		pool.append(AGENTS[0].id)
	return pool[randi() % pool.size()]

func mode_name(id: String) -> String:
	return "SPIKE RUSH" if id == "spike" else "DEATHMATCH"

func difficulty_name(d: int) -> String:
	return ["FÁCIL", "NORMAL", "DIFÍCIL"][clampi(d, 0, 2)]

## Multiplicadores usados pelo bot.gd
func difficulty_profile(d: int) -> Dictionary:
	match clampi(d, 0, 2):
		0:
			return {"accuracy": 0.55, "reaction": 0.75, "damage": 0.65, "speed": 3.9, "hp": 85.0}
		2:
			return {"accuracy": 0.92, "reaction": 0.22, "damage": 1.15, "speed": 5.4, "hp": 100.0}
	return {"accuracy": 0.76, "reaction": 0.42, "damage": 0.9, "speed": 4.7, "hp": 100.0}

func team_color(team: String) -> Color:
	return Color(1.0, 0.42, 0.35) if team == "defense" else Color(0.40, 0.88, 1.0)

func team_label(team: String) -> String:
	return "DEFESA" if team == "defense" else "ATAQUE"
