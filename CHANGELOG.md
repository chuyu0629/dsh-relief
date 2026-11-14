# 更新记录

## v3.1.0 (2026-11-15)

- 鏂扮晫闈細鍘绘帀娓愬彉銆佸彂鍏夈€佸渾鐜笌寮硅烦锛屾敼鎴愪竴寮犲畨闈欑殑榛戝崱锛堝ぇ鍙风粏浣撴暟瀛?+ 1px 缁嗙嚎杩涘害 + 绛夊鏃ュ織琛岋級
- 鍔ㄧ敾鍙墿涓や欢锛氱獥鍙?420ms 娣″叆銆佽繘搴︾嚎缂撳姩锛屼笉鍐嶆湁寰幆鎵厜
- 鎸夐挳鏀规垚鎻忚竟骞界伒鎸夐挳锛岄粯璁や笉鎶㈣绾縛n
## v3.0.1 (2026-11-15)

- After a successful repair the window now points users to the repo (star), and stays 7s instead of 4s
- First line of dsh-repair.log carries the project URL
- README: added a short English section
- Fixed: scripts must be saved as UTF-8 with BOM (PowerShell 5.1 mis-parses the WPF UI otherwise)

## v3 (2026-11-14)

- 诊断分类从 8 类扩到 26 类，按类对症处理，不再一律重启
- 修复两个静默失效的环节：日志分类器和进程结束
- 精准摘除可疑插件（逐行注释 + 摘依赖，四道安全检查，可 -Undo）
- 改前预检（`-Preflight`）、改后隔离复验（`-Verify`）
- 冻结机制：同一插件连续失败多次后不再尝试
- 安全模式（`-SafeMode`）：只留官方插件启动
- 故障知识库：每类故障给出成因与"已验证无效的做法"
- 移植为通用版本：自动发现安装目录、node、用户目录，不再写死路径

## v2 (2026-11-13)

- 两轮修复阶梯 + 插件急救 1/2 级
- 凭证缓存自动改名、cookie 库定向清理
- iOS 风格界面，进度条与实时日志
