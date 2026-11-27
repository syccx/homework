// Execute the actual ArkTS service/store; replace only HarmonyOS HTTP and local storage.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const { test } = require('node:test');
const ts = require('D:/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const files = ['common/DeepSeekService.ets', 'viewmodel/DeepSeekStore.ets'];
const source = files.filter(f => fs.existsSync(path.join(root, f))).map(f => fs.readFileSync(path.join(root, f), 'utf8')).join('\n').replace(/^import .*$/gm, '');
const code = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS, experimentalDecorators: true, useDefineForClassFields: false } }).outputText;
const tasks = () => [
  { title: '明确需求与页面结构', description: '梳理新增、筛选与持久化的验收条件。', priority: 1 },
  { title: '实现核心业务功能', description: '完成页面与状态管理，并验证保存行为。', priority: 1 },
  { title: '完成测试与报告', description: '执行用例，截图记录实际结果。', priority: 0 }
];
const response = (items = tasks(), finish = 'stop') => ({ responseCode: 200, result: JSON.stringify({ choices: [{ finish_reason: finish, message: { content: JSON.stringify({ tasks: items }) } }] }) });
function harness() {
  const h = { requests: [], destroys: 0, writes: [], failSave: false, respond: async () => response() };
  const todo = { storageError: '', isStorageProtected: false, importJson: text => { if (h.failSave) throw new Error('磁盘不可写'); const items = JSON.parse(text); h.writes.push(items); return items.length; } };
  const sandbox = { exports: {}, ObservedV2: target => target, Trace: () => {},
    http: { RequestMethod: { POST: 'POST' }, createHttp: () => ({ request: (url, options) => { h.requests.push({ url, options }); return h.respond(url, options); }, destroy: () => h.destroys++ }) },
    TodoStore: { instance: todo }, Todo: class { constructor(id, title, description, done, priority, createdAt) { Object.assign(this, { id, title, description, done, priority, createdAt, dueAt: 0, deleted: false, doneAt: 0 }); } },
    Date, JSON, Number, Error, Set, Promise
  };
  vm.runInNewContext(code, sandbox); Object.assign(h, sandbox.exports); h.todo = todo;
  h.store = () => { assert.equal(typeof h.DeepSeekStore, 'function', 'DeepSeekStore must be implemented'); return h.DeepSeekStore.instance; };
  h.fetch = (key = 'sk-test-example-not-a-real-key', goal = '完成鸿蒙课程设计', proxy) => { assert.equal(typeof h.DeepSeekService, 'function', 'DeepSeekService must be implemented'); return h.DeepSeekService.generate(key, goal, proxy); };
  return h;
}
const plain = value => JSON.parse(JSON.stringify(value));

// Integration path keeps the installed SDK's actual Trace accessors and both real stores.
// A plain Todo stub cannot detect JSON.stringify losing decorated public properties.
const sdkBinary = fs.readFileSync(process.env.TODO_RUNTIME_DLL || 'D:/DevEco Studio/sdk/default/openharmony/previewer/common/bin/libace_compatible.dll').toString('utf8');
function sdkExtract(startMarker, endMarker) {
  const start = sdkBinary.indexOf(startMarker); const end = sdkBinary.indexOf(endMarker, start);
  assert.ok(start >= 0 && end >= start, `SDK runtime missing: ${startMarker}`);
  return sdkBinary.slice(start, end + endMarker.length);
}
const sdkRuntime = [
  sdkExtract('const trackInternal = (target, propertyKey) => {', '}; // trackInternal'),
  sdkExtract('function observedV2Internal(BaseClass) {', 'return observedClass;') + '\n}',
  sdkExtract('function ObservedV2(BaseClass) {', 'return observedV2Internal(BaseClass);') + '\n}',
  sdkExtract('const Trace = (target, propertyKey) => {', 'return trackInternal(target, propertyKey);') + '\n};'
].join('\n');
const integrationSource = ['model/Todo.ets', 'viewmodel/TodoStore.ets', ...files].map(f => fs.readFileSync(path.join(root, f),'utf8')).join('\n').replace(/^import .*$/gm, '');
const integrationCode = ts.transpileModule(integrationSource, { compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS, experimentalDecorators: true, useDefineForClassFields: false } }).outputText;
function integrationHarness(saved = '[]') {
  const h = { failSave: false, pushes: 0, cache: new Map([['seeded', true], ['todos_json', saved]]), events: [] };
  const ObserveV2 = {
    OB_PREFIX: '__test_ob_', V2_DECO_META: Symbol('metadata'), ID_REFS: Symbol('references'),
    getObserve: () => ({ addRef: (target,key) => h.events.push({kind:'read',target,key}), fireChange: (target,key) => h.events.push({kind:'write',target,key}) }),
    autoProxyObject: (target,key) => target[key],
    addVariableDecoMeta: (target,key,deco) => { target[ObserveV2.V2_DECO_META] ||= {}; target[ObserveV2.V2_DECO_META][key] = {deco}; }
  };
  const pref = { hasSync: k => h.cache.has(k), getSync: (k,d) => h.cache.has(k)?h.cache.get(k):d,
    putSync: (k,v) => h.cache.set(k,v), deleteSync: k => h.cache.delete(k), flushSync: () => {if(h.failSave) throw new Error('disk full');} };
  const sandbox = { exports: {}, ObserveV2, ConfigureStateMgmt: {instance:{usingV2ObservedTrack:()=>{}}},
    TrackedObject:{___IS_TRACKED_OPTIMISED:Symbol('v1')}, stateMgmtConsole:{applicationError:m=>{throw new Error(m);}},
    AsyncAddComputedV2:{addComputed:()=>{}}, AsyncAddMonitorV2:{addMonitor:()=>{}}, WeakRefPool:{asyncRegisterToFinalizationRegistry:()=>{}},
    preferences:{getPreferencesSync:()=>pref}, FormService:{push:()=>h.pushes++}, ApiService:{fetchDefaultTodos:async()=>[]},
    http:{RequestMethod:{POST:'POST'},createHttp:()=>{throw new Error('Integration must not access real HTTP');}}, Date,JSON,Number,Error,Set,Map,Promise
  };
  vm.runInNewContext(sdkRuntime+'\n'+integrationCode,sandbox); Object.assign(h,sandbox.exports); return h;
}

test('actual SDK-decorated preview imports through the real TodoStore and persists plain public fields', async () => {
  const h = integrationHarness(); const local = h.TodoStore.instance; await local.init({});
  const observed = new h.Todo(11,'原有个人任务','原有内容',false,0);
  assert.equal(JSON.parse(JSON.stringify(observed)).title, undefined, 'Harness must preserve the actual decorated serialization trap');
  local.add(observed); const before = JSON.parse(h.cache.get('todos_json'));
  const assistant = h.DeepSeekStore.instance; assistant.showExample();
  assert.equal(assistant.addToTodos(),4, 'Preview must convert to plain DTO before actual import validation');
  const saved = JSON.parse(h.cache.get('todos_json')); assert.equal(saved.length,5); assert.equal(local.todoCount,5); assert.equal(assistant.added,true);
  assert.equal(saved.find(t=>t.id===11).description,before[0].description);
  assert.ok(saved.every(t=>Number.isSafeInteger(t.id)&&t.title&&typeof t.done==='boolean'));
  assert.ok(saved.every(t=>!Object.keys(t).some(k=>k.startsWith('__'))));
  assert.equal(assistant.addToTodos(),0); assert.equal(local.todoCount,5);
  assert.ok(h.events.some(e=>e.kind==='write'&&e.target===local&&e.key==='todos'));
});
test('real storage flush failure preserves the whole preview and can retry after disk recovers', async () => {
  const h = integrationHarness(); const local = h.TodoStore.instance; await local.init({});
  local.add(new h.Todo(11,'原有任务','',false,0)); const original = h.cache.get('todos_json');
  const assistant = h.DeepSeekStore.instance; assistant.showExample(); h.failSave = true;
  assert.equal(assistant.addToTodos(),0); assert.equal(local.todoCount,1); assert.equal(assistant.added,false); assert.equal(h.cache.get('todos_json'),original);
  assert.ok(local.storageError, 'Real store must surface its transient disk error');
  h.failSave = false; assert.equal(assistant.addToTodos(),4, 'Transient storageError must not be confused with corrupt-data protection');
  assert.equal(local.storageError,''); assert.equal(local.todoCount,5); assert.equal(assistant.added,true);
});
test('actual corrupt-data protection blocks assistant import without touching original bytes', async () => {
  const damaged = '{broken json'; const h = integrationHarness(damaged); const local = h.TodoStore.instance; await local.init({});
  const assistant = h.DeepSeekStore.instance; assistant.showExample(); assert.equal(assistant.addToTodos(),0); assert.equal(assistant.added,false); assert.equal(local.todos.length,0); assert.equal(h.cache.get('todos_json'),damaged); assert.match(assistant.error,/保护/);
});
test('posts only the goal to the fixed HTTPS endpoint with Bearer auth and JSON mode', async () => {
  const h = harness(); const result = await h.fetch(); assert.equal(result.length, 3);
  const { url, options } = h.requests[0]; const body = JSON.parse(options.extraData);
  assert.equal(url, 'https://api.deepseek.com/chat/completions'); assert.equal(options.method, 'POST');
  assert.equal(options.header.Authorization, 'Bearer sk-test-example-not-a-real-key');
  assert.equal(body.model, 'deepseek-flash'); assert.equal(body.response_format.type, 'json_object'); assert.equal(body.thinking.type, 'disabled');
  assert.equal(body.messages[1].content, '完成鸿蒙课程设计'); assert.equal(body.stream, false); assert.ok(options.connectTimeout > 0 && options.readTimeout > 0);
  assert.equal(options.usingCache, false); assert.equal(options.usingProxy, true); assert.equal(h.destroys, 1); assert.equal(h.writes.length, 0);
});
test('empty / malformed keys and empty / oversized goals never open a connection', async () => {
  const h = harness(); for (const key of ['', 'short', 'sk-a\nbad', 'sk-abc def']) await assert.rejects(h.fetch(key));
  for (const goal of ['', ' ', 'x'.repeat(1001)]) await assert.rejects(h.fetch(undefined, goal));
  assert.equal(h.requests.length, 0); assert.equal(h.destroys, 0);
});
test('optional proxy is passed without changing the target URL', async () => {
  const h = harness(); const proxy = { host: 'proxy.example.com', port: 8080, exclusionList: [] }; await h.fetch(undefined, undefined, proxy);
  assert.deepEqual(plain(h.requests[0].options.usingProxy), proxy); assert.equal(h.requests[0].url, 'https://api.deepseek.com/chat/completions');
});
for (const [status, text] of [[401, /密钥/], [402, /余额/], [429, /频繁/], [500, /服务/], [503, /服务/], [400, /请求/]]) {
  test(`HTTP ${status} yields a safe useful message and destroys the request`, async () => {
    const h = harness(); h.respond = async () => ({ responseCode: status, result: 'secret-server-body-sk-real' });
    await assert.rejects(h.fetch(), e => text.test(e.message) && !e.message.includes('secret-server-body')); assert.equal(h.destroys, 1);
  });
}
test('transport errors never expose raw credentials and always release resources', async () => {
  const h = harness(); h.respond = async () => { throw new Error('sk-sensitive-key: timeout'); };
  await assert.rejects(h.fetch(), e => /网络|超时/.test(e.message) && !e.message.includes('sk-sensitive')); assert.equal(h.destroys, 1);
});
test('truncated/refused and invalid envelopes are rejected as a whole', async () => {
  const h = harness(); for (const value of [response(tasks(), 'length'), response(tasks(), 'content_filter'), { responseCode: 200, result: '{' }, { responseCode: 200, result: '{}' }, { responseCode: 200, result: {} }]) { h.respond = async () => value; await assert.rejects(h.fetch()); }
  assert.equal(h.destroys, 5);
});
test('plans validate all entries, bounds and duplicate titles before returning any tasks', async () => {
  const h = harness(); const badPlans = [[], tasks().slice(0, 2), [...tasks(), ...tasks(), tasks()[0]], [tasks()[0], tasks()[0], tasks()[2]], [...tasks().slice(0,2), { title: '', description: '', priority: 0 }], [...tasks().slice(0,2), { title: 'x'.repeat(201), description: '', priority: 0 }], [...tasks().slice(0,2), { title: 't', description: 'x'.repeat(1001), priority: 0 }], [...tasks().slice(0,2), { title: 't', description: 'd', priority: 9 }]];
  for (const plan of badPlans) { h.respond = async () => response(plan); await assert.rejects(h.fetch()); } assert.equal(h.destroys, badPlans.length);
});
test('key configuration is session-only, validates first, and clearing removes it', () => {
  const h = harness(); const s = h.store(); assert.equal(s.hasKey, false); assert.equal(s.configureKey('short'), false); assert.equal(s.hasKey, false);
  assert.equal(s.configureKey('sk-test-example-not-a-real-key'), true); assert.equal(s.hasKey, true); assert.equal(h.writes.length, 0);
  s.clearKey(); assert.equal(s.hasKey, false); assert.equal(h.writes.length, 0);
});
test('offline example has an explicit source and never contacts API or writes personal data', () => {
  const h = harness(); const s = h.store(); s.showExample(); assert.equal(s.source, 'example'); assert.equal(s.tasks.length, 4); assert.ok(s.resultGoal);
  assert.equal(h.requests.length, 0); assert.equal(h.writes.length, 0);
});
test('generation requires key and preserves an earlier clearly-labelled preview on failure', async () => {
  const h = harness(); const s = h.store(); s.showExample(); const before = s.tasks; await s.generate(); assert.match(s.error, /密钥/); assert.equal(s.tasks, before);
  s.configureKey('sk-test-example-not-a-real-key'); h.respond = async () => ({ responseCode: 401, result: '{}' }); await s.generate(); assert.equal(s.source, 'example'); assert.equal(s.tasks, before); assert.match(s.error, /密钥/); assert.equal(s.loading, false);
});
test('in-flight generation is single request and key/example changes are blocked', async () => {
  const h = harness(); const s = h.store(); s.configureKey('sk-test-example-not-a-real-key'); s.goal = '完成课程设计'; let finish;
  h.respond = () => new Promise(resolve => { finish = resolve; }); const first = s.generate(); const second = s.generate(); assert.equal(first, second); assert.equal(h.requests.length, 1); assert.equal(s.loading, true);
  s.showExample(); s.clearKey(); assert.equal(s.tasks.length, 0); assert.equal(s.hasKey, true); assert.equal(s.configureKey('sk-another-test-key'), false);
  finish(response()); await first; assert.equal(s.source, 'api'); assert.equal(s.tasks.length, 3); assert.equal(s.resultGoal, '完成课程设计'); assert.equal(s.loading, false); assert.equal(h.writes.length, 0);
});
test('confirm adds the full preview atomically once and resets home filters', () => {
  const h = harness(); const s = h.store(); s.showExample(); assert.equal(s.addToTodos(), 4); assert.equal(h.writes.length, 1); assert.equal(h.writes[0].length, 4); assert.equal(new Set(h.writes[0].map(t => t.id)).size, 4);
  assert.ok(h.writes[0].every(t => !t.done && !t.deleted && t.description.includes('离线示例'))); assert.equal(s.added, true); assert.equal(s.addToTodos(), 0); assert.equal(h.writes.length, 1); assert.equal(h.todo.filter, 'all'); assert.equal(h.todo.inTrash, false); assert.equal(h.todo.keyword, '');
});
test('failed persistence keeps preview retryable and does not mark it added', () => {
  const h = harness(); const s = h.store(); s.showExample(); h.failSave = true; assert.equal(s.addToTodos(), 0); assert.equal(s.added, false); assert.equal(s.tasks.length, 4); assert.match(s.error, /保存/);
  h.failSave = false; assert.equal(s.addToTodos(), 4); assert.equal(h.writes.length, 1);
});
test('blocked local data cannot be overwritten through assistant import', () => {
  const h = harness(); const s = h.store(); s.showExample(); h.todo.storageError = '本地数据异常'; h.todo.isStorageProtected = true; assert.equal(s.addToTodos(), 0); assert.equal(h.writes.length, 0); assert.equal(s.added, false);
});
test('proxy validation has no request side effects and is session-only', () => {
  const h = harness(); const s = h.store(); for (const pair of [['http://host','80'],['host','0'],['host','65536'],['','80'],['host/path','80'],['host\nbad','80']]) assert.equal(s.configureProxy(...pair), false);
  assert.equal(s.configureProxy('127.0.0.1', '7897'), true); assert.equal(s.proxyHost, '127.0.0.1'); assert.equal(s.proxyPort, 7897); assert.equal(s.configureProxy('', ''), true); assert.equal(s.proxyHost, ''); assert.equal(h.requests.length, 0); assert.equal(h.writes.length, 0);
});
test('assistant page exposes masked key, confirmation, honest source labels and accessible entry', () => {
  const page = fs.readFileSync(path.join(root,'pages/DeepSeekPage.ets'),'utf8'); const home = fs.readFileSync(path.join(root,'pages/HomePage.ets'),'utf8'); const index = fs.readFileSync(path.join(root,'pages/Index.ets'),'utf8');
  assert.match(page, /InputType.Password/); assert.match(page, /showAlertDialog/); assert.match(page, /离线示例/); assert.match(page, /不是 API/); assert.match(page, /仅.*目标/); assert.match(page, /deepseek-confirm-add/); assert.match(home, /home-deepseek-entry/); assert.match(index, /DeepSeekPage/);
  for (const file of files) assert.doesNotMatch(fs.readFileSync(path.join(root,file),'utf8'), /console\.|hilog\.|preferences\.|getPreferences/);
});
