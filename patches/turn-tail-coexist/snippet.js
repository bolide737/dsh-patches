// ---------------------------------------------------------------------------
// 修复：装了侧边栏插件后，present 交付卡片永不显示
// 目标：dsh-better-sidebar · lib/client.js 与 lib/client-registry.js
// 位置：selectProducedFiles() 函数入口（必须在这里，不能只改注册项的 select 回调）
// ---------------------------------------------------------------------------

		/**
		* Claim the turn-tail chain only when the closing turn produced files.
		* ...
		* @param owner - the turn-tail owner currency ({turn, seq, openFile}).
		* @returns produced paths as the matched value, or null to decline.
		*/
		function selectProducedFiles(owner) {
			// [local patch · 共存] 本轮若有 present 交付（turn data 的 deliverables.presented
			// 非空），本行不接管，让 @deepseek-ai/dsh-client-ui-deliverables 的交付卡片渲染。
			// 回退：用同目录 client.js.bak-before-coexist / client-registry.js.bak-before-coexist 覆盖。
			{
				const _d = owner?.turn?.data?.get?.("deliverables");
				if (Array.isArray(_d?.presented) && _d.presented.length > 0) return null;
			}
			const record = owner;
			if (record === null || typeof record !== "object") return null;
			const seq = typeof record.seq === "number" ? record.seq : Number.POSITIVE_INFINITY;
			const data = record.turn?.data?.get?.("deliverables");
			if (data !== null && typeof data === "object" && Array.isArray(data.produced)) {
				// ...（原逻辑不变：只从 data.produced 收集路径）
			}
			if (!Array.isArray(record.nodes)) return null;
			const paths = producedForClosing(record.nodes, seq);
			return paths.length === 0 ? null : paths;
		}
