import assert from 'node:assert/strict';

let passed = 0;
const test = async (name, fn) => {
  await fn();
  passed += 1;
  console.log(`PASS: ${name}`);
};

const setupBrowserGlobals = ({ origin, protocol, hostname, port, fetchImpl }) => {
  globalThis.window = {
    location: { origin, protocol, hostname, port: String(port || '') },
    addEventListener: () => {},
    dispatchEvent: () => {},
  };
  globalThis.document = {
    visibilityState: 'visible',
    addEventListener: () => {},
  };
  globalThis.CustomEvent = class CustomEvent {
    constructor(type, init) {
      this.type = type;
      this.detail = init?.detail;
    }
  };
  globalThis.fetch = fetchImpl;
};

await test('Scenario 1 (LAN host with healthy local backend): chooses http://192.168.1.38:5006', async () => {
  setupBrowserGlobals({
    origin: 'http://192.168.1.38:2000',
    protocol: 'http:',
    hostname: '192.168.1.38',
    port: 2000,
    fetchImpl: async (url) => {
      if (url === 'http://192.168.1.38:5006/api/health') {
        return { ok: true, status: 200, json: async () => ({ status: 'ok', mongoConnected: true }) };
      }
      throw new Error(`Unexpected url ${url}`);
    },
  });

  const cfg = await import(`../frontend/src/lib/backendConfig.js?s1=${Date.now()}`);
  const result = await cfg.probeAndSelectBackend({ force: true });
  assert.equal(result.mode, 'local');
  assert.equal(result.baseUrl, 'http://192.168.1.38:5006');
  assert.equal(cfg.resolveApiUrl('/api/users'), 'http://192.168.1.38:5006/api/users');
  assert.equal(cfg.resolveMediaUrl('/uploads/test.png'), 'http://192.168.1.38:5006/uploads/test.png');
});

await test('Scenario 2 (Never uses localhost): connects to https://regen.krishub.in when page hostname is localhost', async () => {
  const calledUrls = [];
  setupBrowserGlobals({
    origin: 'http://localhost:2000',
    protocol: 'http:',
    hostname: 'localhost',
    port: 2000,
    fetchImpl: async (url) => {
      calledUrls.push(url);
      if (url === 'https://regen.krishub.in/api/users/me') {
        return { ok: true, status: 200, json: async () => ({ userId: 'U1' }) };
      }
      throw new Error(`Unexpected url ${url}`);
    },
  });

  const cfg = await import(`../frontend/src/lib/backendConfig.js?s2=${Date.now()}`);
  const selected = await cfg.probeAndSelectBackend({ force: true });
  assert.equal(selected.mode, 'public');
  assert.equal(selected.baseUrl, 'https://regen.krishub.in');
  assert.equal(calledUrls.some((u) => u.includes('localhost') || u.includes('127.0.0.1')), false);

  const res = await cfg.apiFetch('/api/users/me');
  assert.equal(res.status, 200);
  assert.equal(
    cfg.resolveMediaUrl('http://localhost:5006/assets/profiles/p1.png'),
    'https://regen.krishub.in/assets/profiles/p1.png',
  );
});

await test('Scenario 3 (Runtime failover): LAN drops mid-session and automatically switches to https://regen.krishub.in', async () => {
  let lanUp = true;
  setupBrowserGlobals({
    origin: 'http://192.168.1.38:2000',
    protocol: 'http:',
    hostname: '192.168.1.38',
    port: 2000,
    fetchImpl: async (url) => {
      if (url.startsWith('http://192.168.1.38:5006')) {
        if (!lanUp) throw new Error('ECONNREFUSED');
        if (url.endsWith('/api/health')) {
          return { ok: true, status: 200, json: async () => ({ status: 'ok' }) };
        }
      }
      if (url === 'https://regen.krishub.in/api/users/me') {
        return { ok: true, status: 200, json: async () => ({ userId: 'U1' }) };
      }
      throw new Error(`Refused ${url}`);
    },
  });

  const cfg = await import(`../frontend/src/lib/backendConfig.js?s3=${Date.now()}`);
  const first = await cfg.probeAndSelectBackend({ force: true });
  assert.equal(first.baseUrl, 'http://192.168.1.38:5006');

  lanUp = false;
  const res = await cfg.apiFetch('/api/users/me');
  assert.equal(res.status, 200);
  assert.equal(cfg.getActiveBackendMode(), 'public');
  assert.equal(cfg.getActiveBackendUrl(), 'https://regen.krishub.in');
});

console.log(`\nAll ${passed} frontend dual-backend checks passed!`);
