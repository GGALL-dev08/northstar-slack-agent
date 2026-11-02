#!/usr/bin/env python3
"""User-run only: read Slack tokens without echo or storing them in chat."""
import getpass, json, os
from pathlib import Path
p=Path(__file__).resolve().parent/'private'
p.mkdir(mode=0o700,exist_ok=True)
app=getpass.getpass('Paste the Slack app-level token (xapp-...), then press Enter: ').strip()
bot=getpass.getpass('Paste the Slack bot token (xoxb-...), then press Enter: ').strip()
if not app.startswith('xapp-') or not bot.startswith('xoxb-'):
 print('Token prefixes do not match; nothing was saved.')
 raise SystemExit(1)
secret=(p/'bridge-secret').read_text().strip()
fd=os.open(p/'config.json',os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
with os.fdopen(fd,'w') as f: json.dump({'app_token':app,'bot_token':bot,'bridge_secret':secret},f)
print('Credentials saved locally with owner-only permissions. You can close this terminal.')
