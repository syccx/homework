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
  state.fetch = (mode, proxy, sampleGroup) => { assert.equal(typeof state.ApiService.fetchRemoteTodos, 'function', 'API must expose remote scenario requests'); return state.ApiService.fetchRemoteTodos(mode, proxy, sampleGroup); };
  return state;
}
const plain = value => JSON.parse(JSON.stringify(value));
const settleResponse = list => ({ responseCode: 200, result: JSON.stringify(list) });
const groupedResponse = () => Array.from({ length: 10 }, (_, i) => ({ id: i + 1, title: `remote ${i + 1}`, completed: i === 0 || (i >= 5 && i < 9) }));

function pageStateLabels(store) {
  const page = fs.readFileSync(path.join(sourceRoot, 'pages/NetworkPage.ets'), 'utf8');
  const methods = ['scenarioLabel', 'updatedLabel'].map(name => {
    const start = page.indexOf(`  private ${name}(`); const end = page.indexOf('\n  }', start);
    assert.ok(start >= 0 && end > start, `Missing page method ${name}`);
    return page.slice(start, end + 4);
  }).join('\n');
  const code = ts.transpileModule(`class Page { ${methods} } exports.Page = Page;`, { compilerOptions: { module: ts.ModuleKind.CommonJS } }).outputText;
  const sandbox = { exports: {} }; vm.runInNewContext(code, sandbox); const instance = new sandbox.exports.Page(); instance.store = store;
  return { successful: instance.updatedLabel(), requested: instance.scenarioLabel(store.mode, store.sampleGroup) };
}

// Record the actual ArkUI builder tree to verify visibility and event wiring.
// Like test-components.cjs, this checks source behavior rather than native pixels/hit testing.
function networkPageHarness(store) {
  const pageSource = fs.readFileSync(path.join(sourceRoot, 'pages/NetworkPage.ets'), 'utf8');
  const ast = ts.createSourceFile('NetworkPage.ets', pageSource, ts.ScriptTarget.Latest, true, ts.ScriptKind.ETS);
  const component = ast.statements.find(node => node.name?.getText(ast) === 'NetworkPage');
  assert.ok(component?.members, 'NetworkPage must remain an ArkUI component');
  const builderMembers = component.members.filter(node => node.body && (node.name?.getText(ast) === 'build' || /@Builder\b/.test(node.getText(ast))));
  const builders = new Map(builderMembers.map(node => [node.name.getText(ast), node]));
  const methods = component.members.filter(node => node.body && !builderMembers.includes(node)).map(node => node.getText(ast)).join('\n');
  const compilerOptions = { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 };
  const enumeration = new Proxy({}, { get: (_, name) => String(name) });
  const box = {
    exports: {}, Date, Math, Number, JSON, NetworkStore: { instance: store },
    NavPathStack: class { pop() {} }, $r: resource => resource,
    FontWeight: enumeration, HorizontalAlign: enumeration, Alignment: enumeration,
    EdgeEffect: enumeration, BarState: enumeration, TextAlign: enumeration,
    InputType: enumeration, DataPanelType: enumeration, FlexAlign: enumeration,
    TextOverflow: enumeration, Visibility: enumeration, Color: enumeration
  };
  const helpers = ['common/Theme.ets', 'common/Sym.ets'].map(file => fs.readFileSync(path.join(sourceRoot, file), 'utf8')).join('\n').replace(/^import .*$/gm, '');
  vm.runInNewContext(ts.transpileModule(helpers, { compilerOptions }).outputText, box);
  Object.assign(box, box.exports);
  vm.runInNewContext(ts.transpileModule(`class Page { ${methods} } exports.Page = Page;`, { compilerOptions }).outputText, box);
  const page = new box.exports.Page();
  function evaluate(node, locals = {}) {
    const expression = node.getText(ast).replace(/\$\$this\./g, 'this.');
    const code = ts.transpileModule(`(function(${Object.keys(locals).join(',')}) { return (${expression}); })`, { compilerOptions }).outputText;
    return vm.runInNewContext(code, box).call(page, ...Object.values(locals));
  }
  for (const member of component.members) {
    if (member.initializer && member.name) page[member.name.getText(ast)] = evaluate(member.initializer);
  }
  // Always bind the supplied real store, even if the component later changes singleton access syntax.
  page.store = store;
  function chain(expression) {
    assert.ok(ts.isCallExpression(expression), `Expected ArkUI call: ${expression.getText(ast)}`);
    const call = { args: expression.arguments, name: undefined };
    if (ts.isPropertyAccessExpression(expression.expression) && ts.isCallExpression(expression.expression.expression)) {
      call.name = expression.expression.name.text;
      return [...chain(expression.expression.expression), call];
    }
    call.name = expression.expression.getText(ast);
    return [call];
  }
  function record(statements, locals = {}) {
    const nodes = [];
    for (let index = 0; index < statements.length; index++) {
      const statement = statements[index];
      if (ts.isIfStatement(statement)) {
        const branch = evaluate(statement.expression, locals) ? statement.thenStatement : statement.elseStatement;
        if (branch) nodes.push(...record(ts.isBlock(branch) ? branch.statements : [branch], locals));
        continue;
      }
      assert.ok(ts.isExpressionStatement(statement), `Unexpected builder statement: ${statement.getText(ast)}`);
      const calls = chain(statement.expression); const first = calls[0];
      if (first.name.startsWith('this.') && builders.has(first.name.slice(5))) {
        nodes.push(...record(builders.get(first.name.slice(5)).body.statements, locals));
        continue;
      }
      if (first.name === 'ForEach') {
        const items = evaluate(first.args[0], locals); const callback = first.args[1];
        assert.ok(ts.isArrowFunction(callback) && ts.isBlock(callback.body), 'Record actual ForEach content');
        items.forEach((item, itemIndex) => {
          const values = [item, itemIndex]; const scope = { ...locals };
          callback.parameters.forEach((parameter, i) => { scope[parameter.name.getText(ast)] = values[i]; });
          nodes.push(...record(callback.body.statements, scope));
        });
        continue;
      }
      const node = { type: first.name, args: Array.from(first.args, arg => evaluate(arg, locals)), props: {}, children: [] };
      const apply = modifiers => {
        for (const modifier of modifiers) node.props[modifier.name] = modifier.args.length === 1 ? evaluate(modifier.args[0], locals) : Array.from(modifier.args, arg => evaluate(arg, locals));
      };
      apply(calls.slice(1));
      if (statements[index + 1] && ts.isBlock(statements[index + 1])) {
        node.children = record(statements[++index].statements, locals);
        const modifiers = statements[index + 1];
        // The SDK parser omits the leading dot in getText() for post-block modifiers.
        if (modifiers && ts.isExpressionStatement(modifiers) && /^[a-z]/.test(chain(modifiers.expression)[0].name) && !chain(modifiers.expression)[0].name.startsWith('this.')) {
          apply(chain(modifiers.expression)); index++;
        }
      }
      nodes.push(node);
    }
    return nodes;
  }
  const flatten = node => [node, ...node.children.flatMap(flatten)];
  return {
    page,
    render: () => record(builders.get('build').body.statements).flatMap(flatten),
    find: (nodes, id) => nodes.find(node => node.props.id === id)
  };
}

test('ordinary example-task view keeps progress and tasks visible while hiding demonstration controls', async () => {
  const h = harness(); const store = h.store(); await store.load();
  const ui = networkPageHarness(store); const nodes = ui.render();
  assert.equal(ui.page.showDemoSettings, false, 'Demonstration settings must start collapsed');
  for (const id of ['network-chart', 'network-list', 'network-refresh', 'network-demo-settings-toggle']) assert.ok(ui.find(nodes, id), `Primary view must expose ${id}`);
  for (const id of ['network-normal', 'network-empty', 'network-error', 'network-proxy-host', 'network-proxy-toggle']) assert.equal(ui.find(nodes, id), undefined, `Primary view must not expose ${id}`);
  assert.equal(ui.find(nodes, 'network-refresh').props.enabled, true);
  let finish;
  h.respond = () => new Promise(resolve => { finish = resolve; });
  ui.find(nodes, 'network-refresh').props.onClick();
  assert.equal(h.requests.at(-1).url, 'https://jsonplaceholder.typicode.com/todos');
  let refreshing = ui.render();
  assert.ok(ui.find(refreshing, 'network-loading'));
  assert.equal(ui.find(refreshing, 'network-refresh').props.enabled, false, 'Refresh stays disabled while its request is in flight');
  assert.ok(ui.find(refreshing, 'network-list'), 'Refreshing should keep the existing task content visible');
  finish(settleResponse([{ id: 7, title: 'updated example', completed: false }]));
  await new Promise(resolve => setImmediate(resolve));
  refreshing = ui.render();
  assert.equal(ui.find(refreshing, 'network-loading'), undefined);
  assert.equal(ui.find(refreshing, 'network-refresh').props.enabled, true);
  assert.ok(ui.find(refreshing, 'network-item-7'), 'The real refresh callback must replace the displayed task data');
});

test('demonstration settings reveal scenario controls only after an explicit toggle and collapse again', async () => {
  const h = harness(); const store = h.store(); await store.load();
  const ui = networkPageHarness(store); const before = h.requests.length;
  let nodes = ui.render();
  const toggle = ui.find(nodes, 'network-demo-settings-toggle');
  assert.equal(typeof toggle?.props.onClick, 'function', 'Provide an accessible settings toggle');
  toggle.props.onClick(); nodes = ui.render();
  assert.equal(ui.page.showDemoSettings, true);
  for (const id of ['network-normal', 'network-empty', 'network-error', 'network-proxy-toggle']) assert.ok(ui.find(nodes, id), `Expanded settings must expose ${id}`);
  assert.equal(h.requests.length, before, 'Opening settings alone must not issue a request');
  ui.find(nodes, 'network-proxy-toggle').props.onClick(); nodes = ui.render();
  for (const id of ['network-proxy-host', 'network-proxy-port', 'network-proxy-apply', 'network-proxy-system']) assert.ok(ui.find(nodes, id), `Proxy fields must remain reachable through settings: ${id}`);
  assert.equal(h.requests.length, before, 'Opening the proxy form alone must not issue a request');
  ui.find(nodes, 'network-demo-settings-toggle').props.onClick(); nodes = ui.render();
  assert.equal(ui.page.showDemoSettings, false);
  assert.equal(ui.page.proxyOpen, false, 'Collapsing demonstration settings also hides the nested proxy form');
  assert.equal(ui.find(nodes, 'network-error'), undefined);
  assert.ok(ui.find(nodes, 'network-list'), 'Closing settings must preserve visible task content');
});

test('failure and empty demonstrations offer a normal return path while advanced retry keeps its current request', async () => {
  const h = harness(); const store = h.store(); h.respond = async () => settleResponse(groupedResponse()); await store.load('normal', 2);
  h.respond = async () => ({ responseCode: 404, result: '{}' }); await store.load('error');
  const ui = networkPageHarness(store); let nodes = ui.render();
  assert.ok(ui.find(nodes, 'network-chart'), 'A failed refresh must retain the last successful progress');
  assert.ok(ui.find(nodes, 'network-list'), 'A failed refresh must retain the last successful tasks');
  assert.ok(nodes.some(node => node.type === 'Text' && /上次|之前/.test(node.args[0]) && /结果|任务/.test(node.args[0])), 'Explain that the retained content belongs to the previous load');
  assert.equal(nodes.some(node => node.type === 'Text' && node.args[0] === store.error), false, 'Raw transport errors should stay inside the optional demonstration settings');
  const normal = ui.find(nodes, 'network-return-normal');
  assert.equal(typeof normal?.props.onClick, 'function', 'Offer a visible escape from an intentionally failing demo');
  // Retrying an intentionally failing request belongs to the explicitly expanded demo controls.
  ui.find(nodes, 'network-demo-settings-toggle').props.onClick(); nodes = ui.render();
  const retry = ui.find(nodes, 'network-retry');
  assert.equal(typeof retry?.props.onClick, 'function');
  retry.props.onClick(); await store.load();
  assert.equal(h.requests.at(-1).url, 'https://jsonplaceholder.typicode.com/this-route-does-not-exist', 'Retry should preserve the selected scenario');
  h.respond = async () => settleResponse(groupedResponse());
  normal.props.onClick(); await new Promise(resolve => setImmediate(resolve));
  assert.equal(store.mode, 'normal'); assert.equal(store.sampleGroup, 2);
  assert.equal(store.error, ''); assert.equal(store.items[0].id, 6);
  h.respond = async () => settleResponse([]); await store.load('empty');
  ui.page.showDemoSettings = false; nodes = ui.render();
  assert.ok(ui.find(nodes, 'network-empty-state'));
  assert.equal(ui.find(nodes, 'network-chart'), undefined, 'A successful empty result must hide the old progress');
  assert.equal(ui.find(nodes, 'network-list'), undefined, 'A successful empty result must hide the old tasks');
  const emptyReturn = ui.find(nodes, 'network-return-normal');
  assert.equal(typeof emptyReturn?.props.onClick, 'function', 'Empty demonstrations also need an ordinary recovery action');
  h.respond = async () => settleResponse(groupedResponse()); emptyReturn.props.onClick();
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(store.mode, 'normal'); assert.equal(store.sampleGroup, 2);
  assert.equal(store.items[0].id, 6); assert.ok(ui.find(ui.render(), 'network-list'));
});

test('entering while an error-demo request is in flight eventually restores normal tasks and closes settings', async () => {
  const h = harness(); const store = h.store(); h.respond = async () => settleResponse(groupedResponse()); await store.load('normal', 2);
  let finish;
  h.respond = () => new Promise(resolve => { finish = resolve; });
  const errorRequest = store.load('error');
  assert.equal(store.loading, true); assert.equal(store.mode, 'error');
  const ui = networkPageHarness(store); ui.page.showDemoSettings = true; ui.page.proxyOpen = true;
  ui.page.aboutToAppear();
  assert.equal(ui.page.showDemoSettings, false); assert.equal(ui.page.proxyOpen, false);
  h.respond = async () => settleResponse(groupedResponse());
  finish({ responseCode: 404, result: '{}' }); await errorRequest;
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(store.mode, 'normal', 'Entry must recover after the merged error request settles');
  assert.equal(store.loading, false); assert.equal(store.error, ''); assert.equal(store.items[0].id, 6);
  assert.deepEqual(h.requests.map(request => request.url), [
    'https://jsonplaceholder.typicode.com/todos',
    'https://jsonplaceholder.typicode.com/this-route-does-not-exist',
    'https://jsonplaceholder.typicode.com/todos'
  ]);
});

test('normal groups take different five-item slices from each fresh response and preserve the default API', async () => {
  const h = harness(); h.respond = async () => settleResponse(groupedResponse());
  assert.deepEqual(plain((await h.fetch('normal')).map(item => item.id)), [1, 2, 3, 4, 5]);
  const second = await h.fetch('normal', undefined, 2);
  assert.deepEqual(plain(second.map(item => item.id)), [6, 7, 8, 9, 10]);
  assert.equal(second.filter(item => item.done).length, 4);
  h.respond = async () => settleResponse(groupedResponse().map(item => ({ ...item, completed: false })));
  assert.equal((await h.fetch('normal', undefined, 2)).filter(item => item.done).length, 0);
  assert.equal(h.requests.length, 3); assert.ok(h.requests.every(request => request.url === 'https://jsonplaceholder.typicode.com/todos'));
});
test('invalid normal sample groups fail before opening a request', async () => {
  const h = harness();
  for (const sampleGroup of [0, 3, -1, 1.5, NaN]) await assert.rejects(h.fetch('normal', undefined, sampleGroup), /分组/);
  assert.equal(h.requests.length, 0); assert.equal(h.destroys, 0);
});
test('invalid Store groups preserve the last valid selection and ordinary refresh remains usable', async () => {
  const h = harness(); const store = h.store(); h.respond = async () => settleResponse(groupedResponse()); await store.load('normal', 2);
  for (const sampleGroup of [3, 0, -1, 1.5, NaN]) {
    const items = store.items; const updated = store.lastUpdatedAt; const requestCount = h.requests.length;
    await store.load('normal', sampleGroup);
    assert.equal(store.sampleGroup, 2); assert.equal(store.mode, 'normal'); assert.equal(store.lastSuccessfulGroup, 2);
    assert.equal(store.items, items); assert.equal(store.lastUpdatedAt, updated); assert.equal(store.loading, false); assert.match(store.error, /分组/);
    assert.equal(h.requests.length, requestCount); await store.load();
    assert.equal(h.requests.length, requestCount + 1); assert.equal(store.error, ''); assert.equal(store.items[0].id, 6);
  }
});
test('invalid Store modes preserve the last valid selection and ordinary refresh remains usable', async () => {
  const h = harness(); const store = h.store(); h.respond = async () => settleResponse(groupedResponse()); await store.load('normal', 2);
  for (const mode of ['', 'unsupported', 'https://untrusted.invalid']) {
    const items = store.items; const updated = store.lastUpdatedAt; const requestCount = h.requests.length;
    await store.load(mode);
    assert.equal(store.mode, 'normal'); assert.equal(store.sampleGroup, 2); assert.equal(store.lastSuccessfulMode, 'normal');
    assert.equal(store.items, items); assert.equal(store.lastUpdatedAt, updated); assert.equal(store.loading, false); assert.match(store.error, /场景/);
    assert.equal(h.requests.length, requestCount); await store.load();
    assert.equal(h.requests.length, requestCount + 1); assert.equal(store.error, ''); assert.equal(store.items[0].id, 6);
  }
});
test('switching normal sample groups requests again, changes chart values and refreshes the selected group', async () => {
  const h = harness(); const store = h.store(); h.respond = async () => settleResponse(groupedResponse());
  await store.load(); assert.equal(store.sampleGroup, 1); assert.equal(store.lastSuccessfulGroup, 1); assert.deepEqual(plain(store.chartValues), [1, 4]);
  assert.equal(typeof store.loadNextGroup, 'function', 'Remote chart needs a real-data group switch');
  await store.loadNextGroup(); assert.equal(store.sampleGroup, 2); assert.equal(store.lastSuccessfulGroup, 2); assert.deepEqual(plain(store.chartValues), [4, 1]);
  assert.equal(store.items[0].id, 6); await store.load(); assert.equal(store.items[0].id, 6); assert.equal(store.sampleGroup, 2);
  await store.loadNextGroup(); assert.equal(store.sampleGroup, 1); assert.equal(store.items[0].id, 1); assert.equal(h.requests.length, 4);
});
test('failed group requests preserve successful group labels and retry the selected sample', async () => {
  const h = harness(); const store = h.store(); h.respond = async () => settleResponse(groupedResponse()); await store.load();
  const items = store.items; const updated = store.lastUpdatedAt;
  assert.equal(typeof store.loadNextGroup, 'function', 'Remote chart needs a real-data group switch');
  h.respond = async () => ({ responseCode: 503, result: '{}' }); await store.loadNextGroup();
  assert.equal(store.sampleGroup, 2); assert.equal(store.lastSuccessfulGroup, 1); assert.equal(store.items, items); assert.equal(store.lastUpdatedAt, updated);
  assert.deepEqual(plain(store.chartValues), [1, 4]); const labels = pageStateLabels(store);
  assert.match(labels.requested, /第 2 组/); assert.match(labels.successful, /第 1 组/); assert.doesNotMatch(labels.successful, /第 2 组/);
  h.respond = async () => settleResponse(groupedResponse()); await store.load();
  assert.equal(store.error, ''); assert.equal(store.lastSuccessfulGroup, 2); assert.equal(store.items[0].id, 6); assert.match(pageStateLabels(store).successful, /第 2 组/);
});
test('empty and error scenarios keep the chosen normal group for a clear return to normal', async () => {
  const h = harness(); const store = h.store(); h.respond = async () => settleResponse(groupedResponse()); await store.load();
  assert.equal(typeof store.loadNextGroup, 'function', 'Remote chart needs a real-data group switch'); await store.loadNextGroup();
  h.respond = async () => settleResponse([]); await store.load('empty'); assert.equal(store.sampleGroup, 2); assert.equal(pageStateLabels(store).successful.includes('第 2 组'), false);
  h.respond = async () => ({ responseCode: 404, result: '{}' }); await store.load('error'); assert.equal(store.sampleGroup, 2);
  h.respond = async () => settleResponse(groupedResponse()); await store.load('normal'); assert.equal(store.items[0].id, 6); assert.equal(store.lastSuccessfulGroup, 2);
});
test('normal sample switch is accessible and the chart names the successful source group', () => {
  const page = fs.readFileSync(path.join(sourceRoot, 'pages/NetworkPage.ets'), 'utf8');
  assert.ok(page.includes(".id('network-next-group')")); assert.match(page, /\.onClick\(\(\) => \{ this\.store\.loadNextGroup\(\); \}\)/);
  const chart = page.slice(page.indexOf('  chart() {'), page.indexOf('  remoteList() {'));
  assert.match(chart, /scenarioLabel\(this\.store\.lastSuccessfulMode, this\.store\.lastSuccessfulGroup\)/);
});

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
  assert.match(page, /不写入文件/); assert.match(page, /\.align\(Alignment\.Top\)/);
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
  const calls = []; const store = { mode: 'normal', load: (...args) => { calls.push(args); return Promise.resolve(); } };
  const ui = networkPageHarness(store); ui.page.showDemoSettings = true; ui.page.proxyOpen = true;
  ui.page.aboutToAppear();
  assert.deepEqual(calls, [['normal']], 'Page entry requests ordinary tasks explicitly');
  assert.equal(ui.page.showDemoSettings, false); assert.equal(ui.page.proxyOpen, false);
  assert.match(home, /pushPathByName\('Network', null\)/); assert.match(home, /示例任务/); assert.match(index, /name === 'Network'/); assert.match(index, /NetworkPage\(\{/);
  assert.match(page, /NavDestination\(\)/); assert.match(page, /Refresh\(/); assert.match(page, /Scroll\(\)/); assert.match(page, /onRefreshing/);
  assert.match(page, /DataPanel\(\{[\s\S]*?values: this\.store\.chartValues[\s\S]*?type: DataPanelType\.Circle/);
  assert.match(page, /if \(this\.store\.items\.length > 0\)/); assert.match(page, /远端/);
  for (const id of ['network-refresh', 'network-normal', 'network-empty', 'network-error', 'network-retry', 'network-chart']) assert.ok(page.includes(`.id('${id}')`), `Missing test id ${id}`);
});
