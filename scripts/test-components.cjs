// Evaluate the real TodoItem builder's AST expressions with the installed SDK parser.
// The recorded tree covers styles/events and gesture state, not native layout or hit testing.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const { test } = require('node:test');
const ts = require(process.env.TODO_TYPESCRIPT || 'D:/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript/lib/typescript.js');
const sourceRoot = path.resolve(__dirname, '../entry/src/main/ets');
const source = fs.readFileSync(path.join(sourceRoot, 'components/TodoItem.ets'), 'utf8');
const ast = ts.createSourceFile('TodoItem.ets', source, ts.ScriptTarget.Latest, true, ts.ScriptKind.ETS);
const component = ast.statements.find(node => node.name?.getText(ast) === 'TodoItem');
const build = component?.members.find(node => node.name?.getText(ast) === 'build');
assert.ok(build?.body, 'TodoItem must have its actual UI builder');
const compilerOptions = { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2021 };
const components = new Set(['Stack', 'Row', 'Column', 'Circle', 'SymbolGlyph', 'Text']);
function callChain(expression) {
  assert.ok(ts.isCallExpression(expression), 'Expected an ArkUI component or modifier call');
  const call = { name: undefined, args: expression.arguments };
  if (ts.isPropertyAccessExpression(expression.expression)) {
    call.name = expression.expression.name.text;
    return [...callChain(expression.expression.expression), call];
  }
  call.name = expression.expression.getText(ast);
  return [call];
}
function harness(done = false, description = 'task details') {
  const state = { deleted: [], toggled: [], edited: [] };
  const box = {
    exports: {}, Date, Math,
    Alignment: { End: 'End' }, FlexAlign: { End: 'End' }, HorizontalAlign: { Start: 'Start' },
    Color: { Transparent: 'transparent' }, FontWeight: { Medium: 'Medium' }, TextOverflow: { Ellipsis: 'Ellipsis' },
    PanDirection: { Horizontal: 'Horizontal' }, Visibility: { Visible: 'visible', Hidden: 'hidden', None: 'none' },
    $r: resource => resource,
    PanGesture: options => {
      const gesture = { options, callbacks: {} };
      for (const name of ['onActionStart', 'onActionUpdate', 'onActionEnd', 'onActionCancel']) {
        gesture[name] = callback => { gesture.callbacks[name] = callback; return gesture; };
      }
      return gesture;
    }
  };
  const helpers = ['common/Theme.ets', 'common/Sym.ets'].map(file => fs.readFileSync(path.join(sourceRoot, file), 'utf8')).join('\n').replace(/^import .*$/gm, '');
  vm.runInNewContext(ts.transpileModule(helpers, { compilerOptions }).outputText, box);
  Object.assign(box, box.exports);
  const methods = component.members.filter(node => node.name && ['overdue', 'timeLabel', 'relativeTime'].includes(node.name.getText(ast))).map(node => node.getText(ast)).join('\n');
  vm.runInNewContext(ts.transpileModule(`class Item { ${methods} } exports.Item = Item;`, { compilerOptions }).outputText, box);
  const item = new box.exports.Item();
  Object.assign(item, {
    todo: { id: 7, title: 'task title', description, done, priority: 1, dueAt: 0, createdAt: Date.now() },
    nowAt: Date.now(), offsetX: 0, startOffset: 0,
    onDelete: todo => state.deleted.push(todo), onToggle: todo => state.toggled.push(todo), onEdit: todo => state.edited.push(todo)
  });
  const evaluate = node => {
    const code = ts.transpileModule(`(function() { return (${node.getText(ast)}); })`, { compilerOptions }).outputText;
    return vm.runInNewContext(code, box).call(item);
  };
  const apply = (node, modifiers) => {
    for (const modifier of modifiers) node.props[modifier.name] = modifier.args.length === 1 ? evaluate(modifier.args[0]) : Array.from(modifier.args, evaluate);
  };
  const isComponent = statement => ts.isExpressionStatement(statement) && components.has(callChain(statement.expression)[0].name);
  function record(statements) {
    const nodes = [];
    for (let index = 0; index < statements.length; index++) {
      const statement = statements[index];
      if (ts.isIfStatement(statement)) {
        const branch = evaluate(statement.expression) ? statement.thenStatement : statement.elseStatement;
        if (branch) nodes.push(...record(ts.isBlock(branch) ? branch.statements : [branch]));
        continue;
      }
      assert.ok(isComponent(statement), `Expected a component, got ${statement.getText(ast)}`);
      const chain = callChain(statement.expression);
      const node = { type: chain[0].name, args: Array.from(chain[0].args, evaluate), props: {}, children: [] };
      apply(node, chain.slice(1));
      if (statements[index + 1] && ts.isBlock(statements[index + 1])) {
        node.children = record(statements[++index].statements);
        const modifiers = statements[index + 1];
        if (modifiers && ts.isExpressionStatement(modifiers) && !isComponent(modifiers)) {
          apply(node, callChain(modifiers.expression)); index++;
        }
      }
      nodes.push(node);
    }
    return nodes;
  }
  function descendants(node) { return [node, ...node.children.flatMap(descendants)]; }
  state.item = item;
  state.render = () => {
    const card = record(build.body.statements)[0];
    const foreground = card.children.find(node => node.props.translate);
    const deletion = card.children.find(node => descendants(node).some(child => child.type === 'Text' && child.args[0] === '删除'));
    const text = foreground.children.find(node => node.type === 'Column');
    assert.ok(foreground && deletion && text, 'Record foreground, delete layer and text from the actual builder');
    return { card, foreground, deletion, text, nodes: descendants(card) };
  };
  return state;
}
const hidden = node => node.props.opacity === 0 || ['hidden', 'none'].includes(node.props.visibility);

test('unswiped pending and completed cards hide and disable the delete layer', () => {
  for (const done of [false, true]) {
    const { deletion } = harness(done).render();
    assert.equal(hidden(deletion), true, `Delete text and red background must be hidden when done=${done}, offsetX=0`);
    assert.equal(deletion.props.enabled, false);
  }
});
test('completed cards keep an opaque foreground while weakening their text', () => {
  const pending = harness(false).render(); const completed = harness(true).render();
  assert.equal(completed.foreground.props.opacity ?? 1, 1, 'Completion must not make the card background transparent');
  assert.equal(completed.foreground.props.backgroundColor, pending.foreground.props.backgroundColor);
  assert.match(completed.foreground.props.backgroundColor, /^#[0-9a-f]{6}$/i);
  assert.ok((completed.text.props.opacity ?? 1) < (pending.text.props.opacity ?? 1), 'Completed text should retain its dimmed appearance');
});
test('the opaque card foreground fills the fixed height with and without description', () => {
  for (const description of ['', 'task details']) {
    const { foreground, card } = harness(true, description).render();
    assert.ok(foreground.props.height === '100%' || foreground.props.height === card.props.height, 'Foreground must cover the entire delete background');
  }
});
test('left swipe reveals deletion and closing or cancelling hides it again without changing callback wiring', () => {
  const h = harness(true); let tree = h.render(); const gesture = tree.foreground.props.gesture.callbacks;
  gesture.onActionStart(); gesture.onActionUpdate({ offsetX: -100 }); gesture.onActionEnd();
  assert.equal(h.item.offsetX, -96); tree = h.render(); assert.equal(hidden(tree.deletion), false); assert.equal(tree.deletion.props.enabled, true);
  tree.deletion.props.onClick(); assert.equal(h.deleted[0], h.item.todo);
  tree.foreground.children.find(node => node.type === 'Stack').props.onClick(); tree.text.props.onClick();
  assert.equal(h.toggled[0], h.item.todo); assert.equal(h.edited[0], h.item.todo);
  gesture.onActionCancel(); assert.equal(h.item.offsetX, 0); assert.equal(hidden(h.render().deletion), true);
  gesture.onActionStart(); gesture.onActionUpdate({ offsetX: -20 }); gesture.onActionEnd();
  assert.equal(h.item.offsetX, 0); assert.equal(hidden(h.render().deletion), true);
});
