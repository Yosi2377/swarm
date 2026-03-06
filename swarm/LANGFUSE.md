# Langfuse — LLM Observability

## Access
- **Local**: http://localhost:3100
- **Domain** (pending DNS): https://langfuse.botverse.dev

## First Login
Go to http://localhost:3100 and create an account.
Then create a project and get API keys.

## Architecture
- Langfuse Web: port 3100 (mapped from 3000)
- Langfuse Worker: port 3030
- Postgres: port 5432 (internal)
- ClickHouse: port 8123 (internal)
- Redis: port 6389 (mapped from 6379, host Redis on 6379)
- MinIO: port 9090 (S3-compatible storage)

## Docker
```bash
cd /root/langfuse-selfhost
docker compose up -d     # start
docker compose down       # stop
docker compose logs -f    # logs
```

## Memory Usage
~1.3GB total (Postgres 64MB, ClickHouse 244MB, Web 480MB, Worker 444MB, Redis 5MB, MinIO 74MB)

## Integration with Swarm
TODO: Add Langfuse Python SDK to track agent token usage
```python
from langfuse import Langfuse
langfuse = Langfuse(
    public_key="pk-...",
    secret_key="sk-...",
    host="http://localhost:3100"
)
```
