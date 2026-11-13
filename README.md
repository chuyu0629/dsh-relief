# DSH 一键修复（DSH Relief）

给 **DeepSeek Harness 桌面版**打不开、白屏、卡在启动界面的人用的一个小工具。
不装插件、不联网、不改你的会话和账号，只在必要时改动 **profile 配置**，并且每次改动前都留备份。

> 现状：作者本机（Windows 11 / DSH 0.2.2-rc.1）验证通过；别人的机器上可能遇到没覆盖到的情况。
> 遇到问题请开 issue，附上 `dsh-repair.log` 里出错那几行（不要贴 token、邮箱、路径里的用户名可以打码）。

## 它能干什么

启动失败时，它不是"重启大法"，而是**先分类再对症**：

| 现象 | 处理 |
| --- | --- |
| 登录态/凭证缓存坏了（401、Web authentication failed、启动后连不上界面） | 把 `%APPDATA%\@deepseek-ai\dsh-desktop` 改名备份后重启 |
| cookie 库膨胀导致 HTTP 431 | 只移走 cookie 文件（不删整个目录） |
| GPU 进程崩溃、黑屏、花屏 | 用 `--disable-gpu` 启动 |
| 渲染缓存被占用/损坏（Access is denied） | 改名缓存目录后重建 |
| 某个第三方插件把启动搞挂 | 按日志点名摘掉该插件，摘之前先备份、可 `-Undo` |
| 插件多到互相冲突 | 安全模式：只留官方插件启动 |
| 端口被占、端口被 Hyper-V 保留、残留进程杀不掉 | 定位并清掉占用者，或直接告诉你哪个服务在抢端口 |
| 磁盘满、断点（STATUS_BREAKPOINT）、V8 快照损坏 | 判断为"本机/系统级问题"，**不瞎折腾**，直接说明原因和建议 |

## 它修不了什么

- 本体文件损坏（`DeepSeek Harness.exe`、runtime 缺失）——只能重装；
- 系统级问题：运行库、驱动、磁盘满、权限、杀软拦截；
- 数据目录被删且没有备份；
- 账号/网络问题（401、KEY 失效、被封、代理不通）；
- 需要 UAC 才能做的改动。

遇到这些它会明说，不会假装修好了。

## 怎么用

### 方式一：一键 exe（推荐给不熟命令行的朋友）

下载 `DSH一键修复.exe`，双击，点「开始修复」。全过程有进度条和日志。

### 方式二：脚本（推荐先体检再动手）

```powershell
cd <解压目录>
powershell -NoProfile -ExecutionPolicy Bypass -File .\dsh-repair.ps1 -DryRun      # 只体检，不改任何文件
powershell -NoProfile -ExecutionPolicy Bypass -File .\dsh-repair.ps1 -Preflight   # 只读检查 profile 配置
powershell -NoProfile -ExecutionPolicy Bypass -File .\dsh-repair.ps1              # 真修
```

首次用建议先跑 `-DryRun`，看看它认为你属于哪类故障、打算做什么。

## 全部参数

| 参数 | 作用 | 会改文件吗 |
| --- | --- | --- |
| （无） | 完整修复流程 | 会（全部有备份） |
| `-DryRun` | 体检：诊断分类 + 数据检查 + 急救会禁哪些插件 | 不会 |
| `-Preflight` | 只读校验 profile（package.json / patch / 依赖 / 磁盘） | 不会 |
| `-Verify` | 用临时 `DSH_HOME` 隔离复验配置能否组合 | 只写临时目录 |
| `-SafeMode` | 只留官方插件启动，其余全部摘出 | 会（可 `-Undo`） |
| `-Undo` | 回退最近一次配置改动 | 会（还原备份） |
| `-SelfTest` | 自检环境（node / exe / 急救脚本是否就位） | 不会 |

## 安全设计

1. **动手前先备份**：配置改到 `dsh-backups\` 与 `dsh-golden\`，命名带时间戳。
2. **可回退**：`-Undo` 按台账 `dsh-repair-ledger.jsonl` 成组还原最近一次改动。
3. **只改必要字段**：摘插件是逐行注释 + 从 `package.json` 摘依赖，不是整文件重写；改前四道安全检查（缩进/空 patch/重叠/仍被引用）。
4. **不联网**：除启动 DSH 本体外不访问网络，不上传任何数据。
5. **只写自己的目录**：日志、备份都写在脚本所在目录（exe 版在 `%LOCALAPPDATA%\DshRelief`）。
6. **单实例锁**：不会两个修复同时跑。

## 产出文件

| 文件 | 内容 |
| --- | --- |
| `dsh-repair.log` | 每次修复的完整流水 |
| `dsh-repair-stats.jsonl` | 每次结果（ok / 失败类目），用于统计 |
| `dsh-repair-ledger.jsonl` | 配置改动台账（`-Undo` 依据） |
| `dsh-backups\` | cookie / 配置回滚点 |
| `dsh-golden\` | 上次正常启动时的插件清单与配置快照 |

## 常见问题

**提示找不到安装目录**
设环境变量指出即可：`setx DSH_APP "C:\Program Files\DeepSeek Harness"`，或用 exe 版（它会自动找注册表和常见目录）。

**杀软报毒**
exe 是 `csc` 编译的启动器，没有签名，可能被误报。介意的话直接用 `.ps1` 脚本方式。

**它说"问题不在第三方插件"**
说明安全模式也起不来，通常是本体或系统级问题，按提示重装/检查。

**会不会把我配置弄丢**
每次改动都先备份，`-Undo` 可回退；但请自己别同时手改配置文件。

## 许可

MIT，见 [LICENSE](LICENSE)。自用、改造、二次分发都行，风险自担。
