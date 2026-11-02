"""jev-locate FILE QUESTION: ask TypeSafe Jev which ~2.5 KB block of FILE answers QUESTION.

Prints `JEV block N/M present=P conf=C` then blocks N-1 and N verbatim when Jev is trusted,
else `JEV FULL ...` (read the whole file). Any error: stderr + exit 1, the caller reads the
whole file. The API key is read from KEY_FILE and only ever sent in the Authorization header.

`jev-locate --self-test` runs offline asserts on the split and the decision; no network.
"""
import io
import json
import os
import sys
import tempfile
import urllib.error
import urllib.request

API = "https://api.typesafe.ai/v1/systemone"
KEY_FILE = os.path.expanduser("~/.config/secrets/typesafe-api-key")
MODEL = "jev-latest"
BLOCK_CHARS = 2500        # ~600 tokens read when Jev is trusted
WINDOW_CHARS = 60000      # stays under the 32k tokens per question (code-heavy pages ~3 chars/token)
PRESENT_MIN = 0.5
CONF_MIN = 0.8
TIMEOUT = 60


class JevError(Exception):
    pass


def split(text, size=BLOCK_CHARS):
    """Blocks of whole lines, each <= size; a longer line is hard-wrapped into size pieces."""
    out, cur = [], ""
    for line in text.splitlines(keepends=True):
        for piece in (line[i:i + size] for i in range(0, len(line), size)):
            if cur and len(cur) + len(piece) > size:
                out.append(cur)
                cur = ""
            cur += piece
    if cur:
        out.append(cur)
    return out


def windows(blocks):
    """Runs of consecutive blocks totalling <= WINDOW_CHARS; numbering is global."""
    state, chars = {}, 0
    for i, b in enumerate(blocks):
        if state and chars + len(b) > WINDOW_CHARS:
            yield state
            state, chars = {}, 0
        state[f"block_{i + 1}"] = b
        chars += len(b)
    if state:
        yield state


def questions(question, state):
    return {
        "present": {"type": "noul", "instructions": f"Does the text answer this question: {question}"},
        "where": {"type": "choice", "instructions": f"Which block answers this question: {question}",
                  "criteria": {k: f"The answer is in {k}" for k in state}},
    }


def parse(res, state):
    """(present, block index 0-based, confidence) from one API response.

    Errors name the field and the exception type only: response values may echo the key.
    """
    field = "answers"
    try:
        answers = res["answers"]
        field = "answers.present.noul"
        present = float(answers["present"]["noul"])
        field = "answers.where.choice"
        choice = answers["where"]["choice"]
        if choice not in state:
            raise JevError(f"{field} is not a block of this window")
        idx = int(choice.split("_")[1]) - 1
        field = "answers.where.confidence"
        conf = answers["where"].get("confidence")
        conf = 0.0 if conf is None else float(conf)
    except (KeyError, TypeError, ValueError, AttributeError, IndexError, OverflowError) as e:
        raise JevError(f"unexpected response at {field} ({type(e).__name__})") from None
    return present, idx, conf


def decide(present, conf, idx):
    """Block indices to print, or None for a full read."""
    if present >= PRESENT_MIN and conf >= CONF_MIN:
        return [idx - 1, idx] if idx > 0 else [idx]
    return None


def render(blocks, present, idx, conf):
    shown = decide(present, conf, idx)
    if shown is None:
        return f"JEV FULL present={present:.2f} conf={conf:.2f} — read the whole file\n"
    head = f"JEV block {idx + 1}/{len(blocks)} present={present:.2f} conf={conf:.2f}\n"
    return head + "".join(blocks[i] for i in shown)


def locate(text, question, ask):
    blocks = split(text)
    if not blocks:
        raise JevError("file is empty")
    best = None
    for state in windows(blocks):
        cand = parse(ask(state, questions(question, state)), state)
        if best is None or cand[0] > best[0]:
            best = cand
    present, idx, conf = best
    return render(blocks, present, idx, conf)


def read_key(path=KEY_FILE):
    """The stripped key; errors name the file, never its content."""
    try:
        with open(path, encoding="utf-8") as f:
            key = f.read().strip()
    except OSError as e:
        raise JevError(f"cannot read key file {path}: {e.strerror}")
    except UnicodeDecodeError:
        raise JevError(f"key file {path} is not UTF-8") from None
    if not key:
        raise JevError(f"key file {path} is empty")
    if not all("!" <= c <= "~" for c in key):
        raise JevError(f"key file {path} holds whitespace, control or non-ASCII characters")
    return key


def redact(text, key):
    return text.replace(key, "[key]") if key else text


class NoRedirect(urllib.request.HTTPRedirectHandler):
    """urllib copies the Authorization header onto a redirect, whatever the host: refuse them."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def make_ask(key, opener=None):
    opener = opener or urllib.request.build_opener(NoRedirect)

    def ask(state, qs):
        body = json.dumps({"model": MODEL, "state": state, "questions": qs}).encode()
        req = urllib.request.Request(API, data=body, method="POST", headers={
            "Authorization": f"Bearer {key}", "Content-Type": "application/json"})
        try:
            with opener.open(req, timeout=TIMEOUT) as r:
                raw = r.read()
        except urllib.error.HTTPError as e:
            # redact before truncating: a key straddling the cut would leave its prefix unmasked
            detail = redact(e.read().decode("utf-8", "replace"), key)[:300]
            raise JevError(f"HTTP {e.code} from {API}: {detail}")
        except (urllib.error.URLError, OSError) as e:
            raise JevError(f"request to {API} failed: {redact(str(getattr(e, 'reason', e)), key)}")
        except ValueError as e:
            # http.client quotes an invalid header value with %r: never echo the message
            raise JevError(f"request to {API} rejected before sending ({type(e).__name__})") from None
        try:
            return json.loads(raw)
        except (ValueError, RecursionError):
            raise JevError(f"response from {API} is not JSON") from None
    return ask


def read_text(path):
    try:
        with open(path, encoding="utf-8", newline="") as f:
            return f.read()
    except (OSError, UnicodeDecodeError) as e:
        raise JevError(f"cannot read {path}: {e}")


def main(argv):
    if len(argv) != 2 or not argv[1].strip():
        raise JevError('usage: jev-locate FILE "QUESTION" | jev-locate --self-test')
    path, question = argv
    text = read_text(path)
    if not text.strip():
        raise JevError(f"{path} is empty")
    sys.stdout.write(locate(text, question, make_ask(read_key())))


def self_test():
    failures = []

    def expect(ok, what):
        if not ok:
            failures.append(what)

    lines = [("x" * (i % 97)) + "\n" for i in range(400)]
    text = "".join(lines) + "tail without newline"
    blocks = split(text)
    expect("".join(blocks) == text, "split: concatenation differs from input")
    expect(all(len(b) <= BLOCK_CHARS for b in blocks), "split: a block exceeds BLOCK_CHARS")
    expect(all(b.endswith("\n") for b in blocks[:-1]), "split: a block does not end on a line boundary")
    expect(len(blocks) > 1, "split: expected several blocks")
    exact = split(("y" * 99 + "\n") * 100)
    expect([len(b) for b in exact] == [2500] * 4, f"split: 100 x 100-char lines gave {[len(b) for b in exact]}, want 4 x 2500")
    long = split("a\n" + "z" * 3000 + "\nb\n")
    expect("".join(long) == "a\n" + "z" * 3000 + "\nb\n", "split: over-long line, concatenation differs")
    expect(all(len(b) <= BLOCK_CHARS for b in long), f"split: over-long line gave {[len(b) for b in long]}")
    one = "q" * 6000
    wrapped = split(one)
    expect("".join(wrapped) == one, "split: 6000-char line, concatenation differs from input")
    expect([len(b) for b in wrapped] == [2500, 2500, 1000], f"split: 6000-char line gave {[len(b) for b in wrapped]}")
    expect(split("") == [], "split: empty text must give no block")

    wins = list(windows(["b" * BLOCK_CHARS] * 30))
    expect([len(w) for w in wins] == [24, 6], f"windows: sizes {[len(w) for w in wins]}, want [24, 6]")
    expect(list(wins[1])[0] == "block_25", "windows: block numbering is not global")
    for name, bl in (("5000-char blocks", ["v" * 5000] * 30), ("minified page", split("m" * 200000))):
        wins = list(windows(bl))
        sizes = [sum(map(len, w.values())) for w in wins]
        expect(all(s <= WINDOW_CHARS for s in sizes), f"windows: {name} gave window chars {sizes}")
        expect(sum(len(w) for w in wins) == len(bl), f"windows: {name} lost blocks")

    expect(decide(0.9, 0.9, 4) == [3, 4], "decide: trusted must show prev + chosen")
    expect(decide(0.9, 0.9, 0) == [0], "decide: block 1 has no prev")
    expect(decide(0.5, 0.8, 2) == [1, 2], "decide: thresholds are inclusive")
    expect(decide(0.49, 0.95, 2) is None, "decide: low present must be FULL")
    expect(decide(0.9, 0.79, 2) is None, "decide: low confidence must be FULL")

    bl = ["first\n", "second\n", "third\n"]
    out = render(bl, 0.97, 2, 0.91)
    expect(out == "JEV block 3/3 present=0.97 conf=0.91\nsecond\nthird\n", f"render: trusted output {out!r}")
    out = render(bl, 0.97, 0, 0.91)
    expect(out == "JEV block 1/3 present=0.97 conf=0.91\nfirst\n", f"render: block 1 output {out!r}")
    out = render(bl, 0.2, 1, 0.99)
    expect(out.startswith("JEV FULL present=0.20 conf=0.99") and "second" not in out, f"render: FULL output {out!r}")

    def resp(present, choice, conf):
        return {"answers": {"present": {"noul": present}, "where": {"choice": choice, "confidence": conf}},
                "usage": {"input_tokens": 1}}

    expect(parse(resp(0.7, "block_2", None), {"block_2": ""}) == (0.7, 1, 0.0), "parse: null confidence must read as 0")
    for bad, state in ((resp(0.7, "block_9", 0.9), {"block_2": ""}), ({"answers": {}}, {"block_2": ""}), ([], {})):
        try:
            parse(bad, state)
            failures.append(f"parse: {bad!r} accepted")
        except JevError:
            pass

    fake_key = "sk-FAKEKEY0123456789abcdefghijklmnop"
    echoes = (("answers.present.noul", resp(fake_key, "block_1", 0.9)),
              ("answers.where.choice", resp(0.9, fake_key, 0.9)),
              ("answers.where.confidence", resp(0.9, "block_1", fake_key)),
              ("answers.where.confidence", resp(0.9, "block_1", 10 ** 400)),
              ("answers.where", {"answers": {"present": {"noul": 0.9}, "where": [fake_key]}}))
    for field, bad in echoes:
        for how, run in (("parse", lambda: parse(bad, {"block_1": ""})),
                         ("locate", lambda: locate("text\n", "q", lambda state, qs: bad))):
            try:
                run()
                failures.append(f"{how}: response echoing at {field} accepted")
            except JevError as e:
                msg = str(e)
                expect(fake_key[:8] not in msg, f"{how}: error echoes a response value: {msg!r}")
                expect(field in msg, f"{how}: error does not name {field}: {msg!r}")
            except Exception as e:
                failures.append(f"{how}: response at {field} raised {type(e).__name__}, not JevError")

    class FakeOpener:
        def __init__(self, status, body):
            self.status, self.body = status, body

        def open(self, req, timeout):
            if self.status != 200:
                raise urllib.error.HTTPError(API, self.status, "err", {}, io.BytesIO(self.body))
            return io.BytesIO(self.body)

    straddle = ("e" * 290 + fake_key + " tail").encode()
    try:
        make_ask(fake_key, FakeOpener(401, straddle))({}, {})
        failures.append("ask: HTTP 401 accepted")
    except JevError as e:
        msg = str(e)
        expect(fake_key[:8] not in msg, f"ask: HTTP error body leaks a key prefix: {msg!r}")
        expect("[key]" in msg, f"ask: HTTP error body not redacted before truncation: {msg!r}")
    for raw in (b"[" * 200000, b"not json"):
        try:
            make_ask(fake_key, FakeOpener(200, raw))({}, {})
            failures.append(f"ask: {raw[:10]!r}... accepted")
        except JevError:
            pass
        except Exception as e:
            failures.append(f"ask: {raw[:10]!r}... raised {type(e).__name__}, not JevError")

    page = "".join(f"line {i:05d} " + "p" * 80 + "\n" for i in range(1000))
    seen = []

    def fake_ask(state, qs):
        seen.append(sorted(qs))
        keys = list(state)
        if "block_30" in state:
            return resp(0.95, "block_30", 0.9)
        return resp(0.3, keys[0], 0.99)

    out = locate(page, "q", fake_ask)
    pb = split(page)
    expect(len(seen) == 2 and seen[0] == ["present", "where"], f"locate: windows asked {seen}")
    expect(out == f"JEV block 30/{len(pb)} present=0.95 conf=0.90\n" + pb[28] + pb[29], "locate: best window not kept")
    try:
        locate("", "q", fake_ask)
        failures.append("locate: empty text accepted")
    except JevError:
        pass

    with tempfile.TemporaryDirectory() as tmp:
        crlf = os.path.join(tmp, "crlf.md")
        with open(crlf, "wb") as f:
            f.write(b"alpha\r\nbeta\r\ngamma\r\n")
        got = read_text(crlf)
        expect(got == "alpha\r\nbeta\r\ngamma\r\n", f"read_text: CRLF not kept verbatim {got!r}")
        out = locate(got, "q", lambda state, qs: resp(0.9, "block_1", 0.9))
        expect(out == "JEV block 1/1 present=0.90 conf=0.90\nalpha\r\nbeta\r\ngamma\r\n",
               f"locate: CRLF block not printed verbatim {out!r}")

        kf = os.path.join(tmp, "key")
        for content in ("sk-SECRETPART\nOTHERPART\n", "sk-SECRETPART OTHERPART", "sk-SECRETPART\x00OTHERPART",
                        "sk-SECRETPARTéOTHERPART"):
            with open(kf, "w", encoding="utf-8") as f:
                f.write(content)
            try:
                read_key(kf)
                failures.append(f"read_key: invalid key {content!r} accepted")
            except JevError as e:
                msg = str(e)
                expect(kf in msg, f"read_key: error does not name the file: {msg!r}")
                expect("SECRET" not in msg and "OTHER" not in msg, f"read_key: error leaks the key: {msg!r}")
        with open(kf, "w", encoding="utf-8") as f:
            f.write("sk-good_KEY.123\n")
        expect(read_key(kf) == "sk-good_KEY.123", "read_key: valid key with trailing newline rejected")

    expect(redact("x SECRET y", "SECRET") == "x [key] y", "redact: key not masked")
    expect(NoRedirect().redirect_request(None, None, 302, "", {}, "https://elsewhere/") is None,
           "redirect: must be refused (it would carry the key)")

    for f in failures:
        print(f"FAIL {f}", file=sys.stderr)
    if failures:
        return 1
    print("jev-locate self-test: OK")
    return 0


if __name__ == "__main__":
    if sys.argv[1:] == ["--self-test"]:
        sys.exit(self_test())
    try:
        main(sys.argv[1:])
    except JevError as e:
        print(f"jev-locate: {e}", file=sys.stderr)
        sys.exit(1)
