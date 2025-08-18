import socket, threading, struct, select, sys, os, base64
from urllib.parse import urlparse, parse_qs
from datetime import datetime
import zoneinfo

try:
    import setproctitle
except:
    setproctitle = None

TZS = sorted([
    "UTC","Asia/Shanghai","Asia/Tokyo","Asia/Dubai","Asia/Singapore",
    "Europe/London","Europe/Berlin","Europe/Paris","Europe/Moscow",
    "Europe/Warsaw","America/New_York","America/Chicago",
    "America/Los_Angeles","Pacific/Auckland","Australia/Sydney"
])

TZX = {
    "UTC": [51.5,-0.1,5],"Asia/Shanghai": [31.2,121.4,7],
    "Asia/Tokyo": [35.6,139.6,7],"Asia/Dubai": [25.2,55.2,8],
    "Asia/Singapore": [1.3,103.8,8],"Europe/London": [51.5,-0.1,8],
    "Europe/Berlin": [52.5,13.4,8],"Europe/Paris": [48.8,2.3,8],
    "Europe/Moscow": [55.7,37.6,7],"Europe/Warsaw": [52.2,21.0,8],
    "America/New_York": [40.7,-74.0,7],"America/Chicago": [41.8,-87.6,7],
    "America/Los_Angeles": [34.0,-118.2,7],"Pacific/Auckland": [-36.8,174.7,7],
    "Australia/Sydney": [-33.8,151.2,7]
}

T = """
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>sys-helper</title>
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css">
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
<style>
body {{ font-family:sans-serif;background:#f4f4f4;display:flex;align-items:center;justify-content:center;height:100vh;margin:0 }}
.b {{ background:#fff;padding:20px;border-radius:8px;box-shadow:0 0 20px rgba(0,0,0,0.1);width:500px;text-align:center }}
select {{ width:100%;padding:10px;margin-bottom:10px }}
.r {{ margin-top:15px;padding:10px;background:#eee;border-radius:5px }}
#map {{ height:250px;margin-top:20px;border:1px solid #ccc }}
</style></head><body>
<div class="b"><form method="GET"><select name="z" onchange="this.form.submit()">
<option value="" disabled {sel}>- Select Timezone -</option>{opts}</select></form>
<div class="r">{res}</div><div id="map"></div></div>
<script>{map}</script></body></html>
"""

def W(res, s=None):
    o = ""
    for z in TZS:
        o += f'<option value="{z}"{" selected" if z==s else ""}>{z}</option>'
    if s and s in TZX:
        c = TZX[s]
        m = f"""try {{
var map = L.map('map').setView({[c[0], c[1]]}, {c[2]});
L.tileLayer('https://{{s}}.tile.openstreetmap.org/{{z}}/{{x}}/{{y}}.png', {{
attribution: 'Map data © OpenStreetMap contributors'}}).addTo(map);
L.marker({[c[0], c[1]]}).addTo(map).bindPopup('<b>{s}</b>').openPopup(); }}
catch(e) {{ document.getElementById('map').innerHTML = 'Map load failed.'; }}"""
    else:
        m = "document.getElementById('map').innerHTML='<div style=\"color:#888;text-align:center\">No Map</div>';"
    return T.format(opts=o, res=res, map=m, sel="selected" if not s else "")

def H(c):
    r = "<p>Select a timezone</p>"
    s = None
    try:
        d = c.recv(4096).decode('utf-8', 'ignore')
        if not d: c.close(); return
        p = urlparse(d.split(' ')[1])
        q = parse_qs(p.query)
        s = q.get('z', [None])[0]
        if s:
            try:
                t = zoneinfo.ZoneInfo(s)
                now = datetime.now(zoneinfo.ZoneInfo("UTC")).astimezone(t)
                r = f"<b>{s}</b><br>{now.strftime('%Y-%m-%d %H:%M:%S %Z')}"
            except Exception as e:
                r = f"<span style='color:red'>Error: {e}</span>"
        b = W(r, s)
        h = f"HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {len(b.encode())}\r\nConnection: close\r\n\r\n{b}"
        c.sendall(h.encode())
    except: pass
    finally: c.close()

V = 5
A = 2
class P:
    def __init__(self, auth): self.auth = auth
    def x(self, c):
        try:
            h = c.recv(2)
            if not h or h[0] != V: return
            m = c.recv(h[1])
            if A not in m: c.sendall(struct.pack("!BB", V, 0xFF)); return
            c.sendall(struct.pack("!BB", V, A))
            if not self.y(c): return
            h = c.recv(4)
            if not h or len(h) < 4: return
            v, cmd, _, t = struct.unpack("!BBBB", h)
            if v != V or cmd != 1: self.r(c, 0x07); return
            if t == 1:
                addr = socket.inet_ntoa(c.recv(4))
            elif t == 3:
                l = c.recv(1)[0]
                addr = c.recv(l).decode()
            elif t == 4:
                addr = socket.inet_ntop(socket.AF_INET6, c.recv(16))
            else:
                self.r(c, 0x08); return
            port = struct.unpack("!H", c.recv(2))[0]
            try:
                r = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                r.connect((addr, port))
                ba, bp = r.getsockname()
                self.r(c, 0x00, socket.inet_aton(ba), bp)
            except:
                self.r(c, 0x01); return
            self.z(c, r)
        except: pass
        finally: c.close()
    def y(self, c):
        try:
            h = c.recv(2)
            if not h or h[0] != 1: return False
            u = c.recv(h[1]).decode()
            p = c.recv(1)[0]
            pw = c.recv(p).decode()
            if self.auth.get(u) == pw:
                c.sendall(struct.pack("!BB", 1, 0)); return True
            else:
                c.sendall(struct.pack("!BB", 1, 1)); return False
        except: return False
    def r(self, c, rep, ba=b'\x00\x00\x00\x00', bp=0):
        res = struct.pack("!BBBB", V, rep, 0, 1) + ba + struct.pack("!H", bp)
        c.sendall(res)
    def z(self, c, r):
        try:
            while True:
                rr, _, _ = select.select([c, r], [], [], 300)
                if not rr: break
                for s in rr:
                    d = s.recv(4096)
                    if not d: return
                    (r if s == c else c).sendall(d)
        except: pass
        finally: r.close()

if __name__ == '__main__':
    HOST = '0.0.0.0'
    PORT = int(os.getenv("S_PORT"))

    U_b64 = os.getenv("S_U")
    PWD_b64 = os.getenv("S_P")
    if not U_b64 or not PWD_b64:
        print("请在 .env 中设置 S_U 和 S_P")
        sys.exit(1)

    # 解码得到实际用户名和密码
    U = base64.b64decode(U_b64).decode()
    PWD = base64.b64decode(PWD_b64).decode()
    C = {U: PWD}

    if setproctitle:
        setproctitle.setproctitle("/usr/lib/systemd/systemd-journald")

    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        s.bind((HOST, PORT))
        s.listen(128)
    except Exception as e:
        print(f"SVC: Failed to bind {PORT}: {e}")
        sys.exit(1)

    print(f"SVC: sys-daemon started. pid={os.getpid()}")
    f = P(C)
    while True:
        try:
            c, a = s.accept()
            b = c.recv(1, socket.MSG_PEEK)
            t = threading.Thread(target=f.x if b == b'\x05' else H, args=(c,))
            t.daemon = True
            t.start()
        except KeyboardInterrupt:
            break
        except:
            pass
    s.close()
    print("SVC: shutdown.")
