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

def rings(rel):
    """Outer ways joined into closed rings."""
    ways = [[(g["lat"], g["lon"]) for g in m["geometry"]] for m in rel.get("members", [])
            if m.get("type") == "way" and m.get("role", "outer") in ("outer", "") and m.get("geometry")]
    out = []
    while ways:
        ring = ways.pop(0)
        changed = True
        while changed and ring[0] != ring[-1]:
            changed = False
            for k, w in enumerate(ways):
                if w[0] == ring[-1]: ring += w[1:]
                elif w[-1] == ring[-1]: ring += w[::-1][1:]
                elif w[-1] == ring[0]: ring = w + ring[1:]
                elif w[0] == ring[0]: ring = w[::-1] + ring[1:]
                else: continue
                ways.pop(k); changed = True; break
        out.append(ring)
    return out

print("== Clean air zones in OpenStreetMap (Britain)")
d = overpass('[out:json][timeout:170];(relation["boundary"="low_emission_zone"](49.8,-8.7,61,2);'
             'way["boundary"="low_emission_zone"](49.8,-8.7,61,2););out tags geom;')
for e in (d or {}).get("elements", []):
    tags = e.get("tags", {})
    rs = rings(e) if e["type"] == "relation" else [[(g["lat"], g["lon"]) for g in e.get("geometry", [])]]
    print("ZONE", e["type"], e["id"], json.dumps(tags))
    for r in rs:
        if len(r) < 4: continue
        s = rdp(r, 120 if len(r) > 2000 else 40)
        print("  RING", len(r), "->", len(s), json.dumps([[round(a, 5), round(b, 5)] for a, b in s]))

print("== Greater London boundary (for the ULEZ, which covers all of it)")
d = overpass('[out:json][timeout:170];relation["boundary"="administrative"]["admin_level"="5"]["name"="Greater London"];out tags geom;')
for e in (d or {}).get("elements", []):
    for r in rings(e):
        s = rdp(r, 250)
        print("  LONDON RING", len(r), "->", len(s), json.dumps([[round(a, 4), round(b, 4)] for a, b in s]))

print("== OSRM time table (Southampton)")
try:
    pts = "-1.4044,50.9097;-1.3966,50.9346;-1.4200,50.9200;-1.3800,50.9300"
    code, body = get(f"https://routing.openstreetmap.de/routed-car/table/v1/driving/{pts}?sources=0;1&destinations=2;3&annotations=duration,distance", t=30)
    print(" ", code, body[:600])
except Exception as e:
    print("  table failed", e)

print("== Valhalla route avoiding a spot (Avenue, Southampton)")
try:
    req = {"locations": [{"lat": 50.9097, "lon": -1.4044}, {"lat": 50.9346, "lon": -1.3966}], "costing": "auto",
           "exclude_locations": [{"lat": 50.9220, "lon": -1.4010}], "directions_options": {"units": "kilometers"}}
    code, body = get("https://valhalla1.openstreetmap.de/route?json=" + urllib.parse.quote(json.dumps(req)), t=30)
    j = json.loads(body)
    print(" ", code, "km", j["trip"]["summary"]["length"], "s", j["trip"]["summary"]["time"], "shape", j["trip"]["legs"][0]["shape"][:80])
    req.pop("exclude_locations")
    code, body = get("https://valhalla1.openstreetmap.de/route?json=" + urllib.parse.quote(json.dumps(req)), t=30)
    j = json.loads(body)
    print("  without:", code, "km", j["trip"]["summary"]["length"], "s", j["trip"]["summary"]["time"])
except Exception as e:
    print("  valhalla failed", e)

print("== Main entrances near big places")
for name, lat, lng in [("Southampton General", 50.9330, -1.4335), ("Westquay", 50.9045, -1.4085),
                       ("Southampton Central station", 50.9077, -1.4136), ("Heathrow T5", 51.4720, -0.4880)]:
    d = overpass(f'[out:json][timeout:60];node["entrance"~"main|yes"](around:400,{lat},{lng});out tags;')
    els = (d or {}).get("elements", [])
    print(" ", name, len(els), "entrances,", sum(1 for x in els if x["tags"].get("entrance") == "main"), "main:",
          [ (x["lat"], x["lon"], x["tags"].get("name") or x["tags"].get("ref") or "", x["tags"].get("access", "")) for x in els if x["tags"].get("entrance") == "main"][:6])

print("== Traffic light tags (central Southampton)")
d = overpass('[out:json][timeout:60];node["highway"="traffic_signals"](50.90,-1.42,50.93,-1.38);out tags;')
els = (d or {}).get("elements", [])
keys = {}
for x in els:
    for k, v in x["tags"].items():
        if "direction" in k: keys[f"{k}={v}"] = keys.get(f"{k}={v}", 0) + 1
print(" ", len(els), "lights; direction tags:", keys)

print("== Google reviews page")
for url in ["https://www.google.com/maps/search/?api=1&query=The+Dancing+Man+Southampton",
            "https://www.google.com/search?q=The+Dancing+Man+Southampton+reviews&hl=en-GB"]:
    try:
        code, body = get(url, h={"User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
                                  "Accept-Language": "en-GB"}, t=30)
        s = body.decode("utf-8", "replace")
        print(" ", code, len(s), "consent" in s.lower(), s.count("review"), url)
    except Exception as e:
        print("  failed", e, url)
