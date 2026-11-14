# MARGIN — Lançamento e voo de teste / Launch & flight test

Cena / scene: `scenes/flight/flight.tscn` (controlador `src/flight/flight_world.gd`).
No hangar, o botão **Lançar / Launch** (barra superior) guarda o foguete em
`FlightSession` (`src/flight/flight_session.gd`, classe estática) e abre o voo. No menu de
pausa (Esc) há **Voltar ao lançamento** e **Voltar ao hangar** (o hangar recarrega o mesmo
foguete).

In the hangar, **Launch** (top bar) stores the vessel in `FlightSession` and opens the
flight. The pause menu (Esc) offers **Revert to launch** and **Revert to hangar** (the
hangar reloads the same vessel).

## Controles / controls

| Tecla / key | Ação / action |
|---|---|
| Espaço / Space | próximo estágio (ignição, separação) · next stage |
| W / S | arfagem (nariz para baixo / cima) · pitch down / up |
| A / D | guinada · yaw |
| Q / E | rolagem · roll |
| Shift / Ctrl | acelerar / desacelerar · throttle up / down |
| Z / X | aceleração total / cortar · full / cut |
| T | SAS: manter atitude · hold attitude |
| G / H | manter progrado / retrógrado · hold prograde / retrograde |
| P | subida automática até órbita de 200 km · auto-ascent |
| M | mapa do sistema solar e manobras (ver `docs/maneuvers.md`) · solar-system map & maneuver nodes |
| B / Y | acelerar até a manobra / executar a manobra · warp to node / execute node |
| , / . | aceleração do tempo: 1×, 2×, 4×, 10×, 50×, 100×, 1000× … 1 000 000× · time warp |
| Botão direito + arrastar, roda | girar câmera, zoom · orbit camera, zoom |
| Esc / Backspace | menu de pausa · pause menu |
| F1 / F2 | ajuda / esconder o HUD · help / hide HUD |
| Enter | relatório (depois da órbita) · report after orbit |

## Arquitetura / architecture

- **Estado em dupla precisão.** `FlightBody` guarda posição e velocidade como floats do
  GDScript (64 bits) num referencial inercial centrado na Terra (PCI, +Y = vertical da
  plataforma). `Vector3` (32 bits) só é usado para direções, rotação e forças.
- **Integrador.** Passo fixo de 0,02 s (50 Hz). Translação por *leapfrog* (kick-drift-kick,
  simplético) para a gravidade, empuxo/arrasto/contato como impulso por passo. Rotação:
  equações de Euler com inércia diagonal, quatérnio integrado com a rotação exata de ω·dt.
  Renderização interpolada entre os dois últimos passos.
- **Origem flutuante.** A cada quadro a origem do render = posição interpolada do foguete;
  base de lançamento, fumaça, destroços e mapa são colocados em (PCI − origem). Padrões
  de chão que usavam coordenadas de mundo foram copiados para `shaders/flight_site_*`
  com um uniform `site_origin`, para não "escorregarem".
- **Modelo físico** (`FlightVessel`): gravidade μ/r² (μ = 3,986004418e14, R = 6371 km, sem
  rotação da Terra); atmosfera exponencial ρ0 = 1,225 kg/m³, H = 8,5 km, topo em 140 km;
  arrasto axial pela área frontal (união dos discos das peças) com subida transônica do Cd;
  força normal aplicada no centro de pressão (a estimativa de CoL do hangar, aletas pesam
  4×) → torque estabilizante/desestabilizante; amortecimento aerodinâmico; empuxo com
  vazão constante e Isp interpolado entre nível do mar e vácuo pela pressão; tanques
  drenados por *pool* (mesma regra do `VesselMath`); massa, CoM e inércia atualizados;
  sólidos queimam até o fim sem acelerador; `throttle_min`, número de reignições; torque de
  controle = gimbal (`gimbal_deg` × empuxo × braço) + rodas de reação; SAS PD limitado pela
  aceleração angular disponível. Contato com o solo: impacto > 8 m/s destrói.
  Limites estruturais: q·sen(α) > 9 kPa, q > 90 kPa ou > 16 g.
- **Estágios.** `FlightStaging` faz a mesma divisão da árvore que
  `Vessel.compute_stages()` (testado), mas guardando as instâncias. Espaço: ignição do
  estágio 1 e soltura das garras; depois, separa o estágio gasto (sub-árvore do desacoplador
  vira um corpo separado com impulso de ejeção `ejection_impulse_kns`), acende o próximo;
  boosters caem sozinhos quando esvaziam; a carenagem é ejetada na ignição do estágio 2
  (a mesma hipótese do hangar). O Δv restante do HUD é calculado com o próprio
  `VesselMath.analyze` usando o propelente que sobrou.
- **Cônicas encadeadas e manobras** (`docs/maneuvers.md`). O estado da nave é relativo ao
  corpo da esfera de influência atual (Terra no lançamento, Lua, Sol, planetas;
  `FlightSolar` a partir de `data/solar_system.json`); a física troca de SOI a cada passo e
  os trilhos seguem as cônicas previstas (`FlightTrajectory`), cruzando SOIs nos tempos
  exatos. Manobras KSP (`FlightManeuverNode`, `FlightManeuvers`) com gizmo no mapa, painel
  numérico, marcador na navebola, contagem, "acelerar até" e piloto de execução.
- **Aceleração do tempo.** Um só seletor: 1×, 2×, 4×, 10×, 50×, 100×, 1000× … 1 000 000×.
  A partir de 10×, a nave vai "nos trilhos" (cônicas exatas, `FlightConic`) sempre que
  pode: fora do ar (Terra: acima de 140 km) ou acima de uma margem do chão em corpos sem
  ar, motores desligados, subida automática e queima do executor fora de ação. Quando não
  pode, a física roda no mesmo nível limitado a 100× (o mesmo passo fixo, só mais passos
  por quadro, com orçamento de 10 ms por quadro) e o topo mostra "100×/1000×" em amarelo
  com o motivo num aviso; ao voltar a planar no espaço, os trilhos assumem sozinhos. Para
  antes do ar / do chão, antes da próxima manobra e no alvo do "acelerar até". O executor
  de manobra desiste (com aviso) quando nenhum estágio tem mais propelente.
- **Céu e planeta** (`shaders/flight_sky.gdshader`, um *sky shader*): a Terra é uma esfera
  analítica com a textura voxel gerada pelo mesmo pintor do mapa do sistema solar
  (`tools/planet_gen.py`, importado por `src/flight/gen/make_flight_textures.py`), nuvens
  voxel com sub-blocos, brilho do sol no oceano, luzes de cidades no lado noturno,
  espalhamento simples Rayleigh + Mie (céu azul que escurece, limbo brilhante), Sol, Lua
  voxel e estrelas. A altitude da câmera entra em dupla precisão e as interseções evitam
  subtrair números enormes. Perto da base o chão do céu usa a mesma linha de costa da
  cena `outside_launch_site`, então a troca do plano local (escondido acima de 1,5 km)
  para o planeta não aparece.
- **HUD** (`scenes/flight/flight_hud.tscn`): navball (SubViewport, textura gerada),
  acelerador, velocidades, Ap/Pe, Δv do estágio e total, G, pressão dinâmica com Max-Q,
  pilha de estágios (`flight_stage_row.tscn`), relógio, aceleração do tempo, mapa,
  pausa e relatório (`FlightPlot` desenha altitude/velocidade). Painéis recolhíveis, F2
  esconde tudo. Textos em `i18n/flight_strings.csv` (EN/PT).
- **Desempenho (GPU integrada).** `GraphicsQuality.apply(self)` no `_ready` (escala 3D,
  SSAO, glow, sombras por nível). Luz ambiente/névoa definidas por script (re-filtrar o
  cubemap de radiância do céu a cada quadro custava ~8 ms), estrelas só calculadas quando o
  céu está escuro. Passada de desempenho (2026-10):
  - céu: o espalhamento (amostras × duas colunas de Chapman) roda na passada de **meia
    resolução** do sky shader, a Via Láctea (4 fBm) na de **1/4**, e a resolução total só faz
    chão voxel, nuvens, Sol, Lua e estrelas, com a transmitância por colunas de Chapman
    fechadas; amostras por qualidade (LOW 6, MEDIUM 9, HIGH 12);
  - SSAO desligado enquanto a base de lançamento está fora de vista (acima de 32 km ou fora
    da Terra): ~2 ms a menos no espaço sem mudar a imagem;
  - `visibility_range` nos objetos da base (6 km; detalhes pequenos 1,5 km) — o céu desenha
    a costa a partir de 5 km;
  - mapa novo sem SSAO / glow / MSAA (o halo do Sol é um billboard, as linhas se
    antisserrilham sozinhas): era a vista mais cara.
  Medidas A/B (Radeon integrada, D3D12, 1600×900, `tests/screenshot_flight_perf.gd`, mesmas
  vistas, código antigo e novo alternados 2× na mesma máquina, ms de GPU, média):

  | vista | antes MEDIUM | depois MEDIUM | antes LOW | depois LOW |
  |---|---|---|---|---|
  | pad | 21,4 | 19,3 | 12,4 | 11,1 |
  | pad, costa | 19,4 | 21,5 | 11,6 | 11,0 |
  | órbita, limbo | 22,6 | 17,0 | 12,7 | 11,3 |
  | órbita, para baixo | 22,2 | 19,2 | 12,9 | 11,6 |
  | mapa | 38,4 | 8,5 (sistema 6,7, solar 6,7) | 27,5 | 7,0 |

  O pad fica dentro do ruído (±3 ms, outra instância do Godot usava a mesma GPU): o piso do
  pipeline (pós-processamento sem nada na cena) já é ~9–10 ms nesta GPU em MEDIUM.

## Testes / tests

```bash
# física: órbita circular de 200 km (1 volta), Kepler, estágios do Garça = hangar,
# equação do foguete por estágio (< 2 %), balanço de massa, subida automática até órbita
godot --headless --path . --script res://tests/test_flight.gd
# cônicas encadeadas, SOI, encontros com a Lua, escape para o Sol, manobras (vis-viva)
godot --headless --path . --script res://tests/test_flight_conics.gd
# SOI dentro da cena de voo (física e trilhos), executor de manobra, acelerar até
godot --headless --path . --script res://tests/test_flight_soi.gd
# mapa nas várias escalas, manobra lunar editada, execução e chegada à Lua
godot --path . --resolution 1600x900 --script res://tests/screenshot_flight_map.gd -- <pasta>
# tempos de GPU por vista (variantes: noglow nossao lowq highq ...)
godot --path . --resolution 1600x900 --script res://tests/screenshot_flight_perf.gd -- <pasta>
# prints: plataforma, decolagem, Max-Q, separação dos boosters e do estágio, espaço com o
# limbo, mapa, relatório, desintegração, verificação de câmera acima do chão e FPS
godot --path . --resolution 1600x900 --script res://tests/screenshot_flight.gd -- <pasta>
```

Gerar texturas de novo / regenerate textures: `python src/flight/gen/make_flight_textures.py`.

## Limitações conhecidas / known limitations

- A Terra não gira (sem os ~400 m/s grátis do lançamento para leste). Sol e Lua seguem o
  sistema solar no tempo da missão (a Lua orbita no plano de lançamento).
- Só a Terra é desenhada como planeta no céu do voo; os outros corpos aparecem no mapa
  (a Lua como disco no céu).
- Arrasto e sustentação são um modelo simples (sem número de Reynolds, aquecimento ou
  ventos); a força normal das aletas entra só pelo centro de pressão.
- Destroços de estágios usam o mesmo integrador (sem controle) e somem a 40 km do
  foguete ou ao tocar o solo; a explosão final usa corpos Jolt locais (≤ 380).
- O chão de colisão para colisão com o foguete é plano (plataforma + nível do mar); o
  relevo voxel da base não é sólido para a física de voo.
