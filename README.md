# DSH patches · 让 DSH 用得更顺手的两个小补丁

这里收集两个**已验证可用**的本地补丁。它们都改 `node_modules` 里的已发布代码，所以：

> ⚠️ **DSH 本体或插件升级后会被覆盖**。每个补丁目录下都附了一键脚本，升级后重跑一次即可。

| 补丁 | 解决的问题 | 目标文件 |
|---|---|---|
| [`patches/turn-tail-coexist`](patches/turn-tail-coexist/) | 装了侧边栏插件后，`present` 交付卡片**永不显示** | `dsh-better-sidebar/lib/client.js`、`lib/client-registry.js` |
| [`patches/card-open-native`](patches/card-open-native/) | 交付卡片的「打开」按钮**只能在侧边栏预览**，想用系统默认程序打开 | `@deepseek-ai/dsh-client-ui-deliverables/lib/client.js` |

环境：DSH `0.1.5-rc.2`（npx 检出）、`dsh-better-sidebar@0.19.0`、Web GUI，Windows。

---

## 补丁一：turn-tail 共存（交付卡片 + 侧栏产出行同时显示）

### 症状

装 `dsh-better-sidebar` 后，只要某一轮**既改文件又 `present` 交付**，那一轮的交付卡片整个消失，只剩侧栏的「本次产出」chip 行。

### 根因

`conversation.chat.turnTail` 是 **chain 槽**：谁先命中就由谁渲染，后面的注册者轮不到。侧栏插件注册在同一槽位，**只要这一轮有 `write`/`edit` 产出就抢占**；而它只读 `deliverables.produced`，`present` 声明的文件只进 `deliverables.presented`——于是官方卡片（`selectDeliverables` 会同时渲染 `produced` + `presented`）根本没机会执行。

判定依据（单变量对照）：停用该插件 → 卡片立刻出现；启用 → 从不出现。

### 修法

在侧栏插件的 `selectProducedFiles()` **函数入口**加一道守卫：本轮若存在 `present` 交付，就返回 `null`（主动退让），把渲染权交回官方卡片。

> ⚠️ 关键位置：守卫必须在 **`selectProducedFiles()` 内部**。只改注册项里的 `select` 回调（更外层）实测**不生效**。

- 守卫源码：[`patches/turn-tail-coexist/snippet.js`](patches/turn-tail-coexist/snippet.js)
- 完整补丁：`patches/turn-tail-coexist/*.patch`（含行号上下文）
- 安装/回退脚本：[`patches/turn-tail-coexist/apply.ps1`](patches/turn-tail-coexist/apply.ps1)、[`revert.ps1`](patches/turn-tail-coexist/revert.ps1)

**效果**：交付轮次显示官方卡片；仅产出轮次仍走侧栏；两者共存。

**代价**：交付轮次的「本次产出」行回到宿主行为（点开走宿主预览，侧栏的「在文件夹中显示」不再出现）。

---

## 补丁二：交付卡片的「打开」按钮 → 系统默认程序

### 症状

卡片上的「打开」按钮点下去是**在右侧边栏预览**，不是用系统程序打开；真正的"默认程序打开"藏在右边那个 `⌄` 菜单里。

### 根因

官方组件里两者绑的是同一个回调：

```js
// dsh-client-ui-deliverables/lib/client.js — PresentedFileCard
// 整卡覆盖按钮（卡片本体）
onClick: onPreview            // → 侧边栏预览
// 「打开」按钮
onClick: onPreview,           // ← 也是侧边栏；aria 文案才是「在侧边栏打开 {name}」
children: t("presented.action")   // 文案是「打开」，容易误解
```

### 修法（A 方案：只改按钮）

只把「打开」按钮的 `onClick` 换成菜单里的原生打开动作 `onAction("open")`；卡片本体点击仍是侧边栏预览。

```js
- onClick: onPreview,                          // 「打开」按钮 → 侧边栏
+ onClick: () => onAction("open"),             // 「打开」按钮 → 系统默认程序
  children: t("presented.action")
```

- 安装/回退脚本：[`patches/card-open-native/apply.ps1`](patches/card-open-native/apply.ps1)、[`revert.ps1`](patches/card-open-native/revert.ps1)
- 若想让整张卡片也走默认程序打开，把**卡片本体**那处 `onClick: onPreview` 同样替换即可（B 方案，未在此提供脚本）。

**注意**：原生打开依赖 host 能解析到 Windows/macOS 的默认关联程序，且只对**本机浏览器**有效；无桌面环境（headless/WSL 服务）下无效——那种场景应等官方的 Download action。

---

## 通用说明

- 两个补丁都**只改客户端 bundle**，不涉及 host 进程；改完刷新页面即可生效，无需重启 DSH。
- 每个 `apply.ps1` 都是**幂等**的：已打过会跳过；且会先做同目录备份（`*.bak-before-*`）。
- 脚本里的目标路径按 npm 缓存型 npx 检出写的，若你的 DSH 安装位置不同，改脚本顶部的 `$cands` 数组即可。

## 许可

补丁代码针对 `@deepseek-ai/dsh-client-ui-deliverables` 与 `dsh-better-sidebar` 的**已发布 bundle**，仅为本地行为调整；请遵守原项目的许可。
