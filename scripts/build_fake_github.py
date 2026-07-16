#!/usr/bin/env python3
"""Generate a static site that mimics the GitHub repo page for
Massed-Compute/gpu-benchmark, including all local model writeups.

Output: fake-github/  (open fake-github/index.html)
"""
from __future__ import annotations

import html
import shutil
from datetime import date
from pathlib import Path

import markdown

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "fake-github"
REPO_OWNER = "Massed-Compute"
REPO_NAME = "gpu-benchmark"
DESCRIPTION = "Various benchmarks across multiple GPU types."

# Top-level entries to publish (dirs + files), in GitHub display order (dirs first)
INCLUDE_DIRS = [
    "bin",
    "catalog",
    "docs",
    "glm-4.7-flash",
    "llama-3.1-8b",
    "llama-3.3-70b",
    "mc_bench",
    "nemotron-3-nano-30b",
    "nemotron-70b-instruct",
    "nemotron-nano-8b",
    "deepseek-r1-distill-llama-8b",
    "deepseek-r1-distill-qwen-32b",
    "deepseek-r1-distill-llama-70b",
    "qwen3-32b",
    "qwen3-30b-a3b",
    "qwen2-5-7b-instruct",
    "scripts",
    "shared-images",
]
INCLUDE_FILES = ["README.md"]

# Per-path commit message + relative time (synthesized, GitHub-like)
COMMITS = {
    "README.md": ("add DeepSeek + newest local model index", "2 minutes ago"),
    "bin": ("add mc-bench orchestrator", "last week"),
    "catalog": ("update model catalog statuses", "2 minutes ago"),
    "docs": ("methodology + new-model playbook", "last week"),
    "mc_bench": ("vLLM + SGLang bench harness", "last week"),
    "scripts": ("add fake-github + showcase render", "2 minutes ago"),
    "shared-images": ("update styling", "on Aug 1, 2024"),
    "glm-4.7-flash": ("GLM-4.7-Flash: Blackwell vs H100", "3 hours ago"),
    "llama-3.1-8b": ("Llama 3.1 8B on L40S", "5 hours ago"),
    "llama-3.3-70b": ("Llama 3.3 70B: Blackwell vs H100", "5 hours ago"),
    "nemotron-3-nano-30b": ("Nemotron 3 Nano 30B benches", "3 hours ago"),
    "nemotron-70b-instruct": ("Nemotron 70B: H200 vs H100", "3 hours ago"),
    "nemotron-nano-8b": ("Nemotron Nano 8B benches", "3 hours ago"),
    "deepseek-r1-distill-llama-8b": ("DeepSeek R1 Distill Llama 8B", "just now"),
    "deepseek-r1-distill-qwen-32b": ("DeepSeek R1 Distill Qwen 32B", "just now"),
    "deepseek-r1-distill-llama-70b": ("DeepSeek R1 Distill Llama 70B", "just now"),
    "qwen3-32b": ("Qwen3 32B: Blackwell vs H100", "just now"),
    "qwen3-30b-a3b": ("Qwen3 30B-A3B MoE benches", "just now"),
    "qwen2-5-7b-instruct": ("Qwen2.5 7B pilot on L40S", "6 hours ago"),
}
DEFAULT_COMMIT = ("update benches", "just now")

CSS = """
:root{--bg:#ffffff;--fg:#1f2328;--muted:#59636e;--border:#d1d9e0;--link:#0969da;--btnbg:#f6f8fa;--headerbg:#f6f8fa;--accent:#0969da;--rowhover:#f6f8fa;}
*{box-sizing:border-box}
body{margin:0;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI","Noto Sans",Helvetica,Arial,sans-serif;color:var(--fg);background:var(--bg);font-size:14px;line-height:1.5}
a{color:var(--link);text-decoration:none}
a:hover{text-decoration:underline}
.topbar{background:#1f2328;color:#fff;padding:12px 16px;display:flex;align-items:center;gap:12px;font-size:14px}
.topbar svg{fill:#fff}
.topbar .repo-path{font-size:15px}
.topbar .repo-path a{color:#fff;font-weight:400}
.topbar .repo-path b{font-weight:600}
.subnav{border-bottom:1px solid var(--border);padding:0 16px;display:flex;gap:8px;background:var(--bg);overflow-x:auto}
.subnav a{padding:12px 8px;color:var(--fg);border-bottom:2px solid transparent;white-space:nowrap;font-size:14px}
.subnav a.active{border-bottom-color:#fd8c73;font-weight:600}
.subnav .counter{background:#eaeef2;border-radius:20px;padding:0 6px;font-size:12px;color:var(--muted);margin-left:4px}
.wrap{max-width:1280px;margin:24px auto;padding:0 16px;display:flex;gap:24px;align-items:flex-start}
.main{flex:1;min-width:0}
.side{width:296px;flex-shrink:0}
@media(max-width:1000px){.wrap{flex-direction:column}.side{width:100%}}
.reporow{display:flex;align-items:center;gap:16px;margin-bottom:16px;flex-wrap:wrap}
.branchbtn{border:1px solid var(--border);background:var(--btnbg);border-radius:6px;padding:5px 12px;font-weight:600;display:inline-flex;align-items:center;gap:6px}
.box{border:1px solid var(--border);border-radius:6px;overflow:hidden}
.commitbar{display:flex;align-items:center;gap:8px;background:var(--headerbg);padding:8px 16px;border-bottom:1px solid var(--border);font-size:13px;color:var(--muted)}
.commitbar .avatar{width:20px;height:20px;border-radius:50%;background:#54aeff}
.commitbar .msg{color:var(--fg);font-weight:600}
.commitbar .right{margin-left:auto;display:flex;align-items:center;gap:6px}
.commitbar .sha{font-family:ui-monospace,SFMono-Regular,Menlo,monospace}
table.files{width:100%;border-collapse:collapse;font-size:14px}
table.files td{padding:8px 16px;border-top:1px solid var(--border)}
table.files tr:first-child td{border-top:0}
table.files tr:hover{background:var(--rowhover)}
.files .icon{width:16px;color:var(--muted);padding-right:0}
.files .folder{color:#54aeff}
.files .name{width:35%}
.files .msg{color:var(--muted)}
.files .age{text-align:right;color:var(--muted);white-space:nowrap}
.readmebox{margin-top:16px}
.readmehead{display:flex;align-items:center;gap:8px;background:var(--bg);padding:8px 16px;border-bottom:1px solid var(--border);font-weight:600}
.filehead{display:flex;align-items:center;gap:12px;background:var(--bg);padding:8px 16px;border-bottom:1px solid var(--border);font-size:13px;color:var(--muted)}
.markdown-body{padding:24px 32px}
.markdown-body h1{font-size:2em;border-bottom:1px solid var(--border);padding-bottom:.3em;margin-top:0}
.markdown-body h2{font-size:1.5em;border-bottom:1px solid var(--border);padding-bottom:.3em;margin-top:24px}
.markdown-body h3{font-size:1.25em;margin-top:24px}
.markdown-body table{border-collapse:collapse;margin:16px 0;display:block;overflow:auto}
.markdown-body th,.markdown-body td{border:1px solid var(--border);padding:6px 13px}
.markdown-body tr:nth-child(2n){background:var(--btnbg)}
.markdown-body code{background:rgba(129,139,152,.12);padding:.2em .4em;border-radius:6px;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:85%}
.markdown-body pre{background:var(--btnbg);padding:16px;border-radius:6px;overflow:auto}
.markdown-body pre code{background:none;padding:0}
.markdown-body img{max-width:100%;border:1px solid var(--border);border-radius:6px}
.markdown-body a{color:var(--link)}
.breadcrumb{font-size:16px;margin-bottom:12px}
.breadcrumb b{font-weight:600}
.side h2{font-size:16px;margin:0 0 8px}
.side .desc{color:var(--fg);margin-bottom:16px}
.side .meta{color:var(--muted);display:flex;flex-direction:column;gap:8px;font-size:13px}
.side .meta a{color:var(--muted)}
.side hr{border:0;border-top:1px solid var(--border);margin:16px 0}
.imggrid{display:grid;grid-template-columns:repeat(auto-fill,minmax(240px,1fr));gap:16px;padding:16px}
.imggrid figure{margin:0}
.imggrid img{width:100%;border:1px solid var(--border);border-radius:6px}
.imggrid figcaption{font-size:12px;color:var(--muted);margin-top:4px;word-break:break-all}
"""

FOLDER_SVG = '<svg class="folder" aria-hidden="true" height="16" width="16" viewBox="0 0 16 16"><path d="M1.75 1A1.75 1.75 0 0 0 0 2.75v10.5C0 14.216.784 15 1.75 15h12.5A1.75 1.75 0 0 0 16 13.25v-8.5A1.75 1.75 0 0 0 14.25 3H7.5a.25.25 0 0 1-.2-.1l-.9-1.2C6.07 1.26 5.55 1 5 1H1.75Z"></path></svg>'
FILE_SVG = '<svg aria-hidden="true" height="16" width="16" viewBox="0 0 16 16" fill="#59636e"><path d="M2 1.75C2 .784 2.784 0 3.75 0h6.586c.464 0 .909.184 1.237.513l2.914 2.914c.329.328.513.773.513 1.237v9.586A1.75 1.75 0 0 1 13.25 16h-9.5A1.75 1.75 0 0 1 2 14.25Zm1.75-.25a.25.25 0 0 0-.25.25v12.5c0 .138.112.25.25.25h9.5a.25.25 0 0 0 .25-.25V6h-2.75A1.75 1.75 0 0 1 9 4.25V1.5Zm6.75.062V4.25c0 .138.112.25.25.25h2.688l-.011-.013-2.914-2.914-.013-.011Z"></path></svg>'
OCTICON_REPO = '<svg height="16" width="16" viewBox="0 0 16 16" fill="#9198a1"><path d="M2 2.5A2.5 2.5 0 0 1 4.5 0h8.75a.75.75 0 0 1 .75.75v12.5a.75.75 0 0 1-.75.75h-2.5a.75.75 0 0 1 0-1.5h1.75v-2h-8a1 1 0 0 0-.714 1.7.75.75 0 1 1-1.072 1.05A2.495 2.495 0 0 1 2 11.5Zm10.5-1h-8a1 1 0 0 0-1 1v6.708A2.486 2.486 0 0 1 4.5 9h8ZM5 12.25a.25.25 0 0 1 .25-.25h3.5a.25.25 0 0 1 .25.25v3.25a.25.25 0 0 1-.4.2l-1.45-1.087a.249.249 0 0 0-.3 0L5.4 15.7a.25.25 0 0 1-.4-.2Z"></path></svg>'

md = markdown.Markdown(extensions=["tables", "fenced_code", "sane_lists", "toc"])


import re

_MD_LINK = re.compile(r'(href=")([^"]+?\.md)(")')


def render_md(text: str) -> str:
    md.reset()
    out = md.convert(text)
    # make in-repo .md links resolve to generated blob pages
    out = _MD_LINK.sub(lambda m: m.group(1) + m.group(2) + ".html" + m.group(3), out)
    return out


def topbar() -> str:
    return (
        '<div class="topbar">'
        '<svg height="28" width="28" viewBox="0 0 16 16"><path d="M8 0c4.42 0 8 3.58 8 8a8.013 8.013 0 0 1-5.45 7.59c-.4.08-.55-.17-.55-.38 0-.27.01-1.13.01-2.2 0-.75-.25-1.23-.54-1.48 1.78-.2 3.65-.88 3.65-3.95 0-.88-.31-1.59-.82-2.15.08-.2.36-1.02-.08-2.12 0 0-.67-.22-2.2.82-.64-.18-1.32-.27-2-.27-.68 0-1.36.09-2 .27-1.53-1.03-2.2-.82-2.2-.82-.44 1.1-.16 1.92-.08 2.12-.51.56-.82 1.28-.82 2.15 0 3.06 1.86 3.75 3.64 3.95-.23.2-.44.55-.51 1.07-.46.21-1.61.55-2.33-.66-.15-.24-.6-.83-1.23-.82-.67.01-.27.38.01.53.34.19.73.9.82 1.13.16.45.68 1.31 2.69.94 0 .67.01 1.3.01 1.49 0 .21-.15.45-.55.38A7.995 7.995 0 0 1 0 8c0-4.42 3.58-8 8-8Z"></path></svg>'
        f'<span class="repo-path"><a href="index.html">{REPO_OWNER}</a> / <a href="index.html"><b>{REPO_NAME}</b></a></span>'
        "</div>"
    )


def subnav(active="code") -> str:
    tabs = [
        ("code", "Code", ""),
        ("issues", "Issues", '<span class="counter">0</span>'),
        ("pr", "Pull requests", '<span class="counter">0</span>'),
        ("actions", "Actions", ""),
        ("projects", "Projects", ""),
        ("security", "Security", ""),
        ("insights", "Insights", ""),
    ]
    items = []
    for key, label, extra in tabs:
        cls = "active" if key == active else ""
        items.append(f'<a class="{cls}" href="index.html">{label}{extra}</a>')
    return '<div class="subnav">' + "".join(items) + "</div>"


def sidebar() -> str:
    return (
        '<div class="side">'
        "<h2>About</h2>"
        f'<div class="desc">{DESCRIPTION}</div>'
        '<div class="meta">'
        '<a href="index.html">Readme</a>'
        "<span>&#11088; 0 stars</span>"
        "<span>&#128064; 1 watching</span>"
        "<span>&#127860; 0 forks</span>"
        "</div><hr>"
        "<h2>Releases</h2><div class=\"meta\"><span>No releases published</span></div><hr>"
        "<h2>Languages</h2><div class=\"meta\"><span>Python &#8226; Shell &#8226; Markdown</span></div>"
        "</div>"
    )


def page(title: str, body: str, active="code") -> str:
    return (
        "<!doctype html><html><head><meta charset=utf-8>"
        f"<title>{html.escape(title)}</title>"
        '<meta name="viewport" content="width=device-width, initial-scale=1">'
        f"<style>{CSS}</style></head><body>"
        + topbar()
        + subnav(active)
        + body
        + "</body></html>\n"
    )


def commit_for(name: str):
    return COMMITS.get(name, DEFAULT_COMMIT)


def file_table(rows) -> str:
    trs = []
    for icon, name, href, msg, age in rows:
        trs.append(
            "<tr>"
            f'<td class="icon">{icon}</td>'
            f'<td class="name"><a href="{href}">{html.escape(name)}</a></td>'
            f'<td class="msg"><a href="{href}">{html.escape(msg)}</a></td>'
            f'<td class="age">{html.escape(age)}</td>'
            "</tr>"
        )
    return '<table class="files"><tbody>' + "".join(trs) + "</tbody></table>"


def commitbar(count: int) -> str:
    msg, age = ("Merge: DeepSeek + newest local models", "just now")
    return (
        '<div class="commitbar">'
        '<span class="avatar"></span>'
        '<span class="author"><b>mc-nic</b></span> '
        f'<span class="msg">{html.escape(msg)}</span>'
        '<span class="right">'
        f'<span class="sha">a1b2c3d</span>'
        f"<span>&#183; {count} commits</span>"
        "</span></div>"
    )


def build():
    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)
    (OUT / "assets").mkdir()

    # ---- root index ----
    rows = []
    for d in INCLUDE_DIRS:
        src = ROOT / d
        if not src.exists():
            continue
        msg, age = commit_for(d)
        rows.append((FOLDER_SVG, d, f"{d}/index.html", msg, age))
    for f in INCLUDE_FILES:
        if not (ROOT / f).exists():
            continue
        msg, age = commit_for(f)
        rows.append((FILE_SVG, f, f"{f}.html", msg, age))

    readme_html = render_md((ROOT / "README.md").read_text())
    body = (
        '<div class="wrap"><div class="main">'
        '<div class="reporow"><span class="branchbtn">&#9660; main</span>'
        f'<span style="color:var(--muted)">{len(INCLUDE_DIRS)+1} branches</span></div>'
        '<div class="box">'
        + commitbar(42)
        + file_table(rows)
        + "</div>"
        '<div class="box readmebox">'
        '<div class="readmehead">' + OCTICON_REPO + " README</div>"
        f'<div class="markdown-body">{readme_html}</div>'
        "</div>"
        "</div>"
        + sidebar()
        + "</div>"
    )
    (OUT / "index.html").write_text(page(f"{REPO_OWNER}/{REPO_NAME}", body))

    # blob of README
    write_blob(Path("README.md"), depth=0)

    # ---- each dir ----
    for d in INCLUDE_DIRS:
        src = ROOT / d
        if not src.exists():
            continue
        build_dir(Path(d))


def rel_prefix(depth: int) -> str:
    return "../" * depth


def build_dir(relpath: Path):
    src = ROOT / relpath
    dst = OUT / relpath
    dst.mkdir(parents=True, exist_ok=True)
    depth = len(relpath.parts)

    subdirs = sorted([p for p in src.iterdir() if p.is_dir() and p.name not in {"__pycache__"}])
    files = sorted([p for p in src.iterdir() if p.is_file() and not p.name.startswith(".")])

    rows = []
    up = rel_prefix(depth) + "index.html"
    rows.append((FOLDER_SVG, "..", up, "", ""))
    for sd in subdirs:
        rows.append((FOLDER_SVG, sd.name, f"{sd.name}/index.html", commit_for(relpath.name)[0], commit_for(relpath.name)[1]))
    for f in files:
        href = f"{f.name}.html"
        rows.append((FILE_SVG, f.name, href, commit_for(relpath.name)[0], commit_for(relpath.name)[1]))

    crumb = f'<a href="{rel_prefix(depth)}index.html">{REPO_NAME}</a>'
    acc = ""
    for i, part in enumerate(relpath.parts):
        remaining = depth - i - 1
        if remaining == 0:
            crumb += f" / <b>{html.escape(part)}</b>"
        else:
            crumb += f' / <a href="{"../"*remaining}index.html">{html.escape(part)}</a>'

    body = (
        '<div class="wrap"><div class="main">'
        f'<div class="breadcrumb">{crumb}</div>'
        '<div class="box">'
        + file_table(rows)
        + "</div></div>"
        + sidebar()
        + "</div>"
    )
    (dst / "index.html").write_text(page(f"{relpath} - {REPO_NAME}", body))

    # image gallery page if this dir is an images dir
    imgs = [f for f in files if f.suffix.lower() in {".png", ".jpg", ".jpeg", ".gif", ".webp"}]
    for f in files:
        if f.suffix.lower() == ".md":
            write_blob(relpath / f.name, depth)
        elif f.suffix.lower() in {".png", ".jpg", ".jpeg", ".gif", ".webp"}:
            shutil.copy2(f, dst / f.name)
            write_image_blob(relpath / f.name, depth)
        else:
            write_text_blob(relpath / f.name, depth)

    for sd in subdirs:
        build_dir(relpath / sd.name)


def blob_head(relpath: Path, depth: int, size_txt: str) -> str:
    crumb = f'<a href="{rel_prefix(depth)}index.html">{REPO_NAME}</a>'
    parts = relpath.parts
    for i, part in enumerate(parts):
        remaining = depth - i  # blob lives in dir at depth; file adds one
        if i == len(parts) - 1:
            crumb += f" / <b>{html.escape(part)}</b>"
        else:
            back = depth - i
            crumb += f' / <a href="{"../"*back}index.html">{html.escape(part)}</a>'
    return (
        f'<div class="breadcrumb">{crumb}</div>'
        '<div class="box"><div class="filehead">'
        f"<span>{size_txt}</span></div>"
    )


def write_blob(relpath: Path, depth: int):
    src = ROOT / relpath
    text = src.read_text(errors="replace")
    body_md = render_md(text)
    dst = OUT / relpath.parent / (relpath.name + ".html")
    dst.parent.mkdir(parents=True, exist_ok=True)
    lines = text.count("\n") + 1
    size = f"{len(text.encode())} Bytes"
    body = (
        '<div class="wrap"><div class="main">'
        + blob_head(relpath, depth, f"{lines} lines &#183; {size}")
        + f'<div class="markdown-body">{body_md}</div>'
        + "</div></div>"
        + sidebar()
        + "</div>"
    )
    dst.write_text(page(f"{relpath} - {REPO_NAME}", body))


def write_text_blob(relpath: Path, depth: int):
    src = ROOT / relpath
    try:
        text = src.read_text(errors="replace")
    except Exception:
        text = "(binary)"
    dst = OUT / relpath.parent / (relpath.name + ".html")
    dst.parent.mkdir(parents=True, exist_ok=True)
    lines = text.count("\n") + 1
    size = f"{len(text.encode())} Bytes"
    body = (
        '<div class="wrap"><div class="main">'
        + blob_head(relpath, depth, f"{lines} lines &#183; {size}")
        + f'<div class="markdown-body"><pre><code>{html.escape(text)}</code></pre></div>'
        + "</div></div>"
        + sidebar()
        + "</div>"
    )
    dst.write_text(page(f"{relpath} - {REPO_NAME}", body))


def write_image_blob(relpath: Path, depth: int):
    dst = OUT / relpath.parent / (relpath.name + ".html")
    body = (
        '<div class="wrap"><div class="main">'
        + blob_head(relpath, depth, relpath.name)
        + f'<div class="markdown-body"><img src="{relpath.name}" alt="{html.escape(relpath.name)}"></div>'
        + "</div></div>"
        + sidebar()
        + "</div>"
    )
    dst.write_text(page(f"{relpath} - {REPO_NAME}", body))


if __name__ == "__main__":
    build()
    print("fake-github built at", OUT)
