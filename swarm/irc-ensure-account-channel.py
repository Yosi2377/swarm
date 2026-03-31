#!/usr/bin/env python3
import json
import subprocess
import sys
from pathlib import Path

CFG = Path('/root/.openclaw/openclaw.json')


def main():
    if len(sys.argv) != 3:
        print('Usage: irc-ensure-account-channel.py <account_id> <channel>', file=sys.stderr)
        return 1
    account_id, channel = sys.argv[1], sys.argv[2]
    if not channel.startswith('#'):
        print('Channel must start with #', file=sys.stderr)
        return 1
    data = json.loads(CFG.read_text(encoding='utf-8'))
    irc = data.setdefault('channels', {}).setdefault('irc', {})
    accounts = irc.setdefault('accounts', {})
    account = accounts.setdefault(account_id, {'enabled': True})
    channels = list(account.get('channels', []))
    changed = False
    if channel not in channels:
        channels.append(channel)
        account['channels'] = channels
        changed = True
    groups = irc.setdefault('groups', {})
    if channel not in groups:
        groups[channel] = {'requireMention': False, 'allowFrom': ['*']}
        changed = True
    if changed:
        CFG.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        subprocess.run('openclaw gateway restart >/tmp/openclaw-irc-account-restart.log 2>&1 || true', shell=True, check=False)
    print('changed' if changed else 'ok')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
