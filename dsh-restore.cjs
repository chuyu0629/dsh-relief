// DSH 数据还原（node 版）：只补缺失或更旧的文件，不覆盖更新的数据
const fs = require('fs'), path = require('path'), os = require('os');
const HOME = process.env.USERPROFILE || os.homedir() || 'C:\\Users\\Administrator';
const DST = path.join(HOME, '.dsh');
const path0 = require('path');
const ROOT = path0.join(__dirname, 'dsh-backups');
const LOG = path0.join(__dirname, 'dsh-backup.log');
function note(m) { try { fs.appendFileSync(LOG, new Date().toISOString() + '  ' + m + '\n'); } catch {} }
const snaps = fs.existsSync(ROOT) ? fs.readdirSync(ROOT, { withFileTypes: true }).filter(d => d.isDirectory()).map(d => d.name).filter(n => !/^prescue-/.test(n)).sort().reverse() : [];
if (!snaps.length) { console.log('没有可用快照'); note('RESTORE no snapshot'); process.exit(2); }
const SRC = path.join(ROOT, snaps[0]);
let copied = 0, skipped = 0;
(function walk(dir, rel) {
  let es; try { es = fs.readdirSync(dir, { withFileTypes: true }); } catch { return; }
  for (const x of es) {
    const s = path.join(dir, x.name), r = rel ? rel + '/' + x.name : x.name, d = path.join(DST, r);
    if (x.isDirectory()) { try { fs.mkdirSync(d, { recursive: true }); } catch {} walk(s, r); continue; }
    try {
      if (!fs.existsSync(d)) { fs.copyFileSync(s, d); copied++; continue; }
      const a = fs.statSync(s), b = fs.statSync(d);
      if (a.mtimeMs > b.mtimeMs + 1000 && a.size !== b.size) { fs.copyFileSync(s, d); copied++; } else skipped++;
    } catch {}
  }
})(SRC, '');
note('RESTORE from ' + snaps[0] + ' copied=' + copied + ' skipped=' + skipped);
console.log('已从快照 ' + snaps[0] + ' 补齐，新增/更新 ' + copied + ' 个文件');
