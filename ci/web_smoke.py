#!/usr/bin/env python3
# Web smoke test: opens an exported web build in headless Chrome (DevTools
# protocol), waits, takes screenshots and fails unless the engine booted
# (Godot's startup line in the console, a WebGL 2 canvas, no JS exceptions).
#   python3 ci/web_smoke.py <url> <out.png> <debug-port> [wait_s,wait_s,...]
#   PRESS_AFTER_SHOT_<n>=O  presses a key after screenshot n (e.g. O = overlays).
# Needs google-chrome and the websocket-client package (pip install websocket-client).
import json, subprocess, sys, time, base64, urllib.request, websocket, os, shutil
url, out, port = sys.argv[1], sys.argv[2], int(sys.argv[3])
waits = [float(x) for x in sys.argv[4].split(',')] if len(sys.argv) > 4 else [20.0]
prof = f"/tmp/dk_web_smoke_{port}"
shutil.rmtree(prof, ignore_errors=True)
chrome = subprocess.Popen(["google-chrome", "--headless=new", "--no-sandbox", "--use-angle=swiftshader",
    "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist", "--autoplay-policy=no-user-gesture-required",
    f"--remote-debugging-port={port}", f"--user-data-dir={prof}", "--window-size=1280,720", "about:blank"],
    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
try:
    for _ in range(50):
        try:
            tabs = json.load(urllib.request.urlopen(f"http://127.0.0.1:{port}/json"))
            break
        except Exception:
            time.sleep(0.2)
    tab = [t for t in tabs if t["type"] == "page"][0]
    ws = websocket.create_connection(tab["webSocketDebuggerUrl"], timeout=60, suppress_origin=True)
    mid = [0]
    logs = []
    def send(method, params=None):
        mid[0] += 1
        ws.send(json.dumps({"id": mid[0], "method": method, "params": params or {}}))
        while True:
            m = json.loads(ws.recv())
            if m.get("method") == "Runtime.consoleAPICalled":
                logs.append(" ".join(str(a.get("value", a.get("description", ""))) for a in m["params"]["args"]))
            elif m.get("method") == "Runtime.exceptionThrown":
                logs.append("EXCEPTION " + json.dumps(m["params"]["exceptionDetails"].get("text")))
            if m.get("id") == mid[0]:
                return m
    send("Runtime.enable")
    send("Page.enable")
    send("Emulation.setDeviceMetricsOverride", {"width": 1280, "height": 720, "deviceScaleFactor": 1, "mobile": False})
    send("Page.navigate", {"url": url})
    t0 = time.time()
    for k, w in enumerate(waits):
        while time.time() - t0 < w:
            ws.settimeout(0.5)
            try:
                m = json.loads(ws.recv())
                if m.get("method") == "Runtime.consoleAPICalled":
                    logs.append(" ".join(str(a.get("value", a.get("description", ""))) for a in m["params"]["args"]))
                elif m.get("method") == "Runtime.exceptionThrown":
                    logs.append("EXCEPTION " + json.dumps(m["params"]["exceptionDetails"].get("text")))
            except Exception:
                pass
        ws.settimeout(60)
        r = send("Page.captureScreenshot", {"format": "png"})
        fn = out if len(waits) == 1 else out.replace(".png", f"_{k+1}.png")
        open(fn, "wb").write(base64.b64decode(r["result"]["data"]))
        print("shot", fn, f"t={time.time()-t0:.1f}s")
        key = os.environ.get("PRESS_AFTER_SHOT_%d" % (k + 1))
        if key:
            send("Input.dispatchMouseEvent", {"type": "mousePressed", "x": 5, "y": 5, "button": "none", "clickCount": 0})
            for typ in ("keyDown", "keyUp"):
                send("Input.dispatchKeyEvent", {"type": typ, "key": key.lower(), "code": "Key" + key.upper(),
                    "windowsVirtualKeyCode": ord(key.upper()), "nativeVirtualKeyCode": ord(key.upper())})
            print("pressed", key)
    r = send("Runtime.evaluate", {"expression": "[document.title, !!document.querySelector('canvas'), (document.getElementById('status')||{}).style ? document.getElementById('status').style.display : 'n/a', (()=>{const c=document.querySelector('canvas'); return c? c.width+'x'+c.height : ''})()].join(' | ')", "returnByValue": True})
    print("page:", r["result"]["result"].get("value"))
    print("console:")
    for l in logs[:40]:
        print("  ", l[:200])
    booted = any(l.startswith("Godot Engine v") for l in logs)
    webgl2 = any("WebGL 2.0" in l for l in logs)
    errors = [l for l in logs if l.startswith("EXCEPTION")]
    print("booted:", booted, "webgl2:", webgl2, "exceptions:", len(errors))
    if not booted or not webgl2 or errors:
        sys.exit(1)
finally:
    chrome.terminate()
