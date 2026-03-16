# Template: API Endpoint

## Steps

### STEP 1: Define the API contract
- Method: GET/POST/PUT/DELETE
- Path: /api/RESOURCE
- Request body (if POST/PUT): list all fields with types
- Response: expected JSON structure
- CHECK: You can write a curl command that would call this endpoint.

### STEP 2: Find existing API patterns
```bash
grep -rn "router\.\|app\.\(get\|post\|put\|delete\)" PROJECT_DIR/server.js PROJECT_DIR/routes/
```
- Note the pattern: how routes are defined, middleware used, response format
- CHECK: You know the exact file and style to follow.

### STEP 3: Query past lessons
```bash
swarm/learn.sh query "API endpoint KEYWORD"
```

### STEP 4: Create/modify the route
- Follow existing patterns EXACTLY (same middleware, same response format)
- Add input validation (check required fields exist)
- Add try/catch error handling
- CHECK: `node -c FILE` passes with no errors

### STEP 5: Add database interaction (if needed)
- Use existing model/collection patterns
- CHECK: Query is correct (test with `mongosh` if unsure)

### STEP 6: Restart and test
```bash
systemctl restart SERVICE && sleep 2
# GET endpoint:
curl -s http://localhost:PORT/api/ENDPOINT | python3 -m json.tool | head -20
# POST endpoint:
curl -s -X POST http://localhost:PORT/api/ENDPOINT \
  -H "Content-Type: application/json" \
  -d '{"field":"value"}' | python3 -m json.tool
```
- CHECK: Response matches expected format. Status code is correct (200/201/404/etc).

### STEP 7: Test error cases
```bash
# Missing required field:
curl -s -X POST http://localhost:PORT/api/ENDPOINT -H "Content-Type: application/json" -d '{}'
# Invalid ID:
curl -s http://localhost:PORT/api/ENDPOINT/invalid-id
```
- CHECK: Returns proper error messages, not crashes or 500s.

### STEP 8: Check logs
```bash
journalctl -u SERVICE --no-pager -n 20
```
- CHECK: No unhandled promise rejections or warnings.

### STEP 9: Report
```bash
swarm/send.sh AGENT_ID THREAD_ID "✅ API endpoint: METHOD /api/ENDPOINT — tested with curl, all cases pass"
```

## Common Failures
- **Route not registered** → Make sure `app.use` or `router.use` includes your new route file
- **Wrong HTTP method** → GET for reading, POST for creating. Don't mix them up
- **No error handling** → Always wrap in try/catch. Return 500 with error message, not crash
- **Missing Content-Type** → POST/PUT routes need `express.json()` middleware
- **Wrong MongoDB query** → Test query in `mongosh` first before putting in code
