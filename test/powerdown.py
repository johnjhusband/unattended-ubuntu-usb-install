# Ask a QEMU VM to shut down cleanly (ACPI power button) through its QMP socket.
# usage: python3 powerdown.py <qmp-socket>
import socket, json, sys, time
s = socket.socket(socket.AF_UNIX); s.connect(sys.argv[1]); f = s.makefile("rw"); f.readline()
for c in ("qmp_capabilities", "system_powerdown"):
    f.write(json.dumps({"execute": c}) + "\n"); f.flush(); f.readline()
