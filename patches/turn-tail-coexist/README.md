# 补丁一 · turn-tail 共存（交付卡片 + 侧栏「本次产出」行同屏）

## 症状

装了 `dsh-better-sidebar` 之后，**只要某一轮既改文件又 `present` 交付**，那一轮的 DSH 官方交付卡片整个消失，只剩侧栏的「本次产出」chip 行；纯命令产出（只 `present`、没有 `write`/`edit`）的轮次卡片正常。

## 根因

- `conversation.chat.turnTail` 是 **chain 槽**：命中即以该注册者渲染，后面的注册者**不会被咨询**。
- 侧栏插件注册在同一槽位，判据是"这一轮有 `write`/`edit` 产出"（`selectProducedFiles` 读 `deliverables.produced`）→ **抢占**。
- 而 `present` 声明的文件只进 `deliverables.presented`；官方卡片的 `selectDeliverables` 本来是 `{ produced, presented }` **一起渲染**，但轮不到它执行。

**判定依据（单变量对照）**：停用该插件 → 卡片立刻出现；启用 → 从不出现。其余条件全部不变。

## 修法

在 `selectProducedFiles()` **函数入口**加守卫：本轮存在 `present` 交付时返回 `null`（主动退让），把渲染权交回官方卡片。

```js
		function selectProducedFiles(owner) {
			// [local patch · 共存] 本轮若有 present 交付（turn data 的 deliverables.presented
			// 非空），本行不接管，让 @deepseek-ai/dsh-client-ui-deliverables 的交付卡片渲染。
			{
				const _d = owner?.turn?.data?.get?.("deliverables");
				if (Array.isArray(_d?.presented) && _d.presented.length > 0) return null;
			}
			const record = owner;
			...
```

> ⚠️ **位置很关键**：必须打在 `selectProducedFiles()` 里面。我一开始只改更外层的注册项 `select` 回调，实测**不生效**（疑似求值时机早于 `presented` 落库）。
>
> ⚠️ 插件里的 `priority: -1` 在 chain 语义下**不参与选举**，所以别指望用优先级解决；只能靠"退让"。

## 文件

- [`snippet.js`](snippet.js) — 带上下文的完整守卫代码
- [`turn-tail-coexist.patch`](turn-tail-coexist.patch) — diff
- [`apply.ps1`](apply.ps1) / [`revert.ps1`](revert.ps1) — 幂等安装 / 一键回退

同时要改 **两个** bundle：`lib/client.js` 与 `lib/client-registry.js`（同源副本，防止加载切换后失效）。

## 效果与代价

| 轮次类型 | 效果 |
|---|---|
| 既写文件又 `present` | 官方交付卡片 + 侧栏「本次产出」行**同时显示** ✅ |
| 只写文件、无 `present` | 与之前一致（侧栏产出行） |
| 只 `present`、无写文件 | 与之前一致（官方卡片） |

**代价**：交付轮次的「本次产出」行回到宿主行为（点开走宿主文件预览，侧栏侧特有的「在文件夹中显示」不再出现）。其余轮次行为不变。

## 实测环境

DSH `0.1.5-rc.2`（npm 缓存型 npx 检出）+ `dsh-better-sidebar@0.19.0` + Web GUI + Windows 11。安装后刷新页面即可生效（纯客户端 bundle，不需要重启 DSH）。
