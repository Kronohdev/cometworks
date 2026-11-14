"""Builds the Cometworks team document: docs/equipe/cometworks_equipe.md -> styled HTML in the
game's paper-sticker look -> A4 PDF (docs/Cometworks_Documento_da_Equipe.pdf), printed with
headless Microsoft Edge.

The Markdown is plain Markdown plus a few fenced blocks (":::" lines) for the cover, chapter
openers, character cards, mission cards and the coloured boxes; the conventions are written
at the top of the .md file. No Markdown library is needed: this script carries a small
converter for the subset the document uses.

The table of contents gets real page numbers from a first print: invisible markers are placed
on every chapter opener and section title, the PDF is searched for them with PyMuPDF, and the
page is printed again with the numbers filled in. PyMuPDF also writes the PDF outline
(bookmarks) and the document properties.

Usage:
  python tools/build_team_doc.py                 build the PDF
  python tools/build_team_doc.py --html OUT.html also keep the final HTML (for a browser preview)
  python tools/build_team_doc.py --edge PATH     use this msedge.exe
"""
from __future__ import annotations

import argparse
import html
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "docs" / "equipe" / "cometworks_equipe.md"
IMG_DIR = ROOT / "docs" / "equipe"
OUT_PDF = ROOT / "docs" / "Cometworks_Documento_da_Equipe.pdf"
FONTS = ROOT / "ui" / "fonts"
ICONS = ROOT / "ui" / "cometworks" / "icons"
STAR = ROOT / "ui" / "menu" / "logo_star.svg"

TITLE = "Cometworks · Documento da Equipe"
AUTHOR = "Equipe Cometworks"
SUBJECT = "NASA Space Apps Challenge 2026 · tudo sobre o jogo"

EDGE_CANDIDATES = [
    r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
]

# accent colours of ui/cometworks_palette.gd
ACCENTS = {
    "pessego": "#ff9a5c", "manteiga": "#ffd25c", "menta": "#6fe0be", "gelo": "#7cc8ff",
    "lilas": "#b39cff", "rosa": "#ff8fb8", "vermelho": "#ff5c6c", "violeta": "#8e7cff",
    "nuvem": "#bfe8ff", "creme": "#fff6e6",
}
KINDS = {
    "sonho": ("Sonho de Cometinho", "#ff8fb8", "heart"),
    "corrida": ("Marco da corrida", "#ff9a5c", "race"),
    "ciencia": ("Pergunta científica", "#7cc8ff", "research"),
    "contrato": ("Cliente", "#ffd25c", "contracts"),
    "spaceapps": ("Desafio Space Apps", "#6fe0be", "planet"),
}
ERAS = {"1": "Galpão", "2": "Órbita", "3": "Lua robótica", "4": "Lua tripulada", "5": "Base de partida"}
BOXES = {
    "spoiler": ("Como resolver (só para a equipe)", "journal"),
    "inspirou": ("Quem inspirou", "star"),
    "nota": ("Nota", "book"),
    "dica": ("Dica", "check"),
    "aviso": ("Atenção", "flame"),
    "efeito": ("Proposta de efeito", "dice"),
    "ciencia": ("A ciência por trás", "research"),
}


# ------------------------------------------------------------------------------ helpers
def uri(p: Path) -> str:
    return p.resolve().as_uri()


_icon_cache: dict[str, str] = {}


def icon(name: str, cls: str = "ic") -> str:
    if name not in _icon_cache:
        f = ICONS / f"{name}.svg"
        if not f.exists():
            raise SystemExit(f"icon not found: {name}")
        svg = f.read_text(encoding="utf-8")
        svg = re.sub(r'\swidth="\d+"\s+height="\d+"', "", svg, count=1)
        _icon_cache[name] = svg
    return f'<span class="{cls}">{_icon_cache[name]}</span>'


def img_src(path: str) -> str:
    if re.match(r"^[a-z]+:", path):
        return path
    p = (IMG_DIR / path)
    if not p.exists():
        raise SystemExit(f"image not found: {p}")
    return uri(p)


def inline(text: str) -> str:
    """Inline Markdown: escapes, `code`, images, links, **bold**, *italic*, [[icon]]."""
    out = html.escape(text, quote=False)
    codes: list[str] = []

    def keep_code(m):
        codes.append(f"<code>{m.group(1)}</code>")
        return f"\x00{len(codes) - 1}\x00"

    out = re.sub(r"`([^`]+)`", keep_code, out)
    out = re.sub(r"!\[([^\]]*)\]\(([^)\s]+)\)",
                 lambda m: f'<img src="{img_src(m.group(2))}" alt="{m.group(1)}">', out)
    out = re.sub(r"\[\[([a-z0-9_]+)\]\]", lambda m: icon(m.group(1)), out)
    out = re.sub(r"\{\{(#[0-9a-fA-F]{6})\}\}", r'<span class="sw" style="background:\1"></span>', out)
    out = re.sub(r"\[([^\]]+)\]\(([^)\s]+)\)", r'<a href="\2">\1</a>', out)
    out = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", out)
    out = re.sub(r"(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])", r"<em>\1</em>", out)
    out = out.replace(" -- ", " – ").replace("Δ", '<span class="nu">Δ</span>')
    out = re.sub(r"\x00(\d+)\x00", lambda m: codes[int(m.group(1))], out)
    return out


def parse_fields(lines: list[str]) -> tuple[dict, list[str]]:
    """'key: value' lines up to a '---' line; the rest is the body (Markdown)."""
    fields: dict[str, str] = {}
    body: list[str] = []
    if "---" in [l.strip() for l in lines]:
        cut = [l.strip() for l in lines].index("---")
        head, body = lines[:cut], lines[cut + 1:]
    else:
        head = lines
    last = None
    for l in head:
        if not l.strip():
            continue
        m = re.match(r"^([a-zA-Zçãéí_]+)\s*:\s?(.*)$", l)
        if m and not l.startswith("  "):
            last = m.group(1).lower()
            fields[last] = m.group(2).strip()
        elif last:
            fields[last] += " " + l.strip()
    return fields, body


# ------------------------------------------------------------------------------ renderer
class Doc:
    def __init__(self, src: str, pages: dict[str, int] | None, markers: bool):
        self.lines = src.splitlines()
        self.pages = pages or {}
        self.markers = markers
        self.h2_count = 0
        self.chapter_count = 0
        self.mission_count = 0
        self.cur_color = ACCENTS["pessego"]
        self.toc = self.scan_toc()

    # -- the table of contents (chapters and their ## sections)
    def scan_toc(self):
        toc = []
        depth = 0
        cur = None
        h2 = 0
        in_comment = False
        i = 0
        while i < len(self.lines):
            l = self.lines[i]
            if in_comment:
                in_comment = "-->" not in l
                i += 1
                continue
            if l.strip().startswith("<!--"):
                in_comment = "-->" not in l
                i += 1
                continue
            m = re.match(r"^:{3,}\s*([\w-]+)", l)
            if m:
                if m.group(1) == "chapter":
                    j = i + 1
                    inner = []
                    while not re.match(r"^:{3,}\s*$", self.lines[j]):
                        inner.append(self.lines[j])
                        j += 1
                    f, _ = parse_fields(inner)
                    cur = {"id": f"c{len(toc) + 1}", "num": f.get("numero", ""), "title": f.get("titulo", ""),
                           "color": f.get("cor", "pessego"), "sections": []}
                    toc.append(cur)
                    i = j + 1
                    continue
            if l.startswith("## ") and cur is not None:
                h2 += 1
                cur["sections"].append({"id": f"s{h2}", "title": l[3:].strip()})
            elif l.startswith("## "):
                h2 += 1
            i += 1
        return toc

    def marker(self, mid: str) -> str:
        return f'<span class="mk">QQ{mid}QQ</span>' if self.markers else ""

    def page_of(self, mid: str) -> str:
        n = self.pages.get(mid)
        return str(n) if n else "00"

    # -- block parser
    def render(self, lines: list[str]) -> str:
        out: list[str] = []
        para: list[str] = []
        i = 0

        def flush():
            if para:
                text = " ".join(s.strip() for s in para)
                out.append(self.paragraph(text))
                para.clear()

        while i < len(lines):
            l = lines[i]
            s = l.strip()
            if s.startswith("<!--"):
                flush()
                while "-->" not in lines[i]:
                    i += 1
                i += 1
                continue
            m = re.match(r"^:{3,}\s*([\w-]+)\s*(.*)$", l)
            if m:
                flush()
                kind, args = m.group(1), m.group(2).strip()
                depth = 1
                j = i + 1
                inner = []
                while j < len(lines):
                    if re.match(r"^:{3,}\s*[\w-]+", lines[j]):
                        depth += 1
                    elif re.match(r"^:{3,}\s*$", lines[j]):
                        depth -= 1
                        if depth == 0:
                            break
                    inner.append(lines[j])
                    j += 1
                out.append(self.block(kind, args, inner))
                i = j + 1
                continue
            if not s:
                flush()
                i += 1
                continue
            if s == "\\pagebreak":
                flush()
                out.append('<div class="pb"></div>')
                i += 1
                continue
            hm = re.match(r"^(#{2,4})\s+(.*)$", l)
            if hm:
                flush()
                level = len(hm.group(1))
                text = hm.group(2).strip()
                if level == 2:
                    self.h2_count += 1
                    sid = f"s{self.h2_count}"
                    out.append(f'<h2 id="{sid}" style="--sec:{self.cur_color}">{self.marker(sid)}{inline(text)}</h2>')
                else:
                    out.append(f"<h{level}>{inline(text)}</h{level}>")
                i += 1
                continue
            if s.startswith("|"):
                flush()
                rows = []
                while i < len(lines) and lines[i].strip().startswith("|"):
                    rows.append(lines[i].strip())
                    i += 1
                out.append(self.table(rows))
                continue
            if re.match(r"^([-*]|\d+\.)\s+", s):
                flush()
                ordered = bool(re.match(r"^\d+\.", s))
                items: list[str] = []
                while i < len(lines):
                    t = lines[i]
                    if re.match(r"^\s*([-*]|\d+\.)\s+", t) and not t.startswith("    "):
                        items.append(re.sub(r"^\s*([-*]|\d+\.)\s+", "", t))
                    elif t.startswith("  ") and t.strip() and items:
                        items[-1] += " " + t.strip()
                    else:
                        break
                    i += 1
                tag = "ol" if ordered else "ul"
                out.append(f"<{tag}>" + "".join(f"<li>{inline(x)}</li>" for x in items) + f"</{tag}>")
                continue
            if s.startswith(">"):
                flush()
                q = []
                while i < len(lines) and lines[i].strip().startswith(">"):
                    q.append(lines[i].strip()[1:].strip())
                    i += 1
                out.append(f'<blockquote>{self.render(q)}</blockquote>')
                continue
            para.append(l)
            i += 1
        flush()
        return "\n".join(out)

    def paragraph(self, text: str) -> str:
        imgs = re.findall(r"!\[([^\]]*)\]\(([^)\s]+)\)(\{\.([\w-]+)\})?", text)
        rest = re.sub(r"!\[([^\]]*)\]\(([^)\s]+)\)(\{\.[\w-]+\})?", "", text).strip()
        if imgs and not rest:
            cls = imgs[0][3] or ""
            figs = []
            for cap, src, _, _ in imgs:
                capt = f"<figcaption>{inline(cap)}</figcaption>" if cap else ""
                figs.append(f'<figure><div class="frame"><img src="{img_src(src)}" alt=""></div>{capt}</figure>')
            return f'<div class="figs n{len(imgs)} {cls}">' + "".join(figs) + "</div>"
        return f"<p>{inline(text)}</p>"

    def table(self, rows: list[str]) -> str:
        cells = [[c.strip() for c in r.strip("|").split("|")] for r in rows]
        head = cells[0]
        body = [r for r in cells[1:] if not all(re.match(r"^:?-{2,}:?$", c) for c in r)]
        h = "".join(f"<th>{inline(c)}</th>" for c in head)
        b = "".join("<tr>" + "".join(f"<td>{inline(c)}</td>" for c in r) + "</tr>" for r in body)
        long = " long" if len(body) > 9 else ""
        return f'<div class="tbl{long}"><table><thead><tr>{h}</tr></thead><tbody>{b}</tbody></table></div>'

    # -- fenced blocks
    def block(self, kind: str, args: str, inner: list[str]) -> str:
        fn = getattr(self, "b_" + kind.replace("-", "_"), None)
        if fn is None:
            raise SystemExit(f"unknown block ::: {kind}")
        return fn(args, inner)

    def b_grid(self, args, inner):
        cls = args or "two"
        return f'<div class="grid {cls}">{self.render(inner)}</div>'

    def b_box(self, args, inner):
        parts = args.split(None, 1)
        kind = parts[0] if parts else "nota"
        title, ic = BOXES.get(kind, ("", "book"))
        if len(parts) > 1:
            title = parts[1]
        return (f'<div class="box {kind}"><div class="box-tab">{icon(ic)}<span>{inline(title)}</span></div>'
                f"{self.render(inner)}</div>")

    def b_cover(self, args, inner):
        f, body = parse_fields(inner)
        star = STAR.read_text(encoding="utf-8")
        star = re.sub(r'\swidth="128"\s+height="128"', "", star)
        pts = ("36,63 43.4,73.8 48.6,81.1 55.5,87.7 64.1,93.8 74.6,99.2 86.8,104.2 100.8,108.5 116.5,112.3 "
               "134.2,115.6 153.6,118.3 174.9,120.5 198.1,122.2 223.1,123.3 250,124 277.7,124.3 305,124.3 "
               "332,123.9 358.5,123.4 384.5,122.5 410.1,121.4 435,120 459.3,118.4 483,116.5 506,114.4 528.2,112.1 "
               "549.7,109.6 570.3,106.9 590,104")
        tail = f"""<svg class="tail" viewBox="0 0 620 160" preserveAspectRatio="none">
<defs><linearGradient id="tailg" gradientUnits="userSpaceOnUse" x1="36" y1="0" x2="590" y2="0">
<stop offset="0" stop-color="#bfe8ff"/><stop offset="0.07" stop-color="#3fe0c5"/>
<stop offset="0.5" stop-color="#8e7cff" stop-opacity="0.95"/><stop offset="0.86" stop-color="#ff8a3d" stop-opacity="0.85"/>
<stop offset="1" stop-color="#ff8a3d" stop-opacity="0"/></linearGradient></defs>
<polyline points="{pts}" fill="none" stroke="url(#tailg)" stroke-width="7" stroke-linecap="round" stroke-linejoin="round" opacity="0.35"/>
<polyline points="{pts}" fill="none" stroke="url(#tailg)" stroke-width="3.2" stroke-linecap="round" stroke-linejoin="round"/>
</svg>"""
        peeks = "".join(f'<img class="peek p{k}" src="{img_src(p.strip())}" alt="">'
                        for k, p in enumerate(f.get("cometinhos", "").split(",")) if p.strip())
        team = " · ".join(html.escape(n.strip()) for n in f.get("equipe", "").split(","))
        chips = ""
        for k, c in enumerate(x.strip() for x in f.get("numeros", "").split(",") if x.strip()):
            ic, _, txt = c.partition(" ")
            chips += f'<span class="cv-chip c{k}">{icon(ic)}{inline(txt)}</span>'
        return f"""<section class="cover">
<div class="stars"></div>
<div class="cv-kicker">{inline(f.get('kicker', ''))}</div>
<div class="logo">
  <span class="lw">C</span><span class="slot"><span class="halo"></span>{tail}<span class="mark">{star}</span></span><span class="lw">METWORKS</span>
</div>
<div class="tagline">{inline(f.get('tagline', ''))}</div>
<div class="cv-photo"><div class="frame"><img src="{img_src(f['imagem'])}" alt=""></div>{peeks}</div>
<div class="cv-card">
  <div class="cv-title">{inline(f.get('titulo', ''))}</div>
  <div class="cv-sub">{inline(f.get('subtitulo', ''))}</div>
  <div class="cv-team">{icon('crew')}<span>{team}</span></div>
</div>
<div class="cv-chips">{chips}</div>
<div class="cv-foot">{inline(f.get('rodape', ''))}</div>
</section>"""

    def b_toc(self, args, inner):
        f, body = parse_fields(inner)
        rows = []
        for ch in self.toc:
            col = ACCENTS.get(ch["color"], ch["color"])
            secs = "".join(f'<li><span class="t">{inline(s["title"])}</span><span class="dots"></span>'
                           f'<span class="pg">{self.page_of(s["id"])}</span></li>' for s in ch["sections"])
            rows.append(f'<div class="toc-ch" style="--c:{col}"><div class="toc-row"><span class="toc-num">{ch["num"]}</span>'
                        f'<span class="toc-t">{inline(ch["title"])}</span><span class="dots"></span>'
                        f'<span class="toc-pg">{self.page_of(ch["id"])}</span></div><ul>{secs}</ul></div>')
        intro = self.render(body) if body else ""
        return (f'<section class="toc"><h1 class="page-title">{inline(f.get("titulo", "Sumário"))}</h1>{intro}'
                f'<div class="toc-list">{"".join(rows)}</div></section>')

    def b_chapter(self, args, inner):
        f, body = parse_fields(inner)
        self.chapter_count += 1
        ch = self.toc[self.chapter_count - 1]
        col = ACCENTS.get(f.get("cor", "pessego"), f.get("cor", "#ff9a5c"))
        self.cur_color = col
        secs = "".join(f"<li>{inline(s['title'])}</li>" for s in ch["sections"])
        cid = ch["id"]
        num = f.get("numero", "")
        return f"""<section class="opener" id="{cid}" style="--c:{col}">{self.marker(cid)}
<div class="op-photo"><div class="frame"><img src="{img_src(f['imagem'])}" alt=""></div></div>
<div class="op-head"><span class="op-n">{num}</span>
<div class="op-tt"><span class="op-cap">Capítulo {num}</span><h1 class="op-title">{inline(f.get('titulo', ''))}</h1></div></div>
<div class="op-intro">{self.render(body)}</div>
<div class="op-list"><div class="op-list-t">{icon(f.get('icone', 'book'))}<span>Neste capítulo</span></div><ul>{secs}</ul></div>
</section>"""

    def b_card(self, args, inner):
        f, body = parse_fields(inner)
        col = ACCENTS.get(f.get("cor", "gelo"), f.get("cor", "#7cc8ff"))
        badge = icon(f.get("icone", "star"), "cc-badge")
        viva = '<span class="alive">pessoa viva · homenagem com carinho</span>' if f.get("viva", "").lower() in ("sim", "yes") else ""
        orig = f.get("original", "").lower() in ("sim", "yes")
        inspir = ""
        if body or f.get("inspirou"):
            title = "Personagem original" if orig else "Quem inspirou"
            who = f'<div class="who">{inline(f.get("inspirou", ""))}{viva}</div>' if f.get("inspirou") else ""
            inspir = (f'<div class="box inspirou small{" orig" if orig else ""}"><div class="box-tab">{icon("star")}<span>{title}</span></div>'
                      f"{who}{self.render(body)}</div>")
        efeito = ""
        if f.get("efeito"):
            efeito = (f'<div class="box efeito small"><div class="box-tab">{icon("dice")}<span>Proposta de efeito</span></div>'
                      f'<p>{inline(f["efeito"])}</p></div>')
        foto = f.get("foto", "")
        photo = f'<img src="{img_src(foto)}" alt="">' if foto else ""
        soon = '<span class="cc-soon">arte final em breve</span>' if f.get("arte", "") != "pronta" else ""
        return f"""<div class="ccard" style="--c:{col}">
<div class="cc-top"><div class="cc-photo">{photo}{badge}{soon}</div>
<div class="cc-head"><div class="cc-kicker">{inline(f.get('grupo', ''))}</div><h4>{inline(f.get('nome', ''))}</h4>
<div class="cc-role">{inline(f.get('papel', ''))}</div>
<div class="cc-func">{inline(f.get('funcao', ''))}</div></div></div>
<p class="cc-way">{inline(f.get('jeito', ''))}</p>
{efeito}{inspir}</div>"""

    def b_mission(self, args, inner):
        f, body = parse_fields(inner)
        self.mission_count += 1
        label, col, ic = KINDS[f.get("tipo", "ciencia")]
        era = f.get("era", "1")
        sol = []
        for key, lab in [("destino", "Destino"), ("missao", "Tipo de missão"), ("leva", "Precisa levar"),
                         ("proporcao", "Proporção do cliente"), ("cuidado", "Cuidado")]:
            if f.get(key):
                sol.append(f"<dt>{lab}</dt><dd>{inline(f[key])}</dd>")
        fonte = f'<p class="src">{icon("book")}<span>{inline(f["fonte"])}</span></p>' if f.get("fonte") else ""
        extra = self.render(body) if body else ""
        return f"""<div class="mcard" style="--k:{col}">
<div class="mc-head"><span class="chip kind">{icon(ic)}{label}</span><span class="chip era">Era {era} · {ERAS.get(era, '')}</span>
<span class="mc-num">#{self.mission_count:02d}</span></div>
<h3>{inline(f.get('titulo', ''))}</h3>
<p class="mc-hook">{inline(f.get('gancho', ''))}</p>
<div class="mc-cols"><div class="mc-left"><h5>{icon('contracts')}O pedido</h5><p>{inline(f.get('pedido', ''))}</p>
<h5>{icon('coin')}Recompensa</h5><p>{inline(f.get('recompensa', ''))}</p></div>
<div class="mc-right"><h5>{icon('research')}A ciência por trás</h5><p>{inline(f.get('ciencia', ''))}</p>{fonte}</div></div>
{extra}
<div class="box spoiler small"><div class="box-tab">{icon('journal')}<span>Como resolver (só para a equipe)</span></div><dl>{''.join(sol)}</dl></div>
</div>"""

    def b_story(self, args, inner):
        f, body = parse_fields(inner)
        lines = [l.strip() for l in body if l.strip()]
        ps = "".join(f"<p>{inline(l)}</p>" for l in lines)
        img = f'<div class="st-img"><img src="{img_src(f["imagem"])}" alt=""></div>' if f.get("imagem") else ""
        kick = f'<div class="st-kicker">{inline(f.get("kicker", ""))}</div>' if f.get("kicker") else ""
        return f'<div class="story">{img}<div class="st-text">{kick}{ps}</div></div>'

    def b_gallery(self, args, inner):
        items = []
        for l in inner:
            if "|" not in l:
                continue
            src, cap = [x.strip() for x in l.split("|", 1)]
            items.append(f'<div class="gal-item"><div class="gal-img"><img src="{img_src(src)}" alt=""></div>'
                         f'<div class="gal-cap">{inline(cap)}</div></div>')
        return f'<div class="gallery {args}">{"".join(items)}</div>'

    def b_quote(self, args, inner):
        f, body = parse_fields(inner)
        who = f'<div class="q-who">{inline(f["quem"])}</div>' if f.get("quem") else ""
        return f'<div class="pull">{icon(f.get("icone", "comet"))}<div>{self.render(body)}{who}</div></div>'

    def b_stats(self, args, inner):
        items = []
        for l in inner:
            if "|" not in l:
                continue
            parts = [x.strip() for x in l.split("|")]
            ic, num, lab = (parts + ["", "", ""])[:3]
            items.append(f'<div class="stat">{icon(ic)}<div class="stat-n">{inline(num)}</div><div class="stat-l">{inline(lab)}</div></div>')
        return f'<div class="stats">{"".join(items)}</div>'

    def b_flow(self, args, inner):
        steps = []
        for l in inner:
            if "|" not in l:
                continue
            ic, t, d = ([x.strip() for x in l.split("|")] + ["", ""])[:3]
            steps.append(f'<div class="step">{icon(ic)}<div class="step-t">{inline(t)}</div><div class="step-d">{inline(d)}</div></div>')
        return f'<div class="flow">{"".join(steps)}</div>'

    def b_page(self, args, inner):
        return f'<section class="page {args}">{self.render(inner)}</section>'


# ------------------------------------------------------------------------------ page
def css() -> str:
    def face(fam, file, weight, style="normal"):
        return (f"@font-face{{font-family:'{fam}';src:url('{uri(FONTS / file)}') format('truetype');"
                f"font-weight:{weight};font-style:{style};font-display:block}}")

    faces = "\n".join([
        face("Fredoka", "fredoka/Fredoka-Variable.ttf", "300 700"),
        face("Nunito", "nunito/Nunito-Variable.ttf", "200 1000"),
        face("Nunito", "nunito/Nunito-Italic-Variable.ttf", "200 1000", "italic"),
        face("Bricolage", "bricolage_grotesque/BricolageGrotesque-Variable.ttf", "200 800"),
        face("Plex Mono", "ibm_plex_mono/IBMPlexMono-Medium.ttf", "500"),
    ])
    dots = ("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='22' height='22'>"
            "<circle cx='5.5' cy='5.5' r='1.5' fill='%23f1e2c8'/><circle cx='16.5' cy='16.5' r='1.5' fill='%23f1e2c8'/></svg>")
    stars = ("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='120' height='120'>"
             "<circle cx='12' cy='18' r='1.1' fill='%23ffffff' opacity='0.8'/><circle cx='70' cy='9' r='0.8' fill='%23ffffff' opacity='0.6'/>"
             "<circle cx='96' cy='52' r='1.4' fill='%23bfe8ff' opacity='0.85'/><circle cx='40' cy='64' r='0.7' fill='%23ffffff' opacity='0.55'/>"
             "<circle cx='22' cy='100' r='1.2' fill='%23ffd25c' opacity='0.6'/><circle cx='84' cy='104' r='0.9' fill='%23ffffff' opacity='0.7'/>"
             "<circle cx='58' cy='36' r='0.6' fill='%23ffffff' opacity='0.5'/></svg>")
    return faces + CSS.replace("__DOTS__", dots).replace("__STARS__", stars)


CSS = r"""
:root{--ink:#2b2a5c;--ink-soft:#5d5b8c;--paper:#fff9ef;--raised:#fffdf8;--well:#f6ead6;--line:#e6d3b3;
--peach:#ff9a5c;--butter:#ffd25c;--mint:#6fe0be;--ice:#7cc8ff;--lilac:#b39cff;--pink:#ff8fb8;
--lilac-l:#eee8ff;--mint-l:#ddf7ee;--butter-l:#fff0c4;--ice-l:#e2f2ff;--peach-l:#ffe7d6;--space:#1e1d4a;
--teal:#0e9077;--violet:#7652e8;--comet:#2f78cc;--ignition:#e5651c}
@page{size:A4;margin:15mm 15mm 17mm 15mm;background:#fff9ef url("__DOTS__") repeat;background-size:22px 22px;
 @bottom-left{content:"Cometworks · documento da equipe";font-family:Fredoka;font-weight:500;font-size:7.5pt;color:#8e8bb5;vertical-align:top;padding-top:4mm}
 @bottom-right{content:counter(page);font-family:Fredoka;font-weight:600;font-size:9pt;color:#2b2a5c;vertical-align:top;padding-top:3.4mm}}
@page full{margin:0}
*{box-sizing:border-box;-webkit-print-color-adjust:exact;print-color-adjust:exact}
body{margin:0;font-family:Nunito,sans-serif;font-size:10pt;line-height:1.5;color:var(--ink);font-weight:500}
p{margin:0 0 2.4mm}
strong{font-weight:800}
em{font-style:italic}
a{color:var(--comet);text-decoration:none;border-bottom:1px dotted var(--comet)}
code{font-family:'Plex Mono',monospace;font-size:8.6pt;background:var(--well);border:1px solid var(--line);border-radius:5px;padding:0 3px}
h2{font-family:Fredoka;font-weight:600;font-size:19pt;line-height:1.15;margin:7mm 0 3mm;position:relative;break-after:avoid;
 padding-left:9mm}
h2::before{content:"";position:absolute;left:0;top:0.12em;width:6mm;height:6mm;border-radius:50%;background:var(--sec,#ff9a5c);
 border:2.2px solid var(--ink);box-shadow:0 2px 0 var(--ink)}
h3{font-family:Fredoka;font-weight:600;font-size:13.5pt;margin:5mm 0 2mm;break-after:avoid}
h4{font-family:Fredoka;font-weight:600;font-size:11.5pt;margin:3mm 0 1.4mm;break-after:avoid}
h5{font-family:Fredoka;font-weight:600;font-size:9.5pt;margin:0 0 1mm;display:flex;align-items:center;gap:1.4mm}
ul,ol{margin:0 0 2.6mm;padding-left:5.5mm}
li{margin:0 0 1.1mm}
ul li::marker{color:var(--peach);font-size:1.1em}
ol li::marker{font-family:Fredoka;font-weight:600;color:var(--ignition)}
blockquote{margin:3mm 0;padding:3mm 5mm;border-left:4px solid var(--lilac);background:var(--lilac-l);border-radius:0 12px 12px 0}
.ic{display:inline-block;width:1.25em;height:1.25em;vertical-align:-0.28em}
.ic svg{width:100%;height:100%;display:block}
.nu{font-family:Nunito}
.sw{display:inline-block;width:1.15em;height:1.15em;border-radius:50%;border:1.6px solid var(--ink);vertical-align:-0.22em;margin-right:0.5mm}
.pb{break-after:page}
.mk{position:absolute;font-size:1px;line-height:1px;color:rgba(255,249,239,0.02);left:0;top:0;white-space:nowrap}
.page-title{font-family:Fredoka;font-weight:600;font-size:30pt;margin:0 0 4mm}

/* ---------- cover */
.cover{page:full;break-after:page;width:210mm;height:297mm;position:relative;overflow:hidden;
 background:linear-gradient(180deg,#151438 0%,#1e1d4a 46%,#2e2a63 100%)}
.cover .stars{position:absolute;inset:0;background:url("__STARS__") repeat;background-size:120px 120px;opacity:0.9}
.cv-kicker{position:absolute;top:18mm;left:0;right:0;text-align:center;font-family:Fredoka;font-weight:500;letter-spacing:0.18em;
 text-transform:uppercase;font-size:9pt;color:#bfe8ff}
.logo{position:absolute;top:27mm;left:0;right:0;display:flex;justify-content:center;align-items:center;
 font-family:Bricolage;font-weight:700;font-variation-settings:'wght' 700,'wdth' 92,'opsz' 96;font-size:62pt;letter-spacing:0.02em;
 color:#e9eef7;line-height:1}
.logo .lw{text-shadow:0 3px 0 #2b2a5c}
.logo .slot{position:relative;display:inline-block;width:0.75em;height:1em}
.logo .mark{position:absolute;left:-0.03em;top:0.18em;width:0.81em;height:0.81em;filter:drop-shadow(0 0 6px rgba(191,232,255,0.9))}
.logo .mark svg{width:100%;height:100%}
.logo .halo{position:absolute;left:-0.46em;top:-0.18em;width:1.67em;height:1.67em;border-radius:50%;
 background:radial-gradient(circle,rgba(191,232,255,0.55) 0%,rgba(158,219,255,0.18) 25%,rgba(102,178,255,0) 70%)}
.logo .tail{position:absolute;left:0;top:0;width:6.46em;height:1.67em;overflow:visible}
.tagline{position:absolute;top:60mm;left:50%;transform:translateX(-50%) rotate(-2deg);font-family:Fredoka;font-weight:600;font-size:12.5pt;
 background:linear-gradient(#ffe38a,#ffcf52);color:var(--ink);border:2.2px solid var(--ink);border-radius:99px;padding:1.2mm 6mm 2mm;
 box-shadow:0 3px 0 #d79a1c,0 5px 0 rgba(26,23,69,0.35);white-space:nowrap}
.cv-photo{position:absolute;top:80mm;left:17mm;right:17mm;height:118mm}
.cv-photo .frame{width:100%;height:100%;border:3px solid var(--ink);border-radius:22px;overflow:hidden;transform:rotate(-1.6deg);
 box-shadow:0 6px 0 #0f0e2e;background:#000}
.cv-photo .frame img{width:100%;height:100%;object-fit:cover;object-position:50% 40%}
.peek{position:absolute;height:52mm}
.peek.p0{left:-9mm;bottom:-16mm;transform:rotate(-6deg)}
.peek.p1{right:-8mm;bottom:-14mm;height:47mm;transform:rotate(5deg)}
.peek.p2{right:2mm;top:-33mm;height:34mm;transform:rotate(-3deg)}
.cv-chips{position:absolute;top:262mm;left:0;right:0;display:flex;justify-content:center;gap:3mm}
.cv-chip{display:inline-flex;align-items:center;gap:1.4mm;font-family:Fredoka;font-weight:600;font-size:9.5pt;color:var(--ink);
 border:2px solid var(--ink);border-radius:99px;padding:0.6mm 3.4mm 0.9mm 1.8mm;box-shadow:0 2.5px 0 #0f0e2e}
.cv-chip.c0{background:var(--peach)}.cv-chip.c1{background:var(--butter)}.cv-chip.c2{background:var(--mint)}.cv-chip.c3{background:var(--lilac)}
.cv-card{position:absolute;left:30mm;right:30mm;top:214mm;background:var(--paper);border:2.6px solid var(--ink);border-radius:20px;
 padding:5mm 7mm 4.5mm;text-align:center;box-shadow:0 5px 0 #0f0e2e}
.cv-title{font-family:Fredoka;font-weight:600;font-size:22pt;line-height:1.1}
.cv-sub{font-size:10pt;color:var(--ink-soft);margin-top:1.5mm}
.cv-team{margin-top:3mm;display:inline-flex;align-items:center;gap:2mm;font-family:Fredoka;font-weight:500;font-size:10.5pt;
 background:var(--mint-l);border:2px solid var(--ink);border-radius:99px;padding:0.8mm 4mm 1.2mm}
.cv-foot{position:absolute;bottom:13mm;left:0;right:0;text-align:center;color:#bfe8ff;font-family:Fredoka;font-size:9pt;letter-spacing:0.06em}

/* ---------- table of contents */
.toc{break-after:page}
.toc-list{columns:1}
.toc .page-title{margin-bottom:2mm}
.toc > p{font-size:9.4pt;margin-bottom:3mm}
.toc-ch{margin:0 0 2.2mm;break-inside:avoid}
.toc-row{display:flex;align-items:baseline;gap:3mm;background:var(--raised);border:2.2px solid var(--ink);border-radius:13px;
 padding:1mm 4mm 1mm 1.6mm;box-shadow:0 2.5px 0 var(--ink)}
.toc-num{width:7.6mm;height:7.6mm;border-radius:50%;background:var(--c);border:2px solid var(--ink);display:inline-flex;align-items:center;
 justify-content:center;font-family:Fredoka;font-weight:600;font-size:10.5pt;align-self:center}
.toc-t{font-family:Fredoka;font-weight:600;font-size:12pt}
.dots{flex:1;border-bottom:2px dotted #cdb894;margin:0 1.5mm;height:1px}
.toc-pg{font-family:Fredoka;font-weight:600;font-size:12pt}
.toc-ch ul{list-style:none;margin:1.2mm 1mm 0 13mm;padding:0;columns:3;column-gap:6mm}
.toc-ch li{display:flex;align-items:baseline;font-size:7.8pt;line-height:1.3;margin:0 0 0.4mm;break-inside:avoid}
.toc-ch li .dots{border-bottom-width:1.4px;margin:0 1mm;min-width:2mm}
.toc-ch li .pg{font-family:Fredoka;font-weight:500;color:var(--ink-soft)}

/* ---------- chapter openers */
.opener{page:full;break-before:page;break-after:page;width:210mm;height:297mm;position:relative;overflow:hidden;
 display:flex;flex-direction:column;padding:15mm 17mm 16mm;background:#fff9ef url("__DOTS__") repeat;background-size:22px 22px}
.opener::before{content:"";position:absolute;left:0;right:0;top:0;height:104mm;background:var(--c)}
.opener::after{content:"";position:absolute;left:0;right:0;top:104mm;height:2.6px;background:var(--ink)}
.op-photo{position:relative;height:122mm;flex:0 0 auto;z-index:1}
.op-photo .frame{width:100%;height:100%;border:3px solid var(--ink);border-radius:24px;overflow:hidden;transform:rotate(1.2deg);
 box-shadow:0 6px 0 var(--ink);background:#000}
.op-photo img{width:100%;height:100%;object-fit:cover}
.op-head{display:flex;align-items:center;gap:7mm;margin-top:9mm;position:relative;z-index:1}
.op-n{font-family:Fredoka;font-weight:700;font-size:150pt;line-height:0.82;color:var(--c);-webkit-text-stroke:3.6px var(--ink);
 text-shadow:0 7px 0 var(--ink);transform:rotate(-5deg);display:inline-block;min-width:30mm;text-align:center}
.op-tt{display:flex;flex-direction:column;align-items:flex-start;gap:2.5mm}
.op-cap{font-family:Fredoka;font-weight:600;font-size:10pt;background:var(--ink);color:var(--paper);border-radius:99px;padding:0.6mm 4mm 1mm}
.op-title{margin:0;font-family:Fredoka;font-weight:600;font-size:33pt;line-height:1.02}
.op-intro{margin-top:8mm;font-size:12pt;line-height:1.55;position:relative;z-index:1}
.op-intro p{margin-bottom:2.8mm}
.op-list{margin-top:auto;background:var(--raised);border:2.4px solid var(--ink);border-radius:18px;
 padding:3.5mm 5mm 2.5mm;box-shadow:0 4px 0 var(--ink);position:relative;z-index:1}
.op-list-t{display:flex;align-items:center;gap:2mm;font-family:Fredoka;font-weight:600;font-size:10.5pt;margin-bottom:1.5mm}
.op-list ul{columns:2;column-gap:8mm;margin:0;padding-left:5mm;font-size:9.2pt}
.op-list li{margin-bottom:0.6mm;break-inside:avoid}
.op-list li::marker{color:var(--c)}

/* ---------- figures */
.figs{display:flex;gap:4mm;margin:2mm 0 4mm;break-inside:avoid}
.figs figure{margin:0;flex:1;min-width:0}
.figs .frame{border:2.4px solid var(--ink);border-radius:14px;overflow:hidden;box-shadow:0 3px 0 var(--ink);background:#000;line-height:0}
.figs img{width:100%;display:block}
.figs.n2 .frame,.figs.n3 .frame{aspect-ratio:16/9}
.figs.n2 img,.figs.n3 img{height:100%;object-fit:cover}
.figs.wide .frame{aspect-ratio:2.35/1}
.figs.wide img{height:100%;object-fit:cover}
.figs.short .frame{aspect-ratio:2.6/1}
.figs.short img{height:100%;object-fit:cover}
figcaption{font-size:8pt;font-style:italic;color:var(--ink-soft);margin-top:1.6mm;line-height:1.35;padding:0 1mm}
.figs.half{float:right;width:84mm;margin:1mm 0 3mm 5mm}
.figs.halfl{float:left;width:84mm;margin:1mm 5mm 3mm 0}
.clear{clear:both}

/* ---------- tables */
.tbl{border:2.4px solid var(--ink);border-radius:14px;overflow:hidden;margin:2mm 0 4.5mm;box-shadow:0 3px 0 var(--ink);background:var(--raised);
 break-inside:avoid}
table{width:100%;border-collapse:collapse;font-size:8.8pt;line-height:1.35}
th{font-family:Fredoka;font-weight:600;font-size:9pt;text-align:left;background:var(--well);border-bottom:2px solid var(--ink);padding:1.6mm 2.4mm}
td{padding:1.4mm 2.4mm;border-bottom:1px solid var(--line);vertical-align:top}
tr:last-child td{border-bottom:none}
tbody tr:nth-child(even) td{background:#fbf3e6}
.tbl.long{break-inside:auto;-webkit-box-decoration-break:clone;box-decoration-break:clone}

/* ---------- boxes */
.box{position:relative;border:2.4px solid var(--ink);border-radius:16px;padding:6.2mm 4.5mm 2.4mm;margin:6mm 0 4.5mm;
 box-shadow:0 3px 0 var(--ink);background:var(--raised);break-inside:avoid}
.box-tab{position:absolute;top:-3.6mm;left:4mm;display:flex;align-items:center;gap:1.4mm;font-family:Fredoka;font-weight:600;font-size:9pt;
 background:var(--tab,#fff);border:2.2px solid var(--ink);border-radius:99px;padding:0.4mm 3.2mm 0.6mm 1.6mm;line-height:1.3}
.box-tab .ic{width:1.35em;height:1.35em}
.box p:last-child,.box ul:last-child{margin-bottom:1mm}
.box.spoiler{background:var(--lilac-l);--tab:var(--lilac)}
.box.inspirou{background:var(--butter-l);--tab:var(--butter)}
.box.nota{background:var(--ice-l);--tab:var(--ice)}
.box.dica{background:var(--mint-l);--tab:var(--mint)}
.box.aviso{background:var(--peach-l);--tab:var(--peach)}
.box.efeito{background:var(--mint-l);--tab:var(--mint)}
.box.ciencia{background:var(--ice-l);--tab:var(--ice)}
.box.small{padding:4.4mm 3.2mm 1.2mm;margin:4.6mm 0 2.2mm;font-size:8.2pt;line-height:1.36;border-radius:13px}
.box.small p{margin-bottom:1mm}
.box.small .box-tab{font-size:8pt;top:-3.2mm}
.box.inspirou.orig{background:#f3f0ff;--tab:var(--lilac)}
.who{font-family:Fredoka;font-weight:600;font-size:9pt;margin-bottom:0.8mm}
.alive{display:inline-block;font-family:Nunito;font-weight:700;font-size:6.8pt;background:#fff;border:1.4px solid var(--ink);
 border-radius:99px;padding:0 2mm;margin-left:1.6mm;vertical-align:1px;color:var(--teal)}
dl{display:grid;grid-template-columns:30mm 1fr;gap:0.8mm 3mm;margin:0 0 1mm}
dt{font-family:Fredoka;font-weight:600}
dd{margin:0}

/* ---------- grids and character cards */
.grid.two{display:grid;grid-template-columns:1fr 1fr;gap:4.5mm 5mm;margin:2mm 0 4mm;align-items:start}
.grid.three{display:grid;grid-template-columns:1fr 1fr 1fr;gap:4mm;margin:3mm 0 5mm}
.grid > *{break-inside:avoid}
.ccard{background:var(--raised);border:2.4px solid var(--ink);border-radius:18px;padding:3mm 3.4mm 0.8mm;box-shadow:0 4px 0 var(--ink);
 break-inside:avoid;position:relative}
.cc-top{display:flex;gap:3mm;align-items:flex-start}
.cc-photo{position:relative;flex:0 0 27mm;height:31mm;border-radius:14px;border:2.2px solid var(--ink);overflow:hidden;
 background:radial-gradient(circle at 50% 35%,#fff 0%,var(--c) 85%)}
.cc-photo img{position:absolute;left:50%;bottom:-1mm;height:30mm;transform:translateX(-50%)}
.cc-badge{position:absolute;right:0.8mm;top:0.8mm;width:7mm;height:7mm;background:#fff;border:1.8px solid var(--ink);border-radius:50%;
 padding:0.9mm;display:block}
.cc-badge svg{width:100%;height:100%;display:block}
.cc-soon{position:absolute;left:0;right:0;bottom:0;text-align:center;font-size:5.6pt;font-weight:700;color:var(--ink-soft);
 background:rgba(255,253,248,0.82);letter-spacing:0.03em;padding:0.2mm 0 0.4mm}
.cc-head{flex:1;min-width:0}
.cc-kicker{font-family:Fredoka;font-weight:500;font-size:7pt;text-transform:uppercase;letter-spacing:0.1em;color:var(--ink-soft)}
.ccard h4{margin:0.4mm 0 1mm;font-size:12.5pt;line-height:1.1}
.cc-role{display:inline-block;font-family:Fredoka;font-weight:600;font-size:8pt;background:var(--c);border:1.8px solid var(--ink);
 border-radius:99px;padding:0 2.6mm 0.3mm;margin-bottom:1mm}
.cc-func{font-size:7.8pt;line-height:1.35;color:var(--ink-soft)}
.cc-way{font-size:8.3pt;font-style:italic;margin:1.6mm 0 0;line-height:1.35}

/* ---------- mission cards */
.mcard{background:var(--raised);border:2.4px solid var(--ink);border-radius:18px;padding:2.8mm 4.4mm 0.6mm;margin:0 0 4mm;
 box-shadow:0 4px 0 var(--ink);break-inside:avoid;position:relative;overflow:hidden}
.mcard::before{content:"";position:absolute;left:0;top:0;bottom:0;width:3mm;background:var(--k);border-right:2px solid var(--ink)}
.mcard > *{margin-left:2mm}
.mc-head{display:flex;align-items:center;gap:2mm;margin-bottom:1mm}
.chip{display:inline-flex;align-items:center;gap:1.2mm;font-family:Fredoka;font-weight:600;font-size:8pt;border:1.8px solid var(--ink);
 border-radius:99px;padding:0.2mm 2.8mm 0.4mm 1.4mm;line-height:1.35}
.chip.kind{background:var(--k)}
.chip.era{background:var(--well);padding-left:2.6mm}
.mc-num{margin-left:auto;font-family:Fredoka;font-weight:600;font-size:10pt;color:var(--ink-soft)}
.mcard h3{margin:0.8mm 0 0.2mm 2mm;font-size:13pt}
.mc-hook{font-style:italic;color:var(--ink-soft);margin-bottom:1.4mm;font-size:9.2pt}
.mc-cols{display:grid;grid-template-columns:0.82fr 1.18fr;gap:5mm;font-size:8.3pt;line-height:1.36}
.mc-cols p{margin-bottom:1.2mm}
.mc-cols h5{font-size:9pt;margin-bottom:0.6mm}
.src{display:flex;gap:1.2mm;font-size:7pt;color:var(--ink-soft);line-height:1.25}
.src .ic{flex:0 0 auto}
.mcard .box.spoiler{margin-top:4mm;margin-bottom:2.2mm;padding-top:4.4mm;font-size:8.1pt;line-height:1.34}
.mcard dl{gap:0.4mm 3mm}

/* ---------- story (cutscene lines) */
.story{display:flex;gap:0;background:var(--space);border:2.6px solid var(--ink);border-radius:18px;overflow:hidden;margin:3mm 0 5mm;
 box-shadow:0 4px 0 var(--ink);break-inside:avoid;color:#fff6e6}
.st-img{flex:0 0 44%;line-height:0}
.st-img img{width:100%;height:100%;object-fit:cover}
.st-text{padding:4mm 5mm 2mm;font-family:Fredoka;font-weight:500;font-size:10pt;line-height:1.38}
.st-text p{margin:0 0 1.8mm}
.st-kicker{font-size:7.5pt;letter-spacing:0.14em;text-transform:uppercase;color:#6fe0be;margin-bottom:2mm}

/* ---------- gallery, quote, stats, flow */
.gallery{display:grid;grid-template-columns:repeat(4,1fr);gap:4mm;margin:3mm 0 5mm;break-inside:avoid}
.gallery.five{grid-template-columns:repeat(5,1fr)}
.gallery.six{grid-template-columns:repeat(6,1fr)}
.gal-item{text-align:center}
.gal-img{height:34mm;border:2.2px solid var(--ink);border-radius:14px;background:radial-gradient(circle at 50% 35%,#fff,#dff1ff);
 position:relative;overflow:hidden;box-shadow:0 3px 0 var(--ink)}
.gal-img img{position:absolute;left:50%;bottom:-1mm;height:32mm;transform:translateX(-50%)}
.gal-cap{font-family:Fredoka;font-weight:600;font-size:9pt;margin-top:1.6mm;line-height:1.2}
.pull{display:flex;gap:4mm;align-items:flex-start;margin:4mm 0 5mm;padding:4mm 6mm;background:var(--raised);border:2.4px solid var(--ink);
 border-radius:20px;box-shadow:0 4px 0 var(--ink);font-family:Fredoka;font-weight:500;font-size:13pt;line-height:1.3;break-inside:avoid}
.pull > .ic{width:11mm;height:11mm;flex:0 0 auto}
.pull p{margin:0 0 1mm}
.q-who{font-family:Nunito;font-size:8.6pt;color:var(--ink-soft);font-weight:700}
.stats{display:grid;grid-template-columns:repeat(4,1fr);gap:3.5mm;margin:3mm 0 5mm;break-inside:avoid}
.stat{background:var(--raised);border:2.2px solid var(--ink);border-radius:14px;padding:2.4mm 3mm;box-shadow:0 3px 0 var(--ink)}
.stat .ic{width:7mm;height:7mm}
.stat-n{font-family:Fredoka;font-weight:600;font-size:15pt;line-height:1.1;margin-top:1mm}
.stat-l{font-size:7.8pt;color:var(--ink-soft);line-height:1.3}
.flow{display:grid;grid-template-columns:repeat(4,1fr);gap:3mm 3mm;margin:3mm 0 5mm;counter-reset:st;break-inside:avoid}
.step{background:var(--raised);border:2.2px solid var(--ink);border-radius:14px;padding:2.4mm 2.8mm 2mm;box-shadow:0 3px 0 var(--ink);
 position:relative;counter-increment:st}
.step::after{content:counter(st);position:absolute;right:2mm;top:1.6mm;font-family:Fredoka;font-weight:600;font-size:9pt;color:var(--ink-soft)}
.step .ic{width:6.5mm;height:6.5mm}
.step-t{font-family:Fredoka;font-weight:600;font-size:9.6pt;line-height:1.15;margin:1mm 0 0.6mm}
.step-d{font-size:7.6pt;line-height:1.32;color:var(--ink-soft)}
.page.credits{break-before:page}
"""


def build_html(src: str, pages: dict[str, int] | None, markers: bool) -> tuple[str, Doc]:
    doc = Doc(src, pages, markers)
    body = doc.render(doc.lines)
    page = f"""<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8">
<title>{html.escape(TITLE)}</title>
<meta name="author" content="{AUTHOR}"><meta name="description" content="{html.escape(SUBJECT)}">
<style>{css()}</style></head>
<body>
{body}
</body></html>"""
    return page, doc


# ------------------------------------------------------------------------------ printing
def find_edge(given: str | None) -> str:
    for c in ([given] if given else []) + EDGE_CANDIDATES:
        if c and Path(c).exists():
            return c
    found = shutil.which("msedge")
    if found:
        return found
    raise SystemExit("Microsoft Edge not found; pass --edge PATH")


def print_pdf(edge: str, html_file: Path, pdf_file: Path, profile: Path) -> None:
    if pdf_file.exists():
        pdf_file.unlink()
    cmd = [edge, "--headless", "--disable-gpu", "--no-first-run", "--no-default-browser-check",
           f"--user-data-dir={profile}", "--allow-file-access-from-files", "--run-all-compositor-stages-before-draw",
           "--virtual-time-budget=15000", f"--print-to-pdf={pdf_file}", "--no-pdf-header-footer", html_file.resolve().as_uri()]
    subprocess.run(cmd, check=False, timeout=240, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if not pdf_file.exists():
        raise SystemExit("Edge did not write the PDF")


def find_markers(pdf: Path) -> dict[str, int]:
    import pymupdf
    pages: dict[str, int] = {}
    with pymupdf.open(pdf) as d:
        for i, p in enumerate(d):
            for m in re.findall(r"QQ([cs]\d+)QQ", p.get_text()):
                pages.setdefault(m, i + 1)
    return pages


def finish_pdf(pdf: Path, out: Path, doc: Doc, pages: dict[str, int]) -> None:
    import pymupdf
    d = pymupdf.open(pdf)
    toc = []
    for ch in doc.toc:
        if ch["id"] in pages:
            toc.append([1, f'{ch["num"]}. {ch["title"]}', pages[ch["id"]]])
        for s in ch["sections"]:
            if s["id"] in pages:
                toc.append([2, re.sub(r"[*`]", "", s["title"]), pages[s["id"]]])
    d.set_toc(toc)
    d.set_metadata({"title": TITLE, "author": AUTHOR, "subject": SUBJECT, "keywords": "Cometworks, Cometinhos, NASA Space Apps 2026",
                    "creator": AUTHOR, "producer": AUTHOR, "creationDate": "", "modDate": ""})
    try:
        d.del_xml_metadata()
    except Exception:
        pass
    tmp = out.with_suffix(".tmp.pdf")
    d.save(tmp, garbage=4, deflate=True, clean=True)
    d.close()
    os.replace(tmp, out)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--html", help="also write the final HTML here")
    ap.add_argument("--edge", help="path of msedge.exe")
    ap.add_argument("--out", default=str(OUT_PDF))
    a = ap.parse_args()

    src = SRC.read_text(encoding="utf-8")
    edge = find_edge(a.edge)
    with tempfile.TemporaryDirectory(prefix="cw_doc_") as tmpd:
        tmp = Path(tmpd)
        profile = tmp / "profile"
        # pass 1: markers, to learn the page of every chapter and section
        page1, doc1 = build_html(src, None, True)
        (tmp / "pass1.html").write_text(page1, encoding="utf-8")
        print_pdf(edge, tmp / "pass1.html", tmp / "pass1.pdf", profile)
        pages = find_markers(tmp / "pass1.pdf")
        missing = [c["id"] for c in doc1.toc if c["id"] not in pages]
        if missing:
            print("warning: markers not found:", missing)
        # pass 2: the same page with the numbers in the table of contents
        page2, doc2 = build_html(src, pages, False)
        (tmp / "final.html").write_text(page2, encoding="utf-8")
        if a.html:
            Path(a.html).write_text(page2, encoding="utf-8")
        print_pdf(edge, tmp / "final.html", tmp / "final.pdf", profile)
        out = Path(a.out)
        finish_pdf(tmp / "final.pdf", out, doc2, pages)
    import pymupdf
    with pymupdf.open(out) as d:
        n = d.page_count
    print(f"{out} · {n} pages · {out.stat().st_size / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
