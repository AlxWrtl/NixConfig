"""Collecte déterministe de la veille TTW : HN, Reddit, releases GitHub, arXiv -> markdown sur stdout.

Les parseurs (`parse_*`) sont purs et testés hors réseau (test_fetch.py) ; le réseau et
la boucle des sources ne tournent que sous `__main__`.
"""

import calendar
import html
import json
import re
import subprocess
import sys
import time
import urllib.parse
import xml.etree.ElementTree as ET
from datetime import datetime, timezone

UA = "macos:veille-ttw:0.2 (lecture seule, 1 run/jour)"
ATOM = {"a": "http://www.w3.org/2005/Atom"}

HN_QUERIES = ["claude code", "coding agent", "llm agent", "codex", "subagent", "agentic", "mcp server", "anthropic"]
REDDIT_SUBS = ["ClaudeAI", "ClaudeCode", "ChatGPTCoding", "LocalLLaMA"]
GH_REPOS = ["anthropics/claude-code", "openai/codex"]
ARXIV_QUERY = (
    '(cat:cs.SE OR cat:cs.AI OR cat:cs.CL) AND '
    '(abs:"coding agent" OR abs:"software engineering agent" OR abs:"LLM agent" '
    'OR abs:"agentic" OR abs:"multi-agent" OR abs:"code review")'
)
ARXIV_MIN_WINDOW_H = 96  # arXiv publie par lots, avec retard
ARXIV_PAGE = 100
ARXIV_MAX_PAGES = 5
# Codes curl passagers, retentés : DNS (6), connexion (7), timeout (28, arXiv est parfois
# lent), poignée de main TLS (35), réception (56).
CURL_TRANSIENT = {6, 7, 28, 35, 56}


def utc(ts: str, fmt: str = "%Y-%m-%dT%H:%M:%SZ") -> float:
    return calendar.timegm(time.strptime(ts, fmt))


def strip_html(s: str, n: int) -> str:
    return " ".join(html.unescape(re.sub(r"<[^>]+>", " ", s)).split())[:n]


def parse_hn(hits: list[dict]) -> list[str]:
    """Hits Algolia (déjà filtrés par date côté API) -> une ligne par story, points décroissants."""
    seen: dict[str, dict] = {}
    for h in hits:
        seen[h["objectID"]] = h
    out = []
    for h in sorted(seen.values(), key=lambda h: -(h.get("points") or 0)):
        if (h.get("points") or 0) < 3:
            continue
        link = h.get("url") or f"https://news.ycombinator.com/item?id={h['objectID']}"
        text = strip_html(h.get("story_text") or "", 300)
        out.append(
            f"- {h['title']} | {h.get('points')}pts {h.get('num_comments') or 0}com | {link} "
            f"| hn: https://news.ycombinator.com/item?id={h['objectID']}" + (f" | {text}" if text else "")
        )
    return out


def parse_reddit(xml: bytes, since: float) -> list[str]:
    """Flux Atom Reddit -> une ligne par entrée mise à jour après `since`."""
    out = []
    for e in ET.fromstring(xml).findall("a:entry", ATOM):
        updated = e.findtext("a:updated", default="", namespaces=ATOM)
        if updated:
            d = datetime.fromisoformat(updated)  # garde le décalage (+00:00, -07:00…)
            if (d if d.tzinfo else d.replace(tzinfo=timezone.utc)).timestamp() < since:
                continue
        title = e.findtext("a:title", default="", namespaces=ATOM)
        cat = e.find("a:category", ATOM)
        sub = cat.get("label", "") if cat is not None else ""
        link_el = e.find("a:link", ATOM)
        link = link_el.get("href", "") if link_el is not None else ""
        body = strip_html(e.findtext("a:content", default="", namespaces=ATOM), 300)
        out.append(f"- {sub} | {title} | {link} | {body}")
    return out


def parse_arxiv(xml: bytes, since: float, page_size: int = 100) -> tuple[list[str], bool]:
    """Une page de l'API arXiv (tri décroissant) -> (lignes, fini).

    `fini` dès qu'une entrée précède `since` (la suite est hors fenêtre) ou que la page
    est incomplète (plus rien à lire).
    """
    entries = ET.fromstring(xml).findall("a:entry", ATOM)
    out = []
    for e in entries:
        if utc(e.findtext("a:published", default="", namespaces=ATOM)) < since:
            return out, True
        title = " ".join(e.findtext("a:title", default="", namespaces=ATOM).split())
        abstract = " ".join(e.findtext("a:summary", default="", namespaces=ATOM).split())[:600]
        out.append(f"- {title} | {e.findtext('a:id', default='', namespaces=ATOM)} | {abstract}")
    return out, len(entries) < page_size


def parse_releases(rels: list[dict], repo: str, since: float) -> list[str]:
    """Releases GitHub -> un bloc par release publiée après `since`."""
    out = []
    for r in rels:
        if utc(r["published_at"]) < since:
            continue
        body = (r.get("body") or "").replace("\r", "")[:2500]
        out.append(f"### {repo} {r['tag_name']} ({r['published_at'][:10]}) {r['html_url']}\n{body}\n")
    return out


def get(url: str, retries: int = 3, timeout: int = 30) -> bytes:
    # curl plutôt qu'urllib : via le proxy du sandbox, urllib lève IncompleteRead.
    cmd = ["curl", "-sS", "--max-time", str(timeout), "-A", UA, "-w", "\n%{http_code}"]
    for attempt in range(retries):
        res = subprocess.run(cmd + [url], capture_output=True, check=False)
        if res.returncode in CURL_TRANSIENT and attempt < retries - 1:
            time.sleep(5 * (attempt + 1))
            continue
        if res.returncode != 0:
            raise RuntimeError(f"curl rc={res.returncode}: {res.stderr.decode(errors='replace').strip()}")
        body, _, code = res.stdout.rpartition(b"\n")
        status = int(code or 0)
        if status == 429 and attempt < retries - 1:
            time.sleep(15 * (attempt + 1))  # Reddit limite les lectures anonymes rapprochées
            continue
        if status != 200:
            raise RuntimeError(f"HTTP {status} sur {url.split('?')[0]}")
        return body
    raise RuntimeError("inaccessible")


def hn(since: float) -> list[str]:
    hits: list[dict] = []
    for q in HN_QUERIES:
        params = urllib.parse.urlencode({
            "query": q,
            "tags": "story",
            "numericFilters": f"created_at_i>{int(since)}",
            "hitsPerPage": 50,
        })
        hits += json.loads(get(f"https://hn.algolia.com/api/v1/search_by_date?{params}"))["hits"]
    return parse_hn(hits)


def reddit(since: float) -> list[str]:
    # L'API JSON anonyme renvoie 403 ; le flux Atom public répond, mais limite vite les appels
    # rapprochés (429 dès le 3e) : un seul flux multi-sous-forums r/A+B+C.
    subs = "+".join(REDDIT_SUBS)
    return parse_reddit(get(f"https://www.reddit.com/r/{subs}/top/.rss?t=day&limit=60"), since)


def gh_releases(since: float) -> list[str]:
    out = []
    for repo in GH_REPOS:
        rels = json.loads(get(f"https://api.github.com/repos/{repo}/releases?per_page=10"))
        out += parse_releases(rels, repo, since)
    return out


def arxiv(since: float) -> list[str]:
    since = min(since, time.time() - ARXIV_MIN_WINDOW_H * 3600)
    out = []
    for page in range(ARXIV_MAX_PAGES):
        if page:
            time.sleep(3)  # délai demandé par arXiv entre deux appels
        params = urllib.parse.urlencode({
            "search_query": ARXIV_QUERY,
            "sortBy": "submittedDate",
            "sortOrder": "descending",
            "start": page * ARXIV_PAGE,
            "max_results": ARXIV_PAGE,
        })
        lines, fini = parse_arxiv(get(f"https://export.arxiv.org/api/query?{params}", timeout=90), since, ARXIV_PAGE)
        out += lines
        if fini:
            return out
    out.append(f"- (tronqué : plus de {ARXIV_MAX_PAGES * ARXIV_PAGE} papiers dans la fenêtre)")
    return out


SOURCES = [("Hacker News", hn), ("Reddit", reddit), ("Releases GitHub", gh_releases), ("arXiv", arxiv)]


def section(name: str, fn, since: float, failed: list[str]) -> str:
    try:
        items = fn(since)
        status = f"{len(items)} éléments"
    except Exception as exc:  # une source en panne ne doit pas tuer les autres, mais elle est signalée
        items, status = [], f"ÉCHEC: {type(exc).__name__}: {exc}"
        failed.append(name)
    print(f"{name}: {status}", file=sys.stderr)
    return f"## {name} ({status})\n" + "\n".join(items) + "\n"


def main() -> None:
    window_h = int(sys.argv[1]) if len(sys.argv) > 1 else 48
    since = time.time() - window_h * 3600
    failed: list[str] = []
    print(f"# Candidats veille TTW, fenêtre {window_h} h\n")
    for name, fn in SOURCES:
        print(section(name, fn, since, failed))
    if len(failed) >= 3:
        sys.exit(f"sources en échec : {', '.join(failed)}")


if __name__ == "__main__":
    main()
