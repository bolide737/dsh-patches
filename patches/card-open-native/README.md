# 补丁二 · 交付卡片「打开」按钮 → 系统默认程序

## 症状

Web GUI 里交付卡片（`present` 声明的文件）上的「**打开**」按钮，点下去是**在右侧边栏预览**，不是用系统程序打开。真正的"用默认应用打开"藏在按钮右边的 `⌄` 菜单里。

## 根因（官方 0.1.5-rc.2 bundle）

`PresentedFileCard` 里两处按钮绑了同一个回调：

| 元素 | 实际行为 | 源码 |
|---|---|---|
| 卡片本体（透明覆盖按钮） | 侧边栏预览 | `className: "...cardPreview", onClick: onPreview` |
| 「打开」按钮 | **也是侧边栏预览** | `className: "...open", onClick: onPreview`，aria 才是 `presented.previewButton`「在侧边栏打开 {name}」 |
| 右半 `⌄` 菜单 | 在默认程序中打开 / 打开所在文件夹 | 菜单项 `onAction("open")` / `onAction("reveal")` |

也就是说：按钮**文案叫「打开」**，但绑的是预览动作 —— 这是让人误判的地方。

## 修法（A 方案：只改按钮）

```diff
  	        const split = ...
-	          onClick: onPreview,
+	          onClick: () => onAction("open"),
 	          children: t("presented.action")
```

- 位置：`lib/client.js` 中 `function PresentedFileCard(...)` 内，**「打开」按钮**（其 `children` 是 `t("presented.action")`）那一处。
- 完整上下文见 [`snippet.js`](snippet.js)、[`card-open-native.patch`](card-open-native.patch)。
- B 方案（连卡片本体一起走默认程序）：把 `cardPreview` 那处的 `onClick: onPreview` 也换成 `onClick: () => onAction("open")`。本目录的 `apply.ps1` 只做 A。

## 安装 / 回退

```powershell
pwsh -File apply.ps1     # 幂等：已打过会跳过；自动备份 *.bak-before-native-open
pwsh -File revert.ps1    # 用备份覆盖并删除备份
```

改完**刷新浏览器页面**即可生效（只改客户端 bundle，不需要重启 DSH）。

## 验证方式（我本机实测）

```powershell
# host 下发的字节里应出现新绑定，且 onPreview 只剩 1 处（卡片本体）
(Invoke-WebRequest "http://127.0.0.1:3080/plugins/??@deepseek-ai/dsh-client-ui-deliverables/client.js&rev=...").Content -match 'onAction\("open"\)'
```

## 注意事项

- 原生打开依赖 **host 能解析到系统的默认关联程序**，且只对**本机浏览器**有效；headless / WSL 服务端没有桌面（会提示 "This Host has no desktop available"），此时此补丁无意义 —— 那种场景应关注官方 Download action（见 DSH Discussions #7549）。
- 该文件属于 **DSH 本体**，DSH 升级会覆盖，需要重打。
