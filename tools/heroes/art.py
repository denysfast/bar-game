#!/usr/bin/env python3
"""Hero art pipeline (dev tool, not shipped logic): icons and portraits for bitmaps/t4heroes/.

  art.py icon <out.png> "<subject>" [--size 128] [--seed N] [--style item|ability|weapon|track]
      Krea 2 (content-master still.krea) text-to-image with the shared sci-fi icon style,
      downscaled with a dark rounded frame so every icon of the set looks alike.
  art.py edit <out.png> <reference.png> "<instruction>" [--size 256] [--seed N]
      Qwen-Image-2.1 edit (content-controller platform home, image.qwen21.edit) of a real render.

Keys are never in the repo: CM_KEY_FILE (content-master owner key, knowledge-guardian
`content-master-owner-api-key-cpu-b`) and CC_KEY_FILE (content-controller tools key,
`content-controller-tools-key`, platform home) name files that hold them.
Qwen jobs wait while the lab holds the cards (availability "degraded"); they run when freed.

v19 UI set (--style track --seed 21 --size 128; key: knowledge-guardian `content-master-owner-api-key-cpu-b`,
project "beyond-all-reason"): stat_vit "a glowing green armored heart inside a hexagonal plate, health and
regeneration", stat_mob "cyan double chevron arrows with a glowing scanner eye, speed and vision", stat_dmg "an
orange blazing explosion burst behind a crossed cannon barrel, firepower", stat_rng "a violet long-range targeting
reticle with distance rings, weapon reach", stat_imp "a golden shockwave blast piercing through a cracked armor
plate, impact and penetration"; ui/ab_generic (--style ability), ui/ui_stash, ui_shop, ui_salvage, ui_altar.
"""
import argparse, json, os, sys, time, urllib.request, io, subprocess

CM = os.environ.get("CM_BASE", "http://192.168.66.198:8080")
CC = os.environ.get("CC_BASE", "https://cc-home.denys.fast")

STYLES = {
    "item": ("Game inventory icon, a single {s}, hard-surface sci-fi hardware, centered, three-quarter view, "
             "glowing energy accents, dark gunmetal background with a subtle radial glow, crisp rim light, "
             "painted game UI art in the style of a real-time strategy game about giant war robots, "
             "high detail, no text, no letters, no border"),
    "ability": ("Game ability icon: {s}. Dramatic sci-fi effect art, bold central shape readable at small size, "
                "strong glow, dark background, painted real-time strategy game UI art, giant war robots universe, "
                "no text, no letters, no border"),
    "weapon": ("Game weapon icon: {s}, a sci-fi war machine weapon, side view, metallic, glowing muzzle, "
               "dark background with radial glow, painted real-time strategy game UI art, no text, no letters, no border"),
    "track": ("Game upgrade icon: {s}, sci-fi weapon upgrade symbol, bold simple readable shape, glowing, dark "
              "background, painted real-time strategy game UI art, no text, no letters, no border"),
}


def key(env):
    path = os.environ.get(env)
    if not path:
        sys.exit(f"{env} is not set (a file holding the key)")
    return open(path).read().strip()


def http(method, url, headers, body=None, raw=False, timeout=120):
    data = None
    if body is not None and not isinstance(body, (bytes, bytearray)):
        data = json.dumps(body).encode()
        headers = dict(headers, **{"Content-Type": "application/json"})
    elif body is not None:
        data = body
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        b = r.read()
        return b if raw else json.loads(b or b"{}")


def frame(png_bytes, out, size, rounded=True):
    """Downscale to size x size; an icon gets a thin dark rounded frame (ImageMagick)."""
    tmp = out + ".src.png"
    open(tmp, "wb").write(png_bytes)
    cmd = ["magick", tmp, "-resize", f"{size}x{size}^", "-gravity", "center", "-extent", f"{size}x{size}"]
    if rounded:
        r = max(4, size // 10)
        cmd += ["(", "+clone", "-alpha", "extract", "-draw",
                f"fill black polygon 0,0 0,{r} {r},0 fill white circle {r},{r} {r},0",
                "(", "+clone", "-flip", ")", "-compose", "Multiply", "-composite",
                "(", "+clone", "-flop", ")", "-compose", "Multiply", "-composite", ")",
                "-alpha", "off", "-compose", "CopyOpacity", "-composite"]
    subprocess.run(cmd + [out], check=True)
    os.remove(tmp)


def icon(a):
    k = key("CM_KEY_FILE")
    h = {"Authorization": f"Bearer {k}"}
    prompt = STYLES[a.style].format(s=a.subject)
    job = http("POST", f"{CM}/v1/jobs", h, {
        "operation": "text_to_image", "model": "content-controller/still.krea",
        "input": {"prompt": prompt}, "params": {"size": 768, "seed": a.seed or 7},
    })
    jid = job["id"]
    for _ in range(300):
        j = http("GET", f"{CM}/v1/jobs/{jid}", h)
        if j["status"] in ("succeeded", "failed", "canceled"):
            break
        time.sleep(3)
    if j["status"] != "succeeded":
        sys.exit(f"{a.out}: {j['status']} {j.get('error')}")
    frame(http("GET", j["artifacts"][0]["url"], h, raw=True), a.out, a.size)
    print(a.out)


def edit(a):
    k = key("CC_KEY_FILE")
    h = {"X-Api-Key": k}
    if a.task:
        return collect(a, h, a.task)
    ref = open(a.ref, "rb").read()
    boundary = "----heroart%d" % time.time_ns()
    payload = {"prompt": a.instruction, "seed": a.seed or 11, "refResolution": 1024, "steps": a.steps}
    parts = []
    for name, val in (("operation", "image.qwen21.edit"), ("payload", json.dumps(payload))):
        parts.append(f"--{boundary}\r\nContent-Disposition: form-data; name=\"{name}\"\r\n\r\n{val}\r\n".encode())
    parts.append((f"--{boundary}\r\nContent-Disposition: form-data; name=\"input0\"; filename=\"ref.png\"\r\n"
                  "Content-Type: image/png\r\n\r\n").encode() + ref + b"\r\n")
    parts.append(f"--{boundary}--\r\n".encode())
    body = b"".join(parts)
    req = urllib.request.Request(f"{CC}/api/content/v1/tasks", data=body, method="POST",
                                 headers=dict(h, **{"Content-Type": f"multipart/form-data; boundary={boundary}"}))
    with urllib.request.urlopen(req, timeout=120) as r:
        t = json.loads(r.read())
    tid = t["taskId"]
    print(f"task {tid}", file=sys.stderr)
    collect(a, h, tid)


def collect(a, h, tid):
    deadline = time.time() + a.wait
    while time.time() < deadline:
        s = http("GET", f"{CC}/api/content/v1/tasks/{tid}?wait=30", h, timeout=90)
        st = s.get("status")
        if st in ("Succeeded", "succeeded", "Completed", "completed"):
            break
        if st in ("Failed", "failed", "Canceled", "canceled", "Blocked"):
            sys.exit(f"{a.out}: {st} {s.get('error') or s.get('failure')}")
    else:
        sys.exit(f"{a.out}: still waiting (task {tid}), rerun later with --task {tid}")
    res = http("GET", f"{CC}/api/content/v1/tasks/{tid}/result", h)
    url = None
    for art in res.get("artifacts") or res.get("results") or []:
        url = art.get("url") or art.get("downloadUrl")
        if url:
            break
    if not url:
        sys.exit(f"{a.out}: no artifact url in {json.dumps(res)[:400]}")
    frame(http("GET", url, {} if "X-Amz" in url or "sig" in url else h, raw=True), a.out, a.size, rounded=False)
    print(a.out)


p = argparse.ArgumentParser()
sub = p.add_subparsers(dest="cmd", required=True)
i = sub.add_parser("icon"); i.add_argument("out"); i.add_argument("subject")
i.add_argument("--size", type=int, default=128); i.add_argument("--seed", type=int); i.add_argument("--style", default="item", choices=STYLES)
e = sub.add_parser("edit"); e.add_argument("out"); e.add_argument("ref"); e.add_argument("instruction")
e.add_argument("--size", type=int, default=256); e.add_argument("--seed", type=int); e.add_argument("--steps", type=int, default=40)
e.add_argument("--wait", type=int, default=3600); e.add_argument("--task", help="collect an already submitted task")
a = p.parse_args()
icon(a) if a.cmd == "icon" else edit(a)
