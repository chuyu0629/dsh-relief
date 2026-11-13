// DSH 插件急救：启动失败时逐级禁用可疑插件（改 package.json 的 deps+bundles，node_modules 保留）
// 用法: node dsh-rescue.cjs --level 1|2 [--dry]
const fs = require('fs');
const path = require('path');
const HOME = process.env.USERPROFILE || 'C:\\Users\\Administrator';
const PROF = path.join(HOME, '.dsh', 'profiles', 'desktop');
const PATCHES = [path.join(HOME, '.dsh', 'cordis.patch.yml'), path.join(PROF, 'cordis.patch.yml')];
const PKG = path.join(PROF, 'package.json');
const NM = path.join(PROF, 'node_modules');

const argv = process.argv.slice(2);
const onlyArg = argv.find(a => a.startsWith('--packages='));
const only = onlyArg ? onlyArg.slice('--packages='.length).split(',').map(s => s.trim()).filter(Boolean) : [];
const lvArg = argv.find(a => a.startsWith('--level')) || '--level=1';
const level = only.length ? 0 : (Number(lvArg.split('=')[1] || 1) || 1);
const dry = argv.includes('--dry');
const stamp = new Date().toISOString().replace(/[-:T]/g, '').slice(0, 14);
const out = { level, dry, only, removedPackages: [], removedPatchIds: [], backups: [], errors: [] };

const isOfficial = n => /^@deepseek-ai\//.test(n);
const isPathLike = n => /^(\.|\/|[A-Za-z]:)/.test(n) || n.includes('\\') || n.includes(':');

function stripQuotes(s) {
  s = s.trim();
  if ((s[0] === '"' && s.endsWith('"')) || (s[0] === "'" && s.endsWith("'"))) return s.slice(1, -1);
  return s;
}
function parsePatch(text) {
  const lines = text.split(/\r?\n/);
  const blocks = []; let cur = null;
  for (let i = 0; i < lines.length; i++) {
    if (/^- id:/.test(lines[i])) {
      if (cur) { cur.end = i; blocks.push(cur); }
      cur = { start: i, end: lines.length, id: lines[i].replace(/^- id:\s*/, '').trim(), name: '' };
    } else if (cur) {
      const m = /^\s+name:\s*(.+)$/.exec(lines[i]);
      if (m && !cur.name) cur.name = stripQuotes(m[1]);
    }
  }
  if (cur) { cur.end = lines.length; blocks.push(cur); }
  return { lines, blocks };
}
function newestMtime(dir, depth) {
  let best = 0;
  try {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      if (e.name === 'node_modules') continue;
      const p = path.join(dir, e.name);
      if (e.isDirectory()) { if (depth > 0) best = Math.max(best, newestMtime(p, depth - 1)); continue; }
      best = Math.max(best, fs.statSync(p).mtimeMs);
    }
  } catch { }
  return best;
}

const pj = JSON.parse(fs.readFileSync(PKG, 'utf8'));
const deps = pj.dependencies || {};
const bundles = (pj.dsh && pj.dsh.profile && pj.dsh.profile.bundles) || [];
const candidates = [...new Set([...Object.keys(deps), ...bundles])].filter(n => !isOfficial(n));

const now = Date.now(), WINDOW = 24 * 3600 * 1000;
const drop = new Set();
if (only.length) {
  for (const name of only) {
    if (isOfficial(name)) { out.errors.push('skip-official:' + name); continue; }
    if (!candidates.includes(name)) { out.errors.push('not-installed:' + name); continue; }
    drop.add(name); out.removedPackages.push({ name, why: 'failed-plugin' });
  }
} else if (level === 2) {
  for (const name of candidates) { drop.add(name); out.removedPackages.push({ name, why: 'third-party-isolation' }); }
} else {
  const info = n => {
    const dir = path.join(NM, n);
    if (!fs.existsSync(dir)) return { name: n, why: 'missing-module', mt: Number.MAX_SAFE_INTEGER };
    const mt = newestMtime(dir, 2);
    return { name: n, why: '', mt };
  };
  let known = null;
  try {
    const bp = path.join(__dirname, 'dsh-golden', 'last-good-plugins.json');
    known = new Set(JSON.parse(fs.readFileSync(bp, 'utf8').replace(/^\uFEFF/, '')).packages || []);
  } catch { }
  const picked = new Set();
  if (known) {
    const fresh = candidates.filter(n => !known.has(n)).map(info).sort((a, b) => b.mt - a.mt);
    for (const s of fresh.slice(0, 3)) { picked.add(s.name); drop.add(s.name); out.removedPackages.push({ name: s.name, why: 'not-in-last-good' }); }
  }
  if (picked.size < 3) {
    const scored = candidates.filter(n => !picked.has(n)).map(info).filter(x => { if (!x.why) { if (now - x.mt < WINDOW) x.why = 'recent-change'; } return x.why; }).sort((a, b) => b.mt - a.mt);
    for (const s of scored.slice(0, 3 - picked.size)) { picked.add(s.name); drop.add(s.name); out.removedPackages.push({ name: s.name, why: s.why }); }
  }
}

if (drop.size && !dry) {
  const bak = PKG + '.bak-' + stamp + '-rescue' + level;
  fs.copyFileSync(PKG, bak); out.backups.push(bak);
  for (const n of Object.keys(deps)) if (drop.has(n)) delete deps[n];
  pj.dependencies = deps;
  pj.dsh.profile.bundles = bundles.filter(b => !drop.has(b));
  fs.writeFileSync(PKG, JSON.stringify(pj, null, 2) + '\n', 'utf8');
}

for (const file of PATCHES) {
  if (!fs.existsSync(file)) continue;
  const text = fs.readFileSync(file, 'utf8');
  const { lines, blocks } = parsePatch(text);
  const kill = blocks.filter(b => b.name && drop.has(b.name));
  if (!kill.length) continue;
  const drop2 = new Set();
  for (const b of kill) { out.removedPatchIds.push({ file, id: b.id, name: b.name }); for (let i = b.start; i < b.end; i++) drop2.add(i); }
  if (!dry) {
    const bak = file + '.bak-' + stamp + '-rescue' + level;
    fs.copyFileSync(file, bak); out.backups.push(bak);
    fs.writeFileSync(file, lines.filter((_, i) => !drop2.has(i)).join('\r\n').replace(/(\r\n)+$/, '\r\n'), 'utf8');
  }
}

try { require('fs').appendFileSync(path.join(__dirname, 'dsh-rescue.log'), new Date().toISOString() + ' ' + JSON.stringify(out) + '\n'); } catch { }
console.log(JSON.stringify(out));
