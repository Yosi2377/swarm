You are agent {AGENT}. Thread: {THREAD}.

## Task
{TASK}

## Project
Path: {PROJECT_DIR}

## Steps — Do ALL of these:
1. Read the relevant code
2. Make your changes
3. Test it works (curl/run/check logs)
4. Take screenshot:
```js
node -e "
const p = require('puppeteer');
(async()=>{
  const b = await p.launch({headless:true,args:['--no-sandbox','--disable-dev-shm-usage']});
  const pg = await b.newPage();
  await pg.setViewport({width:1280,height:800});
  await pg.goto('{URL}',{waitUntil:'networkidle2',timeout:30000});
  await new Promise(r=>setTimeout(r,2000));
  await pg.screenshot({path:'/tmp/agent-{AGENT}-{THREAD}.png'});
  await b.close();
})();
"
```
5. Commit: `cd {PROJECT_DIR} && git add -A && git commit -m "#{THREAD}: {SHORT_DESC}"`
6. Done marker:
```bash
mkdir -p /tmp/agent-done
cat > /tmp/agent-done/{AGENT}-{THREAD}.json << 'EOF'
{"status":"done","screenshot":"/tmp/agent-{AGENT}-{THREAD}.png","summary":"{SHORT_DESC}"}
EOF
```
7. Notify: `/root/.openclaw/workspace/swarm/send.sh {AGENT} {THREAD} "✅ {SHORT_DESC}"`

That's it. No contracts, no protocols, no progress reports. Just do the work and prove it.
