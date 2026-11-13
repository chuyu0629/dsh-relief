// DSH 崩溃归类器：读桌面端日志 + 少量文件度量，判定崩溃类别（只读，不改任何文件）
// 用法: node dsh-diagnose.cjs [--logs=<dir>] [--pkg=<package.json>] [--minutes=180] [--out=<file>]
const fs = require('fs');
const path = require('path');

const argv = process.argv.slice(2);
const arg = (k, d) => { const a = argv.find(x => x.startsWith('--' + k + '=')); return a ? a.slice(k.length + 3) : d; };
const HOME = process.env.USERPROFILE || 'C:\\Users\\Administrator';
const APPDATA = process.env.APPDATA || path.join(HOME, 'AppData', 'Roaming');
const LOGS = arg('logs', path.join(APPDATA, '@deepseek-ai', 'dsh-desktop', 'logs'));
const USERDATA = arg('userdata', path.join(APPDATA, '@deepseek-ai', 'dsh-desktop'));
const PKG = arg('pkg', path.join(HOME, '.dsh', 'profiles', 'desktop', 'package.json'));
const MINUTES = Number(arg('minutes', '180')) || 180;

const out = {
  logsDir: LOGS, scanned: [], classes: [], failedPlugins: [], missingModules: [], ports: [], slotIds: [],
  evidence: {}, knownPlugins: 0, metrics: {}, suggest: []
};

function readCap(p, cap) {
  try {
    const st = fs.statSync(p);
    if (st.size > cap) {
      const fd = fs.openSync(p, 'r');
      const buf = Buffer.alloc(cap);
      fs.readSync(fd, buf, 0, cap, Math.max(0, st.size - cap));
      fs.closeSync(fd);
      return buf.toString('utf8');
    }
    return fs.readFileSync(p, 'utf8');
  } catch { return ''; }
}

let files = [];
try {
  const cut = Date.now() - MINUTES * 60000;
  files = fs.readdirSync(LOGS).filter(n => /\.log$/i.test(n)).map(n => {
    const p = path.join(LOGS, n);
    let mt = 0; try { mt = fs.statSync(p).mtimeMs; } catch { }
    return { p, n, mt };
  }).filter(f => f.mt > cut).sort((a, b) => b.mt - a.mt).slice(0, 8);
} catch { }
if (!files.length) {
  try {
    files = fs.readdirSync(LOGS).filter(n => /crash|fatal/i.test(n)).map(n => {
      const p = path.join(LOGS, n);
      let mt = 0; try { mt = fs.statSync(p).mtimeMs; } catch { }
      return { p, n, mt };
    }).sort((a, b) => b.mt - a.mt).slice(0, 4);
  } catch { }
}

let text = '';
for (const f of files) { out.scanned.push(f.n); text += '\n<<<FILE ' + f.n + '>>>\n' + readCap(f.p, 2 * 1024 * 1024); }

let known = new Set();
try {
  const pj = JSON.parse(fs.readFileSync(PKG, 'utf8').replace(/^\uFEFF/, ''));
  for (const k of Object.keys(pj.dependencies || {})) known.add(k);
  const b = (pj.dsh && pj.dsh.profile && pj.dsh.profile.bundles) || [];
  for (const k of b) known.add(k);
} catch { }
out.knownPlugins = known.size;

function firstLine(re) {
  const m = re.exec(text);
  if (!m) return null;
  const i = text.lastIndexOf('\n', m.index) + 1;
  let j = text.indexOf('\n', m.index); if (j < 0) j = text.length;
  return text.slice(i, j).trim().slice(0, 260);
}
function add(name, note, re) {
  const line = re ? firstLine(re) : null;
  if (!line) return;
  if (out.classes.indexOf(name) >= 0) return;
  out.classes.push(name);
  out.evidence[name] = line;
  if (note) out.evidence[name + '_note'] = note;
}

add('auth431', 'cookie 累积导致 welcome 被拒；重置 cookie 库可解，约每 70 次启动复发', /Web authentication failed|Handshake failed with status code 431/i);
add('notActivate', '任一插件激活失败即整机退出（官方设计）', /did not activate|startup failed:\s*\d+\s+required plugin/i);
add('moduleMissing', '依赖文件缺失或被写坏；覆盖重装客户端无效，要修 node_modules', /Cannot find module|ERR_MODULE_NOT_FOUND/);
add('portInUse', '端口被占，DSH 起不来', /EADDRINUSE/);
add('stuckKill', '进程杀不掉，官方三条恢复路径也会失效', /did not exit after SIGKILL|SIGKILL/i);
add('slotConflict', '插件注册了同名槽位/服务，表现为白屏', /already has an entry with id|slot .{0,40}conflict/i);
add('peerIncompat', '宿主升级后插件 peer 不满足', /does not satisfy|peer.{0,60}(incompat|missing)|version mismatch/i);
add('whiteScreen', '渲染进程崩了：窗口白屏但进程还在', /Uncaught Error|renderer.{0,30}(crash|exited)/i);

add('cookiesBloat', '登录 cookie 在 Network\\Cookies 里只增不减，约 70 次启动后 Cookie 头超 16KB 触发 431；只重置 cookie 库即可，不必删整个目录', /Handshake failed with status code 431|Web authentication failed/i);
add('gpuCrash', 'GPU 进程反复崩（驱动/双显卡切换/远程桌面/Overlay 注入）：用 --disable-gpu 起一次多半能进', /GPU process isn't usable|gpu_?process.{0,40}(crash|exited|fail)|Failed to create GLES|viz_main_impl|angle::[a-zA-Z_]+.{0,30}(fail|error)/i);
add('cacheDenied', '缓存目录被占或权限被拒（Unable to move the cache）：改名缓存目录可解', /Unable to move the cache|Access is denied.{0,40}(cache|Cache)/i);
add('v8Snapshot', 'V8 快照缺失/损坏：本体文件被截断（下载中断或被杀软隔离），改配置无效', /Failed to load V8 snapshot|snapshot_blob|v8_context_snapshot|Invalid snapshot/i);
add('breakpoint', 'STATUS_BREAKPOINT 秒退（exit -2147483645 / 0x80000003）：Electron 本体与系统 build 不兼容，禁插件改配置都无效', /STATUS_BREAKPOINT|0x80000003|-2147483645|EXCEPTION_BREAKPOINT/i);
add('serviceConflict', '客户端插件注册了已被核心占用的服务名，白屏 Failed to load plugins 而服务端日志正常', /Failed to load plugins.{0,300}has been registered|service "[^"]+" has been registered/i);
add('gnuWhoami', 'PATH 里 Git for Windows 的 whoami 抢在系统命令前：身份检查无限重试、CPU 打满', /whoami: extra operand/i);
add('portReserved', '端口落在 Hyper-V/WSL2/Docker 保留段：报 EACCES 而不是 EADDRINUSE，换端口才解', /excludedportrange|reserved port|EACCES.{0,80}(listen|bind)/i);
add('corruptSession', '会话日志损坏或序号断裂：侧栏空白、历史打不开，程序本身能起', /seq gap|INVALID_REPLAY_STATE|corrupt session|insufficient tool messages|dangling tool_calls/i);
add('diskFull', '磁盘写满：缓存、日志、快照都写不下去', /ENOSPC|No space left|not enough space on the disk/i);
add('clockSkew', '系统时间偏差导致证书/令牌被判失效', /ERR_CERT_DATE_INVALID|certificate.{0,40}(expired|not yet valid)|token.{0,20}expired/i);
add('rendererOom', '渲染进程内存耗尽或栈溢出', /JavaScript heap out of memory|STATUS_STACK_BUFFER_OVERRUN|SIGILL|Out of memory/i);
add('singleInstance', '已有实例占着用户数据目录：第二个进程闪退或空转', /second instance|SingletonLock|already running/i);
add('sandboxDenied', '沙箱/ACL 拒绝访问用户数据或工作区', /EPERM|Access is denied/i);
add('hostCrash', '宿主进程自己退出（不是插件激活失败）：退出码 -1/4294967295，窗口随即消失', /host exited with (4294967295|-1|1)\b/i);
add('providerLoop', '某个 provider 在无限重试模型列表，把宿主拖到退出；先禁掉那个 provider 插件', /\[[a-z0-9-]+\] model listing from/i);

const loopN = (text.match(/\[[a-z0-9-]+\] model listing from/g) || []).length;
out.metrics.loopListings = loopN;
if (loopN >= 5) {
  if (out.classes.indexOf('providerLoop') < 0) out.classes.push('providerLoop');
  const tag = /\[([a-z0-9-]+)\] model listing from/.exec(text);
  out.metrics.loopProvider = tag ? tag[1] : '';
  out.evidence.providerLoop = '模型列表被重试 ' + loopN + ' 次（提供者 ' + (tag ? tag[1] : '?') + '），宿主随后退出';
}

const segMatch = /Failed plugins \(\d+\):([\s\S]{0,6000})/.exec(text);
if (segMatch) {
  const segText = segMatch[1];
  const esc = (s) => s.replace(/[^A-Za-z0-9@\/._-]/g, '\\$&');
  const hits = [];
  for (const name of known) {
    const re = new RegExp('(^|[\\s\\-(\\[,])' + esc(name) + '(?![\\w.\\/-])', 'm');
    if (re.test(segText)) hits.push(name);
  }
  if (!hits.length) {
    const skip = new Set(['stage', 'detail', 'plugin', 'plugins', 'entry', 'failed', 'activate', 'inject', 'required', 'service', 'missing']);
    for (const m of segText.matchAll(/[@A-Za-z0-9][@A-Za-z0-9._\/-]{2,80}/g)) {
      const t = m[0].replace(/[,:;)]+$/, '');
      const bare = t.includes('@') && !t.startsWith('@') ? t.slice(0, t.lastIndexOf('@')) : t;
      if (!skip.has(bare) && /^(@[A-Za-z0-9._-]+\/)?[A-Za-z0-9][A-Za-z0-9._-]+$/.test(bare)) hits.push(bare);
    }
  }
  out.failedPlugins = [...new Set(hits)].slice(0, 12);
  if (out.failedPlugins.length) out.classes.push('failedPlugins');
}

for (const m of text.matchAll(/(?:Cannot find module|Cannot resolve module)\s+['"]([^'"]+)['"]/g)) out.missingModules.push(m[1]);
for (const m of text.matchAll(/ERR_MODULE_NOT_FOUND[\s\S]{0,200}?['"](@?[\w.@\/-]+)['"]/g)) out.missingModules.push(m[1]);
out.missingModules = [...new Set(out.missingModules)].slice(0, 20);

for (const m of text.matchAll(/EADDRINUSE[^\n]{0,120}/g)) {
  for (const pm of m[0].matchAll(/(\d{2,5})/g)) { const v = Number(pm[1]); if (v >= 1024 && v <= 65535) out.ports.push(v); }
}
out.ports = [...new Set(out.ports)];

for (const m of text.matchAll(/already has an entry with id "([^"]+)"/g)) out.slotIds.push(m[1]);
out.slotIds = [...new Set(out.slotIds)].slice(0, 10);

const svc = /service "([^"]+)" has been registered/.exec(text);
if (svc) out.registeredService = svc[1];

function dirSize(p) {
  let sum = 0;
  try {
    for (const e of fs.readdirSync(p, { withFileTypes: true })) {
      const fp = path.join(p, e.name);
      try { sum += e.isDirectory() ? dirSize(fp) : fs.statSync(fp).size; } catch { }
    }
  } catch { }
  return sum;
}
function fileSize(p) { try { return fs.statSync(p).size; } catch { return 0; } }

const cookieFiles = ['Network\\Cookies', 'Network\\Cookies-journal', 'Cookies', 'Cookies-journal'];
let cookieBytes = 0;
for (const rel of cookieFiles) cookieBytes += fileSize(path.join(USERDATA, rel));
out.metrics.cookieBytes = cookieBytes;

let cacheBytes = 0;
const cacheDirs = ['GPUCache', 'Code Cache', 'Cache', 'DawnCache', 'DawnGraphiteCache', 'DawnWebGPUCache', 'ShaderCache', 'GrShaderCache', 'blob_storage'];
const cacheHit = [];
for (const d of cacheDirs) {
  const sz = dirSize(path.join(USERDATA, d));
  if (sz > 0) { cacheBytes += sz; cacheHit.push(d + '=' + (sz / 1048576).toFixed(1) + 'MB'); }
}
out.metrics.cacheBytes = cacheBytes;
out.metrics.cacheDirs = cacheHit;

try {
  const st = fs.statfsSync(path.parse(HOME).root || 'C:\\');
  out.metrics.freeGB = +((st.bavail * st.bsize) / 1073741824).toFixed(1);
} catch { out.metrics.freeGB = -1; }

if (out.classes.indexOf('cookiesBloat') < 0 && cookieBytes > 200 * 1024) {
  out.classes.push('cookiesBloat');
  out.evidence.cookiesBloat = 'cookie 库 ' + (cookieBytes / 1024).toFixed(0) + ' KB，超过 200KB 说明账号 cookie 在累积';
}
if (out.classes.indexOf('diskFull') < 0 && out.metrics.freeGB >= 0 && out.metrics.freeGB < 1) {
  out.classes.push('diskFull');
  out.evidence.diskFull = '系统盘只剩 ' + out.metrics.freeGB + ' GB';
}

const SUG = {
  hostCrash: 'reportHost', providerLoop: 'reportProvider',
  cookiesBloat: 'resetCookies', auth431: 'resetCookies',
  gpuCrash: 'noGpu',
  cacheDenied: 'renameCache',
  portInUse: 'killPort', portReserved: 'reportPort',
  diskFull: 'reportDisk',
  breakpoint: 'reportReinstall', v8Snapshot: 'reportReinstall',
  serviceConflict: 'disableNamedPlugin', failedPlugins: 'disableNamedPlugin',
  corruptSession: 'quarantineSession',
  moduleMissing: 'reportModules',
  gnuWhoami: 'reportPath',
  clockSkew: 'reportClock'
};
for (const c of out.classes) if (SUG[c]) out.suggest.push(SUG[c]);
out.suggest = [...new Set(out.suggest)];

out.classes = [...new Set(out.classes)];
out.verdict = out.classes.length ? out.classes.join(',') : 'unknown';
const json = JSON.stringify(out, null, 2);
const outFile = arg('out', null);
if (outFile) { try { fs.writeFileSync(outFile, json, 'utf8'); } catch (e) { console.error('write out failed: ' + e.message); } }
if (!outFile) console.log(json);
