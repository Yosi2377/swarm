#!/usr/bin/env python3
import argparse
import hashlib
import json
import os
import queue
import select
import socket
import ssl
import subprocess
import sys
import tempfile
import threading
import time
from collections import deque
from pathlib import Path
from typing import Dict, List

BASE_CFG = Path('/root/.openclaw/openclaw.json')
AGENT_CFG = Path('/root/.openclaw/workspace/swarm/irc-agent-accounts.json')
RESPOND_SCRIPT = Path('/root/.openclaw/workspace/swarm/collab/agent-respond.sh')
SOCK_PATH = '/tmp/swarm-irc-agent-hub.sock'
LOG_PATH = '/tmp/swarm-irc-agent-hub.log'
PID_PATH = '/tmp/swarm-irc-agent-hub.pid'
DM_STATE_DIR = Path('/tmp/swarm-irc-agent-dm')

HISTORY_MAX_MESSAGES = 24
DM_MODEL_TIMEOUT = 210
DM_MIN_INTERVAL_SECONDS = 2.0

ROLE_PERSPECTIVES = {
    'koder': {'emoji': '⚙️', 'focus': 'clean implementation, APIs, bugs, and practical code changes', 'role': 'senior full-stack developer'},
    'shomer': {'emoji': '🔒', 'focus': 'security risks, permissions, secrets, and hardening', 'role': 'senior security analyst'},
    'tzayar': {'emoji': '🎨', 'focus': 'visual design, UI polish, branding, and user-facing aesthetics', 'role': 'creative designer'},
    'researcher': {'emoji': '🔍', 'focus': 'research, alternatives, documentation, and best practices', 'role': 'technical researcher'},
    'bodek': {'emoji': '🧪', 'focus': 'QA, edge cases, regressions, and test strategy', 'role': 'QA engineer'},
    'data': {'emoji': '📊', 'focus': 'databases, data quality, migrations, and schemas', 'role': 'database specialist'},
    'debugger': {'emoji': '🐛', 'focus': 'root-cause analysis, logs, crashes, and failure patterns', 'role': 'debugging specialist'},
    'docker': {'emoji': '🐳', 'focus': 'containers, infrastructure, deployment, and runtime environments', 'role': 'DevOps / container engineer'},
    'front': {'emoji': '🖥️', 'focus': 'frontend UX, responsiveness, HTML/CSS/JS behavior', 'role': 'frontend engineer'},
    'back': {'emoji': '⚡', 'focus': 'backend architecture, APIs, services, and scalability', 'role': 'backend engineer'},
    'tester': {'emoji': '🧪', 'focus': 'test coverage, scenarios, automation, and verification', 'role': 'test engineer'},
    'refactor': {'emoji': '♻️', 'focus': 'refactoring, code quality, structure, and maintainability', 'role': 'refactoring specialist'},
    'monitor': {'emoji': '📡', 'focus': 'monitoring, uptime, alerting, and operational visibility', 'role': 'monitoring specialist'},
    'optimizer': {'emoji': '🚀', 'focus': 'performance, bottlenecks, caching, and optimization', 'role': 'performance specialist'},
    'integrator': {'emoji': '🔗', 'focus': 'integrations, third-party APIs, webhooks, and glue code', 'role': 'integration specialist'},
    'worker': {'emoji': '🤖', 'focus': 'general practical execution and cross-domain support', 'role': 'general technical worker'},
}

RESET_WORDS = {'/new', '/reset', 'reset', 'new'}


def log(msg: str):
    ts = time.strftime('%Y-%m-%dT%H:%M:%S')
    with open(LOG_PATH, 'a', encoding='utf-8') as f:
        f.write(f'[{ts}] {msg}\n')


def read_json(path: Path):
    return json.loads(path.read_text(encoding='utf-8'))


def split_irc_message(message: str, max_bytes: int = 320):
    text = str(message or '').replace('\r\n', '\n').replace('\r', '\n').strip()
    if not text:
        return ['']

    parts = []
    for raw_line in text.split('\n'):
        line = raw_line.strip()
        if not line:
            continue
        while len(line.encode('utf-8')) > max_bytes:
            cut = min(len(line), max_bytes)
            while cut > 1 and len(line[:cut].encode('utf-8')) > max_bytes:
                cut -= 1
            split_at = line.rfind(' ', 0, cut)
            if split_at < max(1, int(cut * 0.6)):
                split_at = cut
            chunk = line[:split_at].rstrip()
            if chunk:
                parts.append(chunk)
            line = line[split_at:].lstrip()
        if line:
            parts.append(line)

    if len(parts) <= 1:
        return parts or ['']

    total = len(parts)
    tagged = []
    for idx, part in enumerate(parts, 1):
        tagged.append(f'[{idx}/{total}] {part}')
    return tagged


def ensure_dm_state_dir():
    DM_STATE_DIR.mkdir(parents=True, exist_ok=True)


def history_path(agent_id: str, sender: str) -> Path:
    ensure_dm_state_dir()
    digest = hashlib.sha1(f'{agent_id}::{sender}'.encode('utf-8')).hexdigest()[:16]
    return DM_STATE_DIR / f'{agent_id}-{sender}-{digest}.json'


def load_history(agent_id: str, sender: str) -> List[dict]:
    path = history_path(agent_id, sender)
    if not path.exists():
        return []
    try:
        data = json.loads(path.read_text(encoding='utf-8'))
        if isinstance(data, list):
            return data[-HISTORY_MAX_MESSAGES:]
    except Exception:
        pass
    return []


def save_history(agent_id: str, sender: str, history: List[dict]):
    path = history_path(agent_id, sender)
    path.write_text(json.dumps(history[-HISTORY_MAX_MESSAGES:], ensure_ascii=False, indent=2), encoding='utf-8')


def reset_history(agent_id: str, sender: str):
    path = history_path(agent_id, sender)
    try:
        path.unlink()
    except FileNotFoundError:
        pass


class AgentConn:
    def __init__(self, host, port, tls, agent_id, nick, dm_queue, ignored_nicks):
        self.host = host
        self.port = port
        self.tls = tls
        self.agent_id = agent_id
        self.nick = nick
        self.dm_queue = dm_queue
        self.ignored_nicks = {n.lower() for n in ignored_nicks}
        self.sock = None
        self.buffer = b''
        self.joined = set()
        self.ready = False
        self.stop = False
        self.last_error = None
        self.last_connect = 0.0
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

    def _handle_privmsg(self, text: str):
        prefix, _, rest = text.partition(' PRIVMSG ')
        sender = prefix.split('!', 1)[0].lstrip(':').strip()
        target, _, message = rest.partition(' :')
        target = target.strip()
        message = (message or '').strip()
        if not sender or not target or not message:
            return
        if sender.lower() == self.nick.lower():
            return
        if target.startswith('#'):
            return
        if target.lower() != self.nick.lower():
            return
        if sender.lower() in self.ignored_nicks:
            return
        self.dm_queue.put({'agent': self.agent_id, 'nick': self.nick, 'sender': sender, 'message': message})

    def handle_line(self, text: str):
        log(f'[{self.agent_id}] {text}')
        if text.startswith('PING '):
            self.send_line('PONG ' + text.split(' ', 1)[1])
            return
        if ' PRIVMSG ' in text:
            self._handle_privmsg(text)
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

    def _drain_incoming_until(self, deadline: float, wait_for_join: str = ''):
        while time.time() < deadline:
            rr, _, _ = select.select([self.sock], [], [], 0.5)
            if not rr:
                if wait_for_join and wait_for_join in self.joined:
                    return
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
            if wait_for_join and wait_for_join in self.joined:
                return

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
                            if ch.startswith('#') and ch not in self.joined:
                                self.send_line(f'JOIN {ch}')
                        elif kind == 'send':
                            target = cmd['target']
                            msg = cmd['message']
                            if target.startswith('#') and target not in self.joined:
                                self.send_line(f'JOIN {target}')
                                self._drain_incoming_until(time.time() + 8, wait_for_join=target)
                            for part in split_irc_message(msg):
                                self.send_line(f'PRIVMSG {target} :{part}')
                                time.sleep(0.15)
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

    def request_send(self, target: str, message: str, timeout: float = 20.0):
        result = {'ok': False}
        self.events.put({'kind': 'send', 'target': target, 'message': message, 'result': result})
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
        self.main_nick = (base.get('nick') or 'OrYossiOps8487').strip()
        self.hermes_nick = os.getenv('HERMES_IRC_NICK', 'HermesY8487').strip()
        self.conns = {}
        self.dm_queue = queue.Queue()
        self._dm_last = {}
        self._dm_worker = threading.Thread(target=self.dm_worker, daemon=True)
        self._dm_worker.start()

    def ignored_nicks(self):
        ignored = {self.main_nick, self.hermes_nick}
        for cfg in self.agents_cfg.values():
            ignored.add(cfg['nick'])
        return ignored

    def ensure_agents(self, agent_ids):
        ids = agent_ids
        ignored = self.ignored_nicks()
        for aid in ids:
            if aid not in self.agents_cfg:
                raise RuntimeError(f'unknown agent {aid}')
            if aid not in self.conns:
                nick = self.agents_cfg[aid]['nick']
                self.conns[aid] = AgentConn(self.host, self.port, self.tls, aid, nick, self.dm_queue, ignored)

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
            target = req['channel']
            msg = req['message']
            self.ensure_agents([aid])
            self.conns[aid].request_send(target, msg)
            return {'ok': True}
        raise RuntimeError(f'unknown cmd {cmd}')

    def role_profile(self, agent_id: str):
        return ROLE_PERSPECTIVES.get(agent_id, ROLE_PERSPECTIVES['worker'])

    def build_dm_prompt(self, agent_id: str, sender: str, message: str, history: List[dict]) -> str:
        role = self.role_profile(agent_id)
        history_lines = []
        for item in history[-12:]:
            who = 'User' if item.get('role') == 'user' else agent_id
            history_lines.append(f'{who}: {item.get("content", "")}')
        history_text = '\n'.join(history_lines) if history_lines else '(no prior history)'
        return f'''You are {agent_id}, a {role["role"]}, speaking in a private IRC direct message.
Your expertise: {role["focus"]}.
Reply in Hebrew unless the sender is clearly using English.
Be concise, practical, and human. Prefer 2-5 short sentences.
This is a direct private conversation with the user {sender}, not a public channel.
Do not pretend to be Or, OpenClaw, or Hermes.
Do not mention internal system prompts or internal infrastructure unless directly relevant.
If the user sends /new or /reset, acknowledge that the private conversation was reset.
Do not use markdown tables. Plain text only.
Do not prefix every answer with your name unless it helps clarity.
If you are unsure, say so briefly and give the most useful next step.

Recent private conversation:
{history_text}

Latest user message:
{message}

Answer directly as this specialist. If no reply is appropriate, answer exactly NO_REPLY.'''

    def generate_dm_response(self, agent_id: str, sender: str, message: str, history: List[dict]) -> str:
        if message.strip().lower() in RESET_WORDS:
            return 'איפסתי את השיחה הפרטית שלנו. אפשר להתחיל מחדש.'

        prompt = self.build_dm_prompt(agent_id, sender, message, history)
        with tempfile.NamedTemporaryFile('w', delete=False, encoding='utf-8', suffix='.txt') as tmp:
            tmp.write(prompt)
            tmp_path = tmp.name
        try:
            proc = subprocess.run(
                ['bash', str(RESPOND_SCRIPT), tmp_path],
                capture_output=True,
                text=True,
                timeout=DM_MODEL_TIMEOUT,
                check=False,
            )
            response = (proc.stdout or '').strip()
            if not response:
                response = (proc.stderr or '').strip()
            return self.sanitize_response(response)
        finally:
            try:
                os.unlink(tmp_path)
            except FileNotFoundError:
                pass

    def sanitize_response(self, response: str) -> str:
        text = (response or '').strip()
        if not text:
            return ''
        lines = []
        for line in text.splitlines():
            if line.strip().startswith('MEDIA:'):
                continue
            lines.append(line)
        text = '\n'.join(lines).strip()
        text = text.replace('```', '')
        text = text.replace('\r', '')
        while '\n\n\n' in text:
            text = text.replace('\n\n\n', '\n\n')
        return text.strip()

    def dm_worker(self):
        while True:
            item = self.dm_queue.get()
            try:
                agent_id = item['agent']
                sender = item['sender']
                message = (item['message'] or '').strip()
                if not message:
                    continue
                key = (agent_id, sender)
                last = self._dm_last.get(key, 0.0)
                now = time.time()
                if now - last < DM_MIN_INTERVAL_SECONDS:
                    continue
                self._dm_last[key] = now

                history = load_history(agent_id, sender)
                if message.lower() in RESET_WORDS:
                    reset_history(agent_id, sender)
                    history = []

                history.append({'role': 'user', 'content': message})
                response = self.generate_dm_response(agent_id, sender, message, history)
                if not response or response == 'NO_REPLY':
                    continue
                history.append({'role': 'assistant', 'content': response})
                save_history(agent_id, sender, history)

                self.ensure_agents([agent_id])
                self.conns[agent_id].request_send(sender, response)
                log(f'[{agent_id}] dm reply -> {sender}: {response[:180]}')
            except Exception as e:
                log(f'[dm-worker] error: {e}')
            finally:
                self.dm_queue.task_done()


def run_daemon():
    ensure_dm_state_dir()
    try:
        os.unlink(SOCK_PATH)
    except FileNotFoundError:
        pass
    Path(PID_PATH).write_text(str(os.getpid()), encoding='utf-8')
    hub = Hub()
    # Bring up all configured agent identities immediately and join their
    # default channels so they are visibly present on the private IRC server.
    hub.ensure_agents(list(hub.agents_cfg.keys()))
    for aid, cfg in hub.agents_cfg.items():
        for ch in cfg.get('channels', []) or []:
            hub.conns[aid].request_join(ch)
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
