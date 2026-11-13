// DSH 依赖与配置自检（只读）：输出 JSON 报告
// 用法: node dsh-check.cjs [--root=DIR]
const fs = require('fs');
const path = require('path');
const HOME = process.env.USERPROFILE || 'C:\\Users\\Administrator';
const PROF = path.join(HOME, '.dsh', 'profiles', 'desktop');
const NM = path.join(PROF, 'node_modules');
const PKG = path.join(PROF, 'package.json');
const PATCHES = [path.join(HOME, '.dsh', 'cordis.patch.yml'), path.join(PROF, 'cordis.patch.yml')];
const argv = process.argv.slice(2);
const rootArg = argv.find(a => a.startsWith('--root='));
const ROOT = rootArg ? rootArg.slice(7) : __dirname;

const res = {
  ok: true,
  deps: { missing: [], broken: [] },
  bundles: { missing: [] },
  patch: { nameMismatch: [], missingPackage: [] },
  baseline: { exists: false, newPlugins: [] },
  notes: []
};

function readJson(p) { return JSON.parse(fs.readFileSync(p, 'utf8').replace(/^\uFEFF/, '')); }
function stripQuotes(s) { s = s.trim(); if ((s[0] === '"' && s.endsWith('"')) || (s[0] === "'" && s.endsWith("'"))) return s.slice(1, -1); return s; }
function parsePatch(text) {
  const lines = text.split(/\r?\n/); const blocks = []; let cur = null;
  for (let i = 0; i < lines.length; i++) {
    if (/^- id:/.test(lines[i])) { if (cur) { cur.end = i; blocks.push(cur); } cur = { start: i, end: lines.length, id: lines[i].replace(/^- id:\s*/, '').trim(), name: '' }; }
    else if (cur) { const m = /^\s+name:\s*(.+)$/.exec(lines[i]); if (m && !cur.name) cur.name = stripQuotes(m[1]); }
  }
  if (cur) { cur.end = lines.length; blocks.push(cur); }
  return { lines, blocks };
}

let pj = null;
try { pj = readJson(PKG); } catch (e) { res.ok = false; res.notes.push('package.json parse error: ' + e.message); }

if (pj) {
  const deps = pj.dependencies || {};
  const bundles = (pj.dsh && pj.dsh.profile && pj.dsh.profile.bundles) || [];
  for (const name of Object.keys(deps)) {
    const dir = path.join(NM, name);
    if (!fs.existsSync(dir)) { res.deps.missing.push(name); continue; }
    const pp = path.join(dir, 'package.json');
    if (!fs.existsSync(pp)) { res.deps.broken.push(name); continue; }
    try { readJson(pp); } catch { res.deps.broken.push(name); }
  }
  for (const name of bundles) {
    if (/^@deepseek-ai\//.test(name)) continue;
    if (!fs.existsSync(path.join(NM, name))) res.bundles.missing.push(name);
  }
  res.notes.push('skip: package-internal patch name check (multi-plugin packages)');

  // 两份运行配置里引用的包是否存在
  for (const f of PATCHES) {
    if (!fs.existsSync(f)) continue;
    let blocks = [];
    try { blocks = parsePatch(fs.readFileSync(f, 'utf8')).blocks; } catch { continue; }
    for (const b of blocks) {
      if (!b.name) continue;
      if (/^@deepseek-ai\//.test(b.name)) continue;
      if (/\.(js|cjs|mjs)$/.test(b.name) || /\.(js|cjs|mjs)$/.test(b.id)) continue;
      if (/^(\.|\/|[A-Za-z]:)/.test(b.name)) continue;
      if (!fs.existsSync(path.join(NM, b.name))) res.patch.missingPackage.push({ file: f, id: b.id, name: b.name });
    }
  }
}

// 基准：上次成功启动的插件集合
try {
  const bp = path.join(ROOT, 'dsh-golden', 'last-good-plugins.json');
  const base = readJson(bp);
  res.baseline.exists = true;
  const known = new Set(base.packages || []);
  const cur = new Set();
  if (pj) {
    for (const n of Object.keys(pj.dependencies || {})) cur.add(n);
    for (const n of ((pj.dsh && pj.dsh.profile && pj.dsh.profile.bundles) || [])) cur.add(n);
  }
  for (const n of cur) if (!known.has(n) && !/^@deepseek-ai\//.test(n)) res.baseline.newPlugins.push(n);
} catch { }

if (res.deps.missing.length || res.deps.broken.length || res.bundles.missing.length || res.patch.nameMismatch.length || res.patch.missingPackage.length) res.ok = false;
const outStr = JSON.stringify(res).replace(/[^\x00-\x7F]/g, ch => '\\u' + ch.charCodeAt(0).toString(16).padStart(4, '0'));
console.log(outStr);
process.exit(res.ok ? 0 : 2);
