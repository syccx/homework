// Keep ArkUI decorators: business-only tests strip them and cannot catch eager-singleton shadowing.
// Runtime functions are extracted from the installed SDK, never copied into production code.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const { test } = require('node:test');
const ts = require(process.env.TODO_TYPESCRIPT || 'D:/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript/lib/typescript.js');
const runtimePath = process.env.TODO_RUNTIME_DLL || 'D:/DevEco Studio/sdk/default/openharmony/previewer/common/bin/libace_compatible.dll';
const binaryText = fs.readFileSync(runtimePath).toString('utf8');
function extract(startMarker, endMarker) {
  const start = binaryText.indexOf(startMarker);
  const end = binaryText.indexOf(endMarker, start);
  assert.ok(start >= 0 && end >= start, `SDK runtime function missing: ${startMarker}`);
  return binaryText.slice(start, end + endMarker.length);
}
const runtimeSource = [
  extract('const trackInternal = (target, propertyKey) => {', '}; // trackInternal'),
  extract('function observedV2Internal(BaseClass) {', 'return observedClass;') + '\n}',
  extract('function ObservedV2(BaseClass) {', 'return observedV2Internal(BaseClass);') + '\n}',
  extract('const Trace = (target, propertyKey) => {', 'return trackInternal(target, propertyKey);') + '\n};'
].join('\n');
const sourceRoot = path.resolve(__dirname, '../entry/src/main/ets');
let source = ['model/Todo.ets', 'viewmodel/TodoStore.ets']
  .map(file => fs.readFileSync(path.join(sourceRoot, file), 'utf8')).join('\n').replace(/^import .*$/gm, '');
// Diagnostic red run: node scripts/test-reactivity.cjs --legacy-fixture
// This restores only the original eager singleton in memory, without touching project source.
if (process.argv.includes('--legacy-fixture')) {
  const markerStart = source.indexOf('  private static singleton: TodoStore');
  const markerEnd = source.indexOf('  @Trace todos:', markerStart);
  assert.ok(markerStart >= 0 && markerEnd > markerStart, 'Lazy singleton block must exist for the legacy regression fixture');
  source = source.slice(0, markerStart) + '  static instance: TodoStore = new TodoStore();\n' + source.slice(markerEnd);
}
const compiled = ts.transpileModule(source, { compilerOptions: {
  target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS,
  experimentalDecorators: true, useDefineForClassFields: false
} }).outputText;

function harness() {
  const state = { events: [], fail: false, cache: new Map([['seeded', true], ['todos_json', '[]']]) };
  const effects = [];
  let activeEffect;
  function runEffect(effect) {
    const previous = activeEffect;
    activeEffect = effect;
    effect.dependencies = [];
    try { effect.value = effect.render(); } finally { activeEffect = previous; }
  }
  state.watch = render => {
    const effect = { render, dependencies: [], value: undefined };
    effects.push(effect);
    runEffect(effect);
    return effect;
  };
  const observer = {
    addRef: (target, key) => {
      state.events.push({ kind: 'read', target, key });
      if (activeEffect) activeEffect.dependencies.push({ target, key });
    },
    fireChange: (target, key) => {
      state.events.push({ kind: 'write', target, key });
      for (const effect of effects) {
        if (effect.dependencies.some(dependency => dependency.target === target && dependency.key === key)) runEffect(effect);
      }
    }
  };
  // Replace only scheduling/metadata dependencies. Accessor and class-decoration logic above is actual SDK code.
  const ObserveV2 = {
    OB_PREFIX: '__test_ob_', V2_DECO_META: Symbol('metadata'), ID_REFS: Symbol('references'),
    getObserve: () => observer,
    autoProxyObject: (target, key) => target[key],
    addVariableDecoMeta: (target, key, deco) => {
      target[ObserveV2.V2_DECO_META] ||= {};
      target[ObserveV2.V2_DECO_META][key] = { deco };
    }
  };
  const pref = {
    hasSync: key => state.cache.has(key),
    getSync: (key, fallback) => state.cache.has(key) ? state.cache.get(key) : fallback,
    putSync: (key, value) => state.cache.set(key, value),
    deleteSync: key => state.cache.delete(key),
    flushSync: () => { if (state.fail) throw new Error('disk full'); }
  };
  const sandbox = {
    exports: {}, ObserveV2,
    ConfigureStateMgmt: { instance: { usingV2ObservedTrack: () => {} } },
    TrackedObject: { ___IS_TRACKED_OPTIMISED: Symbol('v1 track') },
    stateMgmtConsole: { applicationError: message => { throw new Error(message); } },
    AsyncAddComputedV2: { addComputed: () => {} },
    AsyncAddMonitorV2: { addMonitor: () => {} },
    WeakRefPool: { asyncRegisterToFinalizationRegistry: () => {} },
    preferences: { getPreferencesSync: () => pref },
    FormService: { push: () => {} },
    ApiService: { fetchDefaultTodos: async () => [] },
    Date, JSON, Number, Set, Map, Error
  };
  vm.runInNewContext(runtimeSource + '\n' + compiled, sandbox);
  state.Store = sandbox.exports.TodoStore;
  state.Todo = sandbox.exports.Todo;
  state.hasEvent = (kind, target, key) => state.events.some(event => event.kind === kind && event.target === target && event.key === key);
  return state;
}

// Exercise the actual builder's numeric Text expression with the SDK Trace accessors.
// Like generated observeComponentCreation2 callbacks, each leaf keeps its builder arguments
// from mounting; only reads made inside that leaf subscribe it to later state changes.
// This verifies binding/dependency behaviour, not ArkUI layout or native scheduling.
function mountHomeFilterCounts(h, store) {
  const pageSource = fs.readFileSync(path.join(sourceRoot, 'pages/HomePage.ets'), 'utf8');
  const ast = ts.createSourceFile('HomePage.ets', pageSource, ts.ScriptTarget.Latest, true, ts.ScriptKind.ETS);
  const component = ast.statements.find(node => node.name?.getText(ast) === 'HomePage');
  const builder = component?.members.find(node => node.name?.getText(ast) === 'filterChip');
  assert.ok(builder, 'Home must define its filter chip builder');
  const texts = [];
  const calls = [];
  function visit(node) {
    if (ts.isCallExpression(node)) {
      const name = node.expression.getText(ast);
      if (name === 'Text' && node.arguments.length) texts.push(node.arguments[0].getText(ast));
      if (name === 'this.filterChip') calls.push(node.arguments.map(argument => argument.getText(ast)));
    }
    ts.forEachChild(node, visit);
  }
  visit(builder);
  assert.equal(texts.length, 2, 'The chip must render a label and its numeric count');
  visit(component.members.find(node => node.name?.getText(ast) === 'overview'));
  assert.equal(calls.length, 3, 'All, active and done chips must all be covered');
  const parameters = builder.parameters.map(parameter => parameter.getText(ast)).join(', ');
  const script = `function leaf(${parameters}) { return () => (${texts[1]}); }\n` +
    `function args() { return [${calls.map(arguments_ => `[${arguments_.join(', ')}]`).join(', ')}]; }`;
  const context = {};
  vm.runInNewContext(ts.transpileModule(script, { compilerOptions: { target: ts.ScriptTarget.ES2021 } }).outputText, context);
  const page = { store };
  return context.args.call(page).map(arguments_ => h.watch(context.leaf.apply(page, arguments_)));
}

test('shared singleton is created after Trace accessors are installed', () => {
  const h = harness(); const store = h.Store.instance;
  assert.equal(store, h.Store.instance);
  assert.equal(Object.hasOwn(store, 'todos'), false, 'An eager singleton creates an own data field that shadows the Trace accessor');
  assert.equal(Object.hasOwn(store, 'notice'), false);
});

test('reading list and computed counts registers the actual singleton as a dependency', () => {
  const h = harness(); const store = h.Store.instance; h.events.length = 0;
  assert.equal(store.todos.length, 0); assert.equal(store.todoCount, 0); assert.equal(store.doneCount, 0);
  assert.ok(h.hasEvent('read', store, 'todos'));
});

test('save from Add emits list and notice changes to the same store read by Home', () => {
  const h = harness(); const homeStore = h.Store.instance; const addStore = h.Store.instance;
  assert.equal(homeStore.todoCount, 0); h.events.length = 0;
  assert.equal(addStore.add(new h.Todo(1, 'reactive check', '', false, 0)), true);
  assert.ok(h.hasEvent('write', homeStore, 'todos'), 'Saving must notify the list observed by Home');
  assert.ok(h.hasEvent('write', homeStore, 'notice'), 'Preview-only save notice must also notify Home');
  assert.equal(homeStore.todoCount, 1); assert.equal(homeStore.viewOf[0].title, 'reactive check');
});

test('Trace on Todo fields still emits changes after the decorated constructor runs', () => {
  const h = harness(); const todo = new h.Todo(1, 'task', '', false, 0); h.events.length = 0;
  todo.done = true; assert.ok(h.hasEvent('write', todo, 'done'));
});

test('persistence failure emits reactive error and preserves the observed list', async () => {
  const h = harness(); const store = h.Store.instance; await store.init({}); h.fail = true; h.events.length = 0;
  assert.equal(store.add(new h.Todo(1, 'cannot save', '', false, 0)), false);
  assert.ok(h.hasEvent('write', store, 'storageError')); assert.equal(store.todos.length, 0);
});

test('mounted Home filter counts track additions, completion and trash without remounting', () => {
  const h = harness(); const store = h.Store.instance;
  const counts = mountHomeFilterCounts(h, store);
  const assertCounts = expected => assert.deepEqual(Array.from(counts, effect => effect.value), expected.map(String));
  assertCounts([0, 0, 0]);
  store.add(new h.Todo(1, 'first task', '', false, 0));
  assertCounts([1, 1, 0]);
  store.add(new h.Todo(2, 'second task', '', false, 0));
  store.toggle(1);
  assertCounts([2, 1, 1]);
  store.filter = 'done';
  assert.equal(store.viewOf.length, 1);
  assertCounts([2, 1, 1]);
  store.remove(1);
  assertCounts([1, 1, 0]);
  store.restore(1);
  assertCounts([2, 1, 1]);
  store.clearDone();
  assertCounts([1, 1, 0]);
});
