# 代码审查报告（2026-09-08）

> 范围：全仓审查 + 修复「学业快览」统计卡对齐 bug。本报告按优先级列出发现与建议。
>
> **状态更新（2026-09-08 第二轮）**：报告中全部 P1–P3 遗留问题已修复完毕，各项标题已标注 ✅。验证：`pnpm typecheck` 全过、`pnpm test` 26/26 通过、`pnpm lint` 零错误零警告、`pnpm build` 成功、浏览器几何验证课表 13 个课程块与节次行线 0 错位。

## 已修复

### P0 · 「学业快览」四张统计卡文字紧贴卡片边缘

- **根因**：`archive/apps/web/src/pages/Dashboard.tsx` 四张 KPI 统计卡使用了 `p-4.5`。项目实际安装的是 Tailwind v3.4（`archive/apps/web/package.json`），其默认间距刻度没有 `4.5`（Tailwind v4 才加入），该类被**静默丢弃**；而 `@crisp-ui-kit/crisp` 的 `.card` 自身零内边距，导致卡片内容完全贴边，与页面其余 `p-4` 卡片视觉不一致——即「字和卡片没对准」。
- **修复**：四处 `p-4.5` → `p-4`（Dashboard.tsx:515、538、566、589）。
- **验证**：浏览器实测 computed padding 从 0 恢复为 16px；截图确认与相邻卡片对齐；`pnpm typecheck` 全部通过。

## 遗留问题与建议

### P1 · ✅ 已修复 · 同类隐患：其余 Tailwind v4 专属类名在 v3 下静默失效

与 `p-4.5` 同根因的问题还散布在其他文件（均已在构建产物 CSS 中确认缺失对应规则）：

| 位置 | 失效类 | 后果 |
|---|---|---|
| `archive/apps/web/src/components/FloatingChat.tsx:190` | `shadow-3xl` | 无阴影 |
| `archive/apps/web/src/components/FloatingChat.tsx:617, 675, 804` | `shadow-2xs` | 无阴影 |
| `archive/apps/web/src/components/FloatingChat.tsx:729-730` | `shadow-xs`、`rounded-br-xs`、`rounded-bl-xs` | 气泡无阴影、直角 |
| `archive/apps/web/src/components/Layout.tsx:54, 77, 94, 107` | `shadow-xs` | 侧边栏/导航无阴影 |
| `archive/apps/web/src/pages/Chat.tsx:378, 385, 392, 401` | `shadow-xs` | 死代码（见下） |

**建议**：统一改为 v3 等价类（`shadow-xs`→`shadow-sm`、`shadow-2xs`→`shadow-sm`、`shadow-3xl`→`shadow-2xl`、`rounded-*-xs`→`rounded-sm`），或干脆升级 Tailwind v4。**治本手段是接入 `eslint-plugin-tailwindcss`（规则 `no-invalid-classes` 类检查），这类 bug 本可在构建期拦住**——这也是 lint 缺失（见 P2）最直接的代价。

**✅ 已修复（2026-09-08）**：FloatingChat.tsx 5 处、Layout.tsx 4 处全部改为 v3 等价类（`shadow-sm`/`rounded-br-sm`等）；死代码 Chat.tsx 内的 5 处随文件删除。已接入 ESLint 9 + `eslint-plugin-tailwindcss`（`no-custom-classname` 规则，等效拦截无效类名）+ react-hooks 插件，归档实现的 `archive/eslint.config.js` 已生效。首次运行即抓出 9 个错误（含 `prose-xs`——项目未装 typography 插件，该类同样无效，已清除）。

### P1 · ✅ 已修复 · 死代码与大规模重复的聊天实现

- `archive/apps/web/src/pages/Chat.tsx`（**1010 行**）没有挂任何路由（`src/routes/index.tsx:28` 将 `/chat` 重定向到 `/`），功能已被 `FloatingChat.tsx` 取代；两者存在约 500 行近复制粘贴（`PendingConfirmation`、`ToolStep`/`LiveState` 类型、SSE 事件处理、工具确认 UI、markdown 渲染各写一份）。
- `archive/apps/web/src/pages/Toolbox.tsx`（119 行）同样未挂路由（`routes/index.tsx:30`）；`Classroom.tsx`（10 行）是占位符。
- **建议**：直接删除 `Chat.tsx` 与 `Toolbox.tsx`（git 历史可找回）；若未来需要独立聊天页，应先抽取 FloatingChat 中的共享组件（消息列表、工具步骤、确认弹窗）而非再复制一份。

**✅ 已修复（2026-09-08）**：`Chat.tsx`（1010 行）与 `Toolbox.tsx`（119 行）已删除，删除前确认无任何 import 引用（routes 中的 `/chat`、`/toolbox` 重定向不依赖这两个文件）。FloatingChat 保留为唯一聊天实现。

### P2 · ✅ 已修复 · 课表网格的脆弱定位数学

`archive/apps/web/src/components/TimetableGrid.tsx:68-110`：课程色块用**绝对定位 + 手算高度**（`span * 48 + (span - 1) * 1` 补偿边框，行高硬编码 48px、内缩 2px）。注释写着「用 rowSpan 跨行」但实际未用 rowSpan。任何导致行高偏离 48px 的因素（浏览器边框渲染差异、未来加入新内容）都会让色块与节次数字、网格线累积漂移。另外 1 节的小色块高度约 44px，要塞下 3-4 行文字，长课程名会被 `truncate` 截断。

**建议**：改用真正的 `rowSpan`（td 跨行后色块随行自然拉伸，无需手算高度），或用 CSS grid 的 `grid-row: span N`。这是结构性修复，一次做完即可根除。

**✅ 已修复（2026-09-08）**：`TimetableGrid.tsx` 整体重写为 CSS Grid 显式定位：节次列/日格用 `gridColumn`/`gridRow` 精确放置并负责画线，课程块用 `gridRow: span N` 跨行，随行高自动伸缩，彻底删除手算高度逻辑。同格多门课在容器内 flex 并排（容器按最高课跨行）。浏览器几何验证：13 个课程块与节次行线全部对齐（误差 <1px，0 错位），截图确认渲染正常。

### P2 · ✅ 已修复 · 零测试

全仓没有任何测试运行器与测试文件。最值得先补的是纯函数：

- `archive/packages/core/src/domain/schedule.ts`（723 行课表解析/映射，含 `mergeTimetableEntries`）——输入输出明确，最适合单测；
- `archive/apps/web/src/components/TimetableGrid.tsx` 的 `compressWeeks`（周次压缩）；
- `archive/packages/server/src/auth/credentials.ts`（加密存储）。

**建议**：接入 vitest（monorepo 下各包共用一个 workspace 配置即可），从上述纯函数开始。

**✅ 已修复（2026-09-08）**：接入 vitest 2.1.9（归档实现的 `archive/vitest.config.ts`，`pnpm test`）。新增三组共 26 个单测：`archive/packages/core/src/domain/zdbk.test.ts`（mergeTimetableEntries 10 例：连续缝合/周次冲突/教师冲突/子学期隔离/链式合并/排序等）、`archive/apps/web/src/__tests__/compressWeeks.test.ts`（7 例）、`archive/packages/server/src/auth/credentials.test.ts`（9 例：加密往返/进程重启可读/密文不含明文/v2 格式结构/多条混写）。26/26 通过。

### P2 · ✅ 已修复 · lint 是空操作

归档实现的 `archive/package.json:19` 定义 `"lint": "pnpm -r run lint"`，但**没有任何子包定义 lint 脚本**，也没有 ESLint/Prettier 配置——`pnpm lint` 什么都不做。**建议**：接入 ESLint（typescript-eslint + eslint-plugin-react-hooks + eslint-plugin-tailwindcss），一次性解决风格统一与上述无效类名拦截。

**✅ 已修复（2026-09-08）**：接入 ESLint 9 flat config（归档实现的 `archive/eslint.config.js`）：typescript-eslint recommended + react-hooks（error/warn）+ tailwindcss `no-custom-classname`（白名单 `fa-fw`/`input` 两个非 Tailwind 自定义类）。归档脚本改为 `"lint": "eslint ."`。首轮跑出 9 错误 2 警告已全部修复（含 `prose-xs` 无效类、`format.ts` prefer-const、两处 `?? []` 依赖失稳、测试弱断言），现零错误零警告。

### P2 · ✅ 已修复 · 静默吞错

- `archive/packages/zju-services/src/courses/index.ts:54, 64`、`archive/packages/zju-services/src/zdbk/index.ts:79, 93`：裸 `catch {}`，解析失败时无声跳过，用户只会看到「数据莫名缺失」；
- `archive/packages/server/src/auth/credentials.ts` 的 `readAll()`：任何读取失败都返回 `{}`，凭据库损坏对用户不可见。

**建议**：至少记 warn 日志；对「解析失败」与「确实无数据」区分返回，让前端能提示。

**✅ 已修复（2026-09-08）**：zju-services 4 处 `catch {}` 全部改为捕获并 `console.warn`（保留原返回语义，不改变控制流；`runQuiet` 只静音 `console.log`，warn 正常输出）。`credentials.ts` `readAll()` 的 4 个失败分支（机器环境变化/文件读取失败/单条解密失败）均加了 warn 日志。

### P3 · ✅ 已全部修复 · 其他小项

| 位置 | 问题 | 建议 | 状态 |
|---|---|---|---|
| `archive/packages/server/src/auth/credentials.ts` `writeAll()` | 每次写入/删除都对全部凭据重新加密（每条 PBKDF2 200k 迭代） | 缓存派生密钥，或只重写变化的条目 | ✅ 引入 v2 文件格式：文件级共享 salt + PBKDF2 结果内存缓存。首次写入 1 次派生，之后 0 次；GCM 安全性由每条独立随机 IV 保证。读取兼容 v1 旧格式，下次写入自动迁移 |
| `archive/packages/server/src/util/rate-limit.ts` | 过期桶永不从 Map 清除（本地应用影响小） | 写入时顺带清理过期桶 | ✅ 每次 `check()` 顺带清理过期桶 |
| `archive/packages/server/src/server.ts:89-102` | `onSend` 钩子靠字符串嗅探 `{"ok":false` 再反解 JSON 映射 HTTP 状态码，脆弱 | 用 Fastify `setErrorHandler` 统一处理 | ✅ 改为 `preSerialization` 钩子：在序列化前检查已解析对象，无需字符串嗅探（`setErrorHandler` 原本已存在，负责框架层错误） |
| `Dashboard.tsx:306-337` Segmented 切换器 | 角标（日程绿点/作业数徽标）在数据加载后才渲染，crisp 滑块按 `offsetWidth` 测量可能滞后错位 | 角标用固定占位（visibility）或数据到达后再渲染整个 Segmented | ✅ 复核 crisp 源码后确认**无需修复**：滑块测量 `useLayoutEffect` 依赖 `[selected, options]`，Dashboard 每次 render 生成新 options 引用，角标出现会触发重新测量，不存在滞后 |
| `Dashboard.tsx:546-555` | 「待办作业」卡 `items-baseline` 行内混排 16px 高 Badge 与 `text-3xl` 数字，基线对齐观感偏高 | Badge 改 `items-center` + `self-center` | ✅ Badge 加 `self-center` |
| `Layout.tsx:82` | 图标上强行 `w-4 text-center`（对 svg 无效的 text-align） | 用 FA 固定宽类 `fa-fw` 或去掉 | ✅ 改为 `fa-fw` |
| `archive/CLAUDE.md` | 描述了已不存在的固定 dev token `dev-local-token-zju-agent`（现行 auth 走 `/api/bootstrap` 下发）；仓库布局描述（兄弟目录）过时 | 更新文档 | ✅ 两处均已更新 |

## 总体评价

架构质量高于典型学生项目：pnpm monorepo 分包清晰、全仓严格 TypeScript（零 `any`）、统一 API 信封、认真做的本地安全模型（环回绑定、AES-256-GCM + PBKDF2 凭据加密、时序安全 token 比较、启动时清理遗留明文密钥）。主要短板集中在**前端样式构建期校验缺失**（本次 bug 的根因）、**测试与 lint 双缺失**、以及聊天 UI 的复制粘贴式复用。
