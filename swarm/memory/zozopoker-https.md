# ZozoPoker HTTPS Setup

## Task
Connect zozopoker.duckdns.org to poker server (port 3000) with HTTPS.

## Status: Waiting for DNS update

## Done
- Nginx reverse proxy configured: `/etc/nginx/sites-available/zozopoker`
- Proxies to localhost:3000 with WebSocket support
- Enabled and reloaded nginx

## Blocked
- DuckDNS points to 46.210.168.43, needs to be 95.111.247.22
- Need Yossi to update DuckDNS or provide token

## Next Steps
1. Update DuckDNS IP to 95.111.247.22
2. Run: `certbot --nginx -d zozopoker.duckdns.org --non-interactive --agree-tos -m EMAIL`
3. Verify HTTPS works at https://zozopoker.duckdns.org
