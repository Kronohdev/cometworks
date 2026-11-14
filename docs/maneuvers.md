# MARGIN — Mapa do sistema solar e manobras / Solar-system map & maneuver nodes

Parte do voo (`scenes/flight/flight.tscn`). **M** abre o mapa; clique na órbita prevista
para criar uma manobra (nó), arraste as alças para dar Δv, **B** acelera o tempo até a
queima e **Y** executa a manobra com o piloto automático.

Part of the flight scene. **M** opens the map; click the predicted orbit to add a maneuver
node, drag its handles to set the Δv, **B** warps to the burn and **Y** lets the autopilot
fly it.

## Controles / controls

| Tecla / key | Ação / action |
|---|---|
| M | mapa liga / desliga · map on / off |
| 1 / 2 / 3 | escala: órbita da nave · sistema (Terra–Lua) · sistema solar · scale presets |
| Tab / Shift+Tab | foco no próximo / anterior (nave, corpo atual, Sol, planetas, luas) · cycle focus |
| botão direito + arrastar · roda | girar · zoom logarítmico (0,4 km … 170 UA) · rotate · log zoom |
| clique esquerdo na trajetória | cria uma manobra naquele ponto (marcador "+") · add a node |
| clique num corpo | foco nesse corpo · focus a body |
| botão direito num corpo | define / limpa o alvo (aproximação, NA / ND) · set / clear target |
| arrastar alça do nó | Δv progrado / retrógrado, normal / antinormal, radial fora / dentro; quanto mais longe, mais rápido; **Shift** = fino · drag a handle (rate grows with distance, Shift = fine) |
| roda sobre uma alça | ±1 m/s (Shift ±0,1) · wheel over a handle |
| arrastar o centro do nó | move o nó ao longo da órbita (no tempo) · drag the node along its orbit |
| ✕ do nó · Delete · Shift+Delete | apaga a manobra · todas · delete the node · clear all |
| B | acelerar até a queima (para 20 s antes do início) · warp to the burn |
| Y | executar manobra (aponta e queima, metade antes / metade depois) · execute |
| , . | aceleração do tempo: 1×, 2×, 4× (física) ou 10× … 1 000 000× (trilhos) · time warp |

Painel **MANOBRA** (canto inferior direito, no mapa): Δv, tempo de queima (motor do estágio
que vai queimar, empuxo/Isp de vácuo e massa atual), tempo até o nó, campos numéricos
progrado / normal / radial (m/s), « ‹ › » (uma órbita / 30 s antes ou depois; Shift = 5 min),
órbita depois da queima (Ap / Pe), encontro (corpo, periapse e quando), **Acelerar até** e
**Executar**. Acima da navebola: contagem para a queima, Δv restante e duração; na
navebola, o marcador azul da manobra.

## Arquitetura / architecture

### Cônicas encadeadas / patched conics

- `src/flight/flight_solar.gd` (`FlightSolar`): todos os corpos de
  `data/solar_system.json` com GM, raio, esfera de influência e órbita circular em torno do
  pai. GM: valores padrão para Sol, Terra (= `FlightOrbit.MU`) e Lua; os outros
  `g · R²` dos dados. **SOI** `r = a (GM / GM_pai)^(2/5)` → Terra 924 650 km, Lua
  66 190 km, Marte 576 000 km, Júpiter 47,4 Gm. Posições: longitude média JPL J2000 +
  movimento médio até a época da missão (**2026-10-28**, dia 9797 de J2000; uma janela de
  transferência para Marte abre ~19 dias depois). Planetas em órbitas circulares nos seus
  planos inclinados reais; a eclíptica é colocada de modo que, no tempo 0, o Sol fique
  exatamente onde o céu do voo o desenha e a normal da eclíptica seja a mais próxima da
  normal da órbita de lançamento (uma órbita de estacionamento para leste já contém a
  velocidade orbital da Terra). A Lua orbita no plano de lançamento (como a Mun do KSP;
  a real tem 18–28° do equador) com a fase real (elongação ao Sol na época).
- `src/flight/flight_conic.gd` (`FlightConic`): uma cônica (elipse / hipérbole) em dupla
  precisão a partir de um estado: base perifocal, tempo de periapse, anomalias
  excêntrica / hiperbólica (Newton), estado em qualquer tempo, tempo até um raio / anomalia
  verdadeira. Órbitas radiais caem na propagação por variáveis universais.
- `src/flight/flight_trajectory.gd` (`FlightTrajectory.predict`): segue a cônica até o
  primeiro evento — **ESCAPE** (sai da SOI → continua em torno do pai), **ENCOUNTER**
  (entra na SOI de um filho), **IMPACT**, **NODE** (soma o Δv da manobra; dali em diante o
  plano é tracejado) ou **HORIZON** (uma volta). Busca de encontros: amostragem uniforme em
  anomalia excêntrica/hiperbólica, cada filho testado em cada amostra (entrada na SOI ou
  mínimo de distância refinado por seção áurea) e a fronteira achada por bissecção no
  tempo (< 1 cm). As amostras ficam guardadas para o mapa desenhar e escolher pontos sem
  recalcular. Custo medido: órbita baixa 1,4 ms, transferência lunar 2–3 ms, escape + um
  ano heliocêntrico 8,6 ms.
- **Cache**: `FlightWorld` só recalcula a previsão quando algo muda (edição de manobra,
  empuxo/arrasto — 5 Hz no mapa, 1 Hz fora —, troca de SOI, horizonte atingido) e com
  qualidade 0,4 enquanto um nó é arrastado. Nunca por quadro.
- **Voo**: `FlightBody` guarda posição/velocidade relativas ao corpo da SOI atual (com GM,
  raio, ar e "planeta de lançamento"); a cada passo de física `_check_soi` testa a saída da
  SOI e a entrada nas dos filhos e rebaseia o estado (contínuo em velocidade). Nos
  **trilhos** (10× … 1 000 000×) a nave segue exatamente as cônicas previstas, cruzando as
  SOIs nos tempos calculados; a aceleração para antes do ar / do chão, antes da próxima
  manobra e no alvo do "acelerar até". O céu sempre recebe a câmera relativa à Terra; Sol e
  Lua vêm da geometria real no tempo da missão (a Lua é desenhada maior que o real quando
  longe e no tamanho real ao chegar perto).

### Mapa / map

- Cena `scenes/flight/flight_map.tscn` (gerada por `src/flight/gen/make_flight_map.py`),
  script `src/flight/flight_map.gd`. **Espaço do mapa: 1 unidade = 1 km, escala real, com o
  foco (nave ou corpo) na origem**: tudo é calculado em dupla precisão relativo ao foco e
  só depois convertido, então a precisão vale em qualquer zoom; a câmera orbita a origem com
  zoom logarítmico e near/far acompanham a distância.
- Corpos: os planetas voxel do sistema solar (`assets/voxel/planets/*_lod0/1/2.glb`) com a
  mesma regra de LOD por `visibility_range` (lod0 até 14 r, lod1 até 46 r, lod2 até 400 r ≈
  2,5 px); longe, só o ícone 2D. Os modelos são escalados para que o relevo voxel exagerado
  fique dentro do raio real (uma órbita de 200 km continua visível). Sol com halo de tamanho
  mínimo na tela (`shaders/flight_map_glow.gdshader`), atmosferas, nuvens e anéis.
- Linhas: órbitas, trajetórias por SOI (Terra azul, Lua verde-água, Sol violeta, Marte
  rosa) e anéis de SOI são malhas-faixa com largura constante em pixels
  (`shaders/flight_map_line.gdshader`, `src/flight/flight_map_lines.gd`): antisserrilhadas,
  tracejadas para o plano depois de uma manobra, com teste de profundidade contra os
  planetas. As órbitas usam um círculo unitário compartilhado; as trajetórias são
  reconstruídas só quando a previsão muda; por quadro só mudam transformações e alguns
  uniforms de instância. Com zoom muito próximo, uma linha fina em volta da nave substitui a
  amostrada (64 pontos).
- Convenção KSP: um segmento em torno de um corpo do referencial da câmera é desenhado em
  volta da posição atual do corpo; um segmento de encontro é desenhado em volta de um
  "fantasma" do corpo no instante da periapse (marcado no mapa).
- Marcadores: Ap / Pe com tempo, NA / ND em relação ao plano do alvo, entrada / saída de
  SOI com tempo, impacto, periapse no encontro, aproximação máxima do alvo, nós. Rótulos e
  marcadores somem quando a órbita é pequena demais na tela, ficam translúcidos atrás de um
  planeta e não se sobrepõem.
- Céu do mapa: `shaders/flight_map_sky.gdshader` (Via Láctea na passada de 1/4 de
  resolução, estrelas na resolução total).

### Manobras / maneuver nodes

- `FlightManeuverNode`: tempo absoluto + Δv no referencial da órbita (x progrado, y normal
  = r × v, z radial para fora = progrado × normal). O previsor preenche corpo, estado e Δv
  no espaço. `FlightManeuvers`: lista ordenada, regras de edição (não vai para o passado
  nem pula vizinhos), ajudantes de escolha de ponto.
- Δv restante: o empuxo perto do nó é acumulado em `node.burned` (vetor inercial, como no
  KSP); o marcador da navebola e a contagem usam o restante.
- `FlightNodeExecutor` (Y): aponta para o Δv restante, liga na hora `t_nó − t_queima/2`,
  diminui o acelerador no último 1,5 s, troca de estágio se esvaziar. Queimas que mudam a
  energia orbital terminam quando a energia específica atinge a planejada: uma queima de
  7 min não é um impulso (a gravidade gira a velocidade durante a queima) e o vetor exato
  deixaria a apoapse ~110 000 km curta numa injeção translunar; pela energia ela fica a
  0,1 % do plano.

- Gizmo do nó no mapa: centro na cor de manobra (laranja, que nenhuma trajetória de SOI
  usa), hastes coloridas até cada alça, seta laranja na direção do Δv, alça sob o mouse
  maior e com o componente na etiqueta. O trajeto depois do nó fica laranja tracejado
  enquanto segue em volta do corpo do nó; ao entrar em outro corpo volta à cor dele.

### Inserção orbital automática / orbit insertion

- Painel "Inserção orbital" no mapa (`flight_capture_panel.tscn`), acima do painel de
  manobra: aparece o corpo do encontro do plano atual; escolha periapse, apoapse (ou
  órbita circular) e, opcionalmente, a inclinação (0° prograda, 90° polar, 180°
  retrógrada, em relação ao plano da órbita do próprio corpo; desligada mantém o plano da
  chegada). "Planejar inserção" adiciona até dois nós (marcados `auto_capture`; planejar
  de novo os substitui):
  1. correção no meio do caminho (15 % do trajeto até o encontro), que mira a chegada;
  2. queima de captura na periapse, retrógrada até a apoapse escolhida.
- `FlightCapture`: mira pelo plano B da chegada (plano pela Lua / planeta perpendicular à
  velocidade de entrada S): |B| fixa a periapse (conservação de energia e momento a partir
  da entrada na SOI), a direção de B fixa o plano (h = B × S). O Δv normal / radial da
  correção sai de iterações de Newton no erro 2-D de B, cada avaliação uma previsão
  completa de cônicas (~30 ms no total para a Lua). A captura usa vis-viva na periapse.

## Testes / tests

```bash
godot --headless --path . --script res://tests/test_flight_conics.gd   # cônicas, SOI, nós
godot --headless --path . --script res://tests/test_flight_soi.gd      # SOI no voo, trilhos, executor
godot --headless --path . --script res://tests/test_flight_capture.gd  # inserção orbital (Lua)
godot --path . --resolution 1600x900 --script res://tests/screenshot_flight_map.gd -- <pasta>
godot --path . --resolution 1600x900 --script res://tests/screenshot_flight_perf.gd -- <pasta> [variantes]
```

## Imagens / screenshots

`docs/screenshots/flight_map_01_vessel.png` (órbita da nave), `flight_map_02_earth_moon.png`
(sistema Terra–Lua), `flight_map_03_node_moon.png` (manobra translunar com o trajeto
tracejado e o encontro com a Lua), `flight_map_04_node_close.png` (gizmo de perto),
`flight_map_05_solar.png` (sistema solar), `flight_map_06_escape.png` (escape para o Sol),
`flight_map_07_moon.png` (depois de executar a manobra, dentro da SOI da Lua),
`flight_11_navball_node.png` (marcador da manobra na navebola e contagem),
`flight_12_near_moon.png` (perto da periapse lunar).

## Limitações / limitations

- Planetas em órbitas circulares (planos inclinados reais); a Lua no plano de lançamento;
  sem precessão nem perturbações de terceiros corpos (cônicas encadeadas).
- Só a Terra tem atmosfera, céu e superfície detalhados no voo; perto da Lua ela aparece
  como disco texturizado no céu, sem terreno (dá para "pousar" num chão liso a < 8 m/s).
- A busca de encontros cobre uma volta (ou até a próxima manobra); encontros em voltas
  posteriores aparecem quando a nave chega lá (a previsão é refeita no horizonte).
- O Δv no espaço de uma manobra fica congelado quando a queima começa; queimas longas que
  não mudam a energia (troca de plano) terminam pelo vetor e acumulam o erro de não ser
  impulsiva.
- Sem rotação da Terra (o pad não ganha ~400 m/s), como antes.
