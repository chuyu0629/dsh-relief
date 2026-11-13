---
name: 修复失败
about: 工具没能解决你的启动问题
title: "[失败] "
labels: bug
---

**现象**（卡在哪一步、有没有报错窗口）

**DSH 版本**（关于页面里的版本号）

**Windows 版本**

**先跑这两条，把输出贴上来**
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\dsh-repair.ps1 -DryRun
powershell -NoProfile -ExecutionPolicy Bypass -File .\dsh-repair.ps1 -Preflight
```

**日志**：`dsh-repair.log` 里最后 20 行（贴之前删掉邮箱/token/用户名）

**它自己的判断**：日志里 `diag classes:` 那行
