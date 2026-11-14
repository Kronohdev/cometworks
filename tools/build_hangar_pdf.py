"""Builds docs/Hangar_Catalogo_de_Pecas.pdf from the catalog, the hangar math and the voxel renders.

Usage: python tools/build_hangar_pdf.py
Inputs: tools/parts_catalog.py, tools/hangar_calc.py, docs/hangar_renders/*.png
"""
import io
import math
from datetime import date
from pathlib import Path

from PIL import Image as PILImage
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import cm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (Image, KeepTogether, PageBreak, Paragraph, SimpleDocTemplate, Spacer, Table,
                                TableStyle, Preformatted)

import hangar_calc
import parts_catalog as pc

ROOT = Path(__file__).resolve().parent.parent
RENDERS = ROOT / "docs" / "hangar_renders"
SHEETS = ROOT / "docs" / "voxel_renders"
OUT = ROOT / "docs" / "Hangar_Catalogo_de_Pecas.pdf"

pdfmetrics.registerFont(TTFont("UI", "C:/Windows/Fonts/segoeui.ttf"))
pdfmetrics.registerFont(TTFont("UI-B", "C:/Windows/Fonts/segoeuib.ttf"))
pdfmetrics.registerFont(TTFont("UI-L", "C:/Windows/Fonts/segoeuisl.ttf"))
pdfmetrics.registerFont(TTFont("Mono", "C:/Windows/Fonts/consola.ttf"))
pdfmetrics.registerFontFamily("UI", normal="UI", bold="UI-B", italic="UI-L", boldItalic="UI-B")

NAVY = colors.HexColor("#0E1A33")
ACCENT = colors.HexColor("#E8A33A")
CYAN = colors.HexColor("#2C7DA0")
LIGHT = colors.HexColor("#EEF2F7")
GRID = colors.HexColor("#C9D3E0")
MUTED = colors.HexColor("#5B6677")

ST = {
    "title": ParagraphStyle("title", fontName="UI-B", fontSize=26, leading=31, textColor=NAVY),
    "subtitle": ParagraphStyle("subtitle", fontName="UI", fontSize=13, leading=18, textColor=MUTED),
    "h1": ParagraphStyle("h1", fontName="UI-B", fontSize=18, leading=23, textColor=NAVY, spaceBefore=6, spaceAfter=8),
    "h2": ParagraphStyle("h2", fontName="UI-B", fontSize=13, leading=17, textColor=CYAN, spaceBefore=10, spaceAfter=5),
    "h3": ParagraphStyle("h3", fontName="UI-B", fontSize=10.5, leading=14, textColor=NAVY, spaceBefore=6, spaceAfter=3),
    "body": ParagraphStyle("body", fontName="UI", fontSize=9.5, leading=13.5, spaceAfter=5),
    "small": ParagraphStyle("small", fontName="UI", fontSize=8, leading=10.5, textColor=MUTED),
    "cell": ParagraphStyle("cell", fontName="UI", fontSize=8, leading=10.2),
    "cellb": ParagraphStyle("cellb", fontName="UI-B", fontSize=8, leading=10.2),
    "hcell": ParagraphStyle("hcell", fontName="UI-B", fontSize=8, leading=10.2, textColor=colors.white),
    "formula": ParagraphStyle("formula", fontName="UI-B", fontSize=11, leading=16, alignment=TA_CENTER,
                              textColor=NAVY, spaceBefore=4, spaceAfter=6),
    "code": ParagraphStyle("code", fontName="Mono", fontSize=7.6, leading=9.6, textColor=colors.HexColor("#1D2B45")),
    "bullet": ParagraphStyle("bullet", fontName="UI", fontSize=9.5, leading=13.5, leftIndent=12, bulletIndent=2,
                             spaceAfter=2),
}

SRC_LABEL = {
    "ref": "dado público",
    "approx": "aprox. de dado público",
    "derived": "derivado (geometria × densidade)",
    "game": "valor de jogo",
}


def P(text, style="body"):
    return Paragraph(text, ST[style])


def bullets(items):
    return [Paragraph(t, ST["bullet"], bulletText="•") for t in items]


def table(rows, widths, header=True, zebra=True, font_cells=True):
    data = []
    for i, r in enumerate(rows):
        st = "hcell" if (header and i == 0) else "cell"
        data.append([c if not isinstance(c, str) else Paragraph(c, ST[st]) for c in r] if font_cells else r)
    t = Table(data, colWidths=widths, repeatRows=1 if header else 0)
    style = [
        ("GRID", (0, 0), (-1, -1), 0.4, GRID),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (-1, -1), 4),
        ("RIGHTPADDING", (0, 0), (-1, -1), 4),
        ("TOPPADDING", (0, 0), (-1, -1), 3),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
    ]
    if header:
        style.append(("BACKGROUND", (0, 0), (-1, 0), NAVY))
    if zebra:
        for i in range(1 if header else 0, len(rows)):
            if i % 2 == 0:
                style.append(("BACKGROUND", (0, i), (-1, i), LIGHT))
    t.setStyle(TableStyle(style))
    return t


_THUMBS = {}


def thumb(model, max_w=2.5 * cm, max_h=3.3 * cm):
    """Catalog card picture: the render downscaled to ~220 dpi at card size (keeps the PDF small)."""
    p = RENDERS / f"{model}.png"
    if not p.exists():
        return P("(sem render)", "small")
    if model not in _THUMBS:
        im = PILImage.open(p).convert("RGB")
        im.thumbnail((int(max_w / 72 * 220), int(max_h / 72 * 220)), PILImage.LANCZOS)
        buf = io.BytesIO()
        im.save(buf, "JPEG", quality=90)
        _THUMBS[model] = (buf.getvalue(), im.size)
    data, (w, h) = _THUMBS[model]
    s = min(max_w / w, max_h / h)
    return Image(io.BytesIO(data), width=w * s, height=h * s)


def image_fit(path, max_w, max_h):
    w, h = PILImage.open(path).size
    s = min(max_w / w, max_h / h)
    return Image(str(path), width=w * s, height=h * s)


def fmt(v, nd=0):
    if v is None:
        return "—"
    if isinstance(v, (int, float)):
        s = f"{v:,.{nd}f}".replace(",", "X").replace(".", ",").replace("X", ".")
        return s
    return str(v)


def on_page(canvas, doc):
    canvas.saveState()
    if doc.page > 1:
        canvas.setFillColor(NAVY)
        canvas.rect(0, A4[1] - 0.9 * cm, A4[0], 0.9 * cm, fill=1, stroke=0)
        canvas.setFillColor(colors.white)
        canvas.setFont("UI-B", 8.5)
        canvas.drawString(1.6 * cm, A4[1] - 0.58 * cm, "MARGIN · Hangar — Catálogo de Peças e Sistema de Construção")
        canvas.setFont("UI", 8.5)
        canvas.drawRightString(A4[0] - 1.6 * cm, A4[1] - 0.58 * cm, "NASA Space Apps Challenge 2026")
        canvas.setFillColor(MUTED)
        canvas.setFont("UI", 8)
        canvas.drawRightString(A4[0] - 1.6 * cm, 0.9 * cm, f"{doc.page}")
        canvas.drawString(1.6 * cm, 0.9 * cm, "Valores de jogo calibrados em ordem de grandeza real · ver legenda de fontes (§1.6)")
    canvas.restoreState()


# =================================================================== sections
def cover(story):
    story.append(Spacer(1, 1.2 * cm))
    story.append(P("MARGIN", "subtitle"))
    story.append(P("Hangar: Catálogo de Peças e Sistema de Construção de Foguetes", "title"))
    story.append(Spacer(1, 0.3 * cm))
    story.append(P("Space Mission Design Game · NASA Space Apps Challenge 2026 · documento de planejamento "
                   f"(versão 1, {date.today().strftime('%d/%m/%Y')})", "subtitle"))
    story.append(Spacer(1, 0.6 * cm))
    story.append(image_fit(SHEETS / "0_montados.png", 17.5 * cm, 13.5 * cm))
    story.append(Spacer(1, 0.3 * cm))
    story.append(P("Renders reais do Godot 4.6 dos modelos voxel gerados proceduralmente: lançador pequeno "
                   "<b>Andorinha</b>, lançador médio <b>Condor</b> (≈70 m, escala real) e um satélite montado "
                   "com peças do catálogo.", "small"))
    story.append(PageBreak())


def toc(story):
    story.append(P("Conteúdo", "h1"))
    items = [
        "1. Bases científicas: as equações que o hangar calcula",
        "2. Sistema de construção do hangar",
        f"3. Catálogo de peças ({len(pc.PARTS)} peças em {len(pc.CATEGORIES)} categorias, "
        f"{len(pc.EXPANSION_IDS)} novas na expansão v2)",
        "4. Foguetes de validação: o catálogo reproduz lançadores reais?",
        "5. Modelos voxel: regras, desempenho e limitações",
        "6. Próximos passos e decisões em aberto",
        "7. Referências",
    ]
    story += bullets(items)
    story.append(Spacer(1, 0.4 * cm))
    story.append(P("Como ler este documento", "h2"))
    story.append(P("Este é o plano do hangar <b>antes</b> de criar o projeto Godot. Todos os números vêm de um único "
                   "arquivo de dados (<font face='Mono'>data/parts.json</font>, gerado por "
                   "<font face='Mono'>tools/parts_catalog.py</font>). A calculadora de referência "
                   "(<font face='Mono'>tools/hangar_calc.py</font>) produz as tabelas da seção 4. A versão Godot "
                   "precisa reproduzir esses mesmos números e vai usá-los como testes de regressão."))
    story.append(P("Os nomes das peças são bilíngues (EN/PT) desde o início, porque o jogo será lançado nos dois "
                   "idiomas ao mesmo tempo. As peças têm nomes genéricos e são <i>inspiradas</i> em hardware real, "
                   "sem usar marcas como nome de peça."))
    story.append(PageBreak())


def science(story):
    g0 = pc.G0
    story.append(P("1. Bases científicas", "h1"))
    story.append(P("O hangar não é só um editor 3D. Ele é uma calculadora de engenharia que mostra ao jogador, a cada "
                   "peça encaixada, o efeito no desempenho. Esta seção lista exatamente o que é calculado."))

    story.append(P("1.1 Equação do foguete (Tsiolkovsky)", "h2"))
    story.append(P("Δv = I<sub>sp</sub> · g<sub>0</sub> · ln( m<sub>0</sub> / m<sub>f</sub> )", "formula"))
    story += bullets([
        "<b>Δv</b>: variação de velocidade que o estágio consegue produzir (m/s). É a \"moeda\" das missões.",
        "<b>I<sub>sp</sub></b>: impulso específico (s), a eficiência do motor. Pela definição da NASA Glenn, "
        "I<sub>sp</sub> = empuxo / (vazão de propelente × g<sub>0</sub>). A velocidade efetiva de exaustão é "
        "v<sub>e</sub> = I<sub>sp</sub> · g<sub>0</sub>.",
        f"<b>g<sub>0</sub></b> = {str(g0).replace('.', ',')} m/s² (gravidade padrão, constante de conversão).",
        "<b>m<sub>0</sub></b>: massa no início da queima. <b>m<sub>f</sub></b>: massa no fim (sem o propelente queimado).",
        "O exemplo da NASA Glenn: um motor LOX/LH<sub>2</sub> com I<sub>sp</sub> ~350 s precisa de razão de massa ~10 "
        "para chegar a uma órbita de ~320 km. É por isso que foguetes são quase só tanque.",
    ])
    story.append(P("1.2 Grandezas derivadas que o hangar mostra", "h2"))
    story.append(table([
        ["Grandeza", "Fórmula", "Por que importa no jogo"],
        ["Vazão de massa", "ṁ = F / (I<sub>sp</sub> · g<sub>0</sub>)", "Define quanto tempo o estágio queima."],
        ["Tempo de queima", "t = m<sub>prop</sub> / ṁ", "Queimas longas aumentam as perdas por gravidade."],
        ["TWR (empuxo/peso)", "TWR = F / (m · g<sub>0</sub>)", "Na decolagem precisa ser > 1 (recomendado 1,2–2,0). "
         "Estágios superiores podem ter TWR < 1."],
        ["I<sub>sp</sub> combinado", "I<sub>sp,ef</sub> = ΣF / Σ(F / I<sub>sp</sub>)", "Vários motores diferentes "
         "queimando juntos (núcleo + boosters)."],
        ["Propelente do tanque", "m<sub>prop</sub> = V · ρ<sub>bulk</sub>,  V = π·d²/4·L·0,90",
         "Tanques são gerados pela geometria (90% de enchimento)."],
        ["Massa seca do tanque", "m<sub>seca</sub> = k<sub>prop</sub> · m<sub>prop</sub>",
         "Hidrogênio é leve e volumoso: o tanque pesa proporcionalmente mais."],
        ["Δv de subida (estimativa)", "estágio 1: média de Δv<sub>NM</sub> e Δv<sub>vácuo</sub>; demais: vácuo",
         "Aproximação simples para o jogador comparar com os ~9,4 km/s até a LEO."],
    ], [3.4 * cm, 6.2 * cm, 7.9 * cm]))

    story.append(P("1.3 Por que estágios?", "h2"))
    story.append(P("Como Δv depende do <i>logaritmo</i> da razão de massa, carregar tanques vazios até a órbita é "
                   "desperdício. Ao descartar a estrutura de um estágio, o próximo começa com uma razão de massa "
                   "nova. O hangar mostra isso de forma visível: o jogador vê o Δv total crescer ao dividir um "
                   "foguete em dois estágios com a mesma quantidade de propelente."))

    story.append(P("1.4 Propelentes", "h2"))
    isp_typ = {"kerolox": "282 / 311–348", "methalox": "327 / 350", "hydrolox": "366 / 452–465",
               "hypergolic": "— / 316", "hydrazine": "— / 202–236", "xenon": "— / 1.600–4.190", "solid": "242 / 268",
               "lh2": "— / 875–900 (térmico nuclear)"}
    rows = [["Propelente", "Densidade bulk (kg/m³)", "I<sub>sp</sub> típico NM / vácuo (s)", "Armazenável?",
             "Evaporação (jogo)", "k tanque (jogo)"]]
    for k, v in pc.PROPELLANTS.items():
        rows.append([v["name"]["pt"], f"{fmt(v['density'])} ({SRC_LABEL[v['density_src']]})", isp_typ[k],
                     "sim" if v["storable"] else "não (criogênico)", f"{v['boiloff_pct_day']}%/dia",
                     "integrado" if v["tank_dry_fraction"] is None else f"{v['tank_dry_fraction']:.3f}"])
    story.append(table(rows, [3.4 * cm, 3.4 * cm, 3.0 * cm, 2.6 * cm, 2.3 * cm, 2.8 * cm]))
    story.append(P("As densidades bulk de querosene, metano e hidrogênio seguem a tabela de Bruce Dunn (NSS), na "
                   "mistura típica de cada um. Os trade-offs que o jogo ensina: hidrogênio tem o melhor I<sub>sp</sub> "
                   "químico mas densidade bulk muito baixa, o que pede tanques enormes e evapora em órbita. Querosene "
                   "é denso e barato. Metano fica no meio. Hipergólicos acendem por contato e duram anos no espaço, o "
                   "que os torna ideais para espaçonaves.", "small"))

    story.append(P("1.5 Mapa de Δv (valores aproximados)", "h2"))
    rows = [["De → Para", "Δv (km/s)", "Observação"]]
    for d in pc.DELTA_V_MAP:
        a, b, v, lbl = d
        rows.append([f"{a} → {b}", fmt(v, 2), lbl["pt"]])
    story.append(table(rows, [4.6 * cm, 2.0 * cm, 10.9 * cm]))
    story.append(P("Os ~9,4 km/s até a LEO incluem ~1,5–2 km/s de perdas por gravidade, arrasto e direcionamento "
                   "acima da velocidade orbital (~7,8 km/s). Os valores interplanetários dependem da janela e da "
                   "trajetória. O jogo usa estes números como <i>requisitos</i> de missão.", "small"))

    story.append(P("1.6 Energia e comunicação (resumo para as peças da espaçonave)", "h2"))
    story += bullets([
        "Fluxo solar em 1 UA: 1.361 W/m². Painéis geram P = A · η · 1361 / d² (d em UA), com η ≈ 0,28 "
        "(células de tripla junção de 27–30%). Em Marte rende ~43% do que rende na Terra.",
        "Painel enrolável (classe ROSA): 100–120 W/kg (Redwire). Asa rígida: ~40 W/kg. Painel de corpo: ~25 W/kg (jogo).",
        "RTG (classe MMRTG): ~110 W no início de vida, ~45 kg. Funciona longe do Sol e perde potência com os anos.",
        "Bateria de íons de lítio: ~100–150 Wh/kg no nível de bateria (aprox.). O jogo usa 120 Wh/kg.",
        "Taxa de dados cai com o quadrado da distância. Antenas maiores e mais precisas compensam (GDD §B3).",
    ])
    story.append(P("Legenda das fontes de cada valor", "h3"))
    story.append(table([
        ["Rótulo", "Significado"],
        ["dado público", "Valor publicado do hardware de referência (ex.: RL10B-2: 110,1 kN, 465,5 s, 301 kg)."],
        ["aprox. de dado público", "Ordem de grandeza de dados públicos que variam entre fontes; arredondado."],
        ["derivado", "Calculado pelas fórmulas acima (ex.: massa de propelente = volume × densidade)."],
        ["valor de jogo", "Escolhido para balanceamento, mantendo a ordem de grandeza real."],
    ], [4.0 * cm, 13.5 * cm]))
    story.append(PageBreak())


def hangar_system(story):
    story.append(P("2. Sistema de construção do hangar", "h1"))
    story.append(P("Inspirado no hangar de montagem do Kerbal Space Program, mas com uma diferença central: cada peça "
                   "tem custo, confiabilidade e consequências na missão (os seis recursos do GDD: massa, energia, "
                   "orçamento, dados, comunicação e tempo)."))

    story.append(P("2.1 Fluxo de construção", "h2"))
    story.append(table([
        ["Etapa", "O que o jogador faz", "Saída"],
        ["1. Baia da espaçonave", "Monta a espaçonave: bus, instrumentos, energia, comunicação, propulsão própria.",
         "Massa e envelope da carga útil, Δv próprio, consumo de energia, dados/dia."],
        ["2. Baia do lançador", "Monta o foguete: tanques, motores, desacopladores, boosters, coifa.",
         "Δv por estágio, TWR, tempo de queima, custo."],
        ["3. Integração", "Encaixa a espaçonave no adaptador de carga dentro da coifa.",
         "Checagem: cabe na coifa? O Δv total atinge o requisito da missão?"],
        ["4. Revisão (Design Review)", "Semáforo de validação (ver 2.7). Em equipe, cada papel aprova.",
         "Liberação para lançamento."],
        ["5. Lançamento", "Voo com física real (Jolt) e eventos de estágio.", "Telemetria e resultados para o Debrief."],
    ], [3.3 * cm, 7.6 * cm, 6.6 * cm]))

    story.append(P("2.2 Árvore de peças e nós de encaixe", "h2"))
    story += bullets([
        "O veículo é uma <b>árvore</b>. A raiz é sempre um <b>Núcleo de Aviônica</b> (ou o bus da espaçonave na baia 1). "
        "Cada peça tem um único pai.",
        "<b>Nós de pilha</b> (topo/base) ligam peças no eixo. Só encaixam se a <b>classe de diâmetro</b> for igual. "
        "Para mudar de diâmetro, use um <b>Adaptador</b>.",
        "<b>Encaixe radial</b>: peças marcadas como radiais (boosters com desacoplador radial, aletas, painéis, antenas) "
        "grudam na superfície lateral do pai.",
        "Cada peça também guarda <b>massa, centro de massa local, forma de colisão</b> (convexa simples) e "
        "<b>resistência da junta</b> (para a física de destruição).",
    ])
    rows = [["Classe", "Diâmetro do nó", "Uso típico"]]
    uso = {"XS": "Propulsores, esferas de espaçonave, peças radiais", "S": "Lançador pequeno (classe Electron), estágios superiores",
           "M": "Lançador médio, estágio superior hidrolox, cápsula", "L": "Primeiro estágio de lançador médio/pesado"}
    for k, v in pc.SIZE_CLASSES.items():
        rows.append([k, f"{fmt(v, 3)} m", uso[k]])
    story.append(table(rows, [2.0 * cm, 3.0 * cm, 12.5 * cm]))

    story.append(P("2.3 Simetria", "h2"))
    story.append(P("Peças radiais podem ser colocadas com simetria 1×, 2×, 3×, 4×, 6× ou 8× ao redor do eixo do pai. "
                   "As <b>Placas de Empuxo</b> têm posições fixas para motores (ex.: 9 = 8 em anel + 1 central, como "
                   "nos lançadores reais). Um clique preenche todas as posições."))

    story.append(P("2.4 Fluxo de propelente", "h2"))
    story += bullets([
        "Um motor puxa propelente dos tanques <b>conectados por nós de pilha acima dele, até o próximo desacoplador</b>. "
        "O desacoplador é a fronteira do estágio.",
        "O tipo de propelente precisa ser compatível (motor a querosene só usa tanque de querosene/LOX).",
        "Boosters sólidos têm propelente integrado: <b>não desligam nem aceleram</b>.",
        "Propelentes criogênicos <b>evaporam</b> durante missões longas (taxa por dia na tabela 1.4). "
        "Por isso o estágio de transferência de uma missão a Marte prefere hipergólicos.",
        "Opção avançada (fase 2): <i>crossfeed</i> entre boosters e núcleo.",
    ])

    story.append(P("2.5 Estágios e eventos", "h2"))
    story += bullets([
        "O hangar gera a <b>lista de estágios automaticamente</b>: motores mais baixos disparam primeiro, cada "
        "desacoplador cria um novo evento e a coifa é descartada no início do estágio 2.",
        "O jogador pode arrastar eventos entre estágios. Eventos possíveis: <i>acender motores, desacoplar, "
        "descartar coifa, abrir painéis/antenas, separar espaçonave</i>.",
        "Boosters laterais acendem com o núcleo e são descartados automaticamente quando esvaziam.",
    ])

    story.append(P("2.6 Leituras de engenharia (atualizam a cada peça)", "h2"))
    story.append(table([
        ["Leitura", "Detalhe"],
        ["Por estágio", "Massa inicial, Δv ao nível do mar e no vácuo, TWR inicial, tempo de queima, custo."],
        ["Total", "Δv de subida estimado vs. requisito da missão (ex.: LEO 9,4 km/s; +3,1 km/s para TLI)."],
        ["Marcadores 3D", "Centro de massa (CoM), centro de empuxo (CoT) e centro de pressão (CoP). "
                          "Estável quando o CoP fica atrás do CoM; o empuxo precisa passar pelo CoM."],
        ["Custos e risco", "Custo total, confiabilidade composta (produto das confiabilidades) e número de motores "
                           "(mais motores = mais chance de falha, mas permite perder um motor)."],
        ["Efeito dominó", "Ao trocar uma peça, o painel lista a cadeia: +200 kg de carga → −310 m/s de Δv → "
                          "TWR do 2º estágio cai para 0,62 (ligação direta com o GDD)."],
    ], [3.4 * cm, 14.1 * cm]))

    story.append(P("2.7 Regras de validação", "h2"))
    story.append(table([
        ["Tipo", "Regra", "Mensagem (PT / EN)"],
        ["Erro", "Sem núcleo de aviônica", "Nenhum computador de voo / No flight computer"],
        ["Erro", "Nós com classes de diâmetro diferentes (motores encaixam em qualquer nó, como no KSP)", "Use um adaptador / Use an adapter"],
        ["Erro", "Motor sem propelente compatível no estágio", "Motor sem combustível / Engine has no fuel"],
        ["Erro", "TWR de decolagem < 1,0", "O foguete não sai da plataforma / Rocket can't lift off"],
        ["Erro", "Carga não cabe na coifa (diâmetro interno)", "Carga maior que a coifa / Payload too wide"],
        ["Aviso", "TWR de decolagem entre 1,0 e 1,2", "Perdas por gravidade altas / High gravity losses"],
        ["Aviso", "Δv abaixo do requisito + 5% de margem", "Margem de Δv baixa / Low Δv margin"],
        ["Aviso", "Peça frágil exposta fora da coifa (painel, antena)", "Vai quebrar no Max-Q / Will break at Max-Q"],
        ["Aviso", "CoP à frente do CoM sem gimbal suficiente", "Foguete instável / Unstable rocket"],
        ["Aviso", "Estágio superior criogênico em missão > 30 dias", "Propelente vai evaporar / Boil-off"],
    ], [1.4 * cm, 7.4 * cm, 8.7 * cm]))

    story.append(P("2.8 Física de voo e destruição", "h2"))
    story += bullets([
        "No voo, cada peça vira um corpo rígido com forma convexa simples, ligado ao pai por uma junta com "
        "<b>força máxima</b> (N), <b>aceleração máxima</b> (g), <b>velocidade de impacto</b> (m/s) e "
        "<b>temperatura máxima</b>.",
        "Quando uma junta quebra, a peça se solta. Se ela é destruída, o modelo voxel vira de 200 a 400 blocos de "
        "detrito (voxels agrupados em 2×2×2), com vida curta.",
        "Orçamento medido no teste com Jolt (desktop): 500 corpos ≈ 1,5 ms/passo; 1.000 ≈ 6 ms; 2.000 ≈ 16 ms; "
        "4.000 ≈ 33 ms. Limite de projeto: <b>≤ 1.000 detritos ativos</b> no executável.",
    ])

    story.append(P("2.9 Interface do hangar", "h2"))
    story.append(Preformatted(
        "┌───────────────┬────────────────────────────────────────┬────────────────────┐\n"
        "│ CATEGORIAS    │                                        │ ESTÁGIOS           │\n"
        "│ ▸ Comando     │            vista 3D orbital            │  S3 ▸ separar sat  │\n"
        "│ ▸ Tanques     │         (girar / zoom / encaixe)       │  S2 ▸ coifa, MVac  │\n"
        "│ ▸ Motores     │                                        │  S1 ▸ 9× Falcão-1  │\n"
        "│ ▸ Estrutura   │            ● CoM  ▲ CoT  ■ CoP         │                    │\n"
        "│ ▸ Aerodinâm.  │                                        ├────────────────────┤\n"
        "│ ▸ Energia ... │                                        │ Δv  9.767 / 9.400  │\n"
        "│ [busca]       │                                        │ TWR 1,32  $ 61 M   │\n"
        "├───────────────┴────────────────────────────────────────┤ ⚠ margem Δv 3,9%   │\n"
        "│ EFEITO DOMINÓ: +Falcão-1V → +550 kg → Δv S2 +412 m/s   │ [EN | PT]          │\n"
        "└────────────────────────────────────────────────────────┴────────────────────┘",
        ST["code"]))

    story.append(P("2.10 Modelo de dados (trecho de data/parts.json)", "h2"))
    eng = pc.by_id()["eng_hidra_rl"]
    snippet = ("{\n"
               f'  "id": "{eng["id"]}", "category": "engine", "model": "{eng["model"]}",\n'
               f'  "name": {{"en": "{eng["name"]["en"]}", "pt": "{eng["name"]["pt"]}"}},\n'
               f'  "propellant": "hydrolox", "size": "S",\n'
               f'  "thrust_vac_kn": {eng["thrust_vac_kn"]}, "isp_vac_s": {eng["isp_vac_s"]}, "mass_kg": {eng["mass_kg"]},\n'
               f'  "gimbal_deg": {eng["gimbal_deg"]}, "restarts": {eng["restarts"]}, "cost_musd": {eng["cost_musd"]},\n'
               f'  "reliability": {eng["reliability"]}, "attach": {{"top": "S", "bottom": null, "radial": false}},\n'
               '  "src": "ref"\n}')
    story.append(Preformatted(snippet, ST["code"]))

    story.append(P("2.11 Algoritmo de cálculo do Δv (referência)", "h2"))
    story.append(Preformatted(
        "para cada estágio i (ordem de disparo):\n"
        "    m = carga + coifa(se i < estágio_coifa) + massa de todos os estágios acima + estágio i + boosters\n"
        "    enquanto houver propelente no núcleo ou em algum booster:\n"
        "        para cada grupo ativo:  ṁ = F/(Isp·g0);  queima = ṁ·dt;  m -= queima\n"
        "        Δv += ΣF/m · dt\n"
        "        booster vazio -> descarta sua massa seca imediatamente\n"
        "    descarta massa seca do estágio i\n"
        "(roda duas vezes: empuxo/Isp ao nível do mar e no vácuo; dt = 0,25 s)",
        ST["code"]))
    story.append(PageBreak())


def part_stats(p):
    rows = []
    add = lambda k, v: rows.append(f"<b>{k}:</b> {v}")
    if p["category"] == "engine":
        if p.get("thrust_sl_kn"):
            add("Empuxo NM / vácuo", f"{fmt(p['thrust_sl_kn'], 1)} / {fmt(p['thrust_vac_kn'], 1)} kN")
            add("Isp NM / vácuo", f"{fmt(p['isp_sl_s'])} / {fmt(p['isp_vac_s'])} s")
        else:
            t = p["thrust_vac_kn"]
            add("Empuxo vácuo", f"{fmt(t * 1000, 1)} N" if t < 1 else f"{fmt(t, 1)} kN")
            add("Isp vácuo", f"{fmt(p['isp_vac_s'])} s")
        add("Massa", f"{fmt(p['mass_kg'], 1 if p['mass_kg'] < 10 else 0)} kg")
        twr = p["thrust_vac_kn"] * 1000 / (p["mass_kg"] * pc.G0)
        add("TWR do motor (vácuo)", fmt(twr, 1 if twr < 10 else 0))
        if p.get("prop_mass_kg"):
            add("Propelente integrado", f"{fmt(p['prop_mass_kg'])} kg")
        add("Gimbal / reignições", f"{p['gimbal_deg']}° / {'ilimitadas' if p['restarts'] >= 999 else p['restarts']}")
        if p.get("throttle_min", 1.0) < 1.0:
            add("Aceleração mínima", f"{p['throttle_min'] * 100:.0f}%")
        if p.get("flag"):
            add("Atenção", p["flag"]["pt"])
        if p.get("power_w"):
            add("Energia", f"{fmt(p['power_w'])} W")
    else:
        if "prop_mass_kg" in p and p["category"] == "tank":
            add("Propelente", f"{fmt(p['prop_mass_kg'], 1)} kg ({pc.PROPELLANTS[p['propellant']]['name']['pt']})")
        add("Massa" + (" seca" if p["category"] == "tank" else ""), f"{fmt(p['mass_kg'], 1 if p['mass_kg'] < 10 else 0)} kg")
        for key, label, unit, nd in (("power_w", "Consumo", "W", 0), ("power_gen_w_1au", "Geração em 1 UA", "W", 0),
                                     ("capacity_wh", "Capacidade", "Wh", 0), ("data_gbit_day", "Dados", "Gbit/dia", 1),
                                     ("rate_ref_mbps_moon", "Taxa ref. (Lua)", "Mbps", 2),
                                     ("payload_capacity_kg", "Carga útil máx.", "kg", 0),
                                     ("instrument_slots", "Posições de instrumento", "", 0),
                                     ("engine_slots", "Posições de motor", "", 0),
                                     ("inner_diameter_m", "Diâmetro interno", "m", 1), ("heat_reject_w", "Rejeição de calor", "W", 0),
                                     ("area_m2", "Área", "m²", 1), ("specific_power_w_kg", "Potência específica", "W/kg", 0),
                                     ("crew_seats", "Tripulantes (assentos)", "", 0),
                                     ("life_support_days", "Suporte de vida", "dias", 1),
                                     ("pressurized_m3", "Volume pressurizado", "m³", 0),
                                     ("momentum_nms", "Momento angular", "N·m·s", 2), ("torque_nm", "Torque", "N·m", 3),
                                     ("thrust_vac_kn", "Empuxo (RCS)", "kN", 3), ("isp_vac_s", "Isp (RCS)", "s", 0),
                                     ("abort_thrust_kn", "Empuxo de abortagem", "kN", 0),
                                     ("canopy_diameter_m", "Diâmetro do velame", "m", 0),
                                     ("deploy_alt_km", "Altitude de abertura", "km", 1),
                                     ("max_entry_kms", "Reentrada máx.", "km/s", 0),
                                     ("relay_rate_mbps", "Retransmissão", "Mbps", 1),
                                     ("reactant_kg_per_kwh", "Reagentes", "kg/kWh", 2),
                                     ("separation_speed_ms", "Velocidade de separação", "m/s", 1),
                                     ("length_m", "Comprimento", "m", 1)):
            if p.get(key):
                add(label, f"{fmt(p[key], nd)} {unit}".strip())
        if p.get("capabilities"):
            add("Capacidade científica", ", ".join(f"{k} {v:.1f}" for k, v in p["capabilities"].items()))
    add("Custo", f"US$ {fmt(p['cost_musd'], 2)} M")
    if p.get("reliability"):
        add("Confiabilidade", f"{p['reliability'] * 100:.1f}%")
    if p.get("size"):
        add("Classe", p["size"])
    return "<br/>".join(rows)


def part_card(p):
    name = f"<b>{p['name']['pt']}</b><br/><font color='#5B6677'>{p['name']['en']}</font>"
    desc = f"{p['desc']['pt']}<br/><font color='#5B6677'><i>{p['desc']['en']}</i></font>"
    ref = ""
    if p.get("ref"):
        ref = f"<br/><font color='#2C7DA0'><b>Referência:</b> {p['ref']['pt']}</font>"
    src = f"<br/><font color='#5B6677' size='7'>Fonte dos valores: {SRC_LABEL.get(p.get('src', 'game'))}" \
          f"{' · FASE 2' if p.get('phase') == 2 else ''}{' · NOVA (v2)' if p.get('added') == 'v2' else ''}"           f" · id: {p['id']}</font>"
    t = Table([[thumb(p["model"]), Paragraph(name + "<br/>" + desc + ref + src, ST["cell"]),
                Paragraph(part_stats(p), ST["cell"])]],
              colWidths=[2.8 * cm, 8.2 * cm, 6.5 * cm])
    t.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "TOP"), ("LINEBELOW", (0, 0), (-1, -1), 0.4, GRID),
                           ("ALIGN", (0, 0), (0, 0), "CENTER"), ("TOPPADDING", (0, 0), (-1, -1), 4),
                           ("BOTTOMPADDING", (0, 0), (-1, -1), 6)]))
    return t


def catalog(story):
    story.append(P("3. Catálogo de peças", "h1"))
    counts = {}
    for p in pc.PARTS:
        counts[p["category"]] = counts.get(p["category"], 0) + 1
    story.append(P(f"{len(pc.PARTS)} peças no total. Tanques de lançador são famílias geradas por diâmetro × comprimento "
                   "(tabela de variantes); as demais peças aparecem uma a uma. Cada imagem é o render real do modelo voxel."))
    story.append(table([["Categoria", "PT", "EN", "Peças"]] +
                       [[k, v["pt"], v["en"], str(counts.get(k, 0))] for k, v in pc.CATEGORIES.items()],
                       [2.6 * cm, 6.0 * cm, 6.0 * cm, 2.9 * cm]))
    expansion_summary(story)
    for cat, label in pc.CATEGORIES.items():
        items = [p for p in pc.PARTS if p["category"] == cat]
        if not items:
            continue
        story.append(PageBreak())
        story.append(P(f"3.{list(pc.CATEGORIES).index(cat) + 1} {label['pt']} <font color='#5B6677' size='11'>"
                       f"· {label['en']}</font>", "h2"))
        if cat == "tank":
            fams = {}
            for p in items:
                fams.setdefault(p["family"], []).append(p)
            for fam, ps in fams.items():
                first = ps[0]
                if fam in ("tank_kerolox", "tank_methalox", "tank_hydrolox"):
                    prop = pc.PROPELLANTS[first["propellant"]]
                    head = Table([[thumb(first["model"]),
                                   Paragraph(f"<b>Família: Tanque {prop['name']['pt']}</b><br/>"
                                             f"<font color='#5B6677'>{prop['name']['en']} tank family</font><br/>"
                                             f"Densidade bulk {fmt(prop['density'])} kg/m³ · massa seca = "
                                             f"{prop['tank_dry_fraction']:.3f} × propelente · enchimento 90%. "
                                             f"Evaporação em órbita: {prop['boiloff_pct_day']}%/dia (jogo).<br/>"
                                             f"<font color='#5B6677' size='7'>Fonte dos valores: derivado "
                                             f"(geometria × densidade)</font>", ST["cell"])]],
                                 colWidths=[2.8 * cm, 14.7 * cm])
                    head.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "TOP")]))
                    rows = [["id", "Classe", "Comprimento", "Volume", "Propelente", "Massa seca", "Custo"]]
                    for p in ps:
                        rows.append([p["id"], p["size"], f"{fmt(p['length_m'])} m", f"{fmt(p['volume_m3'], 1)} m³",
                                     f"{fmt(p['prop_mass_kg'])} kg", f"{fmt(p['mass_kg'])} kg",
                                     f"US$ {fmt(p['cost_musd'], 2)} M"])
                    story.append(KeepTogether([head, Spacer(1, 3),
                                               table(rows, [3.7 * cm, 1.5 * cm, 2.2 * cm, 2.3 * cm, 2.8 * cm, 2.5 * cm,
                                                            2.5 * cm]), Spacer(1, 8)]))
                else:
                    for p in ps:
                        story.append(part_card(p))
        else:
            for p in items:
                story.append(part_card(p))


def key_spec(p):
    """One-line headline spec for the v2 summary table."""
    if p["category"] == "engine":
        t = p["thrust_vac_kn"]
        f = (f"{fmt(t * 1e6, 0)} mN" if t < 0.001 else f"{fmt(t * 1000, 0)} N" if t < 1 else f"{fmt(t, 0)} kN")
        return f"{f} vácuo · Isp {fmt(p['isp_vac_s'])} s · {fmt(p['mass_kg'], 1 if p['mass_kg'] < 10 else 0)} kg"
    if p["category"] == "tank":
        return f"{fmt(p['prop_mass_kg'])} kg de {pc.PROPELLANTS[p['propellant']]['name']['pt']}"
    bits = []
    for k, lbl, unit in (("crew_seats", "", "lugar(es)"), ("power_gen_w_1au", "", "W"), ("capacity_wh", "", "Wh"),
                         ("heat_reject_w", "rejeita", "W"), ("momentum_nms", "", "N·m·s"),
                         ("rate_ref_mbps_moon", "", "Mbps (Lua)"), ("engine_slots", "", "motores"),
                         ("inner_diameter_m", "interno", "m"), ("canopy_diameter_m", "velame", "m")):
        if p.get(k):
            nd = 0 if float(p[k]).is_integer() or p[k] >= 10 else 1
            bits.append(f"{lbl} {fmt(p[k], nd)} {unit}".strip())
    if p.get("capabilities"):
        bits.append(", ".join(f"{k} {v:.1f}" for k, v in p["capabilities"].items()))
    bits.append(f"{fmt(p['mass_kg'], 1 if p['mass_kg'] < 10 else 0)} kg")
    return " · ".join(bits[:3])


def expansion_summary(story):
    story.append(P("Expansão v2: peças novas", "h2"))
    story.append(P(f"A expansão v2 acrescentou {len(pc.EXPANSION_IDS)} peças com especificações baseadas em hardware real "
                   "(motores de estágio superior, aerospike e térmico nuclear, propulsão Hall, motores de chute, cápsulas de "
                   "1 a 4 lugares com <font face='Mono'>crew_seats</font>, habitats, paraquedas, instrumentos de superfície "
                   "e mais). A coluna Fonte segue a legenda do §1.6; as referências estão no §7."))
    rows = [["id", "Peça (PT)", "Destaque", "Fonte"]]
    byid = pc.by_id()
    for cat in pc.CATEGORIES:
        for pid in pc.EXPANSION_IDS:
            p = byid[pid]
            if p["category"] != cat:
                continue
            rows.append([pid, p["name"]["pt"] + (" (fase 2)" if p.get("phase") == 2 else ""), key_spec(p),
                         SRC_LABEL.get(p.get("src", "game"))])
    story.append(table(rows, [3.6 * cm, 5.2 * cm, 5.9 * cm, 2.8 * cm]))


def validation(story):
    story.append(PageBreak())
    story.append(P("4. Foguetes de validação", "h1"))
    story.append(P("Para confirmar que o catálogo é realista, montamos três foguetes só com peças do catálogo e os "
                   "rodamos na calculadora de referência. O alvo é o Δv até a LEO de ~9,4 km/s. Se os números "
                   "batem com lançadores reais da mesma classe, o balanceamento está na ordem de grandeza certa."))
    P_ = pc.by_id()
    for ex in hangar_calc.EXAMPLES:
        r = hangar_calc.analyze(ex, ex["payload_kg"])
        ok = r["ascent_dv_ms"] >= 9400
        story.append(P(f"{ex['name_pt']} <font color='#5B6677' size='10'>· classe: {ex['inspired']}</font>", "h2"))
        comp = []
        for i, st in enumerate(ex["stages"]):
            items = ", ".join(f"{n}× {P_[pid]['name']['pt']}" for pid, n in st["parts"])
            if st.get("boosters"):
                for g in st["boosters"]:
                    items += "; boosters: " + f"{g['count']}× (" + ", ".join(
                        f"{n}× {P_[pid]['name']['pt']}" for pid, n in g["parts"]) + ")"
            comp.append(f"<b>Estágio {i + 1}:</b> {items}")
        comp.append(f"<b>Coifa:</b> {', '.join(P_[pid]['name']['pt'] for pid, _ in ex['fairing'])} · "
                    f"<b>Carga útil:</b> {fmt(ex['payload_kg'])} kg")
        story += bullets(comp)
        rows = [["Estágio", "Massa inicial", "Δv nível do mar", "Δv vácuo", "TWR inicial", "Tempo de queima"]]
        for s in r["stages"]:
            rows.append([str(s["stage"]), f"{fmt(s['m0_t'], 1)} t", f"{fmt(s['dv_asl_ms'])} m/s", f"{fmt(s['dv_vac_ms'])} m/s",
                         fmt(s["twr_asl"] if s["stage"] == 1 else s["twr0"], 2), f"{fmt(s['burn_s'])} s"])
        rows.append(["<b>Total</b>", f"<b>{fmt(r['liftoff_mass_t'], 1)} t</b>", "", "",
                     f"<b>{fmt(r['liftoff_twr'], 2)}</b>",
                     f"<b>Δv de subida ≈ {fmt(r['ascent_dv_ms'])} m/s {'✓' if ok else '✗'}</b>"])
        story.append(table(rows, [1.6 * cm, 2.6 * cm, 3.0 * cm, 2.6 * cm, 2.4 * cm, 5.3 * cm]))
        story.append(Spacer(1, 4))
    story.append(P("Leitura dos resultados", "h3"))
    story += bullets([
        "<b>Andorinha</b> leva ~300 kg com ~9,3 km/s. É a mesma classe de carga de um lançador pequeno real como o "
        "Electron.",
        "<b>Condor</b> leva 15 t com ~9,7 km/s. Um Falcon 9 descartável leva mais (~22 t), então o Condor fica "
        "conservador, o que é bom para dar margem ao jogador.",
        "<b>Garça</b> leva 9 t com ~10,3 km/s. O estágio superior hidrolox tem TWR 0,37: baixo, mas aceitável no "
        "vácuo. Isso ensina por que estágios Centaur funcionam com pouco empuxo.",
        "Os três passam do alvo sem truques. O catálogo está calibrado; o ajuste fino virá dos playtests.",
    ])


def voxel_section(story):
    story.append(PageBreak())
    story.append(P("5. Modelos voxel", "h1"))
    story.append(P("Todos os modelos são gerados por código (<font face='Mono'>tools/voxel_gen.py</font>), não "
                   "modelados à mão. Isso permite gerar qualquer variante de tanque (diâmetro × comprimento) com o "
                   "mesmo estilo, e mudar o visual de todas as peças de uma vez."))
    story.append(table([
        ["Regra", "Valor", "Motivo"],
        ["Tamanho do voxel do lançador", "5 cm (20 voxels/m)", "Tanque L (3,75 m) com 75 voxels de diâmetro: curvas lisas."],
        ["Tamanho do voxel da espaçonave", "~1,6 cm (64 voxels/m)", "Instrumentos pequenos (10–30 cm) precisam de detalhe."],
        ["Malha", "Só faces expostas + oclusão ambiente por vértice", "Interior sólido não gera triângulos; AO dá profundidade."],
        ["Cor", "Paleta de 24 cores nos vértices", "Um material só para todas as peças; troca de paleta muda o tema."],
        ["Formato", "glTF binário (.glb)", "Importa direto no Godot 4.6 com cor de vértice (testado)."],
    ], [4.4 * cm, 4.6 * cm, 8.5 * cm]))
    story.append(Spacer(1, 6))
    story.append(image_fit(SHEETS / "1_motores.png", 17.5 * cm, 13 * cm))
    story.append(P("Motores e propulsores (render Godot).", "small"))
    story.append(PageBreak())
    story.append(image_fit(SHEETS / "2_tanques_estrutura.png", 17.5 * cm, 11.5 * cm))
    story.append(P("Tanques e estrutura.", "small"))
    story.append(image_fit(SHEETS / "3_espaconave.png", 17.5 * cm, 13 * cm))
    story.append(P("Peças de espaçonave.", "small"))
    story.append(PageBreak())
    story.append(P("Limitações conhecidas", "h2"))
    story += bullets([
        "Motores pequenos (Kestrel, ~0,4 m de bocal) ficam blocados a 5 cm por voxel. Dá para abrir uma exceção de "
        "resolução só para motores, ao custo de misturar tamanhos de voxel no foguete montado.",
        "O Condor em escala real tem ~1,3 milhão de triângulos. Funciona no desktop, mas no jogo vai precisar de "
        "<i>greedy meshing</i> (juntar faces iguais) e LOD para manter o FPS com vários foguetes na cena.",
        "Peças radiais giradas em ângulos que não são múltiplos de 90° são cubos girados (como no KSP). É aceitável "
        "visualmente, mas a destruição desses blocos usa a grade local da peça.",
        "Os renders deste documento são de um projeto de teste. O projeto Godot definitivo ainda não foi criado.",
    ])


def next_steps(story):
    story.append(P("6. Próximos passos e decisões em aberto", "h1"))
    story.append(table([
        ["#", "Passo", "Depende de"],
        ["1", "Criar o projeto Godot (GDScript, executável Windows) com tradução EN/PT desde o primeiro arquivo.", "—"],
        ["2", "Portar a calculadora para GDScript e usar os 3 foguetes da seção 4 como testes automáticos.", "1"],
        ["3", "Hangar v0: paleta de peças, encaixe por nó de pilha, Δv/TWR ao vivo, sem radial.", "1, 2"],
        ["4", "Encaixe radial + simetria + boosters + lista de estágios editável.", "3"],
        ["5", "Validação (2.7) e efeito dominó ligados ao modelo de missão do GDD.", "3"],
        ["6", "Voo com física Jolt e destruição voxel (≤ 1.000 detritos).", "4"],
    ], [0.8 * cm, 13.2 * cm, 3.5 * cm]))
    story.append(P("Decisões para o time", "h2"))
    story += bullets([
        "<b>Peças da Fase 2</b> (cápsula, paraquedas, pernas, aletas em grade) entram agora ou só depois do MVP?",
        "<b>Tanques</b>: manter tamanhos fixos (2/4/8 m, como no KSP) ou permitir comprimento ajustável?",
        "<b>Exceção de resolução para motores</b>: aceitar voxels menores só nos motores?",
        "<b>Nomes das peças</b>: os nomes genéricos (Falcão, Hidra, Kestrel...) estão bons ou o time prefere outro tema?",
    ])


def references(story):
    story.append(P("7. Referências", "h1"))
    for t, u in pc.REFERENCES:
        story.append(Paragraph(f"{t}<br/><font color='#2C7DA0' size='7.5'>{u}</font>", ST["bullet"], bulletText="•"))
    story.append(Spacer(1, 6))
    story.append(P("Valores marcados como \"aprox.\" variam entre fontes e foram arredondados. Antes de citar um "
                   "número em material público do projeto (pitch, vídeo), confirme na fonte primária.", "small"))


def main():
    OUT.parent.mkdir(parents=True, exist_ok=True)
    doc = SimpleDocTemplate(str(OUT), pagesize=A4, leftMargin=1.6 * cm, rightMargin=1.6 * cm,
                            topMargin=1.6 * cm, bottomMargin=1.5 * cm,
                            title="MARGIN — Hangar: Catálogo de Peças e Sistema de Construção",
                            author="MARGIN team", subject="NASA Space Apps Challenge 2026")
    story = []
    cover(story)
    toc(story)
    science(story)
    hangar_system(story)
    catalog(story)
    validation(story)
    voxel_section(story)
    story.append(PageBreak())
    next_steps(story)
    story.append(Spacer(1, 10))
    references(story)
    doc.build(story, onFirstPage=on_page, onLaterPages=on_page)
    print("PDF:", OUT)


if __name__ == "__main__":
    main()
