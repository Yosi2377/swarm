# Ergo External Direct Access — 2026-04-05

## Change
Opened a direct external TLS listener for the new Ergo IRC server.

## Listener
- Internal plain listener remains: `127.0.0.1:16669`
- New external TLS listener: `0.0.0.0:6697`

## TLS
- Self-signed certificate generated under `/root/.ergo-teamwork/tls/`
- SANs include:
  - IP `95.111.247.22`
  - DNS `irc.teamwork.local`

## Verification
- Ergo active with listener on `*:6697`
- TLS handshake works
- Authenticated login as `Yossi` over TLS works
- OpenClaw / agent hub / Hermes remain on internal listener `127.0.0.1:16669`

## User connection info
- Host: `95.111.247.22`
- Port: `6697`
- TLS: on
- SASL: PLAIN
- Account: `Yossi`
- Password sent privately via Telegram DM

## Notes
- The Lounge remains on `http://95.111.247.22:9001/`
- Self-signed certificate means external IRC clients may prompt to trust the cert on first connect.
