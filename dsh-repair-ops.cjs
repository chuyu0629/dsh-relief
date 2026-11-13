#!/usr/bin/env node
'use strict';
const fs = require('fs');
const path = require('path');
const os = require('os');
const { spawnSync } = require('child_process');

function stamp() {
  const d = new Date();
  const p = (n) => String(n).padStart(2, '0');
  return String(d.getFullYear()) + p(d.getMonth() + 1) + p(d.getDate()) + '-' + p(d.getHours()) + p(d.getMinutes()) + p(d.getSeconds());
}
function rd(p) { try { return fs.readFileSync(p, 'utf8'); } catch (e) { return null; } }
function rdj(p) { const t = rd(p); if (t === null) return null; try { return JSON.parse(t.replace(/^\uFEFF/, '')); } catch (e) { return null; } }
function wr(p, t) { fs.mkdirSync(path.dirname(p), { recursive: true }); fs.writeFileSync(p, t, 'utf8'); }
function exists(p) { try { fs.statSync(p); return true; } catch (e) { return false; } }

/* ---------- ledger：所有写盘动作先落账，供 undo 回退 ---------- */
function ledgerPath(profileDir) { return path.join(path.dirname(profileDir), 'dsh-repair-ledger.jsonl'); }
function ledgerAdd(profileDir, entry) {
  const line = JSON.stringify(Object.assign({ ts: stamp(), at: Date.now() }, entry));
  fs.appendFileSync(ledgerPath(profileDir), line + '\n', 'utf8');
}
function ledgerRead(profileDir) {
  const t = rd(ledgerPath(profileDir));
  if (!t) return [];
  return t.split('\n').filter(Boolean).map((l) => { try { return JSON.parse(l); } catch (e) { return null; } }).filter(Boolean);
}
function backupOf(file) {
  const b = file + '.bak-' + stamp();
  fs.copyFileSync(file, b);
  return b;
}

/* ---------- profile 解析 ---------- */
function profilePaths(dir) {
  return {
    pkg: path.join(dir, 'package.json'),
    patch: path.join(dir, 'cordis.patch.yml'),
    nm: path.join(dir, 'node_modules'),
  };
}
function profileState(dir) {
  const P = profilePaths(dir);
  const pkg = rdj(P.pkg) || {};
  const deps = pkg.dependencies && typeof pkg.dependencies === 'object' ? pkg.dependencies : {};
  const prof = pkg.dsh && pkg.dsh.profile ? pkg.dsh.profile : {};
  const bundles = Array.isArray(prof.bundles) ? prof.bundles : [];
  return { pkg: pkg, deps: deps, bundles: bundles, patchText: rd(P.patch), paths: P };
}

/* ---------- 极简 YAML 条目扫描（只认 '- ' 块 + id/name），看不懂就报错 ---------- */
function analyzePatch(text) {
  if (text === null) return { ok: false, reason: 'no_patch_file', message: 'cordis.patch.yml 不存在' };
  const lines = text.replace(/\r\n/g, '\n').split('\n');
  const blocks = [];
  const stack = [];
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (/^[ ]*\t/.test(line)) return { ok: false, reason: 'tab_indent', message: 'patch 第 ' + (i + 1) + ' 行缩进含 Tab，不敢改' };
    const item = /^([ ]*)-(\s|$)/.exec(line);
    const key = /^([ ]*)([A-Za-z_][\w-]*)\s*:\s*(.*)$/.exec(line);
    if (item) {
      const indent = item[1].length;
      while (stack.length && stack[stack.length - 1].indent >= indent) stack.pop();
      const parent = stack.length ? stack[stack.length - 1] : null;
      const block = { start: i, end: i + 1, indent: indent, parent: parent, id: null, name: null, insert: false };
      const inline = /^-\s*([A-Za-z_][\w-]*)\s*:\s*(.*)$/.exec(line);
      if (inline) {
        const ik = inline[1]; const iv = inline[2].replace(/\s+#.*$/, '').trim().replace(/^['\"]|['\"]$/g, '');
        if (ik === 'id') block.id = iv;
        if (ik === 'name' || ik === 'package' || ik === 'plugin') block.name = iv;
      }
      blocks.push(block);
      if (parent && parent.end === i) parent.end = i + 1;
      stack.push(block);
      continue;
    }
    if (key && key[1].length > 0 && stack.length) {
      const block = stack[stack.length - 1];
      if (key[1].length > block.indent) {
        const k = key[2]; const v = key[3].replace(/\s+#.*$/, '').trim().replace(/^['\"]|['\"]$/g, '');
        if (k === 'id') block.id = v;
        if (k === 'name' || k === 'package' || k === 'plugin') block.name = v;
        block.end = i + 1;
        for (const b of stack) if (b.end <= i) b.end = i + 1;
      }
    }
  }
  return { ok: true, lines: lines, blocks: blocks };
}
function blockRefers(block, name) {
  const ids = [block.id, block.name].filter(Boolean);
  return ids.some((v) => v === name || v.indexOf(name) >= 0 || name.indexOf(v) >= 0);
}
function rootOf(blocks, block) { let b = block; while (b.parent) b = b.parent; return b; }
function childrenOf(blocks, root) { return blocks.filter((b) => b.parent === root); }

/* ---------- comment：只注释点名的块，四道安全阀 ---------- */
function commentEntries(text, name) {
  const a = analyzePatch(text);
  if (!a.ok) return a;
  const matched = a.blocks.filter((b) => blockRefers(b, name));
  if (!matched.length) return { ok: true, text: text, changed: false, commented: [] };
  const targets = new Set();
  for (const b of matched) {
    const root = rootOf(a.blocks, b);
    const kids = childrenOf(a.blocks, root);
    if (root.insert && kids.length > 0 && kids.every((k) => matched.indexOf(k) >= 0)) targets.add(root);
    else targets.add(b);
  }
  const roots = a.blocks.filter((b) => b.parent === null);
  if (roots.length > 0 && roots.every((r) => targets.has(r))) return { ok: false, reason: 'patch_would_be_empty', message: '改完 patch 会变成空文件，不敢改' };
  const ordered = [...targets].sort((x, y) => x.start - y.start);
  for (let i = 1; i < ordered.length; i++) if (ordered[i].start < ordered[i - 1].end) return { ok: false, reason: 'overlapping', message: '匹配块嵌套重叠，不敢改' };
  const out = a.lines.slice();
  const ids = [];
  for (const b of ordered) {
    for (let i = b.start; i < b.end; i++) if (out[i].trim()) out[i] = '# ' + out[i];
    ids.push(b.id || b.name || ('line' + (b.start + 1)));
  }
  const res = out.join('\n');
  const after = analyzePatch(res);
  if (!after.ok) return { ok: false, reason: 'patch_broken_after', message: '注释后 patch 不再可解析，不敢改' };
  if (after.blocks.some((b) => blockRefers(b, name))) return { ok: false, reason: 'still_referenced', message: '注释后仍扫得到 ' + name + '，不敢改' };
  if (after.blocks.filter((b) => b.parent === null).length === 0) return { ok: false, reason: 'patch_would_be_empty', message: '改完 patch 没有有效条目，不敢改' };
  return { ok: true, text: res, changed: res !== text, commented: ids };
}

/* ---------- 子命令 ---------- */
function cmdDiff(o) {
  const g = rdj(o.golden);
  const st = profileState(o.profile);
  const golden = g && Array.isArray(g.packages) ? g.packages : null;
  const cur = new Set(Object.keys(st.deps).concat(st.bundles));
  const out = { ok: true, golden: golden ? golden.length : 0, current: cur.size, suspects: [], added: [], missing: [] };
  if (!golden) { out.ok = false; out.reason = 'no_golden'; out.suspects = [...cur]; return out; }
  const gset = new Set(golden);
  out.added = [...cur].filter((n) => !gset.has(n));
  out.missing = golden.filter((n) => !cur.has(n));
  out.added = out.added.filter((n) => n.indexOf('@deepseek-ai/') !== 0);
  out.missing = out.missing.filter((n) => n.indexOf('@deepseek-ai/') !== 0);
  out.suspects = out.added;
  out.bundlesMissing = st.bundles.filter((n) => !exists(path.join(st.paths.nm, n)));
  return out;
}
function cmdComment(o) {
  const st = profileState(o.profile);
  const res = { ok: true, name: o.name, files: [], patch: null, pkg: false };
  const patchText = st.patchText;
  if (patchText !== null) {
    const c = commentEntries(patchText, o.name);
    res.patch = { ok: c.ok, changed: !!c.changed, commented: c.commented || [], message: c.message || null };
    if (!c.ok) { res.ok = false; return res; }
    if (c.changed) {
      const b = backupOf(st.paths.patch);
      wr(st.paths.patch, c.text);
      ledgerAdd(o.profile, { kind: 'comment', file: st.paths.patch, backup: b, name: o.name });
      res.files.push(st.paths.patch);
    }
  }
  const depKey = Object.keys(st.deps).find((k) => k === o.name);
  const bundles = st.bundles.filter((b) => b !== o.name);
  if (depKey || bundles.length !== st.bundles.length) {
    const b = backupOf(st.paths.pkg);
    if (depKey) delete st.pkg.dependencies[depKey];
    if (st.pkg.dsh && st.pkg.dsh.profile) st.pkg.dsh.profile.bundles = bundles;
    wr(st.paths.pkg, JSON.stringify(st.pkg, null, 2));
    ledgerAdd(o.profile, { kind: 'unplug', file: st.paths.pkg, backup: b, name: o.name });
    res.files.push(st.paths.pkg);
    res.pkg = true;
  }
  return res;
}
function cmdUndo(o) {
  const entries = ledgerRead(o.profile);
  if (!entries.length) return { ok: false, reason: 'empty_ledger' };
  const lastTs = entries[entries.length - 1].ts;
  const group = entries.filter((e) => e.ts === lastTs);
  const restored = [];
  for (const e of group) {
    if (e.backup && exists(e.backup)) { fs.copyFileSync(e.backup, e.file); restored.push(e.file); }
  }
  ledgerAdd(o.profile, { kind: 'undo', tsOverride: lastTs, restored: restored });
  return { ok: restored.length > 0, restored: restored, group: group.map((e) => e.kind + ':' + e.name) };
}
function cmdLedger(o) { return { ok: true, entries: ledgerRead(o.profile) }; }

function cmdPreflight(o) {
  const st = profileState(o.profile);
  const f = [];
  const add = (id, level, msg, hint) => f.push({ id: id, level: level, message: msg, hint: hint || null });
  const pkgFile = st.paths.pkg;
  if (!rdj(pkgFile)) add('R1', 'fatal', 'package.json 不存在或无法解析：' + pkgFile, '从 *.bak-* 恢复');
  const patch = analyzePatch(st.patchText);
  if (st.patchText !== null && !patch.ok) add('R2', 'fatal', 'cordis.patch.yml 无法解析：' + patch.message, '人工检查缩进/引号');
  for (const b of st.bundles) {
    if (String(b).indexOf('@deepseek-ai/') === 0) continue;
    const inDeps = Object.prototype.hasOwnProperty.call(st.deps, b);
    const inNm = exists(path.join(st.paths.nm, b));
    if (!inDeps && !inNm) add('R3', 'fatal', 'bundles 里的 ' + b + ' 既不在 dependencies 也不在 node_modules', '删掉该 bundles 行或重新安装');
    else if (!inNm) add('R3', 'info', 'bundles 里的 ' + b + ' 没有 node_modules 目录', 'pnpm 安装不完整，重装该插件');
  }
  for (const d of Object.keys(st.deps)) if (d.indexOf('@deepseek-ai/') !== 0 && !exists(path.join(st.paths.nm, d))) add('R4', 'info', 'dependencies 里的 ' + d + ' 缺 node_modules 目录', '重装该插件');
  const seen = new Set();
  for (const b of st.bundles) { if (seen.has(b)) add('R8', 'warn', 'bundles 重复项：' + b, '删掉重复行'); seen.add(b); }
  for (const d of Object.keys(st.deps)) {
    const pj = rdj(path.join(st.paths.nm, d, 'package.json'));
    if (!pj) continue;
    const host = rdj(path.join(o.home || 'C:/111111/resources/app', 'resources/app/package.json'));
    const peers = pj.peerDependencies && typeof pj.peerDependencies === 'object' ? pj.peerDependencies : {};
    for (const k of Object.keys(peers)) {
      if (k !== 'cordis' && k !== '@cordisjs/core' && k !== 'dsh' && k !== '@deepseek-ai/dsh') continue;
      if (host && host.version) { /* 只报告，不做 semver 判定 */ }
    }
  }
  const free = (function () { try { const s = fs.statfsSync ? fs.statfsSync('C:\\') : null; return s ? Math.round((s.bavail * s.bsize) / 1073741824) : null; } catch (e) { return null; } })();
  if (free !== null && free < 2) add('R9', 'fatal', 'C 盘剩余 ' + free + 'GB，低于 2GB', '清理磁盘后再启动');
  return { ok: true, findings: f, counts: { fatal: f.filter((x) => x.level === 'fatal').length, warn: f.filter((x) => x.level === 'warn').length }, freeGB: free };
}

function cmdFreeze(o) {
  const p = o.state;
  const st = rdj(p) || { plugins: {} };
  const rec = st.plugins[o.name] || { attempts: 0, frozen: false };
  if (o.mode === 'reset') { delete st.plugins[o.name]; wr(p, JSON.stringify(st, null, 2)); return { ok: true, frozen: false, attempts: 0 }; }
  rec.attempts = (rec.attempts || 0) + 1;
  rec.lastFailedAt = new Date().toISOString();
  rec.lastError = (o.error || '').slice(0, 400);
  rec.frozen = rec.attempts >= Number(o.limit || 3);
  st.plugins[o.name] = rec;
  wr(p, JSON.stringify(st, null, 2));
  return { ok: true, frozen: rec.frozen, attempts: rec.attempts };
}

function cmdVerify(o) {
  const src = profileState(o.profile);
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'dsh-verify-'));
  const prof = path.join(tmp, 'profiles', o.name || 'verify');
  fs.mkdirSync(prof, { recursive: true });
  let linked = false;
  try {
    if (src.paths.pkg) fs.copyFileSync(src.paths.pkg, path.join(prof, 'package.json'));
    if (src.patchText !== null) fs.copyFileSync(src.paths.patch, path.join(prof, 'cordis.patch.yml'));
    if (exists(src.paths.nm)) { try { fs.symlinkSync(src.paths.nm, path.join(prof, 'node_modules'), 'junction'); linked = true; } catch (e) { } }
    const dsh = o.dsh || 'C:/111111/resources/runtime/cli/bin/dsh.cmd';
    const r = spawnSync('cmd.exe', ['/c', dsh + ' --profile ' + (o.name || 'verify') + ' --dump-config'], {
      env: Object.assign({}, process.env, { DSH_HOME: tmp }),
      encoding: 'utf8', timeout: Number(o.timeout || 120000),
    });
    const out = ((r.stdout || '') + (r.stderr || '')).replace(/\s+$/, '');
    return { ok: r.status === 0, status: r.status, linked: linked, tail: out.slice(-1200), tmp: tmp, kept: true };
  } finally {
    if (process.env.KEEP_VERIFY !== '1') { try { fs.rmSync(tmp, { recursive: true, force: true, maxRetries: 2 }); } catch (e) { } }
  }
}
function cmdKnowledge(o) {
  const db = rdj(o.file);
  if (!db) return { ok: false, reason: 'no_knowledge' };
  const want = String(o.classes || '').split(',').map((s) => s.trim()).filter(Boolean);
  const list = db.entries && Array.isArray(db.entries) ? db.entries.filter((e) => want.indexOf(e.id) >= 0) : [];
  return { ok: true, matched: list };
}

function cmdSafeMode(o) {
  const st = profileState(o.profile);
  if (!st.pkg || !st.pkg.dsh || !st.pkg.dsh.profile) return { ok: false, reason: 'no_profile' };
  const bundles = Array.isArray(st.pkg.dsh.profile.bundles) ? st.pkg.dsh.profile.bundles : [];
  const kept = bundles.filter((b) => String(b).indexOf('@deepseek-ai/') === 0);
  const removed = bundles.filter((b) => kept.indexOf(b) < 0);
  if (!removed.length) return { ok: true, changed: false, removed: [], kept: kept };
  const b = backupOf(st.paths.pkg);
  st.pkg.dsh.profile.bundles = kept;
  wr(st.paths.pkg, JSON.stringify(st.pkg, null, 2));
  ledgerAdd(o.profile, { kind: 'safemode', file: st.paths.pkg, backup: b, name: 'safemode' });
  return { ok: true, changed: true, removed: removed, kept: kept, backup: b };
}

function main() {
  const argv = process.argv.slice(2);
  const cmd = argv[0];
  const o = {};
  for (let i = 1; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith('--')) { const k = a.slice(2); const v = argv[i + 1] && !argv[i + 1].startsWith('--') ? argv[++i] : '1'; o[k] = v; }
  }
  const table = { diff: cmdDiff, comment: cmdComment, undo: cmdUndo, ledger: cmdLedger, preflight: cmdPreflight, freeze: cmdFreeze, verify: cmdVerify, knowledge: cmdKnowledge, safemode: cmdSafeMode };
  if (!table[cmd]) { console.log(JSON.stringify({ ok: false, reason: 'unknown_command', cmd: cmd })); process.exit(2); }
  let res;
  try { res = table[cmd](o); } catch (e) { res = { ok: false, reason: 'exception', message: String(e && e.message || e) }; }
  console.log(JSON.stringify(res));
  process.exit(res && res.ok ? 0 : 1);
}
main();
