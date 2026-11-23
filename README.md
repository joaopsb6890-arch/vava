# VAVA — Protocolo Tático

Jogo de tiro tático em primeira pessoa inspirado em **Valorant**, feito com arquitetura híbrida **GDScript + C#** para **Godot 4.7 .NET**.

Não existe uma única imagem de interface: lobby, cards de agente, ícones de habilidades, minimapa,
radar, HUD, mira, loja, modelos 3D das armas, corpos dos NPCs e os mapas são **construídos por código**
em tempo de execução. Os únicos ficheiros externos são os FBX/texturas opcionais em `source/` e `textures/`.

> Projeto de fã, sem qualquer afiliação com a Riot Games. Nenhum asset de Valorant é usado.
> Os nomes de agentes/habilidades são referências de inspiração.

---

## O que o jogo tem

### Lobby
- Escolha de **agente** (6), **mapa** (3), **modo** (Spike Rush / Deathmatch) e **dificuldade** (Fácil / Normal / Difícil).
- Painel de detalhe do agente com papel, descrição, estatísticas e as 4 habilidades.
- Ecrã de ajuda com objetivo, controlos e explicação dos kits.
- Tudo navegável com o rato; `ENTER` inicia a partida.

### Agentes (4 habilidades cada: C, Q, E e X)
| Agente | Papel | Kit |
|---|---|---|
| **JETT** | Duelista | Updraft (impulso) · Tailwind (dash) · Cloudburst (fumo) · Blade Storm (5 lâminas) |
| **PHOENIX** | Duelista | Curveball (flash) · Fireball (explosão) · Blaze (parede de fogo) · Sol (impacto) |
| **SOVA** | Iniciador | Shock Dart (explosão) · Recon Bolt (marca inimigos) · Owl Drone (flash) · Fúria do Caçador |
| **SAGE** | Sentinela | Orbe de Cura (cura área) · Muro de Gelo (parede sólida) · Orbe de Vigilância (marca) · Julgamento |
| **RAZE** | Duelista | Carga de Impulso · Granada · Propulsão (dash) · Foguete |
| **OMEN** | Controlador | Manto Sombrio (fumo) · Paranoia (flash) · Passos Sombrios (dash) · Salto Sombrio |

Q/E/C recarregam com o tempo (com cargas); a **X (ultimate)** carrega com eliminações (7 pontos, 6 em alguns agentes).

### Mapas (gerados por código)
| Mapa | Tema | Dimensão / cobertura |
|---|---|---|
| **PEARL** | Cidade submersa (dia, tons pastel) | 140 × 140 m, 8 coberturas extra |
| **ASCENT** | Vale alpino (luz fria, brancos) | 152 × 152 m, 12 coberturas extra |
| **BIND** | Deserto ao pôr do sol (quente) | 132 × 132 m, 16 coberturas extra |

Cada mapa tem paleta de céu/névoa/sol, dimensão, seed dos props e cobertura próprios, mais
**site A e site B** com anel, feixe e marcador 3D.

### NPCs (bots)
- Aliados e inimigos com **percepção por linha de visão** (raycast, não veem através de paredes).
- Rajadas com intervalo, recuo, *strafe*, recuo para trás a curta distância e **desvio de obstáculos**.
- Reagem a **flash** (ficam cegos e param de acertar) e a **recon** (marcador vermelho em cima da cabeça).
- Barra de vida, nome do bot + agente, cores do agente, tracer e flash de cano.
- Dificuldade altera precisão (55/76/92 %), tempo de reação (0,75/0,42/0,22 s), dano e velocidade.

### Partida
- **Spike Rush**: tu + 2 aliados (ataque) contra 3 defensores. Chega a um site, segura `F` 4 s para
  plantar, defende 45 s; a defesa tenta desarmar (6 s). Primeira equipa a **5 rondas** ganha.
- **Deathmatch**: respawns infinitos, primeira equipa a **20 eliminações**.
- **Fase de compra** (9 s) com loja (`B`), arsenal alargado, créditos por ronda e por kill. No modo competitivo o jogador começa sem escudo e pode comprar 50 pontos de armadura.
- Cronómetro, placar de equipas, estado do spike, barra de plantação/desarme, killfeed, placar no `Tab`
  e ecrã final com resultado.

### Arsenal
| Arma | Tipo | Preço | Dano (cabeça/corpo/pernas) |
|---|---|---|---|
| Classic | pistola | 0 | 78 / 26 / 22 |
| Shorty | escopeta | 300 | 24 / 12 / 10 por projétil |
| Frenzy | pistola automática | 450 | 78 / 26 / 22 |
| Ghost | pistola | 500 | 105 / 30 / 25 |
| Sheriff | pistola | 800 | 159 / 55 / 46 |
| Stinger | SMG | 1100 | 67 / 27 / 23 |
| Bucky | escopeta | 850 | 34 / 17 / 14 por projétil |
| Judge | escopeta automática | 1850 | 34 / 17 / 14 por projétil |
| Ares | metralhadora | 1600 | 72 / 30 / 25 |
| Bulldog | rifle | 2100 | 115 / 35 / 30 |
| Guardian | rifle semiautomático | 2250 | 195 / 65 / 49 | 159 / 55 / 46 |
| Spectre | SMG | 1600 | 78 / 26 / 22 |
| Vandal | rifle | 2900 | 160 / 40 / 34 |
| Phantom | rifle | 2900 | 156 / 39 / 33 |
| Odin | metralhadora | 3200 | 95 / 38 / 32 |
| Operator | sniper | 4700 | 255 / 150 / 120 |
| Faca | corpo a corpo | — | 50 / 150 (forte) |

---

## VAVA 2.0 — melhorias em desenvolvimento

Esta versão inclui uma primeira passagem de melhorias sobre o projeto existente:

- Modelos procedurais dos bots com mais equipamento tático e detalhes nas armas.
- Modelos provisórios das armas em primeira pessoa com mais componentes visuais.
- Movimento de câmara com inércia subtil para dar mais sensação de peso ao FPS.
- Mapas com novos detalhes de rota, caixas técnicas, sinalização e marcadores nos sites.
- HUD com identificação própria para o registo de combate.
- Ajustes de objetivos dos bots no início da fase de combate.

Estas alterações estão numa branch de desenvolvimento e precisam de ser testadas no Godot 4.7 antes de serem integradas na versão principal.

## Arquitetura híbrida (GDScript + C#)

O projeto começa a usar C# de forma gradual, sem converter o jogo inteiro:

- **GDScript:** movimento do jogador, câmara, habilidades, armas, modelos, HUD, mapas e ciclo principal da partida.
- **C#:** componentes de decisão e lógica intensiva que beneficiem de uma implementação compilada.
- **Integração inicial:** `scripts/csharp/AI/BotBrain.cs` calcula a pontuação dos alvos; `bot.gd` continua responsável pela perceção (raycast), movimento, disparos e apresentação.
- **Fallback:** se o componente C# ainda não estiver carregado, o bot usa a pontuação simples em GDScript.

### Requisitos para compilar C#

1. Usar a edição **Godot 4.7 .NET** (não a edição standard).
2. Instalar o **.NET SDK 8.0 ou superior**.
3. Abrir o projeto e compilar a solução C# pelo editor Godot antes de testar a IA.
4. Confirmar que não existem erros no painel **Output**.

O projeto C# está configurado em `vava.csproj`. A IA híbrida já usa C# para pontuar alvos por distância, estabilidade, marcação e vida restante, além de ajustar o tempo de reação. A perceção, a navegação, a física e a apresentação continuam em GDScript.

## Como correr

1. Abre o **Godot 4.7**.
2. `Import` → escolhe o `project.godot` desta pasta.
3. `F5` — a cena principal é o **lobby**.

Os modelos FBX em `source/` são **opcionais**: se não forem importados (ou se o FBX falhar), cada arma
usa um modelo 3D gerado por código, e o jogo continua a funcionar.

Cena extra: `node_3d.tscn` abre o mapa com alvos de treino (sem bots), útil para testar movimentação e armas.

---

## Controlos

| Tecla | Ação |
|---|---|
| `WASD` | mover |
| `Shift` | andar (silencioso) |
| `Ctrl` | agachar |
| `Espaço` | saltar — segura no ar para **drift** |
| Rato | mirar |
| `Esq` / `Dir` | disparar / alt (faca: golpe forte) |
| `R` | recarregar |
| `1` / `2` / `3` | primária / secundária / faca (roda do rato também troca) |
| `Q` `E` `C` | habilidades |
| `X` | ultimate |
| `B` | loja (só na fase de compra) |
| `F` | plantar o spike (dentro do site) |
| `Tab` | placar |
| `F1` | mostrar/esconder ajuda |
| `Esc` | libertar o rato |

---

## Estrutura

| Ficheiro | Função |
|---|---|
| `game_state.gd` | autoload `GameState`: elenco de agentes, catálogo de mapas, escolhas e resultados |
| `lobby.gd` / `lobby.tscn` | ecrã inicial (agente, mapa, modo, dificuldade) |
| `match.gd` / `match.tscn` | gestor da partida: spawns, rondas, spike, loja, placar, fim |
| `match_hud.gd` | HUD da partida: cronómetro, placar, barras, loja, killfeed, Tab, ecrã final |
| `bot.gd` | NPC de combate (IA, perceção, tiro, flash/mark, reset de ronda) |
| `scripts/csharp/AI/BotBrain.cs` | pontuação C# dos alvos dos bots |
| `vava.csproj` | configuração do projeto Godot .NET |
| `player.gd` | controlador FPS (movimento, câmara, dano) + sistema de habilidades dos 6 agentes |
| `weapon_manager.gd` | arsenal, viewmodels, recuo, recarga, dano por zona, munição |
| `map.gd` | gerador do mapa (edifícios, ruas, parque, viaduto, cobertura, sites) |
| `node_3d.tscn` | cena de treino livre (mapa + dummies) |

---

## Limitações conhecidas
- É um jogo **offline** contra bots (sem rede/multiplayer).
- Os 3 mapas usam o mesmo gerador de layout; mudam paleta, dimensão, seed e cobertura.
- Os bots navegam por *steering* + desvio de obstáculos (não há navmesh gerada).
- Os kits são uma homenagem: as mecânicas são implementadas de raiz e não são 1:1 com o Valorant.
