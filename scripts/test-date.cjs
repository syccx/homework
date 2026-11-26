const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const ts = require('D:/DevEco Studio/sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript');
const file = path.join(__dirname, '../entry/src/main/ets/common/TodoDate.ets');
if (!fs.existsSync(file)) {
  console.error('FAIL: deadline date/time helper is missing');
  process.exit(1);
}
const box = { exports: {}, Date };
vm.runInNewContext(ts.transpileModule(fs.readFileSync(file, 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS }
}).outputText, box);
const { TodoDate } = box.exports;
const chosen = new Date(2026, 10, 27);
let d = new Date(TodoDate.withDate(0, chosen));
assert.equal(d.getFullYear(), 2026);
assert.equal(d.getMonth(), 10);
assert.equal(d.getDate(), 27);
assert.equal(d.getHours(), 18);
assert.equal(d.getMinutes(), 0);
assert.equal(d.getSeconds(), 0);
const old = new Date(2026, 0, 31, 9, 45, 37).getTime();
d = new Date(TodoDate.withDate(old, chosen));
assert.equal(d.getDate(), 27);
assert.equal(d.getHours(), 9);
assert.equal(d.getMinutes(), 45);
assert.equal(d.getSeconds(), 0);
d = new Date(TodoDate.withTime(d.getTime(), 22, 15));
assert.equal(d.getDate(), 27);
assert.equal(d.getHours(), 22);
assert.equal(d.getMinutes(), 15);
assert.equal(d.getMilliseconds(), 0);
assert.equal(TodoDate.label(0), '未设置');
assert.match(TodoDate.label(d.getTime()), /2026.*11.*27.*22:15/);
console.log('PASS: default deadline, date editing, time editing, full-year label, unset deadline');
