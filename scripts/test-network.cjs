// Run the actual ArkTS business sources with the installed SDK transpiler and decorators.
// Only the platform HTTP transport / Preferences / Form host are replaced in Node.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const { test } = require('node:test');
const ts = require(process.env.TODO_TYPESCRIPT || 'D:/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript/lib/typescript.js');
const sourceRoot = path.resolve(__dirname, '../entry/src/main/ets');
const binary = fs.readFileSync(process.env.TODO_RUNTIME_DLL || 'D:/DevEco Studio/sdk/default/openharmony/previewer/common/bin/libace_compatible.dll').toString('utf8');
function extract(startMarker, endMarker) {
  const start = binary.indexOf(startMarker); const end = binary.indexOf(endMarker, start);
  assert.ok(start >= 0 && end >= start, `SDK runtime function missing: ${startMarker}`);
  return binary.slice(start, end + endMarker.length);
}
const runtime = [
  extract('const trackInternal = (target, propertyKey) => {', '}; // trackInternal'),
  extract('function observedV2Internal(BaseClass) {', 'return observedClass;') + '\n}',
  extract('function ObservedV2(BaseClass) {', 'return observedV2Internal(BaseClass);') + '\n}',
  extract('const Trace = (target, propertyKey) => {', 'return trackInternal(target, propertyKey);') + '\n};'
].join('\n');
const files = ['model/Todo.ets', 'common/ApiService.ets', 'viewmodel/TodoStore.ets', 'viewmodel/NetworkStore.ets'];
const source = files.filter(file => fs.existsSync(path.join(sourceRoot, file)))
  .map(file => fs.readFileSync(path.join(sourceRoot, file), 'utf8')).join('\n').replace(/^import .*$/gm, '');
const compiled = ts.transpileModule(source, { compilerOptions: {
  target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS, experimentalDecorators: true, useDefineForClassFields: false
} }).outputText;
function harness() {
  const state = { requests: [], destroys: 0, writes: 0, formPushes: 0, events: [], respond: async () => ({ responseCode: 200, result: JSON.stringify([
    { id: 1, title: ' remote task ', completed: true }, { id: 2, title: 'other task', completed: false }
  ]) }) };
  const ObserveV2 = {
    OB_PREFIX: '__network_test_', V2_DECO_META: Symbol('metadata'), ID_REFS: Symbol('references'),
    getObserve: () => ({ addRef: (target, key) => state.events.push({ kind: 'read', target, key }), fireChange: (target, key) => state.events.push({ kind: 'write', target, key }) }),
    autoProxyObject: (target, key) => target[key],
    addVariableDecoMeta: (target, key, deco) => { target[ObserveV2.V2_DECO_META] ||= {}; target[ObserveV2.V2_DECO_META][key] = { deco }; }
  };
  const sandbox = {
    exports: {}, ObserveV2,
    ConfigureStateMgmt: { instance: { usingV2ObservedTrack: () => {} } }, TrackedObject: { ___IS_TRACKED_OPTIMISED: Symbol('v1') },
    stateMgmtConsole: { applicationError: message => { throw new Error(message); } },
    AsyncAddComputedV2: { addComputed: () => {} }, AsyncAddMonitorV2: { addMonitor: () => {} }, WeakRefPool: { asyncRegisterToFinalizationRegistry: () => {} },
    http: { RequestMethod: { GET: 'GET' }, createHttp: () => ({
      request: (url, options) => { state.requests.push({ url, options }); return state.respond(url, options); }, destroy: () => { state.destroys++; }
    }) },
    preferences: { getPreferencesSync: () => { throw new Error('Network must not access Preferences'); } },
    FormService: { push: () => { state.formPushes++; } }, Date, JSON, Number, Error, Set, Map
  };
  vm.runInNewContext(runtime + '\n' + compiled, sandbox);
  Object.assign(state, sandbox.exports);
  state.store = () => { assert.equal(typeof state.NetworkStore, 'function', 'Independent NetworkStore must be implemented'); return state.NetworkStore.instance; };
  state.fetch = (mode, proxy) => { assert.equal(typeof state.ApiService.fetchRemoteTodos, 'function', 'API must expose remote scenario requests'); return state.ApiService.fetchRemoteTodos(mode, proxy); };
  return state;
}
const plain = value => JSON.parse(JSON.stringify(value));
const settleResponse = list => ({ responseCode: 200, result: JSON.stringify(list) });

test('remote API whitelists real normal / empty / error paths, keeps legacy default API', async () => {
  const h = harness();
  await h.fetch('normal'); h.respond = async () => settleResponse([]); await h.fetch('empty');
  h.respond = async () => ({ responseCode: 404, result: '{}' }); await assert.rejects(h.fetch('error'), /404/);
  const before = h.requests.length; await assert.rejects(h.fetch('https://untrusted.invalid'), /场景/); assert.equal(h.requests.length, before);
  h.respond = async () => settleResponse([]); await h.ApiService.fetchDefaultTodos();
  assert.deepEqual(h.requests.map(r => r.url), [
    'https://jsonplaceholder.typicode.com/todos', 'https://jsonplaceholder.typicode.com/todos?userId=0',
    'https://jsonplaceholder.typicode.com/this-route-does-not-exist', 'https://jsonplaceholder.typicode.com/todos'
  ]);
  assert.ok(h.requests.every(r => r.options.method === 'GET' && r.options.connectTimeout > 0 && r.options.readTimeout > 0));
  assert.ok(h.requests.every(r => r.options.usingProxy === true), 'Requests should follow the system network proxy');
  assert.ok(h.requests.every(r => r.options.usingCache === false), 'Refreshing examples should request the remote service again');
  assert.equal(h.destroys, h.requests.length);
});
test('normal remote request validates and maps only first five todos', async () => {
  const h = harness(); h.respond = async () => settleResponse(Array.from({ length: 6 }, (_, i) => ({ id: i + 1, title: ` item ${i} `, completed: i % 2 === 0 })));
  const items = await h.fetch('normal'); assert.equal(items.length, 5); assert.equal(items[0].title, 'item 0'); assert.equal(items[0].done, true); assert.equal(items[1].done, false);
});
test('HTTP failure, transport rejection, invalid JSON and malformed payload all destroy the request', async () => {
  const h = harness();
  for (const response of [{ responseCode: 503, result: '[]' }, { responseCode: 200, result: {} }, { responseCode: 200, result: '{' }, settleResponse({}), settleResponse([{ id: 1, title: '', completed: false }]), settleResponse([{ id: 1, title: 'valid', completed: 'false' }])]) {
    h.respond = async () => response; await assert.rejects(h.fetch('normal'));
  }
  h.respond = async () => { throw new Error('offline'); }; await assert.rejects(h.fetch('normal'), /offline/);
  assert.equal(h.destroys, 7);
});
test('network singleton is lazy and its Trace fields keep real SDK accessors', () => {
  const h = harness(); const store = h.store(); assert.equal(store, h.NetworkStore.instance);
  for (const field of ['items', 'loading', 'error', 'loaded', 'lastUpdatedAt']) {
    assert.equal(Object.hasOwn(store, field), false, `${field} must not shadow Trace accessor`);
  }
  assert.equal(store.loading, false); assert.equal(store.loaded, false); assert.equal(store.lastUpdatedAt, 0);
});
test('first load exposes loading before completion and success updates list and chart counts reactively', async () => {
  const h = harness(); const store = h.store(); let finish;
  h.respond = () => new Promise(resolve => { finish = resolve; });
  const task = store.load(); assert.equal(store.loading, true); assert.equal(store.loaded, false); assert.equal(store.items.length, 0);
  finish(settleResponse([{ id: 1, title: 'done', completed: true }, { id: 2, title: 'pending', completed: false }])); await task;
  assert.equal(store.loading, false); assert.equal(store.loaded, true); assert.equal(store.error, ''); assert.ok(store.lastUpdatedAt > 0);
  assert.equal(store.doneCount, 1); assert.equal(store.pendingCount, 1); assert.deepEqual(plain(store.chartValues), [1, 1]);
  assert.ok(h.events.some(e => e.kind === 'write' && e.target === store && e.key === 'items'));
});
test('every settled refresh performs a new request rather than stopping after first success', async () => {
  const h = harness(); const store = h.store(); await store.load();
  h.respond = async () => settleResponse([{ id: 3, title: 'new', completed: false }]); await store.load();
  assert.equal(h.requests.length, 2); assert.equal(store.items[0].id, 3); assert.deepEqual(plain(store.chartValues), [0, 1]);
});
test('concurrent loads merge into the same request and cannot change its active mode', async () => {
  const h = harness(); const store = h.store(); let finish; h.respond = () => new Promise(resolve => { finish = resolve; });
  const first = store.load('normal'); const second = store.load('empty'); const third = store.load('error');
  assert.equal(first, second); assert.equal(first, third); assert.equal(h.requests.length, 1); assert.equal(store.mode, 'normal');
  finish(settleResponse([])); await Promise.all([first, second, third]); assert.equal(store.loading, false);
  h.respond = async () => settleResponse([]); await store.load('empty'); assert.equal(h.requests.length, 2); assert.equal(store.mode, 'empty');
});
test('refresh failure preserves successful items, chart and update time then retry recovers', async () => {
  const h = harness(); const store = h.store(); await store.load(); const items = store.items; const updated = store.lastUpdatedAt;
  h.respond = async () => ({ responseCode: 404, result: '{}' }); await store.load('error');
  assert.equal(store.items, items); assert.equal(store.lastUpdatedAt, updated); assert.equal(store.loaded, true); assert.equal(store.loading, false); assert.match(store.error, /404/);
  assert.deepEqual(plain(store.chartValues), [1, 1]); assert.equal(store.lastSuccessfulMode, 'normal');
  h.respond = async () => settleResponse([]); await store.load('normal'); assert.equal(store.error, ''); assert.equal(store.items.length, 0);
});
test('initial failure is retryable and successful remote empty response is a loaded zero state', async () => {
  const h = harness(); const store = h.store(); h.respond = async () => { throw new Error('offline'); }; await store.load();
  assert.equal(store.loaded, false); assert.equal(store.loading, false); assert.match(store.error, /offline/); assert.equal(store.lastUpdatedAt, 0);
  h.respond = async () => settleResponse([]); await store.load('empty');
  assert.equal(store.loaded, true); assert.equal(store.error, ''); assert.equal(store.items.length, 0); assert.deepEqual(plain(store.chartValues), [0, 0]); assert.equal(store.lastSuccessfulMode, 'empty');
});
test('loading network examples never reads or replaces personal TodoStore data', async () => {
  const h = harness(); const personal = h.TodoStore.instance; personal.todos = [new h.Todo(99, 'my own task', '', false, 0)]; const items = personal.todos;
  await h.store().load(); assert.equal(personal.todos, items); assert.equal(personal.todos[0].title, 'my own task'); assert.equal(h.formPushes, 0);
});
test('API passes an optional typed HTTP proxy and defaults back to system proxy', async () => {
  const h = harness(); const proxy = { host: 'proxy.example.com', port: 8080, exclusionList: [] };
  await h.fetch('normal', proxy); assert.deepEqual(plain(h.requests[0].options.usingProxy), proxy);
  await h.fetch('normal'); assert.equal(h.requests[1].options.usingProxy, true);
});
test('applying session proxy validates, refreshes current scenario and never persists personal data', async () => {
  const h = harness(); const store = h.store(); assert.equal(typeof store.applyProxy, 'function', 'Session proxy configuration must be implemented');
  await store.load('empty'); const personal = h.TodoStore.instance; const todos = personal.todos;
  assert.equal(await store.applyProxy('proxy.example.com', '8080'), true);
  assert.equal(store.proxyHost, 'proxy.example.com'); assert.equal(store.proxyPort, 8080); assert.equal(store.proxyError, '');
  assert.equal(h.requests.length, 2); assert.equal(h.requests[1].url, 'https://jsonplaceholder.typicode.com/todos?userId=0');
  assert.deepEqual(plain(h.requests[1].options.usingProxy), { host: 'proxy.example.com', port: 8080, exclusionList: [] });
  assert.equal(personal.todos, todos); assert.equal(h.formPushes, 0);
});
test('proxy rejects incomplete host/port, protocols, paths, newlines and invalid port syntax without requests', async () => {
  const h = harness(); const store = h.store(); assert.equal(typeof store.applyProxy, 'function', 'Session proxy configuration must be implemented');
  for (const [host, port] of [['proxy.example.com', ''], ['', '8080'], ['proxy.example.com', '0'], ['proxy.example.com', '65536'], ['proxy.example.com', '-1'], ['proxy.example.com', '8.5'], ['proxy.example.com', '1e3'], ['proxy.example.com', '80x'], ['http://proxy.example.com', '80'], ['proxy.example.com/path', '80'], ['proxy.example.com\n', '80'], ['\r\n', ''], ['proxy\\evil', '80'], ['user@proxy.example.com', '80']]) {
    assert.equal(await store.applyProxy(host, port), false, `Must reject ${JSON.stringify([host, port])}`);
    assert.ok(store.proxyError); assert.equal(store.proxyHost, ''); assert.equal(store.proxyPort, 0); assert.equal(h.requests.length, 0);
  }
});
test('proxy boundary ports are accepted and empty fields explicitly restore system mode', async () => {
  const h = harness(); const store = h.store(); assert.equal(typeof store.applyProxy, 'function', 'Session proxy configuration must be implemented');
  assert.equal(await store.applyProxy('proxy.example.com', '1'), true); assert.equal(store.proxyPort, 1);
  assert.equal(await store.applyProxy('proxy.example.com', '65535'), true); assert.equal(store.proxyPort, 65535);
  assert.equal(await store.applyProxy('', ''), true); assert.equal(store.proxyHost, ''); assert.equal(store.proxyPort, 0); assert.equal(store.proxyError, '');
  assert.equal(h.requests.at(-1).options.usingProxy, true);
});
test('loading rejects proxy changes while preserving the active request configuration', async () => {
  const h = harness(); const store = h.store(); assert.equal(typeof store.applyProxy, 'function', 'Session proxy configuration must be implemented');
  await store.applyProxy('proxy.example.com', '8080'); let finish; h.respond = () => new Promise(resolve => { finish = resolve; });
  const pending = store.load(); assert.equal(store.loading, true);
  assert.equal(await store.applyProxy('another.example.com', '9000'), false); assert.equal(await store.applyProxy('', ''), false);
  assert.equal(store.proxyHost, 'proxy.example.com'); assert.equal(store.proxyPort, 8080); assert.match(store.proxyError, /请求中/); assert.equal(h.requests.length, 2);
  assert.deepEqual(plain(h.requests[1].options.usingProxy), { host: 'proxy.example.com', port: 8080, exclusionList: [] });
  finish(settleResponse([])); await pending;
});
test('proxy settings are foldable session UI and short pages align at the top', () => {
  const page = fs.readFileSync(path.join(sourceRoot, 'pages/NetworkPage.ets'), 'utf8');
  assert.match(page, /预览网络设置/); assert.match(page, /当前预览会话/); assert.match(page, /不写入文件/); assert.match(page, /\.align\(Alignment\.Top\)/);
  for (const id of ['network-proxy-toggle', 'network-proxy-host', 'network-proxy-port', 'network-proxy-apply', 'network-proxy-system']) assert.ok(page.includes(`.id('${id}')`), `Missing test id ${id}`);
  assert.doesNotMatch(page, /127\.0\.0\.1|10090/);
  for (const id of ['network-normal', 'network-empty', 'network-error']) {
    const start = page.indexOf(`.id('${id}')`); const block = page.slice(start, page.indexOf('.onClick', start));
    assert.match(block, /\.height\(36\)/); assert.match(block, /\.padding\(\{ left: 8, right: 8 \}\)/);
  }
});
test('NetworkPage starts its own load, Home opens the registered route and chart is native', () => {
  const file = path.join(sourceRoot, 'pages/NetworkPage.ets'); assert.ok(fs.existsSync(file), 'NetworkPage must exist');
  const page = fs.readFileSync(file, 'utf8'); const home = fs.readFileSync(path.join(sourceRoot, 'pages/HomePage.ets'), 'utf8'); const index = fs.readFileSync(path.join(sourceRoot, 'pages/Index.ets'), 'utf8');
  const start = page.indexOf('  aboutToAppear(): void {'); const end = page.indexOf('\n  }', start); assert.ok(start >= 0 && end > start);
  const pageCode = ts.transpileModule(`class Page { ${page.slice(start, end + 4)} } exports.Page = Page;`, { compilerOptions: { module: ts.ModuleKind.CommonJS } }).outputText;
  const sandbox = { exports: {} }; vm.runInNewContext(pageCode, sandbox); const p = new sandbox.exports.Page(); let loads = 0; p.store = { load: () => { loads++; return Promise.resolve(); } }; p.aboutToAppear(); assert.equal(loads, 1);
  assert.match(home, /pushPathByName\('Network', null\)/); assert.match(home, /网络示例/); assert.match(index, /name === 'Network'/); assert.match(index, /NetworkPage\(\{/);
  assert.match(page, /NavDestination\(\)/); assert.match(page, /Refresh\(/); assert.match(page, /Scroll\(\)/); assert.match(page, /onRefreshing/);
  assert.match(page, /DataPanel\(\{[\s\S]*?values: this\.store\.chartValues[\s\S]*?type: DataPanelType\.Circle/);
  assert.match(page, /if \(this\.store\.items\.length > 0\)/); assert.match(page, /上次成功/); assert.match(page, /远端/);
  for (const id of ['network-refresh', 'network-normal', 'network-empty', 'network-error', 'network-retry', 'network-chart']) assert.ok(page.includes(`.id('${id}')`), `Missing test id ${id}`);
});
