const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const ts = require('D:/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
function pageClass(name, store, nav, clipboard = {}) {
  let source = fs.readFileSync(path.join(__dirname, `../entry/src/main/ets/pages/${name}.ets`), 'utf8');
  source = source.slice(0, source.indexOf('  build()')) + '\n}';
  source = source.replace('export struct', 'export class').replace(/@(?:ComponentV2|Param|Local|Require)\s*/g, '');
  const ctx = { exports: {}, Date, NavPathStack: class {}, require: (key) => {
    if (key.includes('TodoStore')) return { TodoStore: { instance: store } };
    if (key.includes('/TodoDate')) return {};
    if (key.includes('/Todo')) return { Todo: class { constructor(id,title,description,done,priority,createdAt,dueAt) {Object.assign(this,{id,title,description,done,priority,createdAt,dueAt});} } };
    if (key.includes('BasicServicesKit')) return { pasteboard: clipboard };
    return {};
  }};
  vm.runInNewContext(ts.transpileModule(source, {compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText, ctx);
  const page = new ctx.exports[name](); page.navPathStack = nav; return page;
}
let failures=0;
function test(name, fn) { try { fn(); console.log('PASS:',name); } catch(e) { failures++; console.error('FAIL:',name, e.message); } }
test('progress excludes recycled items',()=>{
 const store={todos:[{done:true},{done:false,deleted:true}],doneCount:1,todoCount:0};
 assert.equal(pageClass('HomePage',store,{}).progress,1);
});
test('zero active items has zero progress',()=>{
 assert.equal(pageClass('HomePage',{todos:[{deleted:true}],doneCount:0,todoCount:0},{}).progress,0);
});
test('empty title is blocked without writing',()=>{
 let writes=0; const p=pageClass('AddTodoPage',{add(){writes++}},{});p.title='  ';p.save();assert.equal(p.showTitleError,true);assert.equal(writes,0);
});
test('successful creation returns to visible unfiltered task list',()=>{
 let pops=0;let created; const store={inTrash:true,filter:'done',keyword:'hidden',add(t){created=t;return true}};
 const p=pageClass('AddTodoPage',store,{pop(){pops++}});p.title='  task  ';p.desc=' description ';p.save();
 assert.equal(created.title,'task');assert.equal(created.description,'description');assert.equal(pops,1);assert.equal(store.inTrash,false);assert.equal(store.filter,'all');assert.equal(store.keyword,'');
});
test('failed persistence keeps the form open',()=>{
 let pops=0; const p=pageClass('AddTodoPage',{storageError:'磁盘不可写',add(){return false}},{pop(){pops++}});p.title='task';p.save();assert.equal(pops,0);assert.equal(p.saveError,'磁盘不可写');
});
test('editing loads the latest route instance and preserves task id',()=>{
 let editId;const p=pageClass('AddTodoPage',{byId(){return {id:2,title:'new',description:'',priority:1,dueAt:0}},edit(id){editId=id;return true}},{getParamByName(){return [{id:1,title:'old'},{id:2,title:'new',description:'',priority:1,dueAt:0}]},pop(){}});
 p.aboutToAppear();assert.equal(p.title,'new');p.save();assert.equal(editId,2);
});
test('editing resolves a stale route snapshot from current saved state',()=>{
 const p=pageClass('AddTodoPage',{byId(){return {id:8,title:'current title',description:'current description',priority:0,dueAt:0}}}, {getParamByName(){return [{id:8,title:'stale title',description:'old',priority:0,dueAt:0}]}});
 p.aboutToAppear();assert.equal(p.title,'current title');assert.equal(p.desc,'current description');
});
test('unsaved back action offers confirmation',()=>{
 let pops=0;let dialog;const p=pageClass('AddTodoPage',{}, {getParamByName(){return []},pop(){pops++}});
 p.getUIContext=()=>({showAlertDialog(d){dialog=d}});p.aboutToAppear();p.title='draft';p.goBack();assert.equal(pops,0);assert.ok(dialog);dialog.primaryButton.action();assert.equal(pops,0);dialog.secondaryButton.action();assert.equal(pops,1);
});
process.exitCode=failures?1:0;
