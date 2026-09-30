"""EZ2 Co-op bridge relay (runs on the dexx server).

A host behind NAT opens a tunnel to CONTROL_PORT and is given one public game port from PORT_RANGE.
Game clients send plain Source UDP to that public port; the relay wraps each datagram with a client id
and pushes it down the host's tunnel. The host helper (ez2coop-bridge.ps1) replays it to the local
listen server from one loopback socket per client, and sends the replies back the same way.

Tunnel datagrams (host <-> relay, all on CONTROL_PORT):
  b'EZ2B' + op(1) + body
  op 1 HELLO     host->relay  body = version(u16) + room name (utf-8, optional)
  op 2 ASSIGNED  relay->host  body = public port(u16)
  op 3 PING      host->relay  (keepalive; relay answers op 4 PONG)
  op 5 DATA      both ways    body = client id(u32) + raw game datagram
  op 6 CLOSE     relay->host  body = client id(u32)      (client went idle)
  op 7 ERROR     relay->host  body = utf-8 message
"""
import asyncio, os, struct, time

MAGIC = b"EZ2B"
PROTO = 1
CONTROL_PORT = int(os.environ.get("CONTROL_PORT", "27600"))
PORT_FIRST = int(os.environ.get("PORT_FIRST", "27601"))
PORT_LAST = int(os.environ.get("PORT_LAST", "27616"))
HOST_TIMEOUT = 30.0     # no ping from the host for this long -> session closed
CLIENT_TIMEOUT = 120.0  # no packets from a game client for this long -> forgotten
MAX_CLIENTS = 32        # per session (Source max players)


def log(*a):
    print(time.strftime("%H:%M:%S"), *a, flush=True)


class Session:
    def __init__(self, relay, host_addr, port, name):
        self.relay, self.host_addr, self.port, self.name = relay, host_addr, port, name
        self.last_host = time.monotonic()
        self.by_addr, self.by_id, self.last_seen = {}, {}, {}
        self.next_id = 1
        self.transport = None

    def client_packet(self, data, addr):
        cid = self.by_addr.get(addr)
        if cid is None:
            if len(self.by_addr) >= MAX_CLIENTS:
                return
            cid = self.next_id
            self.next_id += 1
            self.by_addr[addr], self.by_id[cid] = cid, addr
            log(f"[{self.port}] client {cid} {addr[0]}:{addr[1]} joined")
        self.last_seen[cid] = time.monotonic()
        self.relay.control.sendto(MAGIC + b"\x05" + struct.pack("<I", cid) + data, self.host_addr)

    def host_data(self, cid, payload):
        addr = self.by_id.get(cid)
        if addr and self.transport:
            self.transport.sendto(payload, addr)

    def drop_client(self, cid):
        addr = self.by_id.pop(cid, None)
        self.last_seen.pop(cid, None)
        if addr:
            self.by_addr.pop(addr, None)
            self.relay.control.sendto(MAGIC + b"\x06" + struct.pack("<I", cid), self.host_addr)
            log(f"[{self.port}] client {cid} left (idle)")

    def close(self):
        if self.transport:
            self.transport.close()
            self.transport = None


class GamePort(asyncio.DatagramProtocol):
    def __init__(self, session):
        self.session = session

    def connection_made(self, transport):
        self.session.transport = transport

    def datagram_received(self, data, addr):
        self.session.client_packet(data, addr)


class Relay(asyncio.DatagramProtocol):
    def __init__(self):
        self.sessions = {}   # host addr -> Session
        self.pending = set() # host addrs whose HELLO is being handled
        self.control = None

    def connection_made(self, transport):
        self.control = transport

    def error(self, addr, msg):
        self.control.sendto(MAGIC + b"\x07" + msg.encode(), addr)

    def datagram_received(self, data, addr):
        if len(data) < 5 or data[:4] != MAGIC:
            return
        op, body = data[4], data[5:]
        s = self.sessions.get(addr)
        if s:
            s.last_host = time.monotonic()
        if op == 5 and s and len(body) >= 4:
            s.host_data(struct.unpack_from("<I", body)[0], body[4:])
        elif op == 3:
            self.control.sendto(MAGIC + b"\x04", addr)
        elif op == 1 and addr not in self.pending:
            self.pending.add(addr)
            asyncio.ensure_future(self.hello(addr, body)).add_done_callback(lambda _: self.pending.discard(addr))

    async def hello(self, addr, body):
        if len(body) < 2 or struct.unpack_from("<H", body)[0] != PROTO:
            return self.error(addr, "Bridge version mismatch - update EZ2 Co-op.")
        s = self.sessions.get(addr)
        if s is None:
            name = body[2:66].decode("utf-8", "replace")
            used = {x.port for x in self.sessions.values()}
            loop = asyncio.get_running_loop()
            for port in range(PORT_FIRST, PORT_LAST + 1):
                if port in used:
                    continue
                s = Session(self, addr, port, name)
                try:
                    await loop.create_datagram_endpoint(lambda: GamePort(s), local_addr=("0.0.0.0", port))
                except OSError:
                    continue
                self.sessions[addr] = s
                log(f"host {addr[0]}:{addr[1]} '{name}' -> public port {port} ({len(self.sessions)} sessions)")
                break
            else:
                return self.error(addr, "All relay ports are busy, try again later.")
        self.control.sendto(MAGIC + b"\x02" + struct.pack("<H", s.port), addr)

    async def reaper(self):
        while True:
            await asyncio.sleep(5)
            now = time.monotonic()
            for addr, s in list(self.sessions.items()):
                if now - s.last_host > HOST_TIMEOUT:
                    log(f"host {addr[0]}:{addr[1]} timed out, freeing port {s.port}")
                    s.close()
                    del self.sessions[addr]
                    continue
                for cid, t in list(s.last_seen.items()):
                    if now - t > CLIENT_TIMEOUT:
                        s.drop_client(cid)


async def main():
    relay = Relay()
    loop = asyncio.get_running_loop()
    await loop.create_datagram_endpoint(lambda: relay, local_addr=("0.0.0.0", CONTROL_PORT))
    log(f"EZ2 co-op relay: control udp/{CONTROL_PORT}, game ports udp/{PORT_FIRST}-{PORT_LAST}")
    await relay.reaper()


if __name__ == "__main__":
    asyncio.run(main())
