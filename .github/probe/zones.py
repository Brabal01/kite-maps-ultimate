"""One-off checks for 0.7.17: clean air zone shapes, the router's time table, a way round a road,
main entrances, traffic light tags and Google's reviews page. Prints what it finds."""
import json, math, urllib.request, urllib.parse, time

UA = {"User-Agent": "Kite-Maps (https://github.com/matteofx1/kite-maps)"}
OVERPASS = ["https://overpass-api.de/api/interpreter", "https://overpass.kumi.systems/api/interpreter",
            "https://overpass.private.coffee/api/interpreter"]

def get(url, data=None, h={}, t=90):
    r = urllib.request.urlopen(urllib.request.Request(url, data=data, headers={**UA, **h}), timeout=t)
    return r.status, r.read()

def overpass(q):
    for ep in OVERPASS:
        try:
            code, body = get(ep, urllib.parse.urlencode({"data": q}).encode(), t=180)
            if code == 200: return json.loads(body)
        except Exception as e:
            print("  overpass", ep, "failed", e)
    return None

def dist(a, b):
    k = math.cos(math.radians((a[0] + b[0]) / 2))
    return math.hypot((a[0] - b[0]) * 111320, (a[1] - b[1]) * 111320 * k)

def seg_d(p, a, b):
    k = math.cos(math.radians(p[0]))
    ax, ay, bx, by, px, py = a[1] * k, a[0], b[1] * k, b[0], p[1] * k, p[0]
    dx, dy = bx - ax, by - ay
    t = 0 if dx == dy == 0 else max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy)))
    return math.hypot(px - ax - t * dx, py - ay - t * dy) * 111320

def rdp(pts, eps):
    if len(pts) < 3: return pts
    i, dm = 0, 0
    for j in range(1, len(pts) - 1):
        d = seg_d(pts[j], pts[0], pts[-1])
        if d > dm: i, dm = j, d
    if dm > eps: return rdp(pts[:i + 1], eps)[:-1] + rdp(pts[i:], eps)
    return [pts[0], pts[-1]]

def rings(el):
    """Outer rings of a way or a relation (member ways joined end to end)."""
    if el["type"] == "way":
        return [[(p["lat"], p["lon"]) for p in el["geometry"]]]
    parts = [[(p["lat"], p["lon"]) for p in m["geometry"]] for m in el.get("members", [])
             if m["type"] == "way" and m.get("role", "outer") in ("outer", "") and m.get("geometry")]
    out = []
    while parts:
        ring = parts.pop(0)
        grown = True
        while grown and dist(ring[0], ring[-1]) > 1:
            grown = False
            for i, p in enumerate(parts):
                if dist(ring[-1], p[0]) < 1: ring += p[1:]
                elif dist(ring[-1], p[-1]) < 1: ring += p[::-1][1:]
                elif dist(ring[0], p[-1]) < 1: ring = p + ring[1:]
                elif dist(ring[0], p[0]) < 1: ring = p[::-1] + ring[1:]
                else: continue
                parts.pop(i); grown = True; break
        out.append(ring)
    return out

ZONES = [("way", 770591846, "Birmingham Clean Air Zone", 40), ("relation", 15479588, "Bristol Clean Air Zone", 40),
         ("way", 1146120795, "Bath Clean Air Zone", 40), ("relation", 17748798, "Oxford Zero Emission Zone", 25),
         ("relation", 17878889, "Glasgow Low Emission Zone", 30), ("relation", 17296491, "Edinburgh Low Emission Zone", 30),
         ("relation", 17878642, "Aberdeen Low Emission Zone", 30), ("way", 1432941996, "Dundee Low Emission Zone", 30),
         ("relation", 16389126, "Sheffield Clean Air Zone", 40), ("way", 1338896773, "Newcastle Gateshead Clean Air Zone", 40),
         ("relation", 175342, "London ULEZ", 150)]

import urllib.parse
print("== Google reviews (listugcposts)")
try:
    import http.cookiejar
    cj = http.cookiejar.CookieJar()
    op = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
    hdr = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/156.0.0.0 Safari/537.36",
           "Accept-Language": "en-GB,en;q=0.9", "Cookie": "SOCS=CAESHAgBEhIaAB; CONSENT=YES+"}
    op.open(urllib.request.Request("https://www.google.com/maps?hl=en-GB&gl=gb", headers=hdr), timeout=30).read()
    q = "https://www.google.com/search?tbm=map&authuser=0&hl=en-GB&gl=gb&q=" + urllib.parse.quote("Westquay Southampton")
    body = op.open(urllib.request.Request(q, headers=hdr), timeout=30).read().decode("utf-8", "replace")
    import re
    fids = re.findall(r'"(0x[0-9a-f]+:0x[0-9a-f]+)"', body)
    print("  feature ids:", fids[:3])
    if fids:
        fid = fids[0]
        pb = (f"!1m6!1s{fid}!6m4!4m1!1e1!4m1!1e3!2m2!1i10!2s!5m2!1s!7e81"
              "!8m5!1b1!2b1!3b1!5b1!7b1!11m6!1e3!2e1!3sen-GB!4sgb!6e1!7e1")
        u = "https://www.google.com/maps/rpc/listugcposts?authuser=0&hl=en-GB&gl=gb&pb=" + urllib.parse.quote(pb, safe="!:")
        r = op.open(urllib.request.Request(u, headers=hdr), timeout=30)
        t = r.read().decode("utf-8", "replace")
        print("  status", r.status, "len", len(t), "start", repr(t[:300]))
        j = json.loads(t[t.index("\n") + 1:] if t.startswith(")]}'") else t)
        revs = j[2] or []
        print("  reviews:", len(revs), "next page:", repr(j[1])[:60])
        def at(x, *path):
            for i in path:
                try: x = x[i]
                except Exception: return "?"
            return x
        for x in revs[:3]:
            print("   author", repr(at(x, 0, 1, 4, 5, 0)), "rating", repr(at(x, 0, 2, 0, 0)), "when", repr(at(x, 0, 1, 6)),
                  "text", repr(str(at(x, 0, 2, 15, 0, 0))[:80]))
        if revs: print("   RAW0", json.dumps(revs[0])[:3000])
except Exception as e:
    print("  reviews failed", repr(e))

print("== Zone shapes for the app")
for kind, oid, name, eps in ZONES:
    d = None
    for _ in range(3):
        d = overpass(f"[out:json][timeout:120];{kind}({oid});out geom;")
        if d and d.get("elements"): break
        time.sleep(10)
    if not d or not d.get("elements"):
        print("SHAPE", name, "FAILED"); continue
    rs = [r for r in rings(d["elements"][0]) if len(r) > 3]
    closed = [r for r in rs if dist(r[0], r[-1]) < 5]
    big = max(closed or rs, key=len)
    simple = rdp(big, eps)
    print("SHAPE", json.dumps({"name": name, "rings": len(rs), "closed": len(closed), "raw": len(big), "points": [[round(a, 5), round(b, 5)] for a, b in simple]}))
