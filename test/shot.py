# Screenshot a QEMU VM through its QMP socket, optionally after a delay.
# usage: python3 shot.py <qmp-socket> <out.ppm> [delay-seconds]
import socket, json, sys, time, os
sock, out, delay = sys.argv[1], sys.argv[2], float(sys.argv[3]) if len(sys.argv) > 3 else 0
time.sleep(delay)
s = socket.socket(socket.AF_UNIX); s.connect(sock); f = s.makefile("rw")
f.readline()
def cmd(c, **a):
    f.write(json.dumps({"execute": c, "arguments": a}) + "\n"); f.flush()
    while True:
        r = json.loads(f.readline())
        if "return" in r or "error" in r: return r
cmd("qmp_capabilities")
print(cmd("query-status")["return"]["status"])
print(cmd("screendump", filename=out))
