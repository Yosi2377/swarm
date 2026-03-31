#!/usr/bin/env python3
import argparse
import json
import select
import socket
import ssl
import sys
import time
from pathlib import Path

OPENCLAW_CFG = Path('/root/.openclaw/openclaw.json')
AGENT_CFG = Path('/root/.openclaw/workspace/swarm/irc-agent-accounts.json')


def load_configs(agent_id: str):
    base = json.loads(OPENCLAW_CFG.read_text(encoding='utf-8'))['channels']['irc']
    agents = json.loads(AGENT_CFG.read_text(encoding='utf-8'))
    if agent_id not in agents:
        raise SystemExit(f'Unknown IRC agent account: {agent_id}')
    return base, agents[agent_id]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--agent', required=True)
    ap.add_argument('--target', required=True)
    ap.add_argument('--message', required=True)
    args = ap.parse_args()

    base, account = load_configs(args.agent)
    host = base['host']
    port = int(base.get('port', 6697))
    use_tls = bool(base.get('tls', True))
    nick = account['nick']

    raw = socket.create_connection((host, port), timeout=20)
    sock = ssl.create_default_context().wrap_socket(raw, server_hostname=host) if use_tls else raw
    sock.setblocking(False)

    def send(line: str):
        sock.sendall((line + '\r\n').encode())

    send(f'NICK {nick}')
    send(f'USER {nick} 0 * :{args.agent}')

    buf = b''
    joined = False
    sent = False
    start = time.time()
    while time.time() - start < 45:
        r, _, _ = select.select([sock], [], [], 1)
        if not r:
            continue
        try:
            chunk = sock.recv(4096)
        except ssl.SSLWantReadError:
            continue
        if not chunk:
            break
        buf += chunk
        while b'\r\n' in buf:
            line, buf = buf.split(b'\r\n', 1)
            text = line.decode(errors='ignore')
            if text.startswith('PING '):
                send('PONG ' + text.split(' ', 1)[1])
                continue
            if (' 001 ' in text or ' 376 ' in text or ' 422 ' in text) and not joined:
                send(f'JOIN {args.target}')
                continue
            if ((f' JOIN {args.target}' in text and text.startswith(f':{nick}!')) or (f' 366 {nick} {args.target} ' in text)) and not sent:
                joined = True
                send(f'PRIVMSG {args.target} :{args.message}')
                sent = True
                time.sleep(1)
                send('QUIT :done')
                return 0
            if ' 433 ' in text:
                raise SystemExit(f'Nickname is already in use: {nick}')
            if any(code in text for code in [' 471 ', ' 473 ', ' 474 ', ' 475 ', ' 403 ', ' 404 ', ' 405 '] ):
                raise SystemExit(f'IRC channel error: {text}')

    raise SystemExit('IRC agent send timed out')


if __name__ == '__main__':
    sys.exit(main())
