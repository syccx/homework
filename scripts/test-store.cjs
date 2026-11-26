const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const { test } = require('node:test');
const ts = require(process.env.TODO_TYPESCRIPT || 'D:/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript/lib/typescript.js');
const root = path.resolve(__dirname, '../entry/src/main/ets');
const source = ['model/Todo.ets', 'viewmodel/TodoStore.ets'].map(file => fs.readFileSync(path.join(root, file), 'utf8')).join('\n')
  .replace(/^import .*$/gm, '').replace(/@ObservedV2\s*/g, '').replace(/@Trace\s*/g, '');
const compiled = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS } }).outputText;
function harness(initial = {}) {
  const state = { disk: new Map(Object.entries(initial)), cache: new Map(Object.entries(initial)), fail: false, failPutKey: '', flushCalls: 0, failFlushAt: 0, fetchCalls: 0, formPushes: [], fetch: async () => { throw new Error('offline'); } };
  const pref = { getSync: (key, fallback) => state.cache.has(key) ? state.cache.get(key) : fallback, hasSync: key => state.cache.has(key),
    putSync: (key, value) => { if (state.failPutKey === key) { state.failPutKey = ''; throw new Error('put failed'); } state.cache.set(key, value); },
    deleteSync: key => state.cache.delete(key),
    flushSync: () => { state.flushCalls++; if (state.fail || state.flushCalls === state.failFlushAt) throw new Error('disk full'); state.disk = new Map(state.cache); },
    flush: () => { if (state.fail) return Promise.reject(new Error('disk full')); state.disk = new Map(state.cache); return Promise.resolve(); } };
  const sandbox = { exports: {}, preferences: { getPreferencesSync: () => pref }, FormService: { push: list => state.formPushes.push(JSON.parse(JSON.stringify(list))) },
    formBindingData: { createFormBindingData: value => value }, formProvider: { updateForm: () => Promise.resolve() },
    ApiService: { fetchDefaultTodos: () => { state.fetchCalls++; return state.fetch(); } }, Date, JSON, Error, Number, Set, Map };
  vm.runInNewContext(compiled, sandbox);
  state.Todo = sandbox.exports.Todo; state.Store = sandbox.exports.TodoStore;
  state.make = (id, title, done = false, priority = 0, createdAt = Date.now(), dueAt = 0, deleted = false, doneAt = 0) => new state.Todo(id, title, '', done, priority, createdAt, dueAt, deleted, doneAt);
  state.saved = () => JSON.parse(state.disk.get('todos_json') || '[]');
  return state;
}
function plain(value) { return JSON.parse(JSON.stringify(value)); }
test('offline create is marked initialized and survives reopen', async () => {
  const h = harness(); const store = new h.Store(); await store.init({}); store.add(h.make(100, 'offline-created'));
  assert.equal(h.disk.get('seeded'), true); h.fetch = async () => [h.make(1, 'sample')];
  const reopened = new h.Store(); await reopened.init({}); assert.deepEqual(plain(reopened.todos.map(t => t.title)), ['offline-created']);
});
test('existing local JSON is authoritative even without old seeded marker', async () => {
  const h = harness({ todos_json: '[{"id":7,"title":"legacy local","done":false}]' }); h.fetch = async () => [h.make(1, 'sample')];
  const store = new h.Store(); await store.init({}); assert.equal(store.todos[0].title, 'legacy local'); assert.equal(h.fetchCalls, 0);
});
test('first network response never overwrites a task added while loading', async () => {
  const h = harness(); let finish; h.fetch = () => new Promise(resolve => { finish = resolve; }); const store = new h.Store();
  const pending = store.init({}); store.add(h.make(100, 'user-created')); finish([h.make(1, 'sample')]); await pending;
  assert.deepEqual(plain(store.todos.map(t => t.title)), ['user-created']); assert.deepEqual(h.saved().map(t => t.title), ['user-created']);
});
test('retry requests are deduplicated while first request is pending', async () => {
  const h = harness(); let finish; h.fetch = () => new Promise(resolve => { finish = resolve; }); const store = new h.Store();
  const init = store.init({}); const retry1 = store.reload(); const retry2 = store.reload(); assert.equal(h.fetchCalls, 1);
  finish([]); await Promise.all([init, retry1, retry2]);
});
test('retry never repopulates an intentionally empty initialized database', async () => {
  const h = harness({ seeded: true, todos_json: '[]' }); const store = new h.Store(); await store.init({}); await store.reload(); assert.equal(h.fetchCalls, 0);
});
test('same deadline falls through to priority and newest creation time', () => {
  const h = harness(); const store = new h.Store(); store.todos = [h.make(1, 'normal', false, 0, 10, 100), h.make(2, 'important', false, 1, 11, 100), h.make(3, 'newer important', false, 1, 12, 100)];
  assert.deepEqual(plain(store.viewOf.map(t => t.id)), [3, 2, 1]);
});
test('malformed stored data remains recoverable and blocks accidental overwrite', async () => {
  const original = '[{"id":1,"title":null}]'; const h = harness({ seeded: true, todos_json: original }); const store = new h.Store(); await store.init({});
  assert.ok(store.storageError); store.keyword = 'find'; assert.equal(store.viewOf.length, 0);
  assert.equal(store.add(h.make(2, 'new')), false); assert.equal(h.disk.get('todos_json'), original); assert.equal(store.exportJson(), original);
});
test('broken JSON is not replaced by an empty database or network seed', async () => {
  const h = harness({ todos_json: '{broken' }); const store = new h.Store(); await store.init({}); assert.ok(store.storageError); assert.equal(h.fetchCalls, 0);
  await store.reload(); assert.equal(h.fetchCalls, 0); assert.equal(h.disk.get('todos_json'), '{broken');
});
test('synchronous flush failure is visible and saving can be retried', async () => {
  const h = harness({ seeded: true, todos_json: '[]' }); const store = new h.Store(); await store.init({}); h.fail = true;
  assert.equal(store.add(h.make(3, 'unsaved')), false); assert.ok(store.storageError); assert.deepEqual(h.saved(), []);
  assert.equal(store.todos.length, 0); h.fail = false; assert.equal(store.add(h.make(3, 'unsaved')), true); assert.equal(h.saved()[0].title, 'unsaved'); assert.equal(store.storageError, '');
});
test('toggle persists both done and doneAt; toggle back clears timestamp', async () => {
  const h = harness({ seeded: true, todos_json: '[]' }); const store = new h.Store(); await store.init({}); store.add(h.make(8, 'task')); store.toggle(8);
  assert.equal(h.saved()[0].done, true); assert.ok(h.saved()[0].doneAt > 0); assert.equal(store.doneCount, 1); assert.equal(store.weeklyTrend.at(-1).count, 1);
  store.toggle(8); assert.equal(h.saved()[0].doneAt, 0); assert.equal(store.doneCount, 0);
});
test('duplicate task IDs are repaired on add', async () => {
  const h = harness({ seeded: true, todos_json: '[]' }); const store = new h.Store(); await store.init({}); store.add(h.make(9, 'one')); store.add(h.make(9, 'two'));
  assert.equal(new Set(store.todos.map(t => t.id)).size, 2); assert.equal(store.todos.length, 2);
});
test('import merges records, repairs collisions, and persists atomically', async () => {
  const h = harness({ seeded: true, todos_json: '[]' }); const store = new h.Store(); await store.init({}); store.add(h.make(1, 'existing'));
  const count = store.importJson('[{"id":1,"title":"imported","done":false}]'); assert.equal(count, 1); assert.equal(store.todos.length, 2);
  assert.equal(new Set(store.todos.map(t => t.id)).size, 2); assert.ok(store.todos.some(t => t.title === 'existing')); assert.equal(h.saved().length, 2);
});
test('invalid import rejects the entire batch without changing current state', async () => {
  const h = harness({ seeded: true, todos_json: '[]' }); const store = new h.Store(); await store.init({}); store.add(h.make(2, 'existing')); const before = store.exportJson();
  assert.throws(() => store.importJson('[{"id":3,"title":"valid","done":false},{"id":4,"title":null,"done":false}]'));
  assert.equal(store.exportJson(), before); assert.equal(h.disk.get('todos_json'), before);
});
test('explicit import can recover a corrupt database after preserving original bytes', async () => {
  const original = '{bad data'; const h = harness({ todos_json: original, seeded: true }); const store = new h.Store(); await store.init({});
  assert.equal(store.importJson('[{"id":5,"title":"recovered","done":false}]'), 1); assert.equal(store.storageError, ''); assert.equal(h.saved()[0].title, 'recovered');
  assert.ok([...h.disk.entries()].some(([key, value]) => key !== 'todos_json' && value === original));
});
test('import with storage failure leaves current memory list unchanged', async () => {
  const h = harness({ seeded: true, todos_json: '[]' }); const store = new h.Store(); await store.init({}); store.add(h.make(2, 'existing')); const before = store.exportJson(); h.fail = true;
  assert.throws(() => store.importJson('[{"id":3,"title":"imported","done":false}]')); assert.equal(store.exportJson(), before);
});
test('refresh uses local data and pushes only the latest saved snapshot', async () => {
  const h = harness({ seeded: true, todos_json: '[]' }); const store = new h.Store(); await store.init({}); store.add(h.make(10, 'local')); await store.refresh();
  assert.equal(h.fetchCalls, 0); assert.equal(h.formPushes.at(-1)[0].title, 'local');
});

const apiSource = fs.readFileSync(path.join(root, 'common/ApiService.ets'), 'utf8').replace(/^import .*$/gm, '');
const apiCompiled = ts.transpileModule(apiSource, { compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS } }).outputText;
function apiHarness(result, responseCode = 200) {
  const h = harness(); const state = { destroyed: 0 }; const sandbox = { exports: {}, Todo: h.Todo, http: { RequestMethod: { GET: 'GET' }, createHttp: () => ({
    request: async () => ({ result, responseCode }), destroy: () => { state.destroyed++; }
  }) }, Date, JSON, Error, Number }; vm.runInNewContext(apiCompiled, sandbox); state.api = sandbox.exports.ApiService; return state;
}
test('network rejects malformed records before they reach searchable state and always closes request', async () => {
  const h = apiHarness('[{"id":1,"title":null,"completed":false}]'); await assert.rejects(() => h.api.fetchDefaultTodos()); assert.equal(h.destroyed, 1);
});
test('network response must be an array and status 200', async () => {
  const wrongShape = apiHarness('{"message":"ok"}'); await assert.rejects(() => wrongShape.api.fetchDefaultTodos()); assert.equal(wrongShape.destroyed, 1);
  const badStatus = apiHarness('[]', 503); await assert.rejects(() => badStatus.api.fetchDefaultTodos()); assert.equal(badStatus.destroyed, 1);
});
test('network keeps only the first five valid sample records', async () => {
  const h = apiHarness(JSON.stringify(Array.from({ length: 9 }, (_, i) => ({ id: i + 1, title: `sample ${i}`, completed: false }))));
  const result = await h.api.fetchDefaultTodos(); assert.equal(result.length, 5); assert.equal(result[0].title, 'sample 0'); assert.equal(h.destroyed, 1);
});
test('invalid directly added task cannot corrupt the persisted database', async () => {
  const h = harness({ seeded: true, todos_json: '[]' }); const store = new h.Store(); await store.init({}); const bad = h.make(4, 'bad priority'); bad.priority = 7;
  assert.equal(store.add(bad), false); assert.deepEqual(h.saved(), []);
});
test('deleted records are excluded from counts and can be restored or permanently removed', async () => {
  const h = harness({ seeded: true, todos_json: '[]' }); const store = new h.Store(); await store.init({}); store.add(h.make(20, 'task')); store.remove(20);
  assert.equal(store.todoCount, 0); assert.equal(store.trashCount, 1); assert.equal(store.viewOf.length, 0);
  store.restore(20); assert.equal(store.todoCount, 1); assert.equal(store.destroy(20), false); store.remove(20); assert.equal(store.destroy(20), true); assert.equal(store.todos.length, 0);
});
test('search matches description without case sensitivity and sorting never mutates backing list', () => {
  const h = harness(); const store = new h.Store(); const one = h.make(1, 'First'); one.description = 'HarmonyOS'; const two = h.make(2, 'Second'); store.todos = [one, two];
  store.keyword = 'harmony'; assert.deepEqual(plain(store.viewOf.map(t => t.id)), [1]); assert.deepEqual(plain(store.todos.map(t => t.id)), [1, 2]);
});
test('future completion timestamps never count as today or a streak', () => {
  const h = harness(); const store = new h.Store(); store.todos = [h.make(1, 'future', true, 0, 0, 0, false, Date.now() + 2 * 86400000)];
  assert.equal(store.streakDays, 0); assert.equal(store.weeklyTrend.at(-1).count, 0);
});
test('second init is idempotent and cannot overwrite subsequent local changes', async () => {
  const h = harness({ seeded: true, todos_json: '[]' }); const store = new h.Store(); await store.init({}); store.add(h.make(1, 'task')); await store.init({}); assert.equal(store.todos.length, 1); assert.equal(h.fetchCalls, 0);
});
test('context attachment does not discard tasks accepted before initialization', async () => {
  const h = harness(); const store = new h.Store(); assert.equal(store.add(h.make(1, 'early draft')), true); await store.init({});
  assert.equal(store.todos[0].title, 'early draft'); assert.equal(h.saved()[0]?.title, 'early draft'); assert.equal(h.disk.get('seeded'), true);
});
test('context attachment preserves both disk data and any accepted early draft', async () => {
  const h = harness({ seeded: true, todos_json: '[{"id":2,"title":"existing on disk","done":false}]' }); const store = new h.Store();
  assert.equal(store.add(h.make(1, 'early draft')), true); await store.init({});
  assert.deepEqual(plain(store.todos.map(t => t.title)).sort(), ['early draft', 'existing on disk']);
  assert.equal(h.saved().length, 2);
});
test('a failure between preference puts rolls back uncommitted cached JSON', async () => {
  const h = harness({ seeded: true, todos_json: '[]' }); const store = new h.Store(); await store.init({}); h.failPutKey = 'seeded';
  assert.equal(store.add(h.make(1, 'must not leak')), false); assert.equal(store.todos.length, 0); assert.deepEqual(h.saved(), []); assert.equal(h.cache.get('todos_json'), '[]');
  const reopened = new h.Store(); await reopened.init({}); assert.equal(reopened.todos.length, 0);
});
test('merging below-limit batches cannot create a database above the recoverable record limit', async () => {
  const initial = Array.from({ length: 9500 }, (_, i) => ({ id: i + 1, title: 'task', done: false }));
  const h = harness({ seeded: true, todos_json: JSON.stringify(initial) }); const store = new h.Store(); await store.init({}); const before = h.disk.get('todos_json');
  const batch = JSON.stringify(Array.from({ length: 1000 }, (_, i) => ({ id: i + 20000, title: 'imported', done: false })));
  assert.throws(() => store.importJson(batch)); assert.equal(store.todos.length, 9500); assert.equal(h.disk.get('todos_json'), before);
});
test('merging must not write JSON larger than the next startup can read', async () => {
  const initial = Array.from({ length: 260 }, (_, i) => ({ id: i + 1, title: 'task', description: 'x'.repeat(5000), done: false }));
  const h = harness({ seeded: true, todos_json: JSON.stringify(initial) }); const store = new h.Store(); await store.init({}); const before = h.disk.get('todos_json');
  const batch = JSON.stringify(Array.from({ length: 260 }, (_, i) => ({ id: i + 20000, title: 'imported', description: 'x'.repeat(5000), done: false })));
  assert.throws(() => store.importJson(batch)); assert.equal(store.todos.length, 260); assert.equal(h.disk.get('todos_json'), before);
});
test('failed corrupt-data recovery preserves both original bytes and its durable recovery copy', async () => {
  const original = '{keep me'; const h = harness({ seeded: true, todos_json: original }); const store = new h.Store(); await store.init({}); h.failFlushAt = 2;
  assert.throws(() => store.importJson('[{"id":1,"title":"valid","done":false}]')); assert.equal(store.exportJson(), original); assert.equal(h.disk.get('todos_json'), original);
  assert.ok([...h.disk.entries()].some(([key, value]) => key.startsWith('recovery_json_') && value === original)); assert.equal(store.todos.length, 0);
});
test('recovery backup failure prevents replacing the original database', async () => {
  const original = '[bad'; const h = harness({ seeded: true, todos_json: original }); const store = new h.Store(); await store.init({}); h.failFlushAt = 1;
  assert.throws(() => store.importJson('[{"id":1,"title":"valid","done":false}]')); assert.equal(h.disk.get('todos_json'), original); assert.equal(store.exportJson(), original);
});
test('soft delete preserves completion history while permanent delete removes it', async () => {
  const h = harness({ seeded: true, todos_json: '[]' }); const store = new h.Store(); await store.init({}); store.add(h.make(1, 'task')); store.toggle(1); store.clearDone();
  assert.equal(store.doneCount, 0); assert.equal(store.trashCount, 1); assert.equal(store.weeklyTrend.at(-1).count, 1); assert.equal(store.streakDays, 1);
  store.destroy(1); assert.equal(store.weeklyTrend.at(-1).count, 0); assert.equal(store.streakDays, 0);
});
test('yesterday-only completion keeps a streak but a gap breaks older days', () => {
  const h = harness(); const store = new h.Store(); const now = new Date(); now.setHours(12, 0, 0, 0); store.nowAt = now.getTime();
  const yesterday = new Date(now); yesterday.setDate(yesterday.getDate() - 1); const older = new Date(now); older.setDate(older.getDate() - 3);
  store.todos = [h.make(1, 'yesterday', true, 0, 1, 0, false, yesterday.getTime()), h.make(2, 'older', true, 0, 1, 0, false, older.getTime())];
  assert.equal(store.streakDays, 1); assert.equal(store.weeklyTrend.at(-2).count, 1); assert.equal(store.weeklyTrend.at(-1).count, 0);
});
test('editing resolves the latest stored task rather than stale route-object fields', async () => {
  const h = harness({ seeded: true, todos_json: '[]' }); const store = new h.Store(); await store.init({}); store.add(h.make(1, 'old title'));
  const staleRoute = store.byId(1); store.edit(1, 'latest title', 'new description', 1, 1234);
  const pageSource = fs.readFileSync(path.join(root, 'pages/AddTodoPage.ets'), 'utf8');
  const start = pageSource.indexOf('  aboutToAppear(): void {'); const end = pageSource.indexOf('  private snapshot()', start);
  assert.ok(start >= 0 && end > start); const method = pageSource.slice(start, end);
  const pageCode = ts.transpileModule(`class Page { ${method} } exports.Page = Page;`, { compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS } }).outputText;
  const sandbox = { exports: {} }; vm.runInNewContext(pageCode, sandbox); const page = new sandbox.exports.Page();
  Object.assign(page, { navPathStack: { getParamByName: () => [staleRoute] }, store, snapshot: () => 'snapshot' }); page.aboutToAppear();
  assert.equal(page.title, 'latest title'); assert.equal(page.desc, 'new description'); assert.equal(page.priority, 1); assert.equal(page.dueAt, 1234);
});
test('context attachment clears the preview-only notice after saving accepted drafts', async () => {
  const h = harness(); const store = new h.Store(); store.add(h.make(1, 'draft')); assert.match(store.notice, /预览/); await store.init({}); assert.doesNotMatch(store.notice, /预览/);
});
test('startup-draft save failure keeps accepted drafts visible and refresh can retry durably', async () => {
  const h = harness({ seeded: true, todos_json: '[{"id":2,"title":"on disk","done":false}]' }); const store = new h.Store(); store.add(h.make(1, 'draft')); h.fail = true;
  await store.init({}); assert.equal(store.todos.length, 2); assert.equal(h.saved().length, 1); assert.ok(store.storageError);
  h.fail = false; await store.refresh(); assert.equal(h.saved().length, 2); assert.equal(store.storageError, '');
});
test('rollback restores absent keys instead of creating a phantom initialized empty database', async () => {
  const h = harness(); const store = new h.Store(); await store.init({}); h.failPutKey = 'seeded'; assert.equal(store.add(h.make(1, 'not saved')), false);
  assert.equal(h.cache.has('todos_json'), false); assert.equal(h.cache.has('seeded'), false); assert.equal(h.disk.has('todos_json'), false);
});
test('startup merge repairs colliding draft IDs without replacing an existing disk record', async () => {
  const h = harness({ seeded: true, todos_json: '[{"id":1,"title":"disk record","done":false}]' }); const store = new h.Store(); store.add(h.make(1, 'draft')); await store.init({});
  assert.equal(store.todos.length, 2); assert.equal(new Set(store.todos.map(t => t.id)).size, 2); assert.equal(h.saved().find(t => t.id === 1).title, 'disk record');
});
