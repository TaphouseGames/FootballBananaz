"""A stand-in for Edgegap's matchmaker and host on this one machine.

It answers the three calls the game makes (see scripts/online/edgegap_matchmaker.gd):
POST /tickets, GET /tickets/<id>, DELETE /tickets/<id>, each with the header
"Authorization: <token>". Two tickets that are waiting are put together, and
after a moment both are given the same server.

With --godot it starts that server itself, the way the host does: a headless
Godot on scenes/server.tscn with the two tickets in MM_TICKET_IDS, so only
those two people are let in. Without it, a server has to be listening on the
port already (and lets anyone in).

  python tools/fake_matchmaker.py [--port 8765] [--token dev] [--server-port 24642]
         [--godot <Godot console exe>] [--delay 5]

GET /debug (no token) says how many tickets there are: for the tests.
"""
import argparse
import json
import os
import subprocess
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ARGS = None
LOCK = threading.Lock()
# id -> {"status", "assignment", "ready_at"}
TICKETS = {}
MATCHES = 0


def pair_up():
    """Puts the two longest-waiting tickets together (called with the lock held)."""
    global MATCHES
    waiting = [i for i, t in TICKETS.items() if t["status"] == "SEARCHING"]
    if len(waiting) < 2:
        return
    pair = waiting[:2]
    port = ARGS.server_port + (MATCHES if ARGS.godot else 0)
    MATCHES += 1
    if ARGS.godot:
        env = dict(os.environ)
        env["ARBITRIUM_REQUEST_ID"] = "fake-%d" % MATCHES
        env["MM_TICKET_IDS"] = json.dumps(pair)
        env["ARBITRIUM_PORTS_MAPPING"] = json.dumps(
            {"ports": {"game": {"name": "game", "internal": port, "external": port, "protocol": "UDP"}}})
        project = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        subprocess.Popen([ARGS.godot, "--headless", "--path", project, "res://scenes/server.tscn"], env=env)
    assignment = {
        "fqdn": "localhost",
        "public_ip": "127.0.0.1",
        "ports": {"game": {"internal": port, "external": port, "protocol": "UDP", "link": "localhost:%d" % port}},
    }
    for ticket in pair:
        TICKETS[ticket].update(status="TEAM_FOUND", assignment=assignment, ready_at=time.time() + ARGS.delay)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def answer(self, code, body=None):
        data = json.dumps(body).encode() if body is not None else b""
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def allowed(self):
        if self.headers.get("Authorization") == ARGS.token:
            return True
        self.answer(401, {"message": "bad token"})
        return False

    def shown(self, ticket):
        entry = TICKETS[ticket]
        ready = entry["status"] == "TEAM_FOUND" and time.time() >= entry["ready_at"]
        if ready:
            entry["status"] = "HOST_ASSIGNED"
        return {
            "id": ticket,
            "profile": entry["profile"],
            "status": entry["status"],
            "assignment": entry["assignment"] if entry["status"] == "HOST_ASSIGNED" else None,
        }

    def do_POST(self):
        if self.path != "/tickets":
            return self.answer(404)
        if not self.allowed():
            return
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        ticket = uuid.uuid4().hex[:20]
        with LOCK:
            TICKETS[ticket] = {"status": "SEARCHING", "assignment": None, "ready_at": 0.0, "profile": body.get("profile")}
            pair_up()
            self.answer(200, self.shown(ticket))

    def do_GET(self):
        if self.path == "/debug":
            with LOCK:
                return self.answer(200, {"tickets": len(TICKETS), "matches": MATCHES})
        if not self.allowed():
            return
        ticket = self.path.rsplit("/", 1)[-1]
        with LOCK:
            if not self.path.startswith("/tickets/") or ticket not in TICKETS:
                return self.answer(404, {"message": "no such ticket"})
            self.answer(200, self.shown(ticket))

    def do_DELETE(self):
        if not self.allowed():
            return
        ticket = self.path.rsplit("/", 1)[-1]
        with LOCK:
            if TICKETS.pop(ticket, None) is None:
                return self.answer(404, {"message": "no such ticket"})
            self.answer(204)


def main():
    global ARGS
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--token", default="dev")
    parser.add_argument("--server-port", type=int, default=24642)
    parser.add_argument("--godot", default="")
    parser.add_argument("--delay", type=float, default=5.0)
    ARGS = parser.parse_args()
    print("fake matchmaker on http://127.0.0.1:%d (token %s)" % (ARGS.port, ARGS.token), flush=True)
    ThreadingHTTPServer(("127.0.0.1", ARGS.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
