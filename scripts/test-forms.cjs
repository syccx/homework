const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const root = path.resolve(__dirname, '..');
const sdk = process.env.DEVECO_SDK_HOME || 'D:/DevEco Studio/sdk';
const ts = require(path.join(sdk, 'default/openharmony/ets/build-tools/ets-loader/node_modules/typescript'));
const source = 'entry/src/main/ets/';
const tick = () => new Promise(resolve => setImmediate(resolve));

function fixture(todos) {
  const disk = new Map([['todo_store', { todos_json: JSON.stringify(todos) }]]);
  const cache = new Map();
  const updates = [];
  let published = [{ formId: 'saved-widget', bundleName: 'com.example.todoapp',
    moduleName: 'entry', abilityName: 'EntryFormAbility', formName: 'widget' }];
  const preferences = {
    removePreferencesFromCacheSync: (_, name) => cache.delete(name),
    getPreferencesSync: (_, { name }) => {
      if (!cache.has(name)) cache.set(name, { ...(disk.get(name) || {}) });
      return { getSync: (key, fallback) => cache.get(name)[key] ?? fallback };
    }
  };
  const provider = {
    getPublishedRunningFormInfos: async () => published,
    updateForm: async (id, data) => { updates.push({ id, ...data }); }
  };
  const formKit = { FormExtensionAbility: class {}, formInfo: { FormState: { READY: 0 } },
    formBindingData: { createFormBindingData: obj => ({ ...obj }) }, formProvider: provider };
  const mocks = {
    '@kit.FormKit': formKit,
    '@kit.ArkData': { preferences },
    '@kit.AbilityKit': {},
    '@kit.PerformanceAnalysisKit': { hilog: { error() {}, warn() {} } },
    '../viewmodel/TodoStore': { TodoStore: { registerForm() {}, unregisterForm() {}, instance: { todoCount: 0 } } },
    '../model/Todo': { Todo: class {} }
  };
  const modules = new Map();
  function load(relative) {
    if (modules.has(relative)) return modules.get(relative).exports;
    const file = path.join(root, source, relative);
    const output = ts.transpileModule(fs.readFileSync(file, 'utf8'), {
      compilerOptions: { target: ts.ScriptTarget.ES2020, module: ts.ModuleKind.CommonJS }
    }).outputText;
    const mod = { exports: {} };
    modules.set(relative, mod);
    const requireMock = name => {
      if (mocks[name]) return mocks[name];
      if (name.startsWith('.')) {
        return load(path.posix.normalize(path.posix.join(path.posix.dirname(relative), name + '.ets')));
      }
      throw new Error('Unexpected import: ' + name);
    };
    vm.runInNewContext('(function(require,module,exports){' + output + '\n})', {}, { filename: file })(requireMock, mod, mod.exports);
    return mod.exports;
  }
  return { load, disk, updates, provider, setPublished: value => { published = value; } };
}

test('system refresh reads saved tasks after the app process restarts', async () => {
  const f = fixture([{ title: '冷启动后仍保留', done: false, deleted: false, createdAt: 1 }]);
  const Ability = f.load('entryformability/EntryFormAbility.ets').default;
  const ability = new Ability();
  ability.context = {};
  await ability.onUpdateForm('saved-widget');
  await tick();
  assert.equal(f.updates.at(-1)?.count, '1');
  assert.equal(f.updates.at(-1)?.latest, '冷启动后仍保留');
});

test('adding a widget shows the newest active task and ignores trash', () => {
  const f = fixture([
    { title: '旧任务', done: false, deleted: false, createdAt: 1 },
    { title: '新任务', done: false, deleted: false, createdAt: 2 },
    { title: '回收站', done: false, deleted: true, createdAt: 3 }
  ]);
  const Ability = f.load('entryformability/EntryFormAbility.ets').default;
  const ability = new Ability();
  ability.context = {};
  const result = ability.onAddForm({ parameters: { 'ohos.extra.param.key.form_identity': 'widget' } });
  assert.equal(result.count, '2');
  assert.equal(result.latest, '新任务');
});

test('system refresh does not reuse a stale preferences snapshot', async () => {
  const f = fixture([{ title: '旧值', done: false, createdAt: 1 }]);
  const Ability = f.load('entryformability/EntryFormAbility.ets').default;
  const ability = new Ability();
  ability.context = {};
  ability.onAddForm({ parameters: {} });
  f.disk.set('todo_store', { todos_json: JSON.stringify([{ title: '刚保存', done: false, createdAt: 2 }]) });
  await ability.onUpdateForm('saved-widget');
  await tick();
  assert.equal(f.updates.at(-1)?.latest, '刚保存');
});

test('app changes reach existing widgets without an in-memory form registry', async () => {
  assert.ok(fs.existsSync(path.join(root, source, 'common/FormService.ets')), 'FormService must query published widgets');
  const f = fixture([]);
  f.setPublished([
    { formId: 'restored', bundleName: 'com.example.todoapp', moduleName: 'entry', abilityName: 'EntryFormAbility', formName: 'widget' },
    { formId: 'other', bundleName: 'com.other.app', moduleName: 'entry', abilityName: 'Other', formName: 'widget' }
  ]);
  f.load('common/FormService.ets').FormService.push([{ title: '新状态', done: false, deleted: false, createdAt: 1 }]);
  await tick();
  assert.equal(f.updates.length, 1);
  assert.equal(f.updates[0].id, 'restored');
  assert.equal(f.updates[0].latest, '新状态');
});

test('rapid edits finish with the newest widget snapshot', async () => {
  assert.ok(fs.existsSync(path.join(root, source, 'common/FormService.ets')), 'FormService must serialize widget updates');
  const f = fixture([]);
  let release;
  const gate = new Promise(resolve => { release = resolve; });
  f.provider.updateForm = async (id, data) => {
    if (data.latest === '第一次') await gate;
    f.updates.push({ id, ...data });
  };
  const service = f.load('common/FormService.ets').FormService;
  service.push([{ title: '第一次', done: false, createdAt: 1 }]);
  await tick();
  service.push([{ title: '最后一次', done: false, createdAt: 2 }]);
  release();
  await tick();
  await tick();
  assert.equal(f.updates.at(-1)?.latest, '最后一次');
});

test('network permission and scheduled widget refresh are configured', () => {
  const module = JSON.parse(fs.readFileSync(path.join(root, 'entry/src/main/module.json5'), 'utf8'));
  assert.ok(module.module.requestPermissions?.some(item => item.name === 'ohos.permission.INTERNET'));
  const forms = JSON.parse(fs.readFileSync(path.join(root, 'entry/src/main/resources/base/profile/form_config.json'), 'utf8'));
  assert.equal(forms.forms[0].updateEnabled, true);
});
