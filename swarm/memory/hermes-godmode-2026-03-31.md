# Hermes + Godmode integration note (2026-03-31)

## What was implemented
- Added internal Godmode-style decision module to Hermes: `/root/.hermes/hermes-agent/agent/godmode_decision.py`
- Wired `run_agent.py` to compute a per-turn adaptive profile inside Hermes
- Injected per-turn directive into the system prompt
- Applied adaptive sampling overrides to chat completions, codex responses (safe temperature only), and anthropic messages
- Added STM-style output cleanup (direct-mode + hedge reduction) before final user-facing response
- Added default config surface under `godmode` in `hermes_cli/config.py`
- Added example config section in `cli-config.yaml.example`

## Tests
- `venv/bin/python -m pytest tests/agent/test_godmode_decision.py tests/test_run_agent_godmode.py tests/test_anthropic_adapter.py -q`
- Result: 105 passed

## Notes
- This keeps Hermes as the executor/runtime. The adaptive decision behavior is now internal to Hermes, not an external wrapper.
- For portability/safety, only safe sampling knobs are sent to Codex/OpenAI-style routes by default; less-portable knobs stay limited to safer routes.
