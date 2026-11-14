# MARGIN — Space Mission Design Game
**Game Design Document + Análise do desafio** · NASA Space Apps Challenge 2026 · Evento: 14–15/11/2026
Desafio: *Space Mission Design Game* (Intermediário + Beginner/Youth · assunto: Games)

> Nome de trabalho: **MARGIN**. Tagline: *"Every kilogram has a price."*
> Todos os números de balanceamento deste documento são **valores iniciais** para playtest, calibrados em ordens de grandeza reais, não valores oficiais de missões. Os benchmarks reais devem ser conferidos nas páginas da NASA antes de aparecerem no jogo.

---

## 0. Resumo em 10 linhas

1. O desafio pede um jogo educativo em que o jogador **projeta, gerencia e simula uma missão espacial completa**, enfrentando trade-offs reais.
2. A palavra-chave do enunciado é **trade-off**: toda decisão melhora uma coisa e piora outra. Não existe design perfeito.
3. O jogo tem 4 atos: **Briefing → Design → Design Review → Voo (simulação) → Debrief**.
4. Seis recursos acoplados (os do enunciado): **Massa, Energia, Orçamento, Dados, Comunicação, Tempo**.
5. O núcleo é uma **cadeia causal visível**: mais instrumento → mais massa → mais propelente → foguete maior → mais custo. O jogador *vê* a onda de consequências.
6. A simulação é semanal, determinística por **seed**, com eventos aleatórios e **3–6 decisões de operação** durante o voo (o jogador não só assiste).
7. A ciência só conta quando os **dados chegam à Terra**. Dado gerado e não baixado vale zero.
8. O jogo **nunca diz só "errado"**: o *Post-Mission Analysis* aponta o fator limitante e explica por quê.
9. Até 4 jogadores, com **papéis com objetivos conflitantes** (Cientista, Engenheiro de Sistemas, Dinâmica de Voo, Gerente). Solo: 4 conselheiros virtuais discordam entre si.
10. Escopo viável em 48h: **3 cenários** (LEO → Lua → Marte), ~30 componentes, simulação + relatório + tutorial. Online coop e ranking global ficam como stretch.

---

# PARTE A — ANÁLISE DO DESAFIO

## A1. Leitura do enunciado, requisito por requisito

O texto oficial está na página do desafio. Abaixo, cada exigência virou uma linha de checklist.

| # | O que o enunciado diz | Como o jogo atende | Prioridade |
|---|---|---|---|
| R1 | Jogo interativo para **projetar, gerenciar e simular** uma missão completa | Fluxo Design → Review → Voo → Debrief | **MUST** |
| R2 | Jogador toma **decisões de engenharia** e gerencia **recursos limitados** | 6 recursos acoplados + HUD ao vivo | **MUST** |
| R3 | Avaliar **como cada escolha molda o sucesso** | Simulação semanal + Post-Mission Analysis com atribuição de causa | **MUST** |
| R4 | Individual **ou** em equipe de até **4** | Solo (4 conselheiros IA) + modo equipe com 4 papéis | **MUST** (hot-seat) / SHOULD (online) |
| R5 | Definir objetivo da missão **antes** de escolher espaçonave | Fluxo obriga: objetivo vem primeiro, o resto é filtrado por ele | **MUST** |
| R6 | Espaçonave: estrutura, energia, baterias, comunicação, computador, **controle de atitude**, instrumentos | Catálogo por subsistema, encaixado em um esquema da nave | **MUST** |
| R7 | Instrumentos com massa, consumo, **geração de dados**, custo e valor científico | Cada instrumento tem 5 atributos + capacidades científicas | **MUST** |
| R8 | **Várias opções de órbita**, explicando o básico de cada uma | Seletor de órbita com ficha: cobertura, Δv, eclipse, radiação, contato | **MUST** |
| R9 | Veículos de lançamento com **capacidade, custo e restrição orbital**; checar compatibilidade massa × órbita × foguete | Tabela de LVs; *Design Review* bloqueia incompatibilidades | **MUST** |
| R10 | Recursos principais: massa, energia, orçamento, dados, comunicação, tempo | HUD com 6 medidores | **MUST** |
| R11 | **Cada decisão tem consequência** (+instrumentos ⇒ +massa, +energia, +custo, +dados) | Painel "efeito dominó" ao vivo | **MUST** |
| R12 | **Raramente há uma única solução perfeita**; combinações diferentes cumprem o mesmo objetivo | Cenários com várias rotas viáveis + teste automático de dominância (ver B15) | **MUST** |
| R13 | **Feedback claro** de por que a missão teve sucesso ou falhou | Post-Mission Analysis + log causal | **MUST** |
| R14 | Sistema de **pontuação** (sucesso, ciência, uso eficiente de recursos, decisões) | Score composto (ver B6) | **MUST** |
| R15 | **Níveis de dificuldade**, tipos de missão ou cenários | 3 dificuldades × 3+ cenários | **MUST** |
| R16 | Conceitos introduzidos **dentro do próprio jogo**, de forma simples, **sem só dizer certo/errado** | Tutorial integrado, "Por quê?" em cada número, Codex | **MUST** |
| R17 | Extras sugeridos: múltiplos cenários, eventos aleatórios, dashboards em tempo real, ranking, relatório final, salvar/compartilhar designs, modo sandbox, análise pós-missão, modo cooperativo, modo competitivo | Ver escopo (B13) | SHOULD / COULD |

**Conclusão da leitura:** o enunciado é praticamente um *requirements document*. A maioria dos itens é "pode considerar", mas quem avalia vai comparar a entrega com essa lista. Cobrir todos os MUST com qualidade vale mais do que adicionar features fora dela.

## A2. O que o desafio *realmente* quer (leitura nas entrelinhas)

1. **A lição é o acoplamento, não a engenharia em si.** A frase central é "uma decisão que melhora um aspecto pode criar limitações em outro". O jogo precisa tornar esse acoplamento *visível e sentido* e não só correto.
2. **Aprender fazendo, com segurança.** O texto diz que estudantes raramente experimentam uma missão inteira, de conceito a operação. O jogo é um laboratório onde falhar é barato e *informativo*.
3. **Público: Beginner/Youth + Intermediário.** A complexidade do modelo pode ser alta, mas a **complexidade exposta** tem que ser progressiva. Se o jogador novato vê 40 sliders, o jogo falhou no critério educativo.
4. **Feedback de causa, não de resultado.** "Você perdeu" é inútil. "Sua missão perdeu 62% da ciência porque o armazenamento encheu antes do downlink" ensina.
5. **A simulação é o clímax.** Um jogo só de montagem (como um configurador) é anticlimático. O jogador precisa *assistir à consequência* e, melhor, *reagir* a ela.
6. **Equipe = divisão de responsabilidade com conflito.** O enunciado sugere papéis distintos e "negociar prioridades concorrentes". O valor está no conflito produtivo entre ciência, engenharia e orçamento.

## A3. O domínio: engenharia de missões espaciais, em termos de jogo

### A3.1 Fases reais de uma missão (e como viram telas)
Formulação (objetivo) → Design conceitual → Revisões (PDR/CDR) → Construção e teste → Lançamento → Cruzeiro → Inserção orbital → Operação científica → Fim de missão. O jogo comprime isso em: **Briefing → Design → Design Review → Build (revelação de crescimento de massa/custo) → Voo → Debrief.**

### A3.2 O grafo de acoplamentos (o coração do jogo)

```
Mais instrumentos ──► + massa ──► + propelente (equação do foguete) ──► + massa molhada ──► foguete maior ──► + custo
        │                                                                                         ▲
        ├──► + consumo ──► painéis maiores ──► + massa e + área    baterias maiores (eclipse) ────┘
        │                                    └──► estrutura/ADCS mais robustos
        └──► + dados/dia ──► + armazenamento ──► + massa/custo
                         └──► + downlink necessário ──► antena maior ──► + massa, + precisão de apontamento, + custo
                                                       └──► mais passes de estação ──► + custo operacional
Órbita mais baixa ──► melhor resolução ──► mas + Δv, + eclipse/temperatura, + dados por área, + janela de contato menor
Mais Δv ──► + propelente ──► + massa ──► + Δv (círculo vicioso: a "tirania da equação do foguete")
Mais complexidade ──► + tempo de desenvolvimento ──► risco de perder a janela de lançamento (Marte: ~26 meses)
Mais redundância ──► + confiabilidade ──► mas + massa + custo
Menos margem ──► orçamento fecha no papel ──► crescimento de massa/custo na construção estoura o limite
```

Esse grafo é a espinha do design. Toda regra do jogo deve ser uma aresta dele, e todo feedback ao jogador deve percorrê-lo.

### A3.3 Conceitos reais que o jogo ensina (e o modelo simplificado)

| Conceito | Idéia real | No jogo |
|---|---|---|
| **Equação do foguete (Tsiolkovsky)** | Δv = Isp·g₀·ln(m₀/m_f). Cada kg a mais exige mais propelente, que também precisa ser carregado | Propelente calculado automaticamente a partir do Δv necessário |
| **Orçamento de Δv** | Cada órbita/manobra custa Δv (inserção, manutenção, descarte) | Ficha de órbita mostra Δv de inserção + manutenção/ano |
| **Capacidade de lançador por destino** | Um foguete leva mais para LEO do que para a Lua ou Marte | Tabela de capacidade por classe de órbita de partida |
| **Fluxo solar ∝ 1/d²** | Em Marte, ≈ 43% do fluxo da Terra. Em Júpiter, ≈ 4% | Painéis rendem menos longe do Sol; RTG vira opção (stretch) |
| **Eclipse e baterias** | Em órbita baixa a nave passa parte do tempo na sombra | Fração de eclipse por órbita dimensiona bateria |
| **Link de comunicação** | Taxa cai com o quadrado da distância e depende da antena | Taxa de downlink por antena × destino |
| **Janelas de lançamento** | Marte: janela a cada ~26 meses | Perder a janela = esperar ou cortar escopo |
| **Margens e reservas** | Projetos reais carregam reserva de massa, potência e custo porque tudo cresce | Mecânica de *mass growth* oculto na fase Build |
| **Confiabilidade e redundância** | Falhas acontecem; radiação degrada eletrônica | Probabilidade de falha por componente, redundância opcional |
| **Critérios de sucesso mínimo/pleno** | Missões definem sucesso mínimo e pleno | Tiers de resultado: Falha / Mínimo / Pleno / Excepcional |
| **Latência de luz** | Lua ≈ 1,3 s, Marte ≈ 3–22 min | Operação em Marte tem comandos pré-programados (sem joystick) |

### A3.4 Missões reais como arquétipos (benchmarks para o Debrief)
Ao final, o jogo compara o design do jogador com um **arquétipo real** (ex.: um orbitador lunar polar, um orbitador marciano de atmosfera, um observatório de Terra). Isso conecta com a NASA e dá credibilidade. **Antes de publicar números reais, conferir nos sites oficiais das missões.** No jogo, usar só descrições qualitativas e intervalos aproximados.

## A4. Critérios de julgamento: como o jogo marca pontos

Nos anos anteriores o Space Apps julgou por **Impact, Creativity, Validity, Relevance e Presentation**. *Confirmar os critérios de 2026 no guia de submissão (previsto para 13/11).*

| Critério | Onde o jogo ganha |
|---|---|
| **Impact** | Ferramenta de sala de aula: ensina trade-offs de sistemas. Modo "Professor" com seeds fixas e relatório exportável |
| **Creativity** | Efeito dominó visível, conselheiros em conflito, post-mortem causal, *Mass Growth Reveal* |
| **Validity** | Física real simplificada (Tsiolkovsky, 1/d², latência de luz), dados e parâmetros baseados em missões NASA, benchmark no Debrief |
| **Relevance** | Responde ponto a ponto o enunciado (tabela A1) |
| **Presentation** | Demo jogável no navegador, vídeo curto, UI limpa estilo "mission control" |

## A5. Riscos do projeto

| Risco | Prob. | Impacto | Mitigação |
|---|---|---|---|
| **Escopo explode** (muitos subsistemas) | Alta | Alto | Cortar para o MVP (B13). Modelo único e simples por subsistema. |
| **Balanceamento ruim** (uma estratégia domina) | Alta | Alto | Teste automático com milhares de designs aleatórios (B15) |
| **Jogo vira planilha** | Média | Alto | Visual forte: esquema da nave, animação de órbita, eventos com decisão |
| **Complexidade afasta novatos** | Média | Alto | Dificuldade Cadet + divulgação progressiva + tutorial |
| **Multiplayer online no prazo** | Alta | Médio | Começar com hot-seat. Online só se sobrar tempo |
| **Export web (Godot) com problemas** | Média | Alto | Testar o export web na **primeira hora**. Plano B: build desktop + vídeo |
| **Erros de física** | Média | Médio | Fórmulas documentadas (B3), testes unitários, revisão de uma pessoa com conhecimento do tema |
| **Falta de polimento no pitch** | Média | Alto | Reservar as últimas 6h só para vídeo, README e submissão |

---

# PARTE B — DEFINIÇÕES DO JOGO

## B1. Visão e pilares

**Pitch (uma frase):** *Você é o engenheiro-chefe. Escolha o objetivo, desenhe a nave, convença a equipe e veja a missão acontecer. Cada quilo tem um preço, e cada decisão cobra a conta mais tarde.*

**Pilares de design**
1. **Trade-off sem vilão.** Nenhuma escolha é "a certa"; cada uma é um troca. O jogo recompensa *consciência* do trade-off.
2. **Consequência visível.** Toda decisão mostra seu efeito dominó na hora (design) e na simulação (voo).
3. **Falhar para entender.** O resultado ruim sempre vem com *porquê* e *o que tentar*.
4. **Profundidade progressiva.** Começa com 3 botões; a complexidade é liberada conforme o jogador aprende.
5. **Ciência só conta quando chega à Terra.** O dado é a moeda do jogo.

**Tom:** sério e acessível, "controle de missão" com um toque de humor nos conselheiros. Sem violência, sem texto longo.

## B2. Loop principal e fluxo de telas

```
┌─────────┐   ┌────────┐   ┌─────────────┐   ┌───────┐   ┌────────┐   ┌─────────┐
│Briefing │ → │ Design │ → │Design Review│ → │ Build │ → │  Voo   │ → │ Debrief │
│objetivo │   │ nave   │   │ (portão)    │   │reveal │   │ simul. │   │ relatório│
└─────────┘   └────────┘   └─────────────┘   └───────┘   └────────┘   └─────────┘
      ▲                          │ reprovado                                │
      └──────────────────────────┴───────── tentar de novo / próximo cenário ┘
```

1. **Briefing:** o cenário apresenta o objetivo científico, o orçamento, a janela de lançamento e os critérios de sucesso (mínimo/pleno/excepcional).
2. **Design:** o jogador escolhe, nesta ordem sugerida (mas navegável): *Órbita/Destino → Instrumentos → Nave (bus, energia, comunicação, computador/armazenamento, ADCS, propulsão) → Lançador → Reservas.* O HUD de 6 recursos atualiza ao vivo.
3. **Design Review (portão):** checklist com semáforo (verde/amarelo/vermelho). Bloqueia incompatibilidades duras (massa > capacidade do LV, energia negativa, sem link de comunicação). Avisa riscos suaves (margem baixa, armazenamento apertado). Em equipe, cada papel dá seu "aprovo/veto".
4. **Build:** a "revelação": crescimento oculto de massa e custo (típico de projetos reais). A margem escolhida absorve ou não. Se estourar, o jogador toma decisões forçadas: cortar instrumento, trocar o lançador, atrasar (e talvez perder a janela).
5. **Voo:** simulação semanal com timeline, telemetria e eventos. Há **3–6 pontos de decisão** (ver B5).
6. **Debrief:** pontuação, tier de sucesso, gráfico do fator limitante, post-mortem, comparação com arquétipo real, botão "tentar de novo com a mesma seed".

## B3. Modelo de sistemas

### B3.1 Os 6 recursos (HUD)

| Recurso | Unidade | Limite vem de | Mostra |
|---|---|---|---|
| **Massa** | kg | Capacidade do LV para aquela órbita | Seca, propelente, molhada, margem |
| **Energia** | W | Geração dos painéis/RTG vs. consumo por modo | Geração, consumo, margem, bateria (Wh) |
| **Orçamento** | US$ M | Teto do cenário | Hardware, lançamento, operações, reserva |
| **Dados** | Gbit/dia | Armazenamento a bordo | Geração, armazenamento, perda prevista |
| **Comunicação** | Mbps e h/dia | Antena, distância e rede de solo | Downlink diário possível |
| **Tempo** | meses | Janela de lançamento + vida útil | Desenvolvimento, cruzeiro, operação |

Regra de UX: cada medidor tem **3 estados** (verde ≥ 20% de margem, amarelo 5–20%, vermelho < 5% ou negativo), cor *e* ícone (acessibilidade).

### B3.2 Fórmulas centrais (modelo simplificado)

**Propelente (equação do foguete)**
```
v_e   = Isp × 9.81                                  [m/s]
m_prop = m_seca × (exp(Δv_total / v_e) − 1) × 1.08  [kg]   // 8% de tanque/estrutura
m_molhada = m_seca + m_prop
```
Exemplo (orbitador lunar, m_seca = 300 kg, Δv_total = 1,3 km/s):
- Bipropelente (Isp 320 s): v_e = 3139 m/s ⇒ m_prop ≈ 300 × 0,513 × 1,08 ≈ **166 kg**
- Monopropelente (Isp 220 s): v_e = 2158 m/s ⇒ m_prop ≈ 300 × 0,826 × 1,08 ≈ **268 kg**
Mesma missão, ~100 kg de diferença. Isso é uma aula de trade-off: monoprop é mais simples e barato; bipropelente poupa massa.

**Energia solar**
```
P_gerada = A × η × (1361 / d²) × cosθ × (1 − degradação)^anos        d em UA
carga_pico = Σ consumo(instrumentos ativos) + consumo_bus(modo)
Bateria_Wh = carga_eclipse × duração_eclipse / DoD_usável
P_necessária ≈ carga × (1 + f_ecl/(1 − f_ecl) × 1,2)                  // recarga
```
Valores-base: η = 0,28 (EOL ≈ 0,25); massa específica dos painéis ≈ 30 W/kg; bateria ≈ 60 Wh/kg utilizável; degradação 2%/ano + efeito da radiação.
Fator de fluxo: Terra/Lua 1,0 · Marte ≈ 0,43 · Júpiter ≈ 0,04.

**Link de comunicação e dados**
```
taxa(Mbps) = taxa_ref(antena, banda) × (d_ref / d)²
downlink_dia(Gbit) = taxa(Mbps) × horas_contato × 3600 / 1000
```
O jogo usa uma **tabela pré-calculada** taxa_ref × destino para não expor decibéis.
Fluxo de dados semanal (a regra mais importante do jogo):
```
gerado    = Σ taxa_instrumento × duty_cycle                (limitado por energia/pointing)
armazenado = min(capacidade, armazenado + gerado)           // excedente = DADO PERDIDO
baixado    = min(downlink_possível, armazenado)
CIÊNCIA SÓ CREDITA O BAIXADO
```

**Custo (paramétrico, como em estimativas reais)**
```
C_hardware = Σ custo_componentes + massa_seca × k_integração(destino)
C_total    = C_hardware × (1 + 0,25 teste) + C_lançador + C_operações(meses) + reserva
reserva    = % escolhida pelo jogador (recomendado 20–30% no conceito)
```

**Tempo / cronograma**
```
T_desenvolvimento = base(classe) + Σ complexidade(componentes, TRL)
Se T_desenvolvimento > tempo_até_janela: perde a janela (+26 meses em Marte, +1 mês na Lua)
```
Perder a janela custa "folha de pagamento parada" (US$/mês) ou força o corte de escopo.

**Crescimento oculto (Build)**
```
crescimento_massa   ~ N(μ = 12%, σ = 6%) × m_seca     // escalado pela dificuldade
crescimento_custo   ~ U(0%, 25%)  × C_hardware
// A reserva absorve. O que passar da reserva vira decisão forçada.
```

**Confiabilidade e radiação**
```
p_falha_semana(comp) = λ(comp) × estresse(órbita, radiação, térmico) × (redundância ? 0,25 : 1)
dose_acumulada += taxa_radiação(órbita) × (1 − blindagem)
se dose > rating_eletrônica: λ × 3
```

### B3.3 Componentes (catálogo MVP)

Cada componente: `id, nome, subsistema, massa_kg, potência_W, dados_Gbit_dia, custo_M, TRL, λ_falha, notas, ficha_educativa`.

| Subsistema | Opções (MVP) | Trade-off pedagógico |
|---|---|---|
| **Estrutura / bus** | CubeSat 6U · Pequeno (~150 kg) · Médio (~600 kg) · Grande (~1500 kg) | Mais capacidade de carga útil, mais massa e custo base |
| **Energia** | Painéis fixos · Painéis articulados (+10% massa, melhor ângulo) · Baterias 3 tamanhos · *(stretch: RTG)* | Eclipse vs. massa; distância do Sol |
| **Propulsão** | Monopropelente (Isp 220) · Bipropelente (Isp 320) · *(stretch: elétrica Isp ≈ 2000+, só espirais, tempo extra)* | Massa vs. complexidade vs. tempo |
| **Comunicação** | Antena omni · Média (X-band) · Grande refletor (X/Ka) | Taxa de dados vs. massa vs. apontamento |
| **Computador/armazenamento** | Básico · Redundante · Armazenamento 50/200/1000 Gbit | Buffer de dados vs. custo/radiação |
| **ADCS (apontamento)** | Magnetorquers+roda · Rodas+star tracker · Rodas+star tracker precisos | Resolução dos instrumentos depende do apontamento |
| **Térmica** | Passiva · Ativa (aquecedores/radiadores) | Consumo aumenta longe do Sol |
| **Instrumentos** | Ver tabela abaixo | Valor científico vs. massa/energia/dados/custo |
| **Blindagem** | Nenhuma · Leve · Pesada | Massa vs. vida do eletrônico |

### B3.4 Instrumentos (valores iniciais)

| Instrumento | Massa | Potência | Dados | Custo | Capacidade científica (nível) | Exige |
|---|---|---|---|---|---|---|
| Câmera grande-angular | 6 kg | 12 W | 8 Gbit/d | $12M | Imageamento (médio) | Nadir |
| Câmera de alta resolução | 18 kg | 25 W | 20 Gbit/d | $30M | Imageamento (alto) | Nadir, ADCS bom |
| Espectrômetro de nêutrons | 12 kg | 14 W | 0,5 Gbit/d | $22M | Hidrogênio/gelo (alto) | Órbita baixa |
| Espectrômetro IR | 25 kg | 30 W | 6 Gbit/d | $40M | Composição (alto) | Nadir |
| Radar (sondagem/SAR) | 20 kg | 90 W | 40 Gbit/d | $55M | Subsuperfície (alto) | Muita energia e downlink |
| Altímetro laser | 15 kg | 25 W | 1 Gbit/d | $35M | Topografia (alto) | Nadir |
| Radiômetro térmico | 10 kg | 15 W | 2 Gbit/d | $20M | Ambiente térmico (alto) | — |
| Magnetômetro | 3 kg | 2 W | 0,1 Gbit/d | $8M | Campos e partículas (médio) | Boom |
| *(Terra)* Multiespectral | 15 kg | 20 W | 15 Gbit/d | $28M | Vegetação/queimadas (alto) | LEO |

### B3.5 Lançadores (genéricos, sem marcas)

| Classe | LEO | TLI (Lua) | TMI (Marte) | Custo | Confiabilidade | Observação |
|---|---|---|---|---|---|---|
| Rideshare | ≤ 200 kg | — | — | $2M | 0,94 | Órbita imposta pelo lançador principal |
| **Lark** (S) | 350 kg | — | — | $8M | 0,92 | Só LEO |
| **Heron** (M) | 3.500 kg | 1.100 kg | 700 kg | $60M | 0,96 | Lua sim; Marte só nave pequena |
| **Condor** (L) | 15.000 kg | 5.500 kg | 3.800 kg | $120M | 0,97 | Marte confortável |
| **Colossus** (H) | 50.000 kg | 20.000 kg | 14.000 kg | $350M | 0,97 | Superdimensionado: bom para stretch |

Regra de compatibilidade: `m_molhada × 1,05 ≤ capacidade(classe_de_partida)`. O Design Review mostra a folga em %.

### B3.6 Órbitas (fichas educativas)

| Destino | Órbita | Δv inserção* | Cobertura | Eclipse | Contato c/ Terra | Observação |
|---|---|---|---|---|---|---|
| Terra | LEO síncrona ao Sol (~500 km) | 0 (o LV entrega) | Global, revisita ~dias | Baixo (dawn-dusk) | Muitos passes curtos | Ótima para observação da Terra |
| Terra | LEO equatorial | 0 | Só tropical | ~35% | Passes curtos | — |
| Lua | Polar baixa (~100 km) | ~0,9–1,0 km/s | Global, alta resolução | ~35–40% | Intermitente (lado oculto) | Instável: manutenção alta |
| Lua | Elíptica polar | ~0,8 km/s | Polo sul detalhado | Variável | Melhor contato | Menos resolução fora do periápsis |
| Marte | Elíptica (~1 sol) | ~1,0–1,2 km/s | Média | Baixo | Bom | Barata em propelente |
| Marte | Baixa circular | ~2 km/s ou aerofrenagem | Alta resolução | ~30% | Janela curta/dia | Aerofrenagem poupa massa mas custa meses |

\* Valores de ordem de grandeza para balanceamento.

Cada ficha traz um botão **"Por que essa órbita?"** com uma explicação em 2 frases.

## B4. Cenários e campanha

**Estrutura:** uma "escada" de 3 cenários no MVP (+3 stretch). Cada cenário reutiliza o mesmo sistema; só mudam objetivo, destino, orçamento, janela e eventos.

| # | Cenário | Objetivo científico | Orçamento | Ensina | Nível |
|---|---|---|---|---|---|
| 1 | **Fire Watch** (tutorial) | Monitorar queimadas e vegetação em LEO | ~$120M | Instrumento ↔ energia ↔ dados ↔ downlink | Cadet |
| 2 | **Polar Ice** | Mapear gelo de água no polo sul lunar | ~$400M | Δv, equação do foguete, escolha de LV, órbita baixa | Cadet / Engineer |
| 3 | **Red Climate** | Orbitador marciano para atmosfera e clima | ~$600M | Fluxo solar, janela de 26 meses, latência, DSN | Engineer |
| 4* | Rock Rendezvous | Asteroide: encontro e mapeamento | ~$700M | Navegação, Δv baixo mas precisão alta | Engineer |
| 5* | Frozen Moon | Sobrevoo de lua gelada: RTG, radiação | ~$2.000M | Energia nuclear, radiação, Júpiter | Chief |
| 6* | Deep Eye | Telescópio em L2 | ~$1.500M | Pointing, criogenia, estabilidade | Chief |

### Exemplo completo: Cenário 2 "Polar Ice"
- **Briefing:** "Selecionar sítios de pouso para missões lunares: onde há gelo de água, como é o terreno e a luz?"
- **Objetivos científicos (pesos):**
  - G1 Mapa de hidrogênio/gelo — 40% (neutrons *forte*, radar/IR *médio*)
  - G2 Imagens de alta resolução de candidatos a pouso — 25% (câmera HR *forte*, WAC *médio*)
  - G3 Topografia e iluminação — 20% (altímetro *forte*)
  - G4 Ambiente térmico em crateras sombreadas — 15% (radiômetro *forte*, IR *médio*)
- **Critérios de sucesso:** *Mínimo* G1 ≥ 50% · *Pleno* score ciência ≥ 75% · *Excepcional* ≥ 95% + meta extra (ex.: radar confirma gelo em subsuperfície).
- **Rotas viáveis (provando "não há solução única"):**
  - *Enxuta:* neutrons + câmera HR + altímetro em bus pequeno, Heron, monoprop. Barata, ciência média.
  - *Equilibrada:* + radiômetro, bipropelente, antena média. Melhor custo-benefício.
  - *Ambiciosa:* + radar e IR, bus médio, antena grande. Ciência máxima, mas pesada, cara e com risco de dado perdido.
- **Eventos do cenário:** tempestade solar, falha de roda de reação, eclipse mais longo que o planejado, janela de contato perdida, degradação de painel.

## B5. Simulação (fase de Voo)

**Passo:** 1 semana de missão = 1 tick. Missão típica: 52–104 ticks. Velocidade 1×/4×/16×.

**Fases do voo:** `Lançamento → Cruzeiro → Inserção orbital → Comissionamento → Ciência → Fim de missão/extensão`.

**A cada tick:**
1. Calcula energia disponível (eclipse, distância, degradação) vs. consumo do **modo operacional**.
2. Gera dados dos instrumentos ativos (limitado por energia e apontamento).
3. Atualiza armazenamento e executa o downlink.
4. Credita ciência pelos dados *baixados* (ponderados por objetivo).
5. Rola falhas e eventos (RNG com seed).
6. Registra no **log causal**: qual restrição limitou a ciência neste tick.

**Pontos de decisão do jogador (a camada de gameplay do voo)**
| Momento | Decisão | Consequência |
|---|---|---|
| Lançamento | — (apenas risco do LV) | Sucesso ou perda total |
| Inserção em Marte/Lua | Inserção direta *vs.* aerofrenagem (Marte) | Δv/massa vs. tempo e risco |
| Comissionamento | Ligar todos os instrumentos de uma vez ou escalonar | Risco de sobrecarga vs. tempo |
| Evento: tempestade solar | Modo seguro (perde dias de ciência) *vs.* arriscar | Dose de radiação, chance de falha |
| Evento: falha de componente | Usar redundância, reconfigurar, aceitar perda | Ciência reduzida ou recuperada |
| Rotina | Modo operacional: **Ciência / Balanceado / Economia** e prioridade de downlink | Energia, dados, desgaste |
| Fim da vida nominal | Estender missão (consome reserva) ou encerrar com descarte | Mais ciência *vs.* risco |

**Biblioteca de eventos (MVP ≈ 10):** tempestade solar · falha de roda de reação · degradação de painel · eclipse prolongado · perda de passe de comunicação · micrometeoroide · sobrecarga térmica · reinicialização do computador · atraso de estação de solo · **sucesso inesperado** (evento positivo, ex.: o instrumento rende acima do esperado). Eventos têm probabilidade base × estresse, e **mitigação possível pelo design** (blindagem, redundância, margem). Isso premia planejamento.

**Falhas suaves:** a maioria dos problemas *degrada* a missão em vez de terminar o jogo. Só perda do LV e falha de inserção sem propelente são "game over" completo.

## B6. Pontuação

```
Score (0–1000) = 1000 × [ 0,50 × Ciência + 0,20 × Eficiência + 0,20 × Resiliência + 0,10 × Bônus ]
```
| Componente | Definição |
|---|---|
| **Ciência** | Σ peso(objetivo) × min(1, dados_válidos_baixados / dados_requeridos) |
| **Eficiência** | Ciência por US$ gasto, normalizada pela faixa do cenário (premia design enxuto sem sacrificar a missão) |
| **Resiliência** | Quão bem a missão absorveu eventos: margens, redundância usada, ciência preservada |
| **Bônus** | Metas extras, margens saudáveis (≥ 20% em massa e custo), nenhuma perda de janela, eventos positivos aproveitados, consenso da equipe |

**Tiers:** `Falha` · `Sucesso Mínimo` · `Sucesso Pleno` · `Excepcional`. O tier vem dos critérios do cenário, não só do score numérico, igual às missões reais.

## B7. Modos de jogo

1. **Campanha (solo):** 3 cenários em sequência, dificuldade crescente. Conselheiros virtuais opinam.
2. **Equipe (2–4 jogadores):** os **papéis** definem quais painéis cada jogador controla e quais critérios deve aprovar.
   - **Cientista-chefe (PI):** objetivos e instrumentos. *Quer mais ciência.*
   - **Engenheiro de Sistemas:** bus, energia, térmica, ADCS, comunicação, computador. *Quer margens.*
   - **Dinâmica de Voo / Lançamento:** órbita, propulsão, lançador, Δv. *Quer folga de Δv e LV adequado.*
   - **Gerente de Programa / Operações:** orçamento, cronograma, reserva, plano operacional. *Quer custo e prazo sob controle.*
   - **Implementação no MVP:** **hot-seat** (mesma tela, trocar de papel) ou "um jogador por vez, os demais aprovam/vetam". **Stretch:** online.
   - **Portão de aprovação:** o Design Review exige o "OK" dos 4 papéis, cada um com seu critério objetivo. Isso materializa a negociação entre prioridades concorrentes.
3. **Seed Challenge (competitivo):** mesma seed e mesmo cenário para todos; o melhor score vence. Ranking local no MVP, global no stretch.
4. **Sandbox:** sem limites de orçamento/massa, para experimentar a cadeia causal.
5. **Compartilhar design:** o design vira um **código de texto** (JSON comprimido em Base64) que outro jogador cola e simula. Barato de implementar e cobre "salvar, compartilhar e comparar designs".

**Solo com 4 conselheiros virtuais** (personagens curtos e com humor):
- *Dra. Vega* (cientista): "Mais um instrumento. Sempre mais um."
- *Eng. Okafor* (sistemas): "Cada watt adicional é um problema meu."
- *Cap. Lindqvist* (dinâmica de voo): "Me dê Δv e eu te dou o planeta."
- *Gerente Moreau* (programa): "O orçamento não é uma sugestão."
(Nomes de exemplo; podem ser trocados.) Cada um comenta o design em tempo real a partir do mesmo cálculo que o jogo usa para o Review.

## B8. Dificuldade

| Opção | **Cadet** | **Engineer** | **Chief** |
|---|---|---|---|
| Subsistemas visíveis | Simplificados (3–4 slots) | Completos | Completos + opções avançadas |
| Orçamento | Folgado (+30%) | Padrão | Apertado (−15%) |
| Mass/cost growth | Desligado | Moderado | Alto |
| Eventos aleatórios | Poucos, mitigáveis | Normais | Frequentes |
| Janela de lançamento | Sempre com folga | Normal | Apertada |
| Dicas | Automáticas | Sob demanda | Só no Codex |
| Cenários | 1, 2 | 1–4 | Todos |

## B9. Educação e feedback

- **"Por quê?"** em cada número e semáforo: abre uma explicação curta com o cálculo e *"o que fazer para melhorar"*.
- **Efeito dominó:** ao alterar um componente, os medidores afetados **piscam** e o painel lateral lista, em linguagem simples, a cadeia ("+20 kg → +31 kg de propelente → Heron fica com 4% de folga").
- **Tutorial integrado** (Cenário 1): 5 passos, cada um introduz *um* conceito quando ele aparece pela primeira vez.
- **Codex** (≈ 15 verbetes no MVP): Δv, Isp, equação do foguete, eclipse, fluxo solar, link/downlink, duty cycle, margem, janela de lançamento, TRL, redundância, radiação, latência, órbita polar, aerofrenagem.
- **Post-Mission Analysis:**
  1. Linha do tempo com os eventos.
  2. **Fator limitante** em barras: "% da ciência perdida por energia / dados / downlink / falha / apontamento".
  3. Texto gerado por regras: *"A ciência ficou 62% abaixo do possível porque o armazenamento encheu antes de cada passe. Considere uma antena maior ou compressão a bordo."*
  4. Comparação com o arquétipo real.
  5. Sugestão de 2–3 mudanças para a próxima tentativa.
- **Sem resposta "certa":** o jogo mostra o **custo de oportunidade** ("sua rota enxuta entregou 71% da ciência por 58% do custo").

## B10. UX / UI / Arte / Áudio

**Estilo:** *blueprint / mission control* em 2D vetorial. Fundo escuro azul-petróleo, linhas finas ciano, acentos âmbar (alerta) e verde (ok). Poucos assets, ótimo para 48h e leitura rápida.

**Tela de Design (a mais importante)**
```
┌──────────────────────────────────────────────────────────────────────────┐
│ MISSÃO: Polar Ice            Dificuldade: Engineer      Papel: Eng.Sist. │
├──────────────┬───────────────────────────────────────┬───────────────────┤
│ CATÁLOGO     │          ESQUEMA DA NAVE              │  HUD DE RECURSOS  │
│ [Bus]        │       ┌──┐  ┌────────┐  ┌──┐          │ Massa  ██████░ 82%│
│ [Energia]    │       │PV│══│  BUS   │══│PV│          │ Energia█████░░ 71%│
│ [Propulsão]  │       └──┘  │ ◉ ◉ ◉  │  └──┘          │ Orçam. ███████ 96%│
│ [Comunic.]   │             └─┬────┬─┘                │ Dados  ████░░░ 58%│
│ [Instrum.]   │            antena  instr.             │ Comun. ████░░░ 60%│
│ [Lançador]   │                                       │ Tempo  ██████░ 78%│
├──────────────┴───────────────────────────────────────┤ ────────────────  │
│ EFEITO DOMINÓ: +Radar → +20 kg → +34 kg prop →       │ CONSELHEIROS      │
│  Heron folga 9% → 4% ⚠  · +90 W → +0,3 m² painel     │ Vega: "Radar!"    │
│                                                       │ Okafor: "Energia" │
└──────────────────────────────────────────────────────┴───────────────────┘
```
- Arrastar e soltar componentes nos slots do esquema.
- Hover mostra a ficha do componente; clique em "Por quê?" abre o Codex no verbete certo.

**Tela de Voo:** órbita 2D animada, painel de telemetria (energia, armazenamento, dados baixados), barra de ciência acumulada, timeline de eventos, botões de modo operacional.

**Acessibilidade:** cor + ícone + texto nos semáforos; escala de fonte; navegação por teclado; legendas.

**Idiomas:** **inglês primeiro** (juízes internacionais) e português como segundo. Todas as strings em tabela de tradução desde o dia 1.

**Áudio:** ambiente espacial discreto, bipes de interface, voz opcional (stretch). Efeitos para sucesso/alerta/falha.

## B11. Arquitetura técnica

**Engine recomendada:** **Godot 4.x (GDScript)** com **export Web (HTML5)** publicado no itch.io ou em página estática, assim o juiz joga no navegador sem instalar.
*Alternativa:* TypeScript + Canvas/React se a equipe já domina web. A decisão deve ser tomada na primeira hora.

**Camadas (essencial para testar e balancear):**
```
/data        → JSON/Resources: componentes, lançadores, órbitas, cenários, eventos, codex, strings
/sim         → núcleo PURO (sem UI): fórmulas, tick, RNG com seed, log causal, score
/ui          → telas: briefing, design, review, voo, debrief, codex
/net         → (stretch) sincronização de equipe
/tests       → testes do núcleo + simulação em massa (headless)
```
- O núcleo `sim` recebe `Design + Scenario + Seed` e devolve `MissionResult` (ciência, custo, logs, fator limitante). A UI só o exibe.
- **Dados em arquivos, não em código:** balancear = editar JSON.
- **Determinismo:** mesma seed ⇒ mesmo resultado (replay, ranking justo, debug).
- **Serialização do design:** `Design → JSON → Base64` para compartilhar.
- **Nota sobre o MCP:** o servidor `godot-ai` falhou ao conectar nesta sessão. Se quiser usá-lo no fluxo de desenvolvimento, é preciso reconectá-lo.

**Esquema de dados (exemplo)**
```json
{
  "id": "inst_neutron_spec",
  "name": "Neutron Spectrometer",
  "subsystem": "instrument",
  "mass_kg": 12, "power_w": 14, "data_gbit_day": 0.5, "cost_musd": 22,
  "trl": 7, "failure_rate_week": 0.0008,
  "capabilities": { "hydrogen_detection": 0.9 },
  "requires": { "pointing": "nadir", "max_altitude_km": 150 },
  "codex": ["neutron_spectroscopy"]
}
```
```json
{
  "id": "scn_polar_ice",
  "objective": "Map water ice at the lunar south pole",
  "budget_musd": 400, "launch_window_months": 18,
  "goals": [
    { "id": "G1", "weight": 0.40, "needs": { "hydrogen_detection": 0.7 } },
    { "id": "G2", "weight": 0.25, "needs": { "imaging_hr": 0.7 } }
  ],
  "success": { "minimum": { "G1": 0.5 }, "full": 0.75, "outstanding": 0.95 }
}
```

## B12. Ciência → capacidade → objetivo (como o valor científico é calculado)

1. Cada instrumento tem **capacidades** (ex.: `hydrogen_detection: 0.9`).
2. Cada objetivo exige combinações de capacidades com **nível mínimo**.
3. A capacidade *efetiva* depende de: apontamento (ADCS), altitude/órbita, duty cycle e **dados efetivamente baixados**.
4. O progresso do objetivo é a integral ao longo da missão: `progresso_G += capacidade_efetiva × cobertura × tick`.
5. `Ciência = Σ peso_G × min(1, progresso_G / requerido_G)`.

Isso separa **projeto** (que capacidades tenho), **operação** (que dados consigo gerar) e **sistema** (que dados consigo trazer), exatamente a lição do jogo.

## B13. Escopo: MVP, Stretch e cortes

**MVP (Definition of Done: um juiz joga do início ao fim sem ajuda)**
- [ ] 3 cenários jogáveis (Fire Watch, Polar Ice, Red Climate)
- [ ] ~30 componentes + 4 lançadores + 6 órbitas
- [ ] Tela de Design com HUD de 6 recursos e efeito dominó
- [ ] Design Review (semáforo + bloqueios)
- [ ] Build com mass/cost growth
- [ ] Simulação semanal com ~10 eventos e 3–6 decisões
- [ ] Debrief: score, tier, fator limitante, texto causal
- [ ] 3 dificuldades (flags de configuração)
- [ ] Tutorial no cenário 1 + Codex de ~15 verbetes
- [ ] Equipe em **hot-seat** com 4 papéis + conselheiros solo
- [ ] Compartilhar design por código
- [ ] Export web funcionando + README + vídeo curto

**SHOULD (se sobrar tempo):** sandbox, ranking local por seed, mais 1 cenário (asteroide), aerofrenagem, benchmark com missão real, voz/áudio extra.

**COULD / Stretch:** coop online, ranking global, RTG e Júpiter, propulsão elétrica, telescópio em L2, modo Professor com relatório exportável, localização completa PT/EN.

**Cortes pré-aprovados (se o relógio apertar, nesta ordem):** 3º cenário → aerofrenagem → compartilhar design → térmica detalhada → conselheiros animados.

## B14. Plano de 48 horas

*Assumindo equipe de 3–6. Se for solo, o MVP já é o limite: cortar equipe hot-seat e Codex além de 8 verbetes.*

| Janela | Entrega | Responsável (sugestão) |
|---|---|---|
| **H0–H2** | Escolha da engine, repositório, **export web "hello world" testado**, tabela de dados vazia, divisão de papéis | Todos |
| **H2–H8** | Núcleo `sim`: componentes, equação do foguete, energia, dados, custo, 1 cenário de teste (headless). Em paralelo: UI esqueleto + conteúdo (tabelas de componentes/instrumentos/lançadores) | Dev sim · Dev UI · Conteúdo |
| **H8–H16** | Tela de Design com HUD e efeito dominó; Design Review; cenário 2 (Polar Ice) ponta a ponta | Dev UI · Dev sim |
| **H16–H24** | Simulação semanal visual, eventos, decisões de voo, Debrief + log causal | Dev sim · Dev UI · Arte |
| **H24–H32** | Cenários 1 (tutorial) e 3 (Marte), dificuldades, Build com growth, conselheiros | Conteúdo · Dev |
| **H32–H38** | **Teste automático de balanceamento** (B15) + ajustes; equipe hot-seat; compartilhar design | Dev sim · Todos |
| **H38–H44** | Playtest com 3–5 pessoas de fora, correção de bugs, Codex, polimento de UI/áudio | Todos |
| **H44–H48** | Build final, README, vídeo, página de submissão, **congelar código** | Pitch · Todos |

**Regras de sobrevivência**
- Sempre ter um build jogável. Se uma feature ameaçar isso, corte.
- *Feature freeze* na H38.
- Submeter **antes** do prazo, com folga para falhas de upload.

## B15. Validação e balanceamento

**Teste automático de "solução dominante" (a prova do requisito R12)**
1. Gerar 5.000–20.000 designs aleatórios *válidos* por cenário (headless).
2. Rodar cada um em 20 seeds. Salvar `(ciência, custo, resiliência)`.
3. Calcular a **frente de Pareto**. Verificar que existem **pelo menos 3 clusters** de rotas viáveis (enxuta, equilibrada, ambiciosa).
4. Se um único design domina todos nos 3 eixos, o balanceamento está quebrado: ajustar custos, massas ou eventos.
5. Verificar também: nenhum design válido tem score > 98% sem custo alto; nenhum design trivial passa de "Mínimo".

**Playtest rápido (3–5 pessoas, 15 min cada):** observar sem explicar. Medir: chegaram ao final? Entenderam o motivo da falha? Que número confundiu?

**Testes unitários do núcleo:** equação do foguete (valores conhecidos), fluxo solar, conservação de dados (gerado = armazenado + baixado + perdido), determinismo por seed.

## B16. Pitch e submissão

**Mensagens-chave (3):**
1. *"There is no perfect spacecraft."* Todo design é um trade-off.
2. *"Every kilogram has a price."* A cadeia de consequências é visível.
3. *"Learn by failing, understand why."* O post-mortem explica a causa.

**Roteiro de vídeo (≈ 60–90 s):** problema (estudantes não experimentam missões inteiras) → mostrar o Design com o efeito dominó → o Design Review → a simulação com evento → o Debrief explicando a falha → apelo de uso em sala de aula.

**Página de submissão:** link do jogo web jogável, link do código, README com *como jogar*, tabela de requisitos (A1) marcada, fontes de dados e parâmetros NASA, créditos. *Conferir o formato exato no guia de submissão.*

**Dados NASA:** a aba **Resources** do desafio traz recursos oficiais. Usar parâmetros reais (fluxo solar, distâncias, latência de luz, características de missões) e **citar as fontes** no jogo e no README.

## B17. Decisões em aberto

1. **Engine:** Godot 4 (recomendado, export web) ou stack web (TypeScript)?
2. **Tamanho da equipe** e habilidades (define corte de escopo).
3. **Multiplayer:** hot-seat basta no MVP? (recomendado: sim)
4. **Idioma principal:** inglês (recomendado) com português secundário?
5. **Arte:** estilo blueprint 2D (recomendado) ou algo mais ilustrado?
6. **Nome final:** MARGIN, ou outro?
7. **Evento local:** participar de um evento presencial/virtual perto de você ou do Universal Event online?
