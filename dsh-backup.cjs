// DSH 数据快照（node 版，不依赖 PowerShell/robocopy）
const fs = require('fs'), path = require('path'), os = require('os');
const HOME = process.env.USERPROFILE || os.homedir() || 'C:\\Users\\Administrator';
const SRC = path.join(HOME, '.dsh');
const path0 = require('path');
const ROOT = path0.join(__dirname, 'dsh-backups');
const LOG = path0.join(__dirname, 'dsh-backup.log');
const EXCL = new Set(['node_modules', 'dsh-runtimes', 'cache', 'dsh-purge', 'our-free-model', 'vendor', '.dsh-market', '.git']);
const force = process.argv.includes('--force');
const hours = 12;
function note(m) { try { fs.appendFileSync(LOG, new Date().toISOString() + '  ' + m + '\n'); } catch {} }
function ts() { const d = new Date(), p = n => String(n).padStart(2, '0'); return d.getFullYear() + p(d.getMonth() + 1) + p(d.getDate()) + '-' + p(d.getHours()) + p(d.getMinutes()) + p(d.getSeconds()); }
if (!fs.existsSync(SRC)) { note('SKIP no .dsh'); process.exit(0); }
fs.mkdirSync(ROOT, { recursive: true });
const snaps = fs.readdirSync(ROOT, { withFileTypes: true }).filter(d => d.isDirectory()).map(d => d.name).sort().reverse();
if (!force && snaps.length) {
  const st = fs.statSync(path.join(ROOT, snaps[0]));
  if ((Date.now() - st.mtimeMs) / 36e5 < hours) process.exit(0);
}
const dst = path.join(ROOT, ts());
let bytes = 0, files = 0;
try {
  fs.cpSync(SRC, dst, { recursive: true, filter: (s) => { try { const b = path.basename(s); if (EXCL.has(b)) return false; if (b.endsWith('.log')) return false; return true; } catch { return true; } }, errorOnExist: false, force: true, dereference: false });
} catch (e) { note('FAIL ' + e.message); process.exit(1); }
(function walk(d) { let es; try { es = fs.readdirSync(d, { withFileTypes: true }); } catch { return; } for (const x of es) { const f = path.join(d, x.name); if (x.isDirectory()) walk(f); else { try { bytes += fs.statSync(f).size; files++; } catch {} } } })(dst);
note('OK ' + path.basename(dst) + ' ' + (bytes / 1048576).toFixed(1) + 'MB files=' + files);
for (const old of snaps.slice(3)) { try { fs.rmSync(path.join(ROOT, old), { recursive: true, force: true }); } catch {} }
