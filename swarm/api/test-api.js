const http = require('http');

const BASE = 'http://localhost:9200';
let pass = 0, fail = 0;

function test(name, opts, check) {
  return new Promise(resolve => {
    const url = new URL(opts.path, BASE);
    const req = http.request(url, { method: opts.method || 'GET', headers: opts.headers || {} }, res => {
      let body = '';
      res.on('data', d => body += d);
      res.on('end', () => {
        try {
          const ok = check(res, body);
          if (ok) { pass++; console.log(`✅ ${name}`); }
          else { fail++; console.log(`❌ ${name}`); }
        } catch(e) { fail++; console.log(`❌ ${name}: ${e.message}`); }
        resolve();
      });
    });
    req.on('error', e => { fail++; console.log(`❌ ${name}: ${e.message}`); resolve(); });
    if (opts.body) { req.setHeader('Content-Type','application/json'); req.write(JSON.stringify(opts.body)); }
    req.end();
  });
}

async function run() {
  await test('GET /api/health returns 200', { path: '/api/health' }, (res) => res.statusCode === 200);

  await test('GET /api/tasks returns array', { path: '/api/tasks' }, (res, body) => {
    return res.statusCode === 200 && Array.isArray(JSON.parse(body));
  });

  await test('GET /api/stats returns passRate and totalTasks', { path: '/api/stats' }, (res, body) => {
    const d = JSON.parse(body);
    return 'passRate' in d && 'totalTasks' in d;
  });

  await test('GET / returns HTML with Swarm Agent Dashboard', { path: '/' }, (res, body) => {
    return res.statusCode === 200 && body.includes('Swarm Agent Dashboard');
  });

  await test('POST /api/tasks creates task', {
    path: '/api/tasks', method: 'POST',
    body: { description: 'Test task', agentId: 'koder' }
  }, (res, body) => {
    const d = JSON.parse(body);
    return res.statusCode === 201 && d.id && d.contract;
  });

  console.log(`\n${pass}/${pass+fail} tests passed`);
  process.exit(fail > 0 ? 1 : 0);
}

run();
