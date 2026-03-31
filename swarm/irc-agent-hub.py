#!/usr/bin/env python3
import argparse
import json
import os
import queue
import select
import socket
import ssl
import sys
import threading
import time
from pathlib import Path

BASE_CFG = Path('/root/.openclaw/openclaw.json')
AGENT_CFG = Path('/root/.openclaw/workspace/swarm/irc-agent-accounts.json')
SOCK_PATH = '/tmp/swarm-irc-agent-hub.sock'
LOG_PATH = '/tmp/swarm-irc-agent-hub.log'
PID_PATH = '/tmp/swarm-irc-agent-hub.pid'


def log(msg: str):
    ts = time.strftime('%Y-%m-%dT%H:%M:%S')
    with open(LOG_PATH, 'a', encoding='utf-8') as f:
        f.write(f'[{ts}] {msg}\n')


def read_json(path: Path):
    return json.loads(path.read_text(encoding='utf-8'))


class AgentConn:
    def __init__(self, host, port, tls, agent_id, nick):
        self.host = host
        self.port = port
        self.tls = tls
        self.agent_id = agent_id
        self.nick = nick
        self.sock = None
        self.buffer = b''
        self.joined = set()
        self.ready = False
        self.stop = False
        self.lock = threading.Lock()
        self.last_error = None
        self.last_connect = 0.0
        self.last_pong = 0.0
        self.events = queue.Queue()
        self.thread = threading.Thread(target=self.run, daemon=True)
        self.thread.start()

    def connect(self):
        raw = socket.create_connection((self.host, self.port), timeout=20)
        sock = ssl.create_default_context().wrap_socket(raw, server_hostname=self.host) if self.tls else raw
        sock.setblocking(False)
        self.sock = sock
        self.buffer = b''
        self.ready = False
        self.joined.clear()
        self.last_connect = time.time()
        self.send_line(f'NICK {self.nick}')
        self.send_line(f'USER {self.nick} 0 * :{self.agent_id}')
        log(f'[{self.agent_id}] connect started as {self.nick}')

    def ensure_connected(self):
        if self.sock is None:
            self.connect()

    def close(self):
        s = self.sock
        self.sock = None
        if s is not None:
            try:
                s.close()
            except Exception:
                pass
        self.ready = False
        self.joined.clear()

    def send_line(self, line: str):
        if self.sock is None:
            raise RuntimeError('not connected')
        self.sock.sendall((line + '\r\n').encode())
        log(f'[{self.agent_id}] >>> {line}')

    def handle_line(self, text: str):
        log(f'[{self.agent_id}] {text}')
        if text.startswith('PING '):
            self.send_line('PONG ' + text.split(' ', 1)[1])
            return
        if any(code in text for code in [' 001 ', ' 376 ', ' 422 ']):
            self.ready = True
            return
        if ' 433 ' in text:
            self.last_error = 'nickname in use'
            raise RuntimeError('nickname in use')
        if self.ready:
            if ' JOIN ' in text and text.startswith(f':{self.nick}!'):
                parts = text.split(' JOIN ', 1)
                if len(parts) == 2:
                    ch = parts[1].lstrip(':').strip()
                    self.joined.add(ch)
            if f' 366 {self.nick} ' in text:
                parts = text.split()
                if len(parts) >= 4:
                    self.joined.add(parts[3])

    def run(self):
        backoff = 2
        while not self.stop:
            try:
                self.ensure_connected()
                r, _, _ = select.select([self.sock], [], [], 1)
                if r:
                    try:
                        chunk = self.sock.recv(4096)
                    except ssl.SSLWantReadError:
                        chunk = None
                    if chunk == b'':
                        raise RuntimeError('connection closed')
                    if chunk:
                        self.buffer += chunk
                        while b'\r\n' in self.buffer:
                            line, self.buffer = self.buffer.split(b'\r\n', 1)
                            self.handle_line(line.decode(errors='ignore'))
                try:
                    while True:
                        cmd = self.events.get_nowait()
                        kind = cmd.get('kind')
                        if kind == 'join':
                            ch = cmd['channel']
                            if ch not in self.joined:
                                self.send_line(f'JOIN {ch}')
                        elif kind == 'send':
                            ch = cmd['channel']
                            msg = cmd['message']
                            if ch not in self.joined:
                                self.send_line(f'JOIN {ch}')
                                deadline = time.time() + 8
                                while time.time() < deadline and ch not in self.joined:
                                    rr, _, _ = select.select([self.sock], [], [], 0.5)
                                    if not rr:
                                        continue
                                    try:
                                        chunk = self.sock.recv(4096)
                                    except ssl.SSLWantReadError:
                                        chunk = None
                                    if chunk == b'':
                                        raise RuntimeError('connection closed while waiting for join')
                                    if chunk:
                                        self.buffer += chunk
                                        while b'\r\n' in self.buffer:
                                            line, self.buffer = self.buffer.split(b'\r\n', 1)
                                            self.handle_line(line.decode(errors='ignore'))
                            self.send_line(f'PRIVMSG {ch} :{msg}')
                            if 'result' in cmd:
                                cmd['result']['ok'] = True
                        elif kind == 'quit':
                            self.send_line('QUIT :shutdown')
                            self.stop = True
                            break
                except queue.Empty:
                    pass
                backoff = 2
            except Exception as e:
                self.last_error = str(e)
                log(f'[{self.agent_id}] error: {e}')
                self.close()
                time.sleep(backoff)
                backoff = min(backoff * 2, 30)

    def request_join(self, channel: str):
        self.events.put({'kind': 'join', 'channel': channel})

    def request_send(self, channel: str, message: str, timeout: float = 20.0):
        result = {'ok': False}
        self.events.put({'kind': 'send', 'channel': channel, 'message': message, 'result': result})
        deadline = time.time() + timeout
        while time.time() < deadline:
            if result['ok']:
                return True
            if self.last_error:
                raise RuntimeError(self.last_error)
            time.sleep(0.1)
        raise RuntimeError('send timed out')

    def status(self):
        return {
            'agent': self.agent_id,
            'nick': self.nick,
            'ready': self.ready,
            'joined': sorted(self.joined),
            'last_error': self.last_error,
            'last_connect': self.last_connect,
        }


class Hub:
    def __init__(self):
        base = read_json(BASE_CFG)['channels']['irc']
        self.host = base['host']
        self.port = int(base.get('port', 6697))
        self.tls = bool(base.get('tls', True))
        self.agents_cfg = read_json(AGENT_CFG)
        self.conns = {}

    def ensure_agents(self, agent_ids):
        ids = agent_ids
        for aid in ids:
            if aid not in self.agents_cfg:
                raise RuntimeError(f'unknown agent {aid}')
            if aid not in self.conns:
                nick = self.agents_cfg[aid]['nick']
                self.conns[aid] = AgentConn(self.host, self.port, self.tls, aid, nick)

    def handle(self, req):
        cmd = req.get('cmd')
        if cmd == 'status':
            return {
                'ok': True,
                'agents': {
                    aid: self.conns[aid].status() if aid in self.conns else {
                        'agent': aid,
                        'nick': self.agents_cfg[aid]['nick'],
                        'ready': False,
                        'joined': [],
                        'last_error': None,
                        'last_connect': 0.0,
                    }
                    for aid in self.agents_cfg.keys()
                },
            }
        if cmd == 'join':
            aid = req['agent']
            ch = req['channel']
            self.ensure_agents([aid])
            self.conns[aid].request_join(ch)
            return {'ok': True}
        if cmd == 'send':
            aid = req['agent']
            ch = req['channel']
            msg = req['message']
            self.ensure_agents([aid])
            self.conns[aid].request_send(ch, msg)
            return {'ok': True}
        raise RuntimeError(f'unknown cmd {cmd}')


def run_daemon():
    try:
        os.unlink(SOCK_PATH)
    except FileNotFoundError:
        pass
    Path(PID_PATH).write_text(str(os.getpid()), encoding='utf-8')
    hub = Hub()
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(SOCK_PATH)
    os.chmod(SOCK_PATH, 0o666)
    server.listen(8)
    log('hub started')
    try:
        while True:
            conn, _ = server.accept()
            data = b''
            while True:
                chunk = conn.recv(65536)
                if not chunk:
                    break
                data += chunk
            try:
                req = json.loads(data.decode() or '{}')
                res = hub.handle(req)
            except Exception as e:
                res = {'ok': False, 'error': str(e)}
            conn.sendall((json.dumps(res) + '\n').encode())
            conn.close()
    finally:
        try:
            os.unlink(SOCK_PATH)
        except FileNotFoundError:
            pass


def send_request(payload):
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.connect(SOCK_PATH)
    client.sendall(json.dumps(payload).encode())
    client.shutdown(socket.SHUT_WR)
    buf = b''
    while True:
        chunk = client.recv(65536)
        if not chunk:
            break
        buf += chunk
    client.close()
    if not buf:
        raise RuntimeError('empty hub response')
    return json.loads(buf.decode())


def ensure_started():
    if os.path.exists(SOCK_PATH):
        return
    pid = os.fork()
    if pid > 0:
        for _ in range(50):
            if os.path.exists(SOCK_PATH):
                return
            time.sleep(0.1)
        raise RuntimeError('hub failed to start')
    os.setsid()
    devnull = os.open('/dev/null', os.O_RDWR)
    os.dup2(devnull, 0)
    os.dup2(devnull, 1)
    os.dup2(devnull, 2)
    run_daemon()
    os._exit(0)


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest='cmd', required=True)
    sub.add_parser('daemon')
    sub.add_parser('ensure-start')
    p_send = sub.add_parser('send')
    p_send.add_argument('--agent', required=True)
    p_send.add_argument('--channel', required=True)
    p_send.add_argument('--message', required=True)
    p_join = sub.add_parser('join')
    p_join.add_argument('--agent', required=True)
    p_join.add_argument('--channel', required=True)
    sub.add_parser('status')
    args = ap.parse_args()

    if args.cmd == 'daemon':
        run_daemon()
        return
    if args.cmd == 'ensure-start':
        ensure_started()
        print('ok')
        return
    ensure_started()
    if args.cmd == 'send':
        res = send_request({'cmd': 'send', 'agent': args.agent, 'channel': args.channel, 'message': args.message})
    elif args.cmd == 'join':
        res = send_request({'cmd': 'join', 'agent': args.agent, 'channel': args.channel})
    else:
        res = send_request({'cmd': 'status'})
    if not res.get('ok'):
        print(res.get('error', 'hub command failed'), file=sys.stderr)
        raise SystemExit(1)
    print(json.dumps(res, ensure_ascii=False))


if __name__ == '__main__':
    main()
