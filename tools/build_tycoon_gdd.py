"""Builds docs/GDD_Cometworks.pdf: game design document + megaprompt for the
space-agency tycoon (Cometlings' race to the Moon), the new direction of MARGIN for the
NASA Space Apps Challenge 2026.

Usage: python tools/build_tycoon_gdd.py
Needs: reportlab, Pillow (pip install reportlab pillow); Windows fonts (Segoe UI, Consolas).
"""
from datetime import date
from pathlib import Path

from PIL import Image as PILImage
from reportlab.graphics.shapes import Drawing, Line, Polygon, Rect, String
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import cm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (Image, KeepTogether, PageBreak, Paragraph, Preformatted, SimpleDocTemplate,
                                Spacer, Table, TableStyle)

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs" / "GDD_Cometworks.pdf"
SHOTS = ROOT / "docs" / "screenshots"
CREATURES = ROOT / "assets" / "voxel" / "creatures" / "screenshots"

pdfmetrics.registerFont(TTFont("UI", "C:/Windows/Fonts/segoeui.ttf"))
pdfmetrics.registerFont(TTFont("UI-B", "C:/Windows/Fonts/segoeuib.ttf"))
pdfmetrics.registerFont(TTFont("UI-L", "C:/Windows/Fonts/segoeuisl.ttf"))
pdfmetrics.registerFont(TTFont("UI-I", "C:/Windows/Fonts/segoeuii.ttf"))
pdfmetrics.registerFont(TTFont("Mono", "C:/Windows/Fonts/consola.ttf"))
pdfmetrics.registerFontFamily("UI", normal="UI", bold="UI-B", italic="UI-I", boldItalic="UI-B")

# MARGIN palette (ui/palette.gd), darkened where it sits on white paper
INK = colors.HexColor("#121922")
ORANGE = colors.HexColor("#C8661A")
ORANGE_HI = colors.HexColor("#FF9A3D")
BLUE = colors.HexColor("#2F6FBF")
TEAL = colors.HexColor("#1F9C7C")
VIOLET = colors.HexColor("#7B5BD6")
LIGHT = colors.HexColor("#F2F5F9")
GRID = colors.HexColor("#CBD5E1")
MUTED = colors.HexColor("#5F6F84")
WARN = colors.HexColor("#FFF4DE")

ST = {
    "title": ParagraphStyle("title", fontName="UI-B", fontSize=30, leading=35, textColor=INK),
    "subtitle": ParagraphStyle("subtitle", fontName="UI", fontSize=13, leading=18, textColor=MUTED),
    "h1": ParagraphStyle("h1", fontName="UI-B", fontSize=18, leading=23, textColor=INK, spaceBefore=4, spaceAfter=8),
    "h2": ParagraphStyle("h2", fontName="UI-B", fontSize=12.5, leading=16, textColor=BLUE, spaceBefore=10,
                         spaceAfter=4),
    "h3": ParagraphStyle("h3", fontName="UI-B", fontSize=10.5, leading=14, textColor=INK, spaceBefore=6,
                         spaceAfter=3),
    "body": ParagraphStyle("body", fontName="UI", fontSize=9.5, leading=13.6, spaceAfter=5, textColor=INK),
    "small": ParagraphStyle("small", fontName="UI", fontSize=8, leading=10.5, textColor=MUTED),
    "cell": ParagraphStyle("cell", fontName="UI", fontSize=8, leading=10.3, textColor=INK),
    "cellb": ParagraphStyle("cellb", fontName="UI-B", fontSize=8, leading=10.3, textColor=INK),
    "hcell": ParagraphStyle("hcell", fontName="UI-B", fontSize=8, leading=10.3, textColor=colors.white),
    "code": ParagraphStyle("code", fontName="Mono", fontSize=7.7, leading=9.8, textColor=colors.HexColor("#1D2B45")),
    "bullet": ParagraphStyle("bullet", fontName="UI", fontSize=9.5, leading=13.4, leftIndent=12, bulletIndent=2,
                             spaceAfter=2, textColor=INK),
    "callout": ParagraphStyle("callout", fontName="UI", fontSize=9.3, leading=13.2, textColor=INK),
    "quote": ParagraphStyle("quote", fontName="UI-I", fontSize=11, leading=15.5, textColor=MUTED,
                            alignment=TA_CENTER, spaceBefore=4, spaceAfter=8),
}

W = A4[0] - 3.6 * cm  # text width


def P(text, style="body"):
    return Paragraph(text, ST[style])


def bullets(items, style="bullet"):
    return [Paragraph(t, ST[style], bulletText="•") for t in items]


def numbered(items):
    return [Paragraph(t, ST["bullet"], bulletText=f"{i}.") for i, t in enumerate(items, 1)]


def table(rows, widths, header=True, zebra=True, bold_first=False):
    data = []
    for i, r in enumerate(rows):
        line = []
        for j, c in enumerate(r):
            st = "hcell" if (header and i == 0) else ("cellb" if bold_first and j == 0 else "cell")
            line.append(Paragraph(str(c), ST[st]))
        data.append(line)
    t = Table(data, colWidths=widths, repeatRows=1 if header else 0)
    style = [
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("GRID", (0, 0), (-1, -1), 0.4, GRID),
        ("LEFTPADDING", (0, 0), (-1, -1), 4),
        ("RIGHTPADDING", (0, 0), (-1, -1), 4),
        ("TOPPADDING", (0, 0), (-1, -1), 3),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
    ]
    if header:
        style.append(("BACKGROUND", (0, 0), (-1, 0), INK))
    if zebra:
        for i in range(1 if header else 0, len(rows)):
            if i % 2 == 0:
                style.append(("BACKGROUND", (0, i), (-1, i), LIGHT))
    t.setStyle(TableStyle(style))
    return t


def callout(text, color=ORANGE, bg=WARN):
    t = Table([[Paragraph(text, ST["callout"])]], colWidths=[W])
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), bg),
        ("LINEBEFORE", (0, 0), (0, -1), 3, color),
        ("LEFTPADDING", (0, 0), (-1, -1), 9),
        ("RIGHTPADDING", (0, 0), (-1, -1), 8),
        ("TOPPADDING", (0, 0), (-1, -1), 6),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
    ]))
    return t


def code(text):
    t = Table([[Preformatted(text.strip("\n"), ST["code"])]], colWidths=[W])
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), LIGHT),
        ("BOX", (0, 0), (-1, -1), 0.4, GRID),
        ("LEFTPADDING", (0, 0), (-1, -1), 7),
        ("TOPPADDING", (0, 0), (-1, -1), 5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
    ]))
    return t


def image(path, max_w, max_h, caption=None):
    if not path.exists():
        return []
    with PILImage.open(path) as im:
        w, h = im.size
    k = min(max_w / w, max_h / h)
    out = [Image(str(path), width=w * k, height=h * k)]
    if caption:
        out.append(P(caption, "small"))
    return out


def on_page(canvas, doc):
    canvas.saveState()
    if doc.page > 1:
        canvas.setFillColor(ORANGE_HI)
        canvas.rect(1.8 * cm, A4[1] - 1.25 * cm, 1.2 * cm, 0.12 * cm, stroke=0, fill=1)
        canvas.setFont("UI", 7.5)
        canvas.setFillColor(MUTED)
        canvas.drawString(3.2 * cm, A4[1] - 1.3 * cm, "Cometworks · GDD + megaprompt")
        canvas.drawRightString(A4[0] - 1.8 * cm, 1.1 * cm, str(doc.page))
        canvas.drawString(1.8 * cm, 1.1 * cm, "NASA Space Apps Challenge 2026 · Space Mission Design Game")
    canvas.restoreState()


# ------------------------------------------------------------------ diagrams
def loop_diagram():
    d = Drawing(W, 7.4 * cm)
    boxes = [
        ("Contratos e\nprojetos livres", ORANGE),
        ("Projeto da missão\n3 fases · 4 barras", BLUE),
        ("Revisão de projeto\n6 recursos", VIOLET),
        ("Lançamento e\noperação no mapa", TEAL),
        ("Avaliação, relatório\ne recompensas", ORANGE),
    ]
    bw, bh = 3.0 * cm, 1.55 * cm
    gap = (W - 5 * bw) / 4
    y = 4.9 * cm
    centers = []
    for i, (label, col) in enumerate(boxes):
        x = i * (bw + gap)
        d.add(Rect(x, y, bw, bh, rx=6, ry=6, fillColor=col, strokeColor=None))
        lines = label.split("\n")
        for k, ln in enumerate(lines):
            d.add(String(x + bw / 2, y + bh / 2 + 4 - k * 10, ln, fontName="UI-B", fontSize=7.6,
                         fillColor=colors.white, textAnchor="middle"))
        centers.append(x + bw / 2)
        if i < 4:
            ax = x + bw + 2
            d.add(Line(ax, y + bh / 2, ax + gap - 4, y + bh / 2, strokeColor=INK, strokeWidth=1.2))
            d.add(Polygon([ax + gap - 4, y + bh / 2 + 3, ax + gap + 1, y + bh / 2, ax + gap - 4, y + bh / 2 - 3],
                          fillColor=INK, strokeColor=None))
    # return arrow: rewards feed the agency
    yb = 1.25 * cm
    d.add(Rect(0, yb - 0.55 * cm, W, 1.25 * cm, rx=6, ry=6, fillColor=LIGHT, strokeColor=GRID))
    d.add(String(W / 2, yb + 0.12 * cm, "Agência: dinheiro, reputação, hype, ciência → pesquisa, prédios, contratações",
                 fontName="UI-B", fontSize=8.2, fillColor=INK, textAnchor="middle"))
    d.add(String(W / 2, yb - 0.3 * cm, "A corrida avança em paralelo: rivais anunciam marcos, o relógio anda até a passagem do cometa",
                 fontName="UI", fontSize=7.4, fillColor=MUTED, textAnchor="middle"))
    d.add(Line(centers[4], y, centers[4], yb + 0.7 * cm, strokeColor=INK, strokeWidth=1.1))
    d.add(Line(centers[0], yb + 0.7 * cm, centers[0], y - 4, strokeColor=INK, strokeWidth=1.1))
    d.add(Polygon([centers[0] - 3, y - 6, centers[0], y - 1, centers[0] + 3, y - 6], fillColor=INK, strokeColor=None))
    return d


def eras_diagram():
    eras = [("1", "Galpão", "anos 1–4", ORANGE), ("2", "Órbita", "anos 5–9", BLUE),
            ("3", "Lua robótica", "anos 10–14", TEAL), ("4", "Lua tripulada", "anos 15–19", VIOLET),
            ("5", "Base de partida", "anos 20–25", ORANGE_HI)]
    d = Drawing(W, 2.3 * cm)
    seg = W / 5
    for i, (n, name, yrs, col) in enumerate(eras):
        x = i * seg
        d.add(Rect(x + 1, 0.9 * cm, seg - 2, 0.55 * cm, fillColor=col, strokeColor=None))
        d.add(String(x + seg / 2, 1.08 * cm, f"Era {n}", fontName="UI-B", fontSize=7.5, fillColor=colors.white,
                     textAnchor="middle"))
        d.add(String(x + seg / 2, 0.5 * cm, name, fontName="UI-B", fontSize=8, fillColor=INK, textAnchor="middle"))
        d.add(String(x + seg / 2, 0.12 * cm, yrs, fontName="UI", fontSize=7.2, fillColor=MUTED, textAnchor="middle"))
    d.add(String(W, 1.75 * cm, "passagem do cometa: fim do ano 25 →", fontName="UI-B", fontSize=7.5,
                 fillColor=ORANGE, textAnchor="end"))
    return d


# ------------------------------------------------------------------ sections
def cover(s):
    s.append(Spacer(1, 2.2 * cm))
    s.append(P("NASA Space Apps Challenge 2026 · desafio <i>Space Mission Design Game</i>", "subtitle"))
    s.append(Spacer(1, 0.3 * cm))
    s.append(P("Cometworks", "title"))
    s.append(Spacer(1, 0.15 * cm))
    s.append(P("A agência espacial dos Cometinhos · tycoon · GDD + megaprompt de implementação", "subtitle"))
    s.append(Spacer(1, 0.5 * cm))
    s.append(P("“Cada quilo tem um preço. Cada semana também.”", "quote"))
    s.append(Spacer(1, 0.3 * cm))
    s += image(CREATURES / "creature_roles.png", W, 8.0 * cm)
    s.append(Spacer(1, 0.5 * cm))
    s.append(table([
        ["Campo", "Valor"],
        ["Nome", "<b>Cometworks</b> (mesmo nome em inglês e português). A agência do jogador também se chama Cometworks."],
        ["Gênero", "Tycoon de gestão (estilo <i>Game Dev Tycoon</i>) com expansão de agência, pesquisa e corrida espacial"],
        ["Base técnica", "Repositório MARGIN: Godot 4.6, GDScript, Jolt, build Windows, inglês e português"],
        ["Leitores", "Equipe (GDD) e agente de código, Claude Code (megaprompt: seções 18 a 20, 22 e Apêndice A)"],
        ["Entrega", "Hackathon de 14–15/11/2026, versão de campanha comprimida (seção 17)"],
        ["Versão do documento", f"1.0 · {date.today().strftime('%d/%m/%Y')} · substitui a direção do GDD_MARGIN_Space_Mission_Design_Game.md"],
    ], [3.6 * cm, W - 3.6 * cm], bold_first=True))
    s.append(PageBreak())


def toc(s):
    s.append(P("Sumário", "h1"))
    items = [
        ("0", "Como usar este documento"), ("1", "Resumo em 12 linhas"), ("2", "Decisões tomadas e premissas"),
        ("3", "Visão, fantasia e pilares"), ("4", "Mundo e história: a corrida dos Cometinhos"),
        ("5", "Loop principal e ritmo do tempo"), ("6", "Sistema de desenvolvimento de missões"),
        ("7", "Os 6 recursos e a Revisão de Projeto"), ("8", "Foguetes, satélites e sondas: montagem automática"),
        ("9", "Equipe: profissões dos Cometinhos"), ("10", "Pesquisa e tecnologia"), ("11", "A agência: campus voxel 3D"),
        ("12", "Economia"), ("13", "A corrida: marcos e agências rivais"),
        ("14", "Mapa do sistema solar e operação das missões"), ("15", "Educação: como o jogo ensina"),
        ("16", "Multijogador hot-seat, pontuação e fim de jogo"), ("17", "Escopo do hackathon e campanha comprimida"),
        ("18", "Reaproveitamento do código existente"), ("19", "Arquitetura técnica e dados"),
        ("20", "Plano de implementação com critérios de aceite"), ("21", "Riscos e decisões em aberto"),
        ("22", "Direção de arte da interface: Aurora de observatório"),
        ("A", "Apêndice A: megaprompt para o agente de código"), ("B", "Apêndice B: conformidade com o enunciado"),
        ("C", "Apêndice C: valores iniciais de balanceamento"),
    ]
    s.append(table([["#", "Seção"]] + [[a, b] for a, b in items], [1.2 * cm, W - 1.2 * cm]))
    s.append(PageBreak())


def how_to_use(s):
    s.append(P("0. Como usar este documento", "h1"))
    s.append(P("Este PDF tem dois leitores. A <b>equipe</b> lê as seções 1 a 17 para entender o jogo, discutir e "
               "apresentar. O <b>agente de código</b> (Claude Code no repositório MARGIN) usa o documento inteiro como "
               "especificação: as seções 18 a 20 e 22 dizem o que reaproveitar, como organizar o código e em que ordem "
               "construir, com critérios de aceite; o Apêndice A é o prompt pronto para colar a cada etapa."))
    s.append(P("Regras para o agente", "h2"))
    s += numbered([
        "Trate os números das seções 6, 12, 13 e do Apêndice C como <b>valores iniciais de playtest</b>. Todos ficam em "
        "arquivos JSON de <font name='Mono'>data/tycoon/</font>, nunca fixos no código.",
        "Siga as convenções do repositório: tudo o que é visual fica em cenas (<font name='Mono'>.tscn</font>) editáveis no "
        "editor; scripts só preenchem dados. Nenhum texto fixo no código: chaves de tradução em CSV de "
        "<font name='Mono'>i18n/</font>, inglês e português.",
        "Reaproveite os sistemas listados na seção 18 antes de escrever algo novo. O hangar, o voo e o mapa são "
        "<b>opcionais</b> para o jogador, mas o tycoon usa a matemática deles (Δv, cônicas, catálogo de peças).",
        "Construa na ordem da seção 20. Uma etapa só termina quando os critérios de aceite passam em teste headless "
        "(<font name='Mono'>godot --headless --path . --script res://tests/…</font>).",
        "Toda aleatoriedade sai de um RNG com <i>seed</i> salvo na partida: mesma seed e mesmas decisões dão o mesmo "
        "resultado. Isso viabiliza testes, replays e o hot-seat.",
        "O que está marcado <b>STRETCH</b> não entra antes de todo o <b>MVP</b> estar jogável.",
        "Toda tela segue a direção de arte da seção 22 (tokens, tipografia, componentes e as regras contra a "
        "“cara de IA”).",
        "Commits só com a conta do autor do repositório, sem linha de coautoria de IA.",
    ])
    s.append(P("Convenções do texto", "h2"))
    s += bullets([
        "<b>MVP</b>: entra na versão do hackathon. <b>STRETCH</b>: depois. <b>FUTURO</b>: só no jogo completo.",
        "Moeda do jogo: <b>créditos (cr)</b>. Tempo: semanas e anos de campanha (ano 1 a ano 25).",
        "“Barra” é um dos 4 eixos de qualidade de um projeto; “recurso” é um dos 6 limites físicos e de gestão do enunciado.",
    ])
    s.append(PageBreak())


def summary(s):
    s.append(P("1. Resumo em 12 linhas", "h1"))
    s += numbered([
        "Os <b>Cometinhos</b>, criaturinhas nascidas do gelo de um cometa, querem voltar para casa. O cometa de origem "
        "passa perto do Sol no fim do ano 25 da campanha.",
        "Para alcançá-lo, precisam de uma <b>base de partida na Lua</b>: gravidade baixa e gelo polar que vira propelente.",
        "Várias agências de Cometinhos disputam essa corrida. O jogador dirige uma delas, começando num galpão com "
        "foguetes de sondagem.",
        "O núcleo é o do <i>Game Dev Tycoon</i>: cada missão é um <b>projeto</b> com alvo, tipo e veículo, desenvolvido "
        "em 3 fases com sliders de foco.",
        "A equipe gera pontos em <b>4 barras</b>: Engenharia, Ciência, Operações e Confiabilidade. Cada profissão "
        "valoriza uma barra.",
        "Antes de lançar, a <b>Revisão de Projeto</b> confere os 6 recursos do enunciado: massa, energia, orçamento, "
        "dados, comunicação e tempo.",
        "Foguetes, satélites e sondas são <b>montados automaticamente</b> a partir de opções; o hangar e o voo manual "
        "existem para quem quiser pôr a mão.",
        "Missões ativas aparecem no <b>mapa do sistema solar</b> do jogo, com dados chegando, decisões de operação e eventos.",
        "Cada missão termina com <b>avaliação de 4 jornais</b>, relatório pós-missão com o fator limitante e "
        "recompensas: dinheiro, reputação, hype e ciência.",
        "A agência cresce: <b>pesquisa</b> desbloqueia peças e tipos de missão; prédios aumentam capacidade; "
        "contratos, governo, hype e venda de tecnologia pagam as contas.",
        "Rivais (IA ou até 4 humanos em <b>hot-seat</b>) disputam os “primeiros”. Perder um marco custa prestígio, mas a "
        "meta final, alcançar o cometa, continua aberta.",
        "No hackathon, a campanha de 25 anos roda <b>comprimida</b>, em 40 a 60 minutos, para jurados jogarem de ponta a ponta.",
    ])
    s.append(Spacer(1, 0.3 * cm))
    s.append(loop_diagram())
    s.append(P("Figura 1. Loop principal: contratos e projetos passam pelo desenvolvimento, pela revisão e pelo voo; as "
               "recompensas voltam para a agência.", "small"))
    s.append(PageBreak())


def decisions(s):
    s.append(P("2. Decisões tomadas e premissas", "h1"))
    s.append(P("Decisões fechadas nas conversas de design. Mudar qualquer uma delas exige revisar as seções indicadas."))
    s.append(table([
        ["Tema", "Decisão", "Afeta"],
        ["Relação com o MARGIN", "O tycoon <b>substitui</b> a direção atual. Hangar, voo e sistema solar viram etapas dentro dele.", "tudo"],
        ["Loop", "Estilo Game Dev Tycoon, com expansão da agência, pesquisa, criação de foguetes, satélites e missões variadas. "
         "O mapa do sistema solar mostra as missões ativas.", "5, 6, 14"],
        ["Mão na massa", "<b>Opcional.</b> Os Cometinhos montam e voam sozinhos; o jogador pode assumir hangar ou voo.", "8, 14"],
        ["História", "Corrida espacial dos Cometinhos até a Lua.", "4"],
        ["Meta na Lua", "<b>Base de partida</b> para alcançar o cometa quando ele passar. Abre o jogo tardio.", "4, 13, 16"],
        ["Rivais", "Agências rivais controladas pela IA, cada uma com personalidade.", "13"],
        ["Space Apps", "Este tycoon é a <b>entrega do hackathon</b> de 14–15/11, cumprindo o checklist do enunciado.", "17, B"],
        ["Leitores do PDF", "Agente de IA e equipe.", "0"],
        ["Projetos", "<b>Contratos + projetos livres</b>: contratos pagam as contas; livres dão fama, ciência e “primeiros”.", "6"],
        ["Campanha", "Longa, cerca de 25 anos de jogo, 3 a 5 horas.", "5, 17"],
        ["Profissões", "Expandidas; cada uma valoriza uma barra do sistema de desenvolvimento.", "9"],
        ["Barras", "4 barras de qualidade (Engenharia, Ciência, Operações, Confiabilidade); os 6 recursos viram "
         "restrições da Revisão de Projeto.", "6, 7"],
        ["Dinheiro", "Orçamento do governo, contratos comerciais, venda de tecnologia e hype público.", "12"],
        ["Hackathon", "<b>Campanha comprimida</b>: a campanha inteira, com tempo acelerado e menos conteúdo por era.", "17"],
        ["Rival chega antes", "O jogo <b>continua com perda</b>: some o prêmio do “primeiro”, a meta do cometa segue.", "13, 16"],
        ["Expansão", "Hangar e plataformas, laboratórios de P&amp;D, controle e antenas, treino e fábrica.", "11"],
        ["Visão principal", "<b>Campus voxel 3D</b> isométrico com Cometinhos trabalhando.", "11"],
        ["Satélites e sondas", "Opções que <b>se montam automaticamente</b> para o jogador.", "8"],
        ["Multijogador", "<b>Rivais humanos</b>: hot-seat agora, online depois.", "16"],
        ["Educação", "Enciclopédia de missões reais, conselheiros Cometinhos, relatório pós-missão e contratos "
         "inspirados no Space Apps.", "15"],
        ["Nome", "<b>Cometworks</b>.", "capa"],
        ["Arte da UI", "Aurora com pegada espacial, sem vidro fosco e sem cara de interface feita por IA: "
         "“Aurora de observatório”.", "22"],
        ["Tempo", "Tempo real com pausa e 3 velocidades; no multijogador, turnos de um mês.", "5, 16"],
        ["Idioma do PDF", "Português, termos de código em inglês.", "–"],
    ], [3.3 * cm, W - 4.6 * cm, 1.3 * cm], bold_first=True))
    s.append(Spacer(1, 0.3 * cm))
    s.append(callout("<b>Premissa de escopo.</b> Uma campanha de 25 anos e um hackathon de 48 horas puxam para lados "
                     "opostos. A solução adotada é construir a campanha inteira com <b>pouco conteúdo por era</b> e um "
                     "<b>modo feira</b> com o relógio acelerado (seção 17). Conteúdo extra entra depois sem mudar sistemas."))
    s.append(PageBreak())


def vision(s):
    s.append(P("3. Visão, fantasia e pilares", "h1"))
    s.append(P("<b>Fantasia do jogador:</b> “Eu dirijo a agência espacial mais fofa da galáxia e, decisão por decisão, "
               "levo meus Cometinhos de um galpão de foguetes de sondagem até a Lua, e da Lua de volta ao cometa.”"))
    s.append(P("Pilares", "h2"))
    s.append(table([
        ["Pilar", "O que significa", "Teste de design"],
        ["1. Toda escolha tem preço", "Mais instrumento, mais massa, mais propelente, foguete maior, mais custo, mais tempo. "
         "O acoplamento é o assunto do jogo (enunciado do desafio).",
         "Existe alguma escolha sem desvantagem? Se sim, ela está errada."],
        ["2. Gestão leve, consequência visível", "Poucos cliques por semana; cada decisão aparece num número, numa barra "
         "ou num Cometinho reagindo no campus.", "Um jogador novo entende o efeito de um slider sem abrir ajuda?"],
        ["3. Ciência real, mundo fofo", "Física, órbitas e missões históricas reais por baixo; personagens e tom leves por cima.",
         "Um professor aprovaria o conteúdo? Uma criança de 11 anos quer continuar jogando?"],
        ["4. A corrida dá urgência", "Rivais e o relógio do cometa transformam “otimizar” em “arriscar ou esperar”.",
         "Há momentos em que lançar cedo e arriscar é uma boa ideia?"],
        ["5. Falhar ensina", "Falha nunca é só “errado”: o relatório diz o fator limitante e o que mudaria o resultado.",
         "Depois de falhar, o jogador sabe o que tentar diferente?"],
    ], [3.4 * cm, 7.6 * cm, W - 11.0 * cm], bold_first=True))
    s.append(P("Referências de jogo", "h2"))
    s += bullets([
        "<b>Game Dev Tycoon</b>: projeto com tema × gênero, 3 fases com sliders, pontos de design/tecnologia, notas da "
        "imprensa, expectativa que sobe a cada sucesso, escritório que cresce.",
        "<b>Kerbal Space Program</b>: montar e voar foguetes com física real; o MARGIN já tem hangar, voo e cônicas.",
        "<b>Mars Horizon</b>: agência espacial com corrida histórica e marcos. Aqui a corrida é ficcional e os rivais "
        "são agências de Cometinhos.",
        "<b>Two Point Hospital</b>: campus com personagens visíveis trabalhando e humor leve.",
    ])
    s.append(P("O que este jogo não é", "h2"))
    s += bullets([
        "Não é simulador de voo obrigatório: ninguém precisa pilotar para vencer.",
        "Não usa marca, logo ou nome da NASA dentro do jogo. Missões reais aparecem na enciclopédia como referência "
        "histórica, sem símbolos oficiais.",
        "Não é corrida de reflexo: tudo pode ser pausado.",
    ])
    s.append(PageBreak())


def world(s):
    s.append(P("4. Mundo e história: a corrida dos Cometinhos", "h1"))
    s.append(P("Os Cometinhos (EN: <i>Cometlings</i>) já existem no projeto: cabeça grande, orelhas-cauda que esvoaçam "
               "como a cauda de um cometa, antena com uma lâmpada-estrela na cor da profissão. Nasceram do gelo da cauda "
               "de um cometa e amam foguetes porque um foguete é o único caminho de volta para casa."))
    s += image(CREATURES / "creature_poses.png", W, 6.0 * cm,
               "Figura 2. Cometinhos do projeto (docs/creatures.md): poses e animações já prontas para o campus.")
    s.append(P("Premissa", "h2"))
    s.append(P("O cometa de origem, a <b>Mãe-Gelo</b>, é periódico. Sua próxima passagem perto do Sol acontece no fim do "
               "ano 25 da campanha. Da superfície do planeta natal, alcançá-lo custa Δv demais. Da Lua, com gravidade "
               "baixa e com propelente feito do gelo das crateras polares, a viagem se torna possível. Por isso a corrida "
               "é pela Lua: quem tiver a primeira <b>base de partida</b> operacional sai na frente para o encontro."))
    s.append(callout("<b>Ciência real por trás da ficção.</b> Gravidade lunar ~1/6 da terrestre (Δv de subida muito menor); "
                     "gelo de água em crateras polares permanentemente sombreadas; uso de recursos locais (ISRU) para fazer "
                     "propelente; janelas de lançamento e encontro com cometas. Cada um desses conceitos tem ficha na "
                     "enciclopédia (seção 15).", TEAL, colors.HexColor("#E6F6F1")))
    s.append(P("Eras da campanha", "h2"))
    s.append(eras_diagram())
    s.append(table([
        ["Era", "Anos", "Foco", "Missões típicas", "Marco que fecha a era"],
        ["1 Galpão", "1–4", "Aprender a lançar", "Sondagem suborbital, primeiro satélite pequeno", "Primeiro satélite em órbita"],
        ["2 Órbita", "5–9", "Serviços e primeiro Cometinho no espaço", "Comunicação, observação da Terra, voo tripulado em órbita",
         "Primeiro Cometinho em órbita"],
        ["3 Lua robótica", "10–14", "Chegar à Lua sem tripulação", "Impacto, orbitador, pouso robótico, mapeamento de gelo",
         "Gelo polar confirmado"],
        ["4 Lua tripulada", "15–19", "Levar Cometinhos à Lua", "Sobrevoo tripulado, pouso tripulado, retorno de amostras",
         "Primeiro pouso tripulado"],
        ["5 Base de partida", "20–25", "Construir e abastecer a base", "Módulos da base, ISRU, lançador lunar, missão ao cometa",
         "Encontro com a Mãe-Gelo"],
    ], [2.3 * cm, 1.2 * cm, 3.4 * cm, 5.6 * cm, W - 12.5 * cm], bold_first=True))
    s.append(P("Tom", "h2"))
    s.append(P("Leve e caloroso. Os Cometinhos comemoram lançamentos, choram falhas com balõezinhos de emoji e "
               "mandam cartinhas para casa. As agências rivais provocam no jornal, mas ninguém é vilão: no fim, todos "
               "querem voltar para o cometa. O humor nunca zomba da ciência; zomba dos Cometinhos, que se levam a sério demais."))
    s.append(PageBreak())


def loop(s):
    s.append(P("5. Loop principal e ritmo do tempo", "h1"))
    s.append(P("Três escalas", "h2"))
    s.append(table([
        ["Escala", "Duração", "O jogador faz", "Retorno"],
        ["Micro", "1 semana (segundos)", "Ajusta sliders, aloca Cometinhos, responde eventos, decide na operação",
         "Pontos nas barras, defeitos, dados baixados, moral"],
        ["Meso", "1 projeto (3–12 semanas)", "Escolhe contrato ou projeto livre, alvo, tipo, veículo, opções; passa a revisão; lança",
         "Nota dos jornais, dinheiro, reputação, hype, ciência, XP"],
        ["Macro", "1 era (5 anos)", "Pesquisa, constrói prédios, contrata, cria famílias de foguetes, disputa marcos",
         "Novos tipos de missão, novos alvos, orçamento do governo"],
    ], [1.6 * cm, 3.0 * cm, 6.6 * cm, W - 11.2 * cm], bold_first=True))
    s.append(P("Uma semana típica", "h2"))
    s += numbered([
        "O relógio avança uma semana. Cada Cometinho alocado gera pontos na barra da sua profissão (seção 6).",
        "Projetos em desenvolvimento acumulam pontos e defeitos; se a fase acabou, o jogo pausa e pede os sliders da próxima.",
        "Missões em voo rodam a semana de operação: energia, dados gerados, armazenados e baixados (seção 14).",
        "Laboratórios somam pontos de pesquisa; a tecnologia em estudo pode ficar pronta.",
        "Rivais rolam o progresso deles; o jornal pode anunciar um marco (seção 13).",
        "Eventos aleatórios podem aparecer: falha de componente, greve de Cometinhos com sono, visita de patrocinador.",
        "Contas: no fim do mês, salários e manutenção; no início do ano, orçamento do governo.",
    ])
    s.append(P("Ritmo do tempo", "h2"))
    s.append(table([
        ["Modo", "1 semana dura", "Uso"],
        ["Pausa", "–", "Sempre disponível (Espaço). Todas as telas funcionam pausadas."],
        ["Velocidade 1", "6 s", "Padrão. Campanha de 25 anos ≈ 3 a 5 h com pausas."],
        ["Velocidade 2", "3 s", "Esperando um projeto longo."],
        ["Velocidade 3", "1 s", "Esperando cruzeiro de missão ou pesquisa."],
        ["Modo feira (hackathon)", "1 s fixo + auto-pausa só em decisões", "Campanha inteira em 40–60 min (seção 17)."],
        ["Hot-seat", "Turnos de 1 mês", "Cada agência decide o mês e passa a vez (seção 16)."],
    ], [3.6 * cm, 4.6 * cm, W - 8.2 * cm], bold_first=True))
    s.append(P("Auto-pausa: fim de fase de projeto, lançamento pronto, decisão de operação, evento importante, marco "
               "anunciado, fim do ano fiscal. Cada tipo pode ser desligado nas opções."))
    s.append(PageBreak())


def development(s):
    s.append(P("6. Sistema de desenvolvimento de missões", "h1"))
    s.append(P("É o coração do jogo e a parte mais próxima do <i>Game Dev Tycoon</i>. Um <b>projeto de missão</b> nasce "
               "de um contrato ou de uma ideia livre e passa por: escolha → 3 fases de desenvolvimento → Revisão de "
               "Projeto → lançamento → operação → avaliação."))
    s.append(P("6.1 Contratos e projetos livres", "h2"))
    s.append(table([
        ["", "Contrato", "Projeto livre"],
        ["Origem", "Governo (programas nacionais), clientes comerciais, contratos inspirados no Space Apps", "O jogador"],
        ["Requisitos", "Alvo, tipo, prazo, notas mínimas em barras (ex.: Ciência ≥ 6), às vezes órbita específica", "Nenhum"],
        ["Pagamento", "Fixo + bônus por nota; multa se atrasar ou falhar", "Nenhum direto"],
        ["Ganha", "Dinheiro e reputação estáveis", "Hype, ciência, “primeiros” da corrida, notas altas"],
        ["Risco", "Baixo a médio", "Alto: paga tudo do próprio bolso"],
    ], [2.4 * cm, 7.4 * cm, W - 9.8 * cm], bold_first=True))
    s.append(P("O quadro de contratos mostra 3 a 6 ofertas por vez, renovadas a cada mês. Rivais também disputam contratos "
               "comerciais: uma oferta pode sumir se um rival aceitar antes."))
    s.append(P("6.2 Escolha: alvo × tipo × veículo", "h2"))
    s.append(P("Equivale a tema × gênero × plataforma do Game Dev Tycoon. O jogador sempre escolhe o <b>objetivo antes "
               "da nave</b> (requisito R5 do enunciado): primeiro alvo e tipo, depois as opções da nave e o foguete."))
    s.append(table([
        ["Alvos (desbloqueio)", "Tipos de missão (desbloqueio)"],
        ["Suborbital (início) · Órbita baixa, LEO (era 1) · Órbita polar / heliossíncrona (era 2) · Órbita alta / geoestacionária "
         "(era 2) · Sobrevoo lunar (era 3) · Órbita lunar (era 3) · Superfície lunar (era 3) · Polo lunar (era 3) · "
         "Vênus, Marte, asteroide (STRETCH) · Cometa Mãe-Gelo (era 5)",
         "Sondagem · Satélite de demonstração · Comunicação · Observação da Terra · Clima espacial · Telescópio · Impacto · "
         "Orbitador · Pousador · Rover · Voo tripulado · Pouso tripulado · Retorno de amostra · Módulo de base · "
         "Planta de propelente (ISRU) · Lançador lunar · Missão ao cometa"],
    ], [W / 2, W / 2], zebra=False))
    s.append(P("<b>Compatibilidade.</b> Uma matriz tipo × alvo dá <i>ótima / boa / ruim / impossível</i> (multiplicador "
               "1,15 / 1,0 / 0,75 / bloqueado). Exemplo: observação da Terra em órbita heliossíncrona é ótima; em órbita "
               "geoestacionária é ruim (resolução baixa), mas ótima para clima. O jogador descobre a matriz jogando, e a "
               "enciclopédia explica o porquê depois da primeira tentativa."))
    s.append(P("<b>Veículo.</b> Uma família de foguete da agência (seção 8). A família define capacidade de carga por alvo, "
               "custo por lançamento e confiabilidade."))
    s.append(P("6.3 As 4 barras", "h2"))
    s.append(table([
        ["Barra", "Representa", "Profissões que mais valorizam", "Pesa em"],
        ["Engenharia", "Estrutura, propulsão, massa e integração bem resolvidas", "Engenheiro(a) de sistemas, engenheiro(a) de propulsão",
         "Nota, margem de massa, custo"],
        ["Ciência", "Instrumentos e plano científico", "Cientista, pesquisador(a)", "Nota, ciência retornada"],
        ["Operações", "Plano de voo, software, comunicação, equipe de solo", "Controlador(a) de voo, piloto",
         "Nota, dados baixados, decisões em voo"],
        ["Confiabilidade", "Testes, redundância, prontidão", "Técnico(a) de testes", "Chance de sucesso, defeitos"],
    ], [2.6 * cm, 5.3 * cm, 5.1 * cm, W - 13.0 * cm], bold_first=True))
    s.append(P("Cada tipo de missão tem uma <b>proporção ideal</b> das barras (como a proporção design/tecnologia do "
               "Game Dev Tycoon). Exemplos de valores iniciais:"))
    s.append(table([
        ["Tipo", "Eng.", "Ciên.", "Oper.", "Conf.", "Semanas base", "Tamanho"],
        ["Sondagem", "40%", "20%", "15%", "25%", "3", "0,5"],
        ["Comunicação", "30%", "5%", "40%", "25%", "6", "1,0"],
        ["Observação da Terra", "25%", "35%", "25%", "15%", "6", "1,0"],
        ["Telescópio", "20%", "50%", "15%", "15%", "10", "1,6"],
        ["Pousador", "40%", "20%", "15%", "25%", "9", "1,8"],
        ["Voo tripulado", "30%", "5%", "30%", "35%", "10", "2,0"],
        ["Módulo de base", "40%", "10%", "20%", "30%", "12", "2,5"],
        ["Missão ao cometa", "30%", "20%", "25%", "25%", "16", "3,0"],
    ], [4.2 * cm, 1.4 * cm, 1.4 * cm, 1.4 * cm, 1.4 * cm, 2.6 * cm, W - 12.4 * cm], bold_first=True))
    s.append(P("6.4 As 3 fases e os sliders", "h2"))
    s.append(P("Cada fase dura um terço das semanas do projeto. No início de cada fase o jogador distribui 100% do "
               "tempo entre 3 sliders. Cada slider alimenta barras com pesos fixos:"))
    s.append(table([
        ["Fase", "Slider", "Alimenta"],
        ["1 Concepção", "Arquitetura da missão", "Engenharia 0,8 · Confiabilidade 0,2"],
        ["", "Carga científica", "Ciência 1,0"],
        ["", "Conceito de operações", "Operações 0,8 · Engenharia 0,2"],
        ["2 Construção e integração", "Estrutura e propulsão", "Engenharia 1,0"],
        ["", "Instrumentos", "Ciência 0,8 · Engenharia 0,2"],
        ["", "Testes ambientais", "Confiabilidade 1,0 · remove defeitos"],
        ["3 Preparação do voo", "Software e autonomia", "Operações 0,6 · Engenharia 0,4"],
        ["", "Treino da equipe de solo", "Operações 1,0 · XP extra"],
        ["", "Revisão de prontidão", "Confiabilidade 0,7 · Ciência 0,3 · remove defeitos"],
    ], [4.2 * cm, 4.8 * cm, W - 9.0 * cm]))
    s.append(P("6.5 Fórmulas centrais", "h2"))
    s.append(code("""
# pontos de uma semana, por Cometinho c alocado no projeto, para cada barra b
pts[b] += 10 * (0.4 + 0.6*skill_c) * (0.6 + 0.4*moral_c) * (1 + 0.08*nivel_c)
              * afinidade(profissao_c, b) * foco(b, fase, sliders) * bonus_predios
afinidade: barra principal 1.0 · secundaria 0.4 · demais 0.15
foco(b) = soma dos sliders da fase * peso do slider em b      (0..1)

# defeitos (as "bugs" do Game Dev Tycoon)
defeitos += 0.04 * soma(pts da semana) * (1 - 0.5 * fracao_conf)
defeitos -= 0.10 * pts[Confiabilidade] da semana * (slider de testes ativo ? 1 : 0.3)

# nota (0..10) ao fim do desenvolvimento
total   = soma(pts)
esperado = E_era * tamanho(tipo) * (1 + 0.1 * projetos_recentes_mesmo_tipo)
q = min(total / esperado, 1.5)                       # volume de trabalho vs expectativa
m = 1 - 0.5 * soma_b |fracao_b - ideal_b|            # proporcao certa das barras
nota = 10 * clamp(0.55*q/1.5*1.5 + 0.45*m, 0, 1) * compat(tipo, alvo)
       - 0.6 * defeitos_residuais / max(total/100, 1)
nota = clamp(nota, 0, 10)
"""))
    s.append(P("Como no Game Dev Tycoon, a <b>expectativa sobe</b>: E_era cresce a cada era e também com a melhor nota "
               "recente da agência. Repetir a mesma missão rende cada vez menos; inovar (alvo novo, tipo novo, “primeiro” da "
               "corrida) dá bônus de novidade na avaliação."))
    s.append(P("6.6 Lançamento, resultado e avaliação", "h2"))
    s.append(code("""
p_carga   = clamp(0.55 + 0.45*fracao_conf_normalizada - 0.03*defeitos_residuais, 0.30, 0.99)
p_foguete = confiabilidade da familia (0.75 ao estrear, +0.03 por voo bem-sucedido, max 0.98)
p_sucesso = p_carga * p_foguete * (tripulada ? coragem_media_ajuste : 1)
resultado: Falha | Sucesso parcial | Sucesso pleno | Excepcional   (criterios do contrato/tipo)
"""))
    s.append(P("A avaliação vem de 4 jornais dos Cometinhos, cada um com um viés. A nota de cada jornal é a nota do "
               "projeto ajustada pelo viés, mais um ruído de ±0,7 com a seed da partida:"))
    s.append(table([
        ["Jornal", "Viés"],
        ["O Eco da Cauda (popular)", "Novidade, “primeiros”, tripuladas, hype"],
        ["Revista Órbita (técnica)", "Engenharia e Confiabilidade, margens saudáveis"],
        ["Boletim da Coma (científico)", "Ciência efetivamente baixada para o solo"],
        ["Folha do Contribuinte", "Custo por resultado, atrasos, multas"],
    ], [5.4 * cm, W - 5.4 * cm], bold_first=True))
    s.append(P("Recompensas: pagamento do contrato (com bônus se a média ≥ 8), reputação (+nota − 5, entre −5 e +5), "
               "hype (+média²/5), pontos de ciência (ciência baixada × 0,5, que alimentam a pesquisa) e XP para cada "
               "Cometinho alocado."))
    s.append(PageBreak())


def resources(s):
    s.append(P("7. Os 6 recursos e a Revisão de Projeto", "h1"))
    s.append(P("O enunciado exige 6 recursos principais. Aqui eles não são barras de qualidade: são <b>limites</b> que "
               "a nave e a agência precisam respeitar. Eles aparecem na tela de opções da nave (seção 8) e travam o "
               "lançamento na <b>Revisão de Projeto</b> se algum estiver no vermelho."))
    s.append(table([
        ["Recurso", "Onde mora", "Limite", "Exemplo de efeito dominó"],
        ["Massa", "Nave", "Capacidade do foguete para o alvo (Δv do mapa)", "Instrumento extra → +40 kg → foguete maior → +custo"],
        ["Energia", "Nave", "Geração (painel, bateria, RTG) vs consumo por modo e eclipse", "Radar polar → precisa painel articulado → +massa"],
        ["Orçamento", "Agência", "Caixa + reserva do projeto", "Reserva baixa → crescimento de custo vira corte de escopo"],
        ["Dados", "Nave", "Armazenamento a bordo", "Câmera de alta resolução enche o disco antes do contato"],
        ["Comunicação", "Nave + agência", "Antena da nave × rede de antenas (prédio) × distância", "Lua com antena omni → pouco downlink → pouca ciência"],
        ["Tempo", "Agência", "Prazo do contrato e janelas de lançamento e do cometa", "Atraso perde a janela lunar do mês ou a passagem do cometa"],
    ], [2.2 * cm, 2.0 * cm, 5.0 * cm, W - 9.2 * cm], bold_first=True))
    s.append(P("Estados de cada medidor: verde (margem ≥ 20%), amarelo (5–20%), vermelho (&lt; 5% ou negativo), com cor "
               "e ícone para acessibilidade. As fórmulas de propelente, energia solar, link de dados e fluxo de dados do "
               "GDD anterior continuam válidas e são reaproveitadas (GDD_MARGIN, seção B3.2)."))
    s.append(P("A regra mais importante: ciência só conta quando o dado chega ao solo", "h2"))
    s.append(code("""
gerado     = soma(taxa_instrumento * duty_cycle)          # limitado por energia e apontamento
armazenado = min(capacidade, armazenado + gerado)         # excedente = DADO PERDIDO
baixado    = min(downlink_possivel(antena, distancia, rede_de_antenas), armazenado)
ciencia   += valor(baixado)                               # so o baixado credita
"""))
    s.append(P("Revisão de Projeto (portão antes do lançamento)", "h2"))
    s += bullets([
        "Mostra os 6 medidores, a chance de sucesso e o fator mais arriscado, dito por um conselheiro Cometinho.",
        "Vermelho bloqueia o lançamento. Amarelo permite, com aviso e com a explicação da consequência provável.",
        "Botões rápidos: “trocar opção” (volta às opções da nave), “foguete maior”, “adiar” (mais semanas de testes), "
        "“lançar mesmo assim”.",
        "Atende R9 (compatibilidade massa × órbita × foguete) e R11 (cada decisão tem consequência).",
    ])
    s.append(PageBreak())


def vehicles(s):
    s.append(P("8. Foguetes, satélites e sondas: montagem automática", "h1"))
    s.append(P("Decisão: o jogador escolhe <b>opções</b> e os Cometinhos montam. O hangar e o voo manual continuam no "
               "jogo para quem quer pôr a mão, mas nenhuma missão exige isso."))
    s.append(P("8.1 Nave (satélite, sonda, módulo)", "h2"))
    s.append(P("A tela de opções tem uma linha por subsistema, como exige o item R6 do enunciado. Cada linha oferece 2 a "
               "4 opções desbloqueadas pela pesquisa, e uma delas vem marcada como “recomendada pelos Cometinhos”:"))
    s.append(table([
        ["Subsistema", "Opções (exemplos)", "Trade-off"],
        ["Barramento", "Cubinho 6U · pequeno · médio · grande", "Capacidade de carga vs massa e custo base"],
        ["Energia", "Painéis fixos · articulados · bateria P/M/G · RTG (era 4)", "Eclipse e distância do Sol vs massa"],
        ["Comunicação", "Omni · média · refletor grande", "Downlink vs massa e apontamento"],
        ["Computador e armazenamento", "Básico · redundante · 50/200/1000 Gbit", "Buffer de dados vs custo e radiação"],
        ["Controle de atitude", "Magnetorquers · rodas de reação · rodas + rastreador estelar", "Precisão dos instrumentos vs custo"],
        ["Propulsão da nave", "Nenhuma · monopropelente · bipropelente", "Δv de inserção vs massa (equação do foguete)"],
        ["Instrumentos", "Câmera, espectrômetro, radar, magnetômetro, sismômetro…", "Ciência vs massa, energia, dados e custo"],
        ["Tripulação (tripuladas)", "Cápsula 1, 2 ou 3 lugares · suporte de vida", "Moral e XP vs massa enorme"],
    ], [3.6 * cm, 6.6 * cm, W - 10.2 * cm], bold_first=True))
    s.append(P("Ao mudar uma opção, os 6 medidores e a nave voxel de pré-visualização atualizam na hora (painel “efeito "
               "dominó”). A nave é montada automaticamente com as peças do catálogo de 94 peças do hangar."))
    s.append(P("8.2 Famílias de foguetes", "h2"))
    s += bullets([
        "A agência cria <b>famílias</b> de foguetes (como os motores de jogo do Game Dev Tycoon). Uma família tem "
        "estágios, capacidade de carga por alvo, custo por voo e confiabilidade.",
        "<b>Criar família:</b> o projetista automático propõe 3 versões a partir das peças pesquisadas: <i>Barata</i>, "
        "<i>Equilibrada</i> e <i>Robusta</i>. Ele usa a matemática do hangar (Δv e TWR por estágio) e a tabela de Δv "
        "por alvo tirada das cônicas do mapa.",
        "<b>Abrir no hangar</b> (opcional): a versão escolhida abre no hangar real para ajustes; o que o jogador salvar "
        "vira a família.",
        "<b>Curva de aprendizado:</b> a confiabilidade sobe +3 pontos por voo bem-sucedido (até 98%); a fábrica reduz "
        "custo e tempo de produção de unidades repetidas.",
        "Uma família nova sempre estreia menos confiável: trocar de foguete às vésperas de um marco é um risco real.",
    ])
    s += image(SHOTS / "hangar_wide.png", W, 6.2 * cm,
               "Figura 3. O hangar existente: usado pelo projetista automático e aberto quando o jogador quer ajustar à mão.")
    s.append(PageBreak())


def staff(s):
    s.append(P("9. Equipe: profissões dos Cometinhos", "h1"))
    s.append(P("A equipe já existe no código (<font name='Mono'>CrewMember</font>, <font name='Mono'>CrewRoster</font>): "
               "nome, profissão, coragem, habilidade, curiosidade, experiência. O tycoon <b>expande as profissões</b>, e "
               "cada uma valoriza uma barra do sistema de desenvolvimento."))
    s.append(table([
        ["Profissão", "Barra principal", "Secundária", "Papel extra", "Cor da antena"],
        ["Engenheiro(a) de sistemas", "Engenharia", "Confiabilidade", "Reduz massa seca das naves", "laranja"],
        ["Engenheiro(a) de propulsão", "Engenharia", "–", "Cria e melhora famílias de foguetes", "vermelho"],
        ["Cientista", "Ciência", "Operações", "Aumenta a ciência por dado baixado", "azul"],
        ["Pesquisador(a)", "Ciência", "–", "Gera pontos de pesquisa no laboratório", "violeta"],
        ["Controlador(a) de voo", "Operações", "Confiabilidade", "+1 missão ativa por 2 controladores; decide em voo", "verde-água"],
        ["Técnico(a) de testes", "Confiabilidade", "Engenharia", "Remove defeitos com eficiência dobrada", "amarelo"],
        ["Piloto / astronauta", "Operações", "Confiabilidade", "Obrigatório em tripuladas; coragem pesa no risco", "branco"],
    ], [3.8 * cm, 2.4 * cm, 2.4 * cm, 5.0 * cm, W - 13.6 * cm], bold_first=True))
    s.append(P("Atributos e estado", "h2"))
    s += bullets([
        "<b>Habilidade</b>: multiplica pontos. <b>Curiosidade</b>: chance de “descoberta” (bônus de ciência, desbloqueio "
        "de combinação tipo × alvo, ideia de projeto livre). <b>Coragem</b>: tolerância a risco em tripuladas e moral "
        "depois de falhas.",
        "<b>Nível</b> 1 a 6 (100 XP por nível, como hoje). Cada nível dá +8% de pontos; no nível 3 e no 5 o Cometinho "
        "escolhe uma <b>especialização</b> (ex.: “especialista lunar”, “mestre de antenas”) no centro de treinamento.",
        "<b>Moral</b> 0–100: cai com excesso de trabalho, falhas e salário atrasado; sobe com sucessos, férias e prédios "
        "de lazer. Abaixo de 30, o Cometinho tira um cochilo no campus e não produz naquela semana.",
        "<b>Salário</b> por nível e profissão; contratar custa uma taxa e leva 2 semanas de adaptação.",
        "Contratação: lista de 3 candidatos por mês, com atributos parcialmente ocultos (revelados com o tempo).",
    ])
    s += image(SHOTS / "crew_panel.png", W, 6.0 * cm,
               "Figura 4. Painel de tripulação existente, base para o painel de equipe do tycoon.")
    s.append(PageBreak())


def research(s):
    s.append(P("10. Pesquisa e tecnologia", "h1"))
    s.append(P("Pesquisadores no laboratório geram pontos de pesquisa (PP) toda semana; a ciência retornada pelas missões "
               "também vira PP. Cada tecnologia custa PP e tempo, tem pré-requisitos e desbloqueia algo concreto. Cada "
               "uma aponta para uma ficha da enciclopédia com a tecnologia real equivalente."))
    s.append(table([
        ["Ramo", "Desbloqueia (exemplos por era)", "Inspiração real"],
        ["Propulsão", "Motores sólidos → querosene/oxigênio → hidrogênio/oxigênio → estágio lunar → motor de vácuo de alto Isp",
         "Foguetes de sondagem, primeiros lançadores, estágios criogênicos"],
        ["Estruturas e materiais", "Tanques mais leves, carenagens, adaptadores, módulos habitáveis", "Ligas de alumínio-lítio, compósitos"],
        ["Energia", "Painéis articulados, baterias maiores, RTG, energia para noite lunar", "Painéis solares, geradores de radioisótopos"],
        ["Comunicação", "Antenas maiores, retransmissor lunar, rede de antenas no solo", "Redes de espaço profundo"],
        ["Instrumentos", "Câmeras, espectrômetros, radar de gelo, sismômetros", "Orbitadores e pousadores lunares"],
        ["Aviônica e controle", "Rodas de reação, rastreador estelar, pouso autônomo", "Computadores de bordo, pouso guiado"],
        ["Vida e tripulação", "Cápsulas, suporte de vida, trajes, habitats", "Programas tripulados"],
        ["Recursos locais (ISRU)", "Extração de gelo, eletrólise, planta de propelente lunar", "Estudos de ISRU lunar"],
        ["Operações", "Mais missões simultâneas, automação, treino", "Centros de controle"],
    ], [3.4 * cm, 7.6 * cm, W - 11.0 * cm], bold_first=True))
    s += bullets([
        "Cada tecnologia libera peças do catálogo do hangar (<font name='Mono'>data/parts.json</font>), opções de "
        "subsistema, tipos de missão, alvos, prédios ou especializações.",
        "<b>Venda de tecnologia</b>: uma tecnologia pesquisada pode ser licenciada para um rival por dinheiro imediato. "
        "O rival ganha a tecnologia. É um trade-off direto entre caixa e corrida.",
        "<b>MVP</b>: cerca de 30 tecnologias, 6 por era. <b>Campanha completa</b>: cerca de 80.",
    ])
    s.append(PageBreak())


def agency(s):
    s.append(P("11. A agência: campus voxel 3D", "h1"))
    s.append(P("A tela principal é uma vista isométrica do campus da agência, no mesmo estilo voxel do hangar. "
               "Cometinhos andam entre os prédios, carregam caixas, testam peças e comemoram lançamentos, "
               "reaproveitando os NPCs do hangar (navegação, emotes, conversas). Clicar num prédio abre o painel dele."))
    s.append(table([
        ["Prédio", "Níveis", "Efeito", "Grupo"],
        ["Sede", "1–4", "Limite de funcionários; contratos simultâneos; contratação", "base"],
        ["Hangar de montagem", "1–4", "Altura e massa máximas de foguete; projetos em paralelo", "Hangar e plataformas"],
        ["Plataformas de lançamento", "pequena · média · pesada · tripulada", "Lançamentos por mês; maior família suportada", "Hangar e plataformas"],
        ["Laboratório de P&amp;D", "1–4", "Vagas de pesquisadores; +PP; ramos avançados", "Laboratórios"],
        ["Centro de controle", "1–3", "Missões ativas ao mesmo tempo; decisões em voo melhores", "Controle e antenas"],
        ["Rede de antenas", "1–3 (+ estações remotas)", "Multiplica o downlink de todas as missões", "Controle e antenas"],
        ["Centro de treinamento", "1–3", "Especializações; XP mais rápido; treino de pilotos", "Treino e fábrica"],
        ["Fábrica", "1–3", "Produção em série: −custo e −tempo por unidade repetida", "Treino e fábrica"],
        ["Câmara de testes", "1–2", "Slider de testes remove 50% mais defeitos", "Treino e fábrica"],
        ["Refeitório e dormitório (STRETCH)", "1–2", "Moral e recuperação de cochilos", "bem-estar"],
    ], [4.0 * cm, 3.4 * cm, 6.6 * cm, W - 14.0 * cm], bold_first=True))
    s += bullets([
        "O campus começa como um galpão, uma bancada e uma plataforma de sondagem. Lotes vazios ao redor mostram onde dá "
        "para construir.",
        "Construir leva semanas e Cometinhos operários aparecem trabalhando no lote.",
        "Cada prédio tem custo de manutenção mensal: crescer rápido demais quebra o caixa.",
        "Lançamentos acontecem no campus: o foguete da família sobe da plataforma visível, com a fumaça do sistema de voo.",
    ])
    s.append(PageBreak())


def economy(s):
    s.append(P("12. Economia", "h1"))
    s.append(table([
        ["Entrada", "Como funciona", "Valor inicial"],
        ["Orçamento do governo", "Pago no início de cada ano. Sobe com a reputação e com marcos conquistados.",
         "G = G_era × (0,5 + reputação/100)"],
        ["Contratos comerciais", "Satélites de clientes, observação, telecom. Pagamento na entrega + bônus por nota.", "40k a 600k cr por contrato"],
        ["Venda de tecnologia", "Licenciar uma tecnologia a um rival. O rival ganha a tecnologia.", "30–60% do custo em PP convertido"],
        ["Hype público", "Doações mensais e, depois da tecnologia “Loja”, pelúcias de Cometinho.", "hype × 400 cr/mês"],
        ["Prêmios de marco", "Pago no ato do “primeiro”. Segundo lugar recebe 30%.", "tabela da seção 13"],
    ], [3.6 * cm, 8.4 * cm, W - 12.0 * cm], bold_first=True))
    s.append(table([
        ["Saída", "Quando"],
        ["Salários", "Todo mês, por nível e profissão"],
        ["Manutenção de prédios", "Todo mês"],
        ["Custo de projeto", "Por semana de desenvolvimento (materiais e peças)"],
        ["Lançamento", "Custo da unidade da família de foguete (cai com a fábrica e a repetição)"],
        ["Operações", "Por semana de missão ativa (controle e antenas)"],
        ["Multas", "Contrato atrasado ou falho"],
    ], [5.0 * cm, W - 5.0 * cm], bold_first=True))
    s.append(P("Reputação, hype e falência", "h2"))
    s += bullets([
        "<b>Reputação</b> (0–100) mede confiança do governo e dos clientes. Muda devagar: notas, falhas, multas.",
        "<b>Hype</b> (0–100) mede atenção do público. Sobe rápido com tripuladas e marcos; cai 3% ao mês.",
        "Caixa negativo por 3 meses: o governo intervém. O jogador escolhe entre empréstimo com juros, demitir ou "
        "vender tecnologia. Não há game over por dinheiro no modo normal; no difícil, há.",
    ])
    s.append(PageBreak())


def race(s):
    s.append(P("13. A corrida: marcos e agências rivais", "h1"))
    s.append(P("Marcos (“primeiros”)", "h2"))
    s.append(table([
        ["#", "Marco", "Era", "Prêmio (cr)", "Reputação / hype"],
        ["1", "Primeiro voo suborbital", "1", "50k", "+3 / +10"],
        ["2", "Primeiro satélite em órbita", "1", "200k", "+6 / +20"],
        ["3", "Primeiro sinal de longa distância", "2", "150k", "+3 / +8"],
        ["4", "Primeiro Cometinho no espaço", "2", "300k", "+8 / +30"],
        ["5", "Primeiro Cometinho em órbita", "2", "400k", "+8 / +25"],
        ["6", "Primeira sonda a atingir a Lua", "3", "350k", "+6 / +20"],
        ["7", "Primeira foto do lado oculto", "3", "250k", "+4 / +15"],
        ["8", "Primeiro pouso robótico", "3", "500k", "+8 / +20"],
        ["9", "Gelo polar confirmado", "3", "400k", "+6 / +15"],
        ["10", "Primeiro sobrevoo tripulado da Lua", "4", "700k", "+10 / +35"],
        ["11", "Primeiro pouso tripulado", "4", "1,2M", "+15 / +50"],
        ["12", "Primeiro módulo de base", "5", "800k", "+8 / +20"],
        ["13", "Primeiro propelente feito na Lua", "5", "900k", "+8 / +20"],
        ["14", "<b>Base de partida operacional</b>", "5", "1,5M", "+15 / +40"],
        ["15", "<b>Encontro com a Mãe-Gelo</b>", "5", "vitória", "–"],
    ], [0.8 * cm, 6.6 * cm, 1.2 * cm, 2.4 * cm, W - 11.0 * cm]))
    s.append(P("Quem chega em segundo recebe 30% do prêmio e metade da reputação. A corrida <b>continua</b> mesmo se um "
               "rival conquistar a base de partida primeiro: o encontro com o cometa é a meta final e está aberto a todos."))
    s.append(P("Agências rivais (IA)", "h2"))
    s.append(table([
        ["Agência", "Personalidade", "Força", "Fraqueza"],
        ["Aurora Rubra", "Ousada; lança cedo e arrisca", "Chega primeiro em marcos tripulados", "Falha muito; perde meses com acidentes"],
        ["Consórcio Nimbo", "Comercial e rica", "Ganha contratos e licencia tecnologia", "Lenta em tripuladas"],
        ["Instituto Quietude", "Cientista e cautelosa", "Pesquisa rápida; quase não falha", "Gasta demais e demora"],
    ], [3.2 * cm, 4.2 * cm, 4.4 * cm, W - 11.8 * cm], bold_first=True))
    s.append(code("""
# progresso mensal de um rival r no proximo marco m
p_tentativa = 0.12 * capacidade_r / dificuldade_m * (1 + 0.5 * atraso_r)    # atraso_r: elástico suave
se tenta:  falha com prob = 0.25 * (1 - confiabilidade_r) * ousadia_r  -> recuo de 3 a 6 meses
           senao: conquista o marco (noticia no jornal; premio se for o primeiro)
capacidade_r cresce com o orcamento do rival, que cresce com os marcos dele
"""))
    s += bullets([
        "Os rivais são simulados de forma abstrata (sem projetos reais), com seed. Aparecem no jornal, no quadro da "
        "corrida e no mapa (as missões deles também ganham marcador).",
        "Rivais disputam contratos comerciais e compram tecnologia licenciada.",
        "Dificuldade ajusta capacidade inicial e o elástico.",
    ])
    s.append(PageBreak())


def map_ops(s):
    s.append(P("14. Mapa do sistema solar e operação das missões", "h1"))
    s.append(P("O mapa do sistema solar que já existe no jogo vira a <b>mesa de controle</b> da agência. Ele mostra "
               "todas as missões ativas (da agência e dos rivais) nas suas órbitas reais, calculadas pelas cônicas."))
    s += image(SHOTS / "flight_map_03_node_moon.png", W, 6.4 * cm,
               "Figura 5. Mapa existente com trajetória translunar e encontro com a Lua: base da tela de missões ativas.")
    s.append(P("Cartão da missão", "h2"))
    s += bullets([
        "Clicar numa missão abre o cartão: fase (cruzeiro, inserção, operação), saúde, energia, dados gerados / "
        "armazenados / baixados, ciência acumulada, próximos eventos.",
        "<b>Decisões de operação</b> (3 a 6 por missão, como no GDD anterior): por exemplo “armazenamento cheio: priorizar "
        "câmera ou espectrômetro?”, “roda de reação falhou: modo de segurança ou continuar?”, “tempestade solar: desligar "
        "instrumentos?”. Controladores de voo melhores revelam mais informação antes da escolha.",
        "<b>Assumir</b> (opcional): o botão abre a cena de voo com a nave montada; o jogador pilota a inserção ou o pouso. "
        "O resultado volta para o tycoon. Sem assumir, o resultado é resolvido pelas fórmulas.",
        "Transferências e inserções usam o planejador existente (manobras e inserção orbital automática), então o "
        "tempo de cruzeiro e o Δv mostrados são os mesmos do voo.",
    ])
    s.append(P("Operação semanal (resumo)", "h2"))
    s.append(code("""
para cada missao ativa, por semana:
    energia  = geracao(painel, distancia, eclipse) - consumo(modo)        -> bateria
    dados    = fluxo da secao 7 (gerado, armazenado, baixado)
    falhas   = sorteio por componente: lambda * estresse(orbita, radiacao) * (redundancia ? 0.25 : 1)
    eventos  = tabela do alvo (tempestade solar, micrometeorito, poeira lunar, noite lunar)
    ciencia += valor(baixado) * bonus_cientistas
"""))
    s.append(PageBreak())


def education(s):
    s.append(P("15. Educação: como o jogo ensina", "h1"))
    s.append(P("O enunciado pede que os conceitos sejam introduzidos dentro do jogo, de forma simples, sem só dizer "
               "certo ou errado (R16). Quatro mecanismos fazem isso juntos:"))
    s.append(P("15.1 Enciclopédia de missões reais", "h2"))
    s.append(P("Cada tecnologia, tipo de missão e marco desbloqueia uma ficha: o que é, por que importa, a missão "
               "real que inspirou e um número que o jogador acabou de sentir no jogo. Sem logos ou marcas oficiais."))
    s.append(table([
        ["Ficha (exemplos)", "Conceito ensinado"],
        ["Sputnik 1 (1957)", "Primeiro satélite artificial; órbita baixa"],
        ["Explorer 1 (1958)", "Ciência a bordo: cinturões de radiação"],
        ["Luna 2 e Luna 3 (1959)", "Impacto lunar; primeira foto do lado oculto"],
        ["Vostok 1 (1961)", "Primeiro voo tripulado em órbita"],
        ["Surveyor 1 (1966)", "Pouso suave robótico"],
        ["Apollo 8 e Apollo 11 (1968–69)", "Sobrevoo e pouso tripulado na Lua"],
        ["Landsat 1 (1972)", "Observação da Terra; órbita heliossíncrona"],
        ["Clementine (1994) e LCROSS (2009)", "Indícios e confirmação de gelo de água nos polos lunares"],
        ["Artemis (2020s)", "Retorno à Lua e planos de presença sustentada"],
        ["Rosetta (2004–2016)", "Encontro e pouso em um cometa"],
    ], [5.6 * cm, W - 5.6 * cm], bold_first=True))
    s.append(callout("<b>Checagem obrigatória.</b> Datas e fatos das fichas precisam ser conferidos em fontes oficiais "
                     "antes de entrar no jogo. O agente não deve inventar fatos: fichas sem fonte conferida ficam marcadas "
                     "<font name='Mono'>verified: false</font> no JSON e não aparecem no modo feira."))
    s.append(P("15.2 Conselheiros Cometinhos", "h2"))
    s.append(P("Quatro chefes de setor (Engenharia, Ciência, Operações, Confiabilidade) comentam as escolhas em balões "
               "curtos e <b>discordam entre si</b>, como no GDD anterior: o chefe de Ciência quer mais instrumentos, a "
               "chefe de Confiabilidade quer mais testes. O jogador aprende o conflito ouvindo os dois lados."))
    s.append(P("15.3 Relatório pós-missão", "h2"))
    s += bullets([
        "Resultado, notas dos jornais e a <b>cadeia causal</b> do fator limitante: “ciência 38% abaixo do previsto "
        "porque o armazenamento encheu antes do contato; uma antena média teria baixado 2,4× mais dados”.",
        "Comparação com um design alternativo calculado pelo jogo (o que teria acontecido com uma opção diferente).",
        "Quais barras e quais recursos pesaram, e qual Cometinho fez a diferença.",
    ])
    s.append(P("15.4 Contratos inspirados no Space Apps", "h2"))
    s.append(P("Uma família de contratos traz problemas reais da Terra e do espaço, com temas recorrentes nos desafios do "
               "NASA Space Apps. Cada contrato explica o problema real em um parágrafo, diz por que aquela órbita e aquele "
               "instrumento servem e aponta para dados abertos reais para quem quiser explorar depois."))
    s.append(table([
        ["Contrato", "Exige", "Ensina"],
        ["Vigia de queimadas", "Observação, órbita heliossíncrona, câmera infravermelha", "Revisita diária e órbitas sol-síncronas"],
        ["Ar limpo nas cidades", "Espectrômetro, órbita baixa", "Sensoriamento da atmosfera"],
        ["Enchentes e secas", "Radar ou câmera, cobertura frequente", "Resolução vs revisita"],
        ["Gelo marinho", "Órbita polar", "Por que órbitas polares cobrem a Terra toda"],
        ["Tempestades solares", "Clima espacial, órbita alta", "Alerta antecipado e proteção de satélites"],
        ["Lixo espacial", "Missão de rastreio ou remoção", "Detritos orbitais e sustentabilidade"],
        ["Mapa de recursos lunares", "Orbitador lunar com radar", "Prospecção de gelo antes da base"],
    ], [3.8 * cm, 6.0 * cm, W - 9.8 * cm], bold_first=True))
    s.append(PageBreak())


def multiplayer(s):
    s.append(P("16. Multijogador hot-seat, pontuação e fim de jogo", "h1"))
    s.append(P("16.1 Hot-seat (MVP para 2–4 agências)", "h2"))
    s += bullets([
        "Até 4 agências humanas no mesmo computador; vagas vazias podem ser preenchidas por rivais IA.",
        "O tempo passa em <b>turnos de 1 mês</b>: cada jogador faz o mês da sua agência e passa a vez. Quando todos "
        "terminam, o mundo simula o mês para todos de uma vez (com a mesma seed).",
        "Mundo compartilhado: marcos, contratos comerciais, licenciamento de tecnologia e o cometa são os mesmos para "
        "todos. Cada um vê só o próprio campus; o jornal mostra os anúncios de todos.",
        "Tela de passagem de vez esconde as informações do jogador anterior.",
        "<b>FUTURO</b>: online por turnos, usando o mesmo formato de estado e de decisões (o turno já é uma lista de comandos "
        "serializável).",
    ])
    s.append(P("16.2 Pontuação (atende R14)", "h2"))
    s.append(code("""
Pontuacao final (0..1000) = 1000 * ( 0.30 * Corrida      # marcos conquistados, ponderados (1o lugar = 1, 2o = 0.3)
                                   + 0.30 * Ciencia      # ciencia baixada total / referencia da dificuldade
                                   + 0.20 * Eficiencia   # ciencia + marcos por credito gasto
                                   + 0.20 * Reputacao )  # reputacao media nos ultimos 5 anos
Bonus de vitoria: +200 para quem fizer o encontro com a Mae-Gelo
"""))
    s.append(P("16.3 Fim de jogo", "h2"))
    s += bullets([
        "No fim do ano 25 a Mãe-Gelo passa. Quem tiver a missão ao cometa lançada a tempo e bem-sucedida faz o encontro.",
        "Vitória: cena dos Cometinhos chegando ao cometa. Mais de uma agência pode chegar; a ordem conta para a pontuação.",
        "Sem encontro: o jogo mostra o ranking final das agências e o relatório da campanha, com o que faltou.",
        "Depois do fim (<b>STRETCH</b>): modo livre com planetas, sem relógio.",
    ])
    s.append(P("16.4 Dificuldade (atende R15)", "h2"))
    s.append(table([
        ["Nível", "Efeito"],
        ["Cadete", "Rivais lentos, expectativas mais baixas, sem falência, dicas detalhadas"],
        ["Engenheiro(a)", "Padrão"],
        ["Diretor(a) de voo", "Rivais fortes, crescimento de massa e custo maior, falência possível, menos dicas"],
    ], [3.6 * cm, W - 3.6 * cm], bold_first=True))
    s.append(PageBreak())


def hackathon(s):
    s.append(P("17. Escopo do hackathon e campanha comprimida", "h1"))
    s.append(P("Decisão: os jurados jogam a <b>campanha inteira, comprimida</b>. O relógio acelera e cada era tem pouco "
               "conteúdo, mas todos os sistemas funcionam e a história fecha."))
    s.append(table([
        ["Parâmetro do modo feira", "Valor"],
        ["Duração alvo", "40 a 60 minutos de ponta a ponta"],
        ["1 semana", "1 s; auto-pausa só em decisões"],
        ["Tamanho dos projetos", "Semanas base × 0,5"],
        ["Conteúdo por era", "3 tipos de missão, 2 alvos, 6 tecnologias, 2 prédios, 3 contratos fixos"],
        ["Rivais", "2 rivais IA"],
        ["Tutorial", "Primeiro projeto guiado por um conselheiro (5 minutos)"],
        ["Ponto de entrada rápido", "Salvamentos prontos no início de cada era para demonstrar o jogo tardio"],
    ], [5.2 * cm, W - 5.2 * cm], bold_first=True))
    s.append(P("MVP do hackathon", "h2"))
    s += bullets([
        "Relógio, salvamento e seed; campus voxel com 4 prédios funcionais e Cometinhos andando.",
        "Projeto completo: contrato ou livre, alvo × tipo, opções da nave com os 6 recursos, família de foguete com "
        "projetista automático, 3 fases com sliders, Revisão de Projeto, lançamento, avaliação de 4 jornais e relatório.",
        "Equipe com as 7 profissões, contratação, níveis e moral.",
        "Pesquisa com cerca de 30 tecnologias; economia com governo, contratos, hype e venda de tecnologia.",
        "Corrida com os 15 marcos, 2 rivais IA, jornal e quadro da corrida; fim de jogo com a Mãe-Gelo.",
        "Mapa com missões ativas, só leitura, com 1 decisão de operação por missão.",
        "Hot-seat para 2 jogadores.",
        "Enciclopédia com 12 fichas conferidas; 4 contratos inspirados no Space Apps; inglês e português.",
    ])
    s.append(P("STRETCH (depois do MVP)", "h2"))
    s += bullets([
        "Assumir voo e abrir no hangar a partir do tycoon.",
        "Hot-seat com 4 jogadores; 3 rivais IA; eventos e decisões de operação completos.",
        "Planetas além da Lua; modo livre depois do cometa; refeitório e moral avançada.",
    ])
    s.append(callout("<b>Prazo real.</b> Hoje é 04/11 e o evento é 14–15/11. Antes de escrever código no evento, confirme "
                     "nas regras do Space Apps 2026 o que pode ser feito antes e como declarar código já existente. O "
                     "plano da seção 20 está ordenado para que qualquer corte deixe um jogo jogável."))
    s.append(PageBreak())


def reuse(s):
    s.append(P("18. Reaproveitamento do código existente", "h1"))
    s.append(P("O repositório MARGIN já tem a maior parte do “mundo físico” do jogo. O tycoon é uma camada nova de "
               "gestão em cima dele."))
    s.append(table([
        ["Sistema existente", "Arquivos", "Uso no tycoon"],
        ["Catálogo de peças (94)", "data/parts.json, src/core/part_db.gd (PartDB)", "Peças desbloqueadas pela pesquisa; montagem automática"],
        ["Matemática do foguete", "src/core/vessel_math.gd (VesselMath)", "Δv, TWR, massa e custo das famílias de foguetes"],
        ["Hangar", "scenes/hangar.tscn, src/hangar/*", "Opcional: abrir uma família para ajustar à mão"],
        ["Foguetes de exemplo", "src/hangar/example_vessels.gd", "Ponto de partida do projetista automático"],
        ["Tripulação", "src/crew/crew_member.gd, crew_roster.gd, crew_panel.gd", "Base da equipe; ganhar profissões, moral, salário"],
        ["Cometinhos (NPC)", "scenes/npc/*, src/npc/* (creature, npc_walker, hangar_crowd, cometling_looks)",
         "Campus vivo; cores de antena por profissão"],
        ["Sistema solar", "data/solar_system.json, src/flight/flight_solar.gd", "Alvos, distâncias, janelas"],
        ["Cônicas e trajetórias", "src/flight/flight_conic.gd, flight_trajectory.gd", "Δv e tempo de cruzeiro por alvo; posições no mapa"],
        ["Manobras e inserção orbital", "src/flight/flight_maneuvers.gd, flight_capture.gd", "Planejar transferências e capturas das missões"],
        ["Mapa do sistema solar", "scenes/flight/flight_map.tscn, src/flight/flight_map.gd", "Mesa de controle das missões ativas"],
        ["Voo", "scenes/flight/flight.tscn, src/flight/flight_world.gd, flight_session.gd", "Opcional: assumir lançamento ou pouso"],
        ["Superfícies voxel", "src/world/* (voxel_terrain, planet_surface)", "Cena da Lua para a base de partida (STRETCH)"],
        ["UI kit, tema e paleta", "ui/margin_theme.tres, ui/palette.gd, tools/make_ui_kit.py", "Todas as telas novas"],
        ["Traduções", "i18n/*.csv", "Novo CSV i18n/tycoon_strings.csv"],
    ], [3.6 * cm, 6.2 * cm, W - 9.8 * cm], bold_first=True))
    s.append(P("Mudanças necessárias nos sistemas existentes", "h2"))
    s += bullets([
        "<font name='Mono'>CrewMember.role</font> passa a aceitar as 7 profissões; <font name='Mono'>CometlingLooks</font> "
        "ganha as cores de antena novas. Manter compatibilidade com o roster salvo hoje (piloto, engenheiro, cientista "
        "viram piloto, engenheiro de sistemas, cientista).",
        "<font name='Mono'>FlightSession</font> recebe um modo “missão do tycoon” que devolve o resultado do voo.",
        "<font name='Mono'>FlightMap</font> ganha uma camada de missões ativas (marcadores e cartões) sem depender de uma "
        "nave ativa.",
    ])
    s.append(PageBreak())


def architecture(s):
    s.append(P("19. Arquitetura técnica e dados", "h1"))
    s.append(P("19.1 Módulos novos (src/tycoon/)", "h2"))
    s.append(table([
        ["Classe", "Tipo", "Responsabilidade"],
        ["TycoonGame", "Node (cena raiz)", "Liga estado, relógio, telas e salvamento"],
        ["TycoonClock", "RefCounted", "Semanas, pausa, 3 velocidades, modo feira, turnos mensais do hot-seat, auto-pausa"],
        ["TycoonState", "RefCounted", "Estado serializável da partida: seed, ano, agências, mundo"],
        ["Agency", "RefCounted", "Caixa, reputação, hype, prédios, equipe, tecnologias, famílias, projetos, missões"],
        ["MissionProject", "RefCounted", "Alvo, tipo, veículo, opções da nave, fases, sliders, pontos, defeitos"],
        ["PayloadDesigner", "RefCounted", "Opções da nave → massa, energia, dados, comunicação, custo; peças para o voxel"],
        ["RocketDesigner", "RefCounted", "3 propostas de família (Barata, Equilibrada, Robusta) com VesselMath"],
        ["DesignReview", "RefCounted", "Confere os 6 recursos; diz o fator mais arriscado"],
        ["LaunchResolver", "RefCounted", "Chance de sucesso, sorteio com seed, resultado"],
        ["MissionOps", "RefCounted", "Operação semanal das missões ativas, eventos e decisões"],
        ["ReviewBoard", "RefCounted", "4 jornais, notas e recompensas"],
        ["ResearchTree", "RefCounted", "Tecnologias, PP, desbloqueios"],
        ["Economy", "RefCounted", "Entradas e saídas mensais e anuais, falência"],
        ["ContractBoard", "RefCounted", "Ofertas, disputa com rivais, multas"],
        ["RaceDirector", "RefCounted", "Marcos, rivais IA, jornal"],
        ["EventDirector", "RefCounted", "Eventos aleatórios por tabela"],
        ["TycoonSave", "RefCounted", "JSON em user://tycoon_save_N.json"],
    ], [3.4 * cm, 3.0 * cm, W - 6.4 * cm], bold_first=True))
    s.append(P("Regra: toda a lógica é RefCounted e roda <b>sem cena</b>, para testes headless. As cenas só leem o "
               "estado e enviam comandos."))
    s.append(P("19.2 Comandos e turnos", "h2"))
    s.append(P("Toda ação do jogador vira um <b>comando</b> serializável aplicado ao estado: "
               "<font name='Mono'>{\"t\": \"start_project\", \"agency\": 0, \"contract\": \"c12\", ...}</font>. Isso dá "
               "desfazer na tela de projeto, replays de teste, hot-seat (lista de comandos por turno) e, no futuro, online."))
    s.append(P("19.3 Arquivos de dados (data/tycoon/)", "h2"))
    s.append(table([
        ["Arquivo", "Conteúdo"],
        ["eras.json", "Anos, G_era, E_era, conteúdo liberado, multiplicadores do modo feira"],
        ["targets.json", "Alvo, corpo, tipo de órbita, Δv a partir da órbita baixa, semanas de cruzeiro, fator de distância"],
        ["mission_types.json", "Proporção ideal das barras, semanas base, tamanho, requisitos, desbloqueio"],
        ["compat.json", "Matriz tipo × alvo"],
        ["payload_options.json", "Opções por subsistema: massa, energia, dados, comunicação, custo, peças"],
        ["professions.json", "Barras, afinidades, salários, cor da antena"],
        ["techs.json", "Ramo, custo, pré-requisitos, desbloqueios, ficha da enciclopédia"],
        ["buildings.json", "Níveis, custo, manutenção, efeitos"],
        ["milestones.json", "Marcos, dificuldade, prêmios"],
        ["rivals.json", "Personalidades e parâmetros"],
        ["contracts.json", "Modelos de contrato, incluindo os do Space Apps (flag space_apps)"],
        ["events.json", "Eventos, condições, escolhas e efeitos"],
        ["encyclopedia.json", "Fichas, chave de tradução, fonte, verified"],
        ["newspapers.json", "Jornais e vieses"],
    ], [4.0 * cm, W - 4.0 * cm], bold_first=True))
    s.append(P("Exemplo de esquema", "h3"))
    s.append(code("""
// data/tycoon/mission_types.json (trecho)
{ "id": "earth_obs", "name_key": "TY_MT_EARTH_OBS", "ideal": {"eng": 0.25, "sci": 0.35, "ops": 0.25, "rel": 0.15},
  "base_weeks": 6, "size": 1.0, "needs": ["camera_or_radar"], "unlock_tech": "tech_obs_1",
  "encyclopedia": "enc_landsat_1" }
"""))
    s.append(P("19.4 Cenas (scenes/tycoon/)", "h2"))
    s += bullets([
        "<font name='Mono'>tycoon_game.tscn</font>: raiz; <font name='Mono'>campus.tscn</font>: campus voxel com lotes, "
        "prédios e NPCs; <font name='Mono'>ui/</font>: barra superior (caixa, data, velocidade, reputação, hype), "
        "assistente de projeto, revisão, relatório, equipe, pesquisa, prédios, contratos, corrida, jornal, enciclopédia, "
        "passagem de vez do hot-seat.",
        "Mapa: instância de <font name='Mono'>flight_map.tscn</font> no modo agência.",
    ])
    s.append(P("19.5 Testes", "h2"))
    s += bullets([
        "<font name='Mono'>tests/test_tycoon_core.gd</font>: pontos, defeitos, nota, determinismo por seed.",
        "<font name='Mono'>tests/test_tycoon_economy.gd</font>: 25 anos simulados por um jogador automático simples "
        "não falem na dificuldade padrão; caixa e reputação ficam em faixas.",
        "<font name='Mono'>tests/test_tycoon_race.gd</font>: rivais conquistam marcos em anos plausíveis (tabela da seção 13).",
        "<font name='Mono'>tests/screenshot_tycoon.gd</font>: prints do campus e das telas principais.",
    ])
    s.append(PageBreak())


def plan(s):
    s.append(P("20. Plano de implementação com critérios de aceite", "h1"))
    s.append(P("Cada etapa termina com um jogo que roda. A ordem garante que um corte no hackathon ainda deixe o loop "
               "principal jogável."))
    steps = [
        ("E0 Fundamentos", "Carregadores de data/tycoon/*.json; TycoonState, TycoonClock, TycoonSave, RNG com seed; "
         "CSV de traduções.",
         "Salvar e carregar dão o mesmo estado; 52 semanas com a mesma seed dão o mesmo resultado; teste headless passa."),
        ("E1 Loop de projeto", "MissionProject, 3 fases, sliders, pontos, defeitos, nota, ReviewBoard; equipe com 7 "
         "profissões; tela de projeto e de avaliação simples (sem campus).",
         "Um projeto de sondagem vai do início à nota; mudar sliders muda a nota de forma previsível; teste cobre a fórmula."),
        ("E2 Nave, foguete e revisão", "PayloadDesigner, RocketDesigner (VesselMath), DesignReview com os 6 recursos, "
         "LaunchResolver, relatório pós-missão com fator limitante.",
         "Instrumento extra muda massa, energia, dados e custo; revisão bloqueia no vermelho; relatório cita a causa certa "
         "em 5 cenários de teste."),
        ("E3 Agência", "ResearchTree, prédios, Economy, ContractBoard; campus voxel com lotes, prédios e NPCs andando.",
         "Pesquisar libera peça e tipo de missão; prédio muda capacidade; 25 anos automáticos sem falência no padrão."),
        ("E4 Corrida e fim", "RaceDirector, 2 rivais IA, 15 marcos, jornal, quadro da corrida, Mãe-Gelo, pontuação final, "
         "modo feira.",
         "Partida no modo feira termina em 40–60 min com um jogador de teste; rivais conquistam marcos em anos plausíveis."),
        ("E5 Mapa de missões", "Camada de missões ativas no FlightMap, cartão da missão, MissionOps semanal, 1 decisão "
         "por missão.",
         "Missão lunar aparece na órbita certa; dados baixados mudam com a rede de antenas."),
        ("E6 Hot-seat e educação", "Turnos mensais para 2 jogadores, tela de passagem; enciclopédia com 12 fichas "
         "conferidas; 4 contratos Space Apps; tutorial.",
         "Dois jogadores completam 2 anos de jogo; fichas sem fonte não aparecem."),
        ("E7 STRETCH", "Assumir voo, abrir no hangar, 4 jogadores, 3 rivais, mais eventos, planetas.", "Definidos na etapa."),
    ]
    s.append(table([["Etapa", "Entrega", "Critério de aceite"]] + [list(x) for x in steps],
                   [2.6 * cm, 7.4 * cm, W - 10.0 * cm], bold_first=True))
    s.append(PageBreak())


def risks(s):
    s.append(P("21. Riscos e decisões em aberto", "h1"))
    s.append(table([
        ["Risco", "Mitigação"],
        ["Escopo de 25 anos não cabe no hackathon", "Modo feira, pouco conteúdo por era, plano em etapas jogáveis"],
        ["Fórmulas desbalanceadas", "Tudo em JSON; teste de 25 anos automático; playtest com a equipe antes do evento"],
        ["Jogador não entende os sliders", "Tutorial guiado, conselheiros, prévia do efeito de cada slider"],
        ["Hot-seat confuso", "Tela de passagem de vez; turnos curtos; resumo do mês no início de cada turno"],
        ["Fatos históricos errados", "Fichas com fonte e flag verified; modo feira só mostra fichas conferidas"],
        ["Regras do Space Apps sobre trabalho prévio", "Confirmar antes do evento e declarar o código existente"],
        ["Uso de marca da NASA", "Nenhum logo, emblema ou nome de programa como marca do jogo; só referência histórica"],
    ], [5.6 * cm, W - 5.6 * cm], bold_first=True))
    s.append(P("Decisões em aberto", "h2"))
    s += numbered([
        "Logo do Cometworks (direção na seção 22.7).",
        "Nome do cometa de origem (trabalho: <b>Mãe-Gelo</b>) e dos rivais.",
        "Se o modo feira também tem hot-seat na apresentação aos jurados.",
        "Quanto do voo manual entra até o evento (STRETCH por padrão).",
        "Visual do campus: uma ilha, um vale ou um platô; quantos lotes.",
    ])
    s.append(PageBreak())


def swatch_table(rows):
    data = [[Paragraph(h, ST["hcell"]) for h in ["", "Token", "Hex", "Uso"]]]
    style = [("GRID", (0, 0), (-1, -1), 0.4, GRID), ("BACKGROUND", (0, 0), (-1, 0), INK),
             ("VALIGN", (0, 0), (-1, -1), "MIDDLE"), ("TOPPADDING", (0, 0), (-1, -1), 3),
             ("BOTTOMPADDING", (0, 0), (-1, -1), 3)]
    for i, (tok, hx, use) in enumerate(rows, 1):
        data.append(["", Paragraph(f"<font name='Mono'>{tok}</font>", ST["cell"]),
                     Paragraph(f"<font name='Mono'>{hx}</font>", ST["cell"]), Paragraph(use, ST["cell"])])
        style.append(("BACKGROUND", (0, i), (0, i), colors.HexColor(hx)))
    t = Table(data, colWidths=[0.9 * cm, 3.6 * cm, 2.0 * cm, W - 6.5 * cm])
    t.setStyle(TableStyle(style))
    return t


def screen_mock():
    """Main-screen wireframe drawn in the art direction's own colours."""
    ink, panel, line, hair = (colors.HexColor(h) for h in ("#070B14", "#0E1524", "#24324D", "#3A4D72"))
    teal, violet, orange, ice, dim = (colors.HexColor(h) for h in ("#3FE0C5", "#8E7CFF", "#FF8A3D", "#BFE8FF", "#8C9AB5"))
    txt = colors.HexColor("#E9EEF7")
    w, h = W, 9.2 * cm
    d = Drawing(w, h)
    d.add(Rect(0, 0, w, h, fillColor=ink, strokeColor=None))
    for k in range(1, 12):
        d.add(Line(k * w / 12, 0, k * w / 12, h, strokeColor=colors.HexColor("#0F1830"), strokeWidth=0.5))
    for k in range(1, 7):
        d.add(Line(0, k * h / 7, w, k * h / 7, strokeColor=colors.HexColor("#0F1830"), strokeWidth=0.5))
    cx, cy = w * 0.47, h * 0.42
    for dx, dy, bw, bh, col in ((-60, 0, 46, 30, "#2A3A5C"), (10, 18, 60, 38, "#33466E"), (80, -6, 34, 22, "#2A3A5C"),
                                (-20, -40, 40, 26, "#22304D")):
        d.add(Polygon([cx + dx, cy + dy, cx + dx + bw, cy + dy + bw * 0.35, cx + dx + bw, cy + dy + bw * 0.35 + bh,
                       cx + dx, cy + dy + bh], fillColor=colors.HexColor(col), strokeColor=hair, strokeWidth=0.5))
    d.add(Line(cx + 130, cy - 30, cx + 130, cy + 60, strokeColor=orange, strokeWidth=2.2))
    d.add(String(cx + 136, cy + 52, "plataforma", fontName="UI", fontSize=6, fillColor=dim))
    # top instrument strip with the aurora thread
    d.add(Rect(8, h - 30, w - 16, 22, fillColor=panel, strokeColor=line, strokeWidth=0.6))
    third = (w - 16) / 3
    for k, col in enumerate((teal, violet, orange)):
        d.add(Line(8 + k * third, h - 8, 8 + (k + 1) * third, h - 8, strokeColor=col, strokeWidth=1.6))
    for i, (lab, val) in enumerate((("ANO", "07 · SEM 23"), ("CAIXA", "1 284k cr"), ("REPUTAÇÃO", "64"),
                                     ("HYPE", "41"), ("COMETA", "T− 18a 29s"))):
        x = 20 + i * (w - 40) / 5
        d.add(String(x, h - 18, lab, fontName="UI-B", fontSize=5.5, fillColor=dim))
        d.add(String(x, h - 26, val, fontName="Mono", fontSize=7.5, fillColor=ice))
    # left rail of buildings
    d.add(Rect(8, 48, 34, h - 88, fillColor=panel, strokeColor=line, strokeWidth=0.6))
    for i in range(7):
        d.add(Rect(15, h - 64 - i * 26, 20, 18, fillColor=colors.HexColor("#152036"), strokeColor=hair, strokeWidth=0.4))
    # race board with chamfered corner
    rx = w - 150
    d.add(Rect(rx, 96, 142, h - 136, fillColor=panel, strokeColor=line, strokeWidth=0.6))
    d.add(Polygon([rx + 132, h - 40, rx + 143, h - 40, rx + 143, h - 51], fillColor=ink, strokeColor=None))
    d.add(String(rx + 8, h - 52, "CORRIDA · RÁDIO DA CAUDA", fontName="UI-B", fontSize=6, fillColor=dim))
    for i, (name, prog, col) in enumerate((("Cometworks", 0.62, orange),
                                           ("Aurora Rubra", 0.70, colors.HexColor("#FF5C6C")),
                                           ("Nimbo", 0.48, ice), ("Quietude", 0.55, violet))):
        y = h - 70 - i * 22
        d.add(String(rx + 8, y, name, fontName="UI", fontSize=6.5, fillColor=txt))
        for seg in range(15):
            d.add(Rect(rx + 8 + seg * 8.2, y - 9, 6.6, 4, fillColor=col if seg / 15 < prog else line, strokeColor=None))
    # project flight strips
    sw = (w - 210) / 3 - 8
    for i, (name, ph, col) in enumerate((("SAT-07 · Observação · fase 2/3", 0.55, teal),
                                         ("SND-12 · Sondagem · revisão", 0.95, orange),
                                         ("LUA-01 · Orbitador · fase 1/3", 0.2, violet))):
        x = 50 + i * (sw + 8)
        d.add(Rect(x, 10, sw, 30, fillColor=panel, strokeColor=line, strokeWidth=0.6))
        d.add(Rect(x, 10, 3, 30, fillColor=col, strokeColor=None))
        d.add(String(x + 8, 29, name, fontName="UI-B", fontSize=6, fillColor=txt))
        d.add(Rect(x + 8, 16, sw - 16, 4, fillColor=line, strokeColor=None))
        d.add(Rect(x + 8, 16, (sw - 16) * ph, 4, fillColor=col, strokeColor=None))
    d.add(Rect(w - 150, 10, 142, 30, fillColor=orange, strokeColor=None))
    d.add(String(w - 79, 22, "NOVO PROJETO", fontName="UI-B", fontSize=8, fillColor=ink, textAnchor="middle"))
    return d


def art_direction(s):
    s.append(P("22. Direção de arte da interface: Aurora de observatório", "h1"))
    s.append(P("Pedido: a aurora da cauda de um cometa, com pegada espacial, <b>sem</b> o vidro fosco da moda e "
               "<b>sem</b> a cara genérica de interface gerada por IA. A metáfora escolhida é o <b>painel de "
               "instrumentos de um observatório à noite</b>: superfícies opacas e escuras como metal pintado, gravações "
               "finas, leituras numéricas precisas e, de vez em quando, um fio de aurora acendendo um detalhe."))
    s.append(callout("<b>Frase-guia:</b> “equipamento de verdade, operado por criaturinhas fofas”. A interface é séria "
                     "como um console de missão; a fofura vem dos Cometinhos, dos emblemas e das reações, nunca de "
                     "cores de bala ou cantos de brinquedo.", VIOLET, colors.HexColor("#EFECFF")))
    s.append(P("22.1 Paleta (tokens)", "h2"))
    s.append(swatch_table([
        ("space.0", "#070B14", "Fundo do céu, faixas de vazio"),
        ("panel", "#0E1524", "Painéis (opacos, 100%)"),
        ("panel.raised", "#152036", "Campos, linhas selecionadas, botões secundários"),
        ("line", "#24324D", "Divisórias, trilhos de barra vazios"),
        ("hairline.hi", "#3A4D72", "Bordas gravadas, marcas de canto"),
        ("text", "#E9EEF7", "Texto principal"),
        ("text.dim", "#8C9AB5", "Rótulos, unidades, legendas"),
        ("aurora.teal", "#3FE0C5", "Operações; sucesso; início do gradiente"),
        ("aurora.violet", "#8E7CFF", "Confiabilidade; pesquisa; meio do gradiente"),
        ("ignition", "#FF8A3D", "Ação principal (uma por tela); Engenharia; fim do gradiente"),
        ("comet.ice", "#BFE8FF", "Ciência; números e leituras"),
        ("warning", "#FFC547", "Margem amarela"),
        ("danger", "#FF5C6C", "Margem vermelha, falha"),
    ]))
    s.append(P("As 4 barras usam sempre as mesmas cores: Engenharia <b>ignition</b>, Ciência <b>comet.ice</b>, "
               "Operações <b>aurora.teal</b>, Confiabilidade <b>aurora.violet</b>. A antena de cada Cometinho acende na "
               "cor da barra da sua profissão, então dá para ver no campus quem trabalha em quê."))
    s.append(P("22.2 Tipografia", "h2"))
    s.append(table([
        ["Papel", "Fonte (licença aberta, embutida no jogo)", "Uso"],
        ["Títulos", "Bricolage Grotesque (OFL), semibold", "Nomes de tela, logo, manchetes do jornal"],
        ["Texto", "Atkinson Hyperlegible (OFL)", "Corpo, botões, explicações; feita para legibilidade, boa para o público jovem"],
        ["Números", "IBM Plex Mono (OFL), algarismos tabulares", "Telemetria, dinheiro, datas, contagens"],
        ["Rótulos", "Atkinson em versalete, espaçamento +8%", "CAIXA, REPUTAÇÃO, FASE 2/3"],
    ], [2.4 * cm, 6.2 * cm, W - 8.6 * cm], bold_first=True))
    s.append(P("Fallback enquanto as fontes não estão no repositório: Bahnschrift, Segoe UI e Consolas, já usadas no "
               "tema atual. Escala de tamanhos: 12 · 14 · 16 · 20 · 28 · 40 px em 1600×900."))
    s.append(P("22.3 Formas e superfícies", "h2"))
    s += bullets([
        "<b>Painéis opacos</b>, nunca translúcidos. A profundidade vem do tom (panel → panel.raised) e de uma sombra "
        "curta e dura (2 px, sem blur), não de desfoque.",
        "<b>Borda gravada</b> de 1 px em hairline.hi e <b>marcas de canto</b> (pequenos “L” de 6 px), como a moldura de "
        "um instrumento.",
        "<b>Um canto chanfrado</b> por painel (superior direito, corte de 10 px). Os outros cantos têm raio de 4 px. É "
        "a assinatura visual do Cometworks.",
        "<b>Textura</b>: grão fino (ruído a 3% de opacidade) dentro dos painéis e uma grade de carta celeste quase "
        "invisível no fundo. Isso tira o aspecto de vetor liso.",
        "<b>A aurora é um fio, não um banho</b>: o gradiente teal → violeta → laranja aparece só como linha de 2 px no "
        "topo da barra superior, no foco de um campo e no progresso do cometa. Nunca como fundo de cartão.",
    ])
    s.append(P("22.4 Componentes", "h2"))
    s.append(table([
        ["Componente", "Como é"],
        ["Barra superior de instrumentos", "Faixa única com ANO/SEMANA, caixa, reputação, hype e contagem do cometa em "
         "mono; o fio da aurora no topo; velocidade do tempo como 4 teclas físicas (pausa, 1, 2, 3)."],
        ["Fitas de projeto", "Projetos ativos como <i>flight strips</i> de controle de tráfego aéreo: retângulo baixo com "
         "tarja da cor do tipo, código (SAT-07), fase e régua de progresso. Ficam empilhadas embaixo e podem ser "
         "arrastadas para mudar a prioridade."],
        ["Sliders de fase", "Alavancas de acelerador verticais com entalhes a cada 10%, lado a lado; o total aparece "
         "numa janelinha mono. Mexer numa puxa as outras."],
        ["Barras de qualidade", "Medidores de LED segmentados (15 segmentos) nas cores das barras; a proporção ideal "
         "aparece como marcas gravadas sobre o trilho."],
        ["Medidores dos 6 recursos", "Mostradores semicirculares pequenos com ponteiro e faixa verde/amarela/vermelha, "
         "mais o número; ícone e cor juntos (acessibilidade)."],
        ["Botões", "Primário: bloco cheio em ignition, texto escuro em versalete, um por tela. Secundário: contorno "
         "hairline. Interruptores: alavancas de duas posições, não pílulas de celular."],
        ["Jornal e rádio", "Rádio da Cauda: faixa de texto que corre no quadro da corrida; manchetes em Bricolage, "
         "como recortes de papel presos com fita sobre o painel (o único elemento de papel da UI)."],
        ["Marcos", "Emblemas de missão bordados (patches circulares voxel) carimbados no mural da agência com uma "
         "animação curta de prensa."],
        ["Conselheiros", "Retrato 3D do Cometinho num visor redondo com borda gravada; fala em balão retangular reto, "
         "não em bolha arredondada genérica."],
    ], [4.0 * cm, W - 4.0 * cm], bold_first=True))
    s.append(P("22.5 Tela principal", "h2"))
    s.append(screen_mock())
    s.append(P("Figura 6. Esboço da tela principal: barra de instrumentos no topo, trilho de prédios à esquerda, campus "
               "voxel ao centro, quadro da corrida e Rádio da Cauda à direita, fitas de projeto embaixo e o único botão "
               "primário (Novo projeto).", "small"))
    s.append(P("22.6 Movimento e som", "h2"))
    s += bullets([
        "Painéis entram deslizando 8 px com fade de 140 ms, curva <i>ease-out</i> cúbica. Sem quique na interface.",
        "Números sobem contando (dinheiro, notas). Barras de LED acendem segmento por segmento.",
        "Quem quica e exagera são os Cometinhos: comemoram, tropeçam, cochilam. A interface fica calma.",
        "Sons secos de equipamento: clique de chave, relé, bipe de telemetria. Lançamento com ronco grave.",
    ])
    s.append(P("22.7 Ícones e logo", "h2"))
    s += bullets([
        "Ícones de prédios e de tipos de missão são <b>miniaturas voxel</b> renderizadas do próprio jogo (como os ícones "
        "de peças do hangar), sobre fundo panel.raised. Ícones de interface: traço de 1,5 px, cantos retos.",
        "Logo: a palavra <b>COMETWORKS</b> em Bricolage, com o “O” de COMET trocado pela lâmpada-estrela de quatro pontas "
        "da antena dos Cometinhos, e uma cauda fina saindo dela nas cores da aurora.",
    ])
    s.append(P("22.8 Regras contra a “cara de IA”", "h2"))
    s.append(table([
        ["Evitar", "Fazer no lugar"],
        ["Vidro fosco com blur atrás", "Painel opaco com borda gravada e grão"],
        ["Gradiente roxo-rosa cobrindo cartões", "Fio de aurora de 2 px, só em 3 lugares"],
        ["Brilho neon e sombras difusas em tudo", "Sombra dura de 2 px; brilho só na antena dos Cometinhos e no foguete"],
        ["Grade de cartões iguais (bento)", "Layout assimétrico guiado pela função: fitas, alavancas, mostradores"],
        ["Emoji como ícone", "Miniaturas voxel e ícones de traço próprios"],
        ["Cantos muito arredondados em tudo", "4 px e um canto chanfrado"],
        ["Texto genérico de marketing", "Voz dos Cometinhos e termos reais de missão"],
        ["Inter ou Poppins por padrão", "Bricolage, Atkinson e Plex Mono"],
    ], [6.0 * cm, W - 6.0 * cm], bold_first=True))
    s.append(P("22.9 Implementação no Godot", "h2"))
    s += bullets([
        "Novo tema <font name='Mono'>ui/cometworks_theme.tres</font>: StyleBoxes de painel com borda e canto chanfrado, "
        "marcas de canto, botões, sliders verticais e barras segmentadas.",
        "Tokens em <font name='Mono'>ui/cometworks_palette.gd</font> (class_name <font name='Mono'>CwPalette</font>), nos "
        "mesmos moldes de <font name='Mono'>MarginPalette</font>.",
        "Painel com canto chanfrado, marcas de canto e grão desenhado por um Control próprio "
        "(<font name='Mono'>CwPanel</font>) ou por um shader de CanvasItem único; nada de textura grande.",
        "Cena de vitrine <font name='Mono'>scenes/tycoon/ui/cw_ui_kit.tscn</font> com todos os componentes, para revisar "
        "a direção de arte num só lugar.",
    ])
    s.append(PageBreak())


def appendix_prompt(s):
    s.append(P("Apêndice A: megaprompt para o agente de código", "h1"))
    s.append(P("Cole o bloco abaixo no Claude Code, na raiz do repositório MARGIN, trocando <b>&lt;ETAPA&gt;</b> pela "
               "etapa da seção 20. Junte este PDF à conversa ou aponte para o caminho dele."))
    s.append(code("""
Voce esta no repositorio MARGIN (Godot 4.6, GDScript). Leia docs/GDD_Cometworks.pdf:
ele e a especificacao do jogo "Cometworks", um tycoon de agencia espacial dos Cometinhos que
substitui a direcao anterior do MARGIN para o NASA Space Apps Challenge 2026.

Tarefa: implementar a etapa <ETAPA> da secao 20, e somente ela.

Regras:
1. Reaproveite os sistemas da secao 18 (PartDB, VesselMath, CrewRoster, Cometinhos NPC,
   FlightSolar, FlightConic, FlightTrajectory, FlightCapture, FlightMap, UI kit, i18n).
2. Logica em src/tycoon/ como RefCounted, sem depender de cena; testavel headless.
3. Numeros em data/tycoon/*.json (valores iniciais do Apendice C), nunca fixos no codigo.
4. Visual em cenas .tscn editaveis; scripts so preenchem dados. Textos so por chaves de
   traducao em i18n/tycoon_strings.csv (en e pt).
5. Toda aleatoriedade usa o RNG com seed do TycoonState. Mesma seed + mesmos comandos = mesmo resultado.
6. Acoes do jogador sao comandos serializaveis aplicados ao estado (secao 19.2).
7. Nao implemente nada marcado STRETCH ou FUTURO. Nao invente fatos historicos: fichas da
   enciclopedia sem fonte conferida ficam com "verified": false.
8. Escreva o teste headless da etapa em tests/ e rode:
   godot --headless --path . --script res://tests/<teste>.gd
   A etapa so termina quando os criterios de aceite da secao 20 passam.
9. Interface: siga a secao 22 (Aurora de observatorio). Use os tokens de cor e tipografia do
   tema ui/cometworks_theme.tres; paineis opacos (sem blur), bordas finas com marcas de canto,
   gradiente da aurora so como linha fina; nada de emoji como icone, nada de vidro fosco,
   nada de grade generica de cartoes iguais.
10. Commits pequenos e frequentes, so com a conta do autor, sem linha de coautoria.
11. Ao terminar: resuma o que foi feito, o que ficou de fora e o resultado dos testes.
"""))
    s.append(P("Prompts curtos por tela (para pedir ajustes)", "h2"))
    s += bullets([
        "“Monte a tela de projeto (seção 6.2 a 6.4) com o UI kit: alvo e tipo primeiro, depois opções da nave com os 6 "
        "medidores ao vivo, depois a família de foguete.”",
        "“Monte o campus voxel (seção 11) com 8 lotes, os 4 prédios do MVP e os NPCs do hangar andando entre eles.”",
        "“Gere o relatório pós-missão (seção 15.3) com a cadeia causal do fator limitante e um design alternativo.”",
    ])
    s.append(PageBreak())


def appendix_compliance(s):
    s.append(P("Apêndice B: conformidade com o enunciado", "h1"))
    s.append(P("Itens do desafio <i>Space Mission Design Game</i> (numeração do GDD anterior) e onde o tycoon os atende."))
    rows = [
        ["#", "Exigência", "Onde no jogo", "MVP"],
        ["R1", "Projetar, gerenciar e simular uma missão completa", "Seções 6, 7, 14", "sim"],
        ["R2", "Decisões de engenharia e recursos limitados", "Sliders, opções da nave, 6 recursos", "sim"],
        ["R3", "Avaliar como cada escolha molda o sucesso", "Revisão, notas, relatório", "sim"],
        ["R4", "Individual ou equipe de até 4", "Solo e hot-seat de rivais humanos", "2 jog."],
        ["R5", "Objetivo antes da nave", "Assistente: alvo e tipo antes das opções", "sim"],
        ["R6", "Subsistemas da nave", "Opções da nave (seção 8.1)", "sim"],
        ["R7", "Instrumentos com massa, energia, dados, custo, valor", "payload_options.json", "sim"],
        ["R8", "Várias órbitas, com explicação", "Alvos + fichas", "sim"],
        ["R9", "Lançadores com capacidade, custo e restrição", "Famílias de foguetes + revisão", "sim"],
        ["R10", "Massa, energia, orçamento, dados, comunicação, tempo", "Seção 7", "sim"],
        ["R11", "Cada decisão tem consequência", "Efeito dominó ao vivo", "sim"],
        ["R12", "Sem solução única perfeita", "Proporções ideais, trade-offs, rivais", "sim"],
        ["R13", "Feedback claro de sucesso ou falha", "Relatório pós-missão", "sim"],
        ["R14", "Pontuação", "Seção 16.2", "sim"],
        ["R15", "Dificuldades, tipos de missão ou cenários", "3 dificuldades, 17 tipos, 5 eras", "sim"],
        ["R16", "Conceitos ensinados dentro do jogo", "Seção 15", "sim"],
        ["R17", "Extras: eventos, dashboards, ranking, relatório, sandbox, coop/competitivo", "Eventos, mapa, ranking, hot-seat", "parcial"],
    ]
    s.append(table(rows, [1.0 * cm, 6.4 * cm, 6.4 * cm, W - 13.8 * cm]))
    s.append(PageBreak())


def appendix_balance(s):
    s.append(P("Apêndice C: valores iniciais de balanceamento", "h1"))
    s.append(P("Pontos de partida para o primeiro playtest. Todos vão para data/tycoon/*.json."))
    s.append(table([
        ["Parâmetro", "Valor inicial", "Nota"],
        ["Caixa inicial", "300k cr", "Dá para 2 projetos de sondagem e 4 Cometinhos por 6 meses"],
        ["Equipe inicial", "4: engenheiro(a) de sistemas, cientista, técnico(a) de testes, controlador(a) de voo", ""],
        ["G_era (orçamento do governo por ano)", "400k · 900k · 1,8M · 3,2M · 5M", "eras 1 a 5"],
        ["E_era (expectativa de pontos)", "60 · 140 · 260 · 420 · 600", "multiplicado pelo tamanho do tipo"],
        ["Salário mensal", "nível 1: 4k · cada nível +25%", "piloto +30%"],
        ["Taxa de contratação", "2 salários", ""],
        ["Custo de projeto por semana", "6k × tamanho × fator da era (1 · 1,6 · 2,4 · 3,4 · 4,5)", ""],
        ["Lançamento (unidade)", "sondagem 30k · leve 150k · médio 450k · pesado 1,2M · lunar 2,5M", "−20% com fábrica nível 3"],
        ["Manutenção de prédio", "2% do custo de construção por mês", ""],
        ["Pontos de pesquisa", "pesquisador(a): 8 PP/semana × (0,4 + 0,6 habilidade)", "+50% com laboratório nível 3"],
        ["Custo de tecnologia", "era 1: 80 PP · era 5: 900 PP", ""],
        ["Hype", "cai 3%/mês; doações 400 cr × hype/mês", ""],
        ["Confiabilidade de família", "0,75 ao estrear; +0,03 por sucesso; máx. 0,98", ""],
        ["Ruído dos jornais", "±0,7", "com seed"],
        ["Rivais (capacidade inicial)", "Aurora 1,1 · Nimbo 0,9 · Quietude 1,0", "×0,8 no Cadete; ×1,2 no Diretor(a)"],
    ], [5.0 * cm, 7.0 * cm, W - 12.0 * cm], bold_first=True))


def main():
    OUT.parent.mkdir(parents=True, exist_ok=True)
    doc = SimpleDocTemplate(str(OUT), pagesize=A4, leftMargin=1.8 * cm, rightMargin=1.8 * cm,
                            topMargin=1.8 * cm, bottomMargin=1.7 * cm,
                            title="Cometworks — GDD + megaprompt",
                            author="Equipe MARGIN", subject="NASA Space Apps Challenge 2026")
    s = []
    for part in (cover, toc, how_to_use, summary, decisions, vision, world, loop, development, resources, vehicles,
                 staff, research, agency, economy, race, map_ops, education, multiplayer, hackathon, reuse,
                 architecture, plan, risks, art_direction, appendix_prompt, appendix_compliance, appendix_balance):
        part(s)
    doc.build(s, onFirstPage=on_page, onLaterPages=on_page)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
