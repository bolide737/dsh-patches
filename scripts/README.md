# scripts/

## `dsh-maintenance.ps1`

一个脚本管三件事：**检查 GitHub 进展**、**升级后重打补丁**、**一键回退补丁**。

```powershell
& .\dsh-maintenance.ps1            # 检查（默认，只读）
& .\dsh-maintenance.ps1 -Check     # 同上
& .\dsh-maintenance.ps1 -Reapply   # 重打两个补丁（幂等，自动备份）
& .\dsh-maintenance.ps1 -Revert    # 用备份回退两个补丁
& .\dsh-maintenance.ps1 -All       # Reapply + Check
& .\dsh-maintenance.ps1 -Root 'C:\Users\me\AppData\Local\npm-cache\_npx\<hash>'   # 手动指定检出
```

### 它检查什么（`-Check`）

| # | 项目 |
|---|---|
| 1 | 侧栏插件 PR [omdsh-dev/DSH-better-sidebar#634](https://github.com/omdsh-dev/DSH-better-sidebar/pull/634)：状态 / 是否 merged / **是否冲突（`mergeable_state=dirty`）** / 评审与评论 |
| 2 | DSH Discussion [#8059](https://github.com/deepseek-ai/deepseek-harness/discussions/8059)：回复列表 |
| 3 | DSH Discussion [#7549](https://github.com/deepseek-ai/deepseek-harness/discussions/7549)：交叉引用下的回复 |
| 4 | 账号未读 GitHub 通知 |
| 5 | 本补丁仓库的 star / fork 统计 |

### 它怎么找到该改的文件（`-Reapply` / `-Revert`）

两个补丁**不在同一棵树里**，脚本分别定位：

- `dsh-better-sidebar` → 装在 **profile** 里：`%USERPROFILE%\.dsh\profiles\*\node_modules`
- `dsh-client-ui-deliverables` → 属于 **DSH 本体**：宿主实际服务的那个 npx 检出

"宿主服务的检出"通过三步确定，任一步成功即返回：

1. **读运行中的 node 进程命令行**（argv 里带 `...\_npx\<hash>\...`）—— 最直接；
2. boot 页面（`window.__DSH_BOOT__`）里的条目路径；
3. 兜底：最新一个含目标包的 npx 检出。

> 第 2 步需要页面 token，脚本会从启动日志（`D:\workspace\dsh-web\coldstart-host.out.log`，可用 `$WebUrl` 同目录约定或改脚本）末尾取最近一个 `?token=`。**其它 npx 缓存副本永不被修改**。

### 注意事项

- 脚本内**全部使用 ASCII 字符串**：PowerShell 5.1 会把无 BOM 的 `.ps1` 当 ANSI/GBK 读，中文会变乱码并导致语法错误（这是我踩过的坑，故刻意如此）。
- 若脚本放在别处，`$WebUrl` / 启动日志路径 / `$ProfilesRoot` 可改脚本顶部的参数默认值。
- `-Check` 只读，不会改动任何文件；`-Reapply` / `-Revert` 会自动建/删 `*.bak-before-*` 备份。
