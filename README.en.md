# DSH patches (English summary)

Two verified local patches for DeepSeek Harness (DSH) Web GUI. Full docs are in Chinese: [`README.md`](README.md).

| Patch | Problem it fixes |
|---|---|
| [`patches/turn-tail-coexist`](patches/turn-tail-coexist/) | With `dsh-better-sidebar` installed, the official `present` **deliverable cards never render** on any turn that also wrote files: the sidebar plugin wins the `conversation.chat.turnTail` chain slot while only reading `deliverables.produced`, so `deliverables.presented` has nowhere to render. Fix: the plugin's `selectProducedFiles()` yields (`return null`) when the turn declared deliveries, handing the row back to the official card. Verified by single-variable A/B (disable plugin → card appears). |
| [`patches/card-open-native`](patches/card-open-native/) | The deliverable card's **「打开 / Open」button performs a sidebar preview** because it is wired to `onPreview`; the native default-app open is hidden in the `⌄` menu. Fix: rebind that one button to `onAction("open")`. |

**Install**: each patch ships an idempotent `apply.ps1` (with automatic `.bak-before-*` backups) and a `revert.ps1`.

**Maintenance**: [`scripts/dsh-maintenance.ps1`](scripts/) — `-Check` reports progress on the upstream PR/discussions, `-Reapply` re-applies both patches after an upgrade, `-Revert` restores the originals. It detects which checkout the running host actually serves, so other npx cache copies are never touched.

**Caveats**
- Both patches edit published client bundles inside `node_modules`; a DSH or plugin upgrade overwrites them — re-run `apply.ps1`.
- Only client bundles change; a browser page refresh is enough (no host restart).
- Native open requires a desktop-resolvable default application on the serving host (useless on headless/WSL hosts).
- Tested on DSH `0.1.5-rc.2`, `dsh-better-sidebar@0.19.0`, Web GUI, Windows 11.
