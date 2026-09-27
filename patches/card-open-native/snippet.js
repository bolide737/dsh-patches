// ---------------------------------------------------------------------------
// 补丁：交付卡片的「打开」按钮 → 系统默认程序打开
// 目标：@deepseek-ai/dsh-client-ui-deliverables · lib/client.js
// 组件：PresentedFileCard（文件卡片）
// ---------------------------------------------------------------------------
//
// 现状（官方 0.1.5-rc.2 的 bundle）：两者绑的是同一个回调
//
//   // 整卡覆盖按钮（卡片本体）
//   { type: "button", className: "...cardPreview", onClick: onPreview }
//   // 「打开」按钮（分段控件左半）
//   { type: "button", className: "...open", onClick: onPreview,
//     "aria-label": t("presented.previewButton", { name: file.path }),
//     children: t("presented.action") }        // 文案是「打开」，实际是侧栏预览
//   // 右半 ⌄ 菜单里才是在默认程序中打开（onAction("open")）/ 打开所在文件夹
//
// A 方案：只改「打开」按钮
//
// - onClick: onPreview,
// + onClick: () => onAction("open"),
//   children: t("presented.action")
//
// B 方案（可选）：连卡片本体一起改 —— 把 cardPreview 那处的 onClick: onPreview
// 同样替换为 onClick: () => onAction("open")。
// ---------------------------------------------------------------------------
