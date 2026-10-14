# 分析报告：M1-P01 core 值对象（speckit-analyze 结论与决策待办）

**产出命令**：`/speckit-analyze` ｜ **分析日期**：2026-10-13 ｜ **只读，未改动任何被分析产物**

**位置说明**（2026-10-14 调整）：本文件由所有者指示从特性目录
`specs/001-m1-p01-core-value-types/` 移至 `docs/analysis/001-m1-p01-core-value-types/`，
以避免 analyze 留痕混入规格类产物目录。**文中对 `spec.md` / `plan.md` / `tasks.md` /
`data-model.md` / `research.md` / `contracts/*` / `quickstart.md` 的裸文件名与行号引用，
一律相对特性目录 `specs/001-m1-p01-core-value-types/` 解读**；对宪法的行号引用相对
仓库根 `.specify/memory/constitution.md`（现行 v1.1.0）。

**分析范围**：`spec.md` / `plan.md` / `tasks.md` 三核心产物，辅证
`data-model.md` / `research.md` / `contracts/` / `quickstart.md` /
`checklists/requirements.md`，对照 `.specify/memory/constitution.md` v1.0.0
（批准 2026-10-12）。

**度量**：FR 11 ｜ SC 4 ｜ US 4 ｜ Tasks 19 ｜ FR 覆盖率 100%（2 项部分覆盖）
｜ CRITICAL 1 ｜ HIGH 3 ｜ MEDIUM 5 ｜ LOW 6 ｜ 歧义点 3 ｜ 重复点 1
｜ **回写期新发现 4（N1–N4，已全部定案：均取 A）**

**第二轮度量（2026-10-14 复跑，回改链 clarify → plan → tasks 已走完）**：
19 项决策（C1–M6、L1–L6、N1–N4）逐条核查**全部落地一致**（含 plan V 行
逐字未动、import 键、`@http.Protocol`、derive 口径、两个测试文件、F12 欠账）
｜ Tasks 19→20（新增 T019 SC-005 泄漏验收）｜ 需求 18（13 FR + 5 SC）覆盖率
**17/18**（FR-011 零任务）｜ **新发现 8：CRITICAL 1（R2-D1）、HIGH 1（R2-F1）、
MEDIUM 4（R2-C1/R2-B1/R2-E1/R2-C2）、LOW 2（R2-B2/R2-A1）** ｜ 第一轮条目
已闭环，本轮不重述。

**文档格式说明**（在用户给定模板上的两处调整，理由如下）：

- `## <ID> <标题>` 之下的「问题描述」保留结论表全部信息（类别/严重度/位置/
  摘要/建议）并补充上下文与影响，便于脱离对话独立决策。
- 子节改用 `### 决策及建议`（模板中为 `##`）以维持标题层级；文末追加
  `# 决策登记表` 与 `# 下游动作` 两节——前者供一次性勾选，后者把决策结果
  映射到 speckit 命令链（改需求必须回改 spec 再向下重新生成）。

**结论**：存在 1 个 CRITICAL + 3 个 HIGH，**建议先关闭 C1/H1/H2/H3 再进入
`/speckit-implement`**；另有回写期新发现 N1–N4，**已全部定案（均取推荐项 A）**——
N1 定 derive + 显式 `pub extend` 的零警告口径，N2 定复用上游 `@http.Protocol`，
N3 定头校验与调试脱敏拆为 FR-012/FR-013，N4 定「默认脱敏 + 显式逃生口方法」
（可配置掩码 flag 归 M3）。决策已全部编码进 spec 的链条见 `# 下游动作`。

**第二轮结论（2026-10-14）**：第一轮的 19 项已全部在三层产物闭环，但复跑暴露
**新的 1 个 CRITICAL（R2-D1：`HeadersVBuilder` 的 derive(Debug) 构成宪法掩码
MUST 的旁路——第一轮 C1 只关闭了 HeadersV 一侧）与 1 个 HIGH（R2-F1：SC-004
「四个目标 `moon check` 零警告」与 wasm-gc 显式不支持互斥，质量门按字面必红）**。
**implement 前置条件重新打开**：至少关闭 R2-D1 与 R2-F1；其余 6 条建议同轮
一并勾选，避免第三次回环。

**第三轮度量（2026-10-14·对齐宪法 v1.1.0）**：起因是所有者把宪法人工修订到
**v1.1.0**（`constitution.md:148`，脱敏条款相对 1.0.0 放宽：自动掩码从机制性 MUST
降为「可选手段之一」，同时新增「确需展示 MUST 事先汇报所有者并经人工确认」的程序性
MUST），以及 R2 八条已勾选。新出 **7 条：CRITICAL 1（R3-C1，只能人工关闭——涉宪法
文件，所有者已指令 agent 不得修改）、HIGH 1（R3-H1）、MEDIUM 4（R3-M1/R3-M2/R3-M3/
R3-M4）、LOW 1（R3-L1）**；同时把 R2-D1 的 CRITICAL 定性降级（旁路问题被依据变更
消解）、把 R2-F1 的 HIGH 升级为 CRITICAL（勾选越出规格层，撞上宪法未改的 target
条款）。第一/二轮正文按当时条文成立，**保留为历史留痕不改写**。

**第三轮结论**：P01 仍**不可进入 `/speckit-implement`**。硬阻塞是 R3-C1（js/wasm-gc
口径与宪法 :69/:127-129 冲突，须人工提修订或回退勾选的一半）与 R3-H1（四层产物仍
把「默认脱敏」写成 MUST，与所有者新方向相反，须走 clarify→plan→tasks 回改链）；
R3-M1 是必须补的宪法手续留痕。修订草案文本见文末**附录 A**（未写入宪法文件）。

---

## 回写状态（2026-10-13）

- **C1–M6 讨论结论已全部接受**，L1–L6 按本文件「人类选择」原文接受；决策登记见
  文末 `# 决策登记表`。
- **本文件是这批决策的唯一留痕源**。曾按决策手写回改
  `spec.md`/`data-model.md`/`contracts/`/`plan.md`/`tasks.md`，已按用户指示
  **全部回退**——规格类产物不得手改，必须走
  `/speckit-clarify`（或 `/speckit-specify`）把决策编码进 spec，再
  `/speckit-plan` → `/speckit-tasks` 向下重生成（宪法「开发工作流与质量门」）。
  回退前的手写稿快照留在仓库根 `_revert_backup/`（未跟踪，可整体作为重生成参考）。
- 讨论期相对原始勾选的三处收窄已在对话中达成倾向；**回写期新发现四项 N1–N4**，
  正文条目见 `# 问题` 末尾，勾选位见 `# 决策登记表`：
  - **N1**：`derive(Eq, Hash, Debug)` 触发的 `implicit_impl_as_method` 警告 [0079]
    与「`moon check` 零警告」口径如何两全（derive + 显式 `pub extend`／容忍警告／
    全手写 impl）。
  - **N2**：H3 选「B 且 `HTTP`/`HTTPS` 大写」与上游已有 `@http.Protocol`
    （`request.mbt:17-25`）语义重复，scheme 最终用哪个类型、`default_port`
    归谁所有。
  - **N3**：本报告自身的缺陷——C1 与 H2 的推荐项都写「新增 FR-012」，
    两条独立 MUST 撞同一编号，需定划分与排序。
  - **N4**：用户 2026-10-13 提议「默认启用敏感信息掩码、可用 flag 禁用便于特殊
    调试」，其开关形态（显式逃生口方法 vs 包级全局 flag）与归属里程碑待定；
    技术边界（derive 读不到开关、开发期不脱敏会把明文写进 `.snap`）见该条正文。
  **N1–N4 已全部定案（均取 A）**，H3/M5 的「讨论倾向」随之成为结论；N3 决定
  C1/H2 落地占两条 FR（FR-012 头校验、FR-013 调试脱敏），N4 决定 FR-013 的
  内容形态（默认脱敏 + 显式逃生口，不引入包级 flag）。
- 被回退的手写稿整体留存在仓库根 `_revert_backup/`（未跟踪目录），可作为
  `/speckit-clarify` 重生成时的行文参考，确认无用后可删除。
- **M4 按「这里不动」执行**：plan.md 宪法检查表 V 行保持原样，例外可追溯性仅靠
  本条目与研究 R7 / M1 README D9 / deferred-items F9 承担（本报告即留痕）。
- **回改链进度**：`/speckit-clarify` 已完成（2026-10-13，Auto Mode 下按登记表
  全部定案执行，未新增提问）。spec.md 实测增量与「可预期增量」一致并另加 SC-005：
  FR 11→**13**（新增 FR-012 头校验 raise `HeadersError`、FR-013 调试输出默认脱敏
  + 显式逃生口）、SC 4→**5**（SC-004 写入「四目标 `moon check` 零错误零警告 +
  derive 配 `pub extend`」，新增 SC-005 敏感头零明文泄漏）、Edge Cases 12→**15**
  （端口 `1..=65535` 与 `http://h:0/`、非法头名、头值含 CR/LF、脱敏输出）、
  Clarifications `### Session 2026-10-13` 由 2 条增至 **14** 条、Key Entities 增
  `HeadersVBuilder` 与 `HeadersError`、A7 后新增 **A8**（掩码开关归 M3）、
  术语全量 snake_case（`default_port`/`to_string`）。
  `checklists/requirements.md` 复验 **16/16** 项通过，无回退。
  下游链条已全部跑完：`/speckit-plan`（刷新 plan.md：新增「技术约束与合规·敏感
  信息自动掩码」✅ 行、V 行逐字未动、IV 行改 15 条、源码清单补两个测试文件、
  Performance Goals 写入 M6-A 结论、初始化占位 L5-A 定案；research 补 R11–R14；
  data-model 成为错误变体唯一规范源；contracts 三份与 quickstart 五步同步）→
  `/speckit-tasks`（T001–T020 重生成，新增 T019 零明文泄漏验收）→
  `/speckit-analyze` **复跑（2026-10-14）**：19 项决策核查全部通过，但
  **未达 CRITICAL=0/HIGH=0**，新出 R2-D1（CRITICAL）与 R2-F1（HIGH）等 8 条，
  明细见 `# 问题` 末尾「第二轮复跑」段与文末「第二轮登记表」。
- **回改后的可预期增量**（按当前倾向：N1-A/N2-A/N3-A；供
  `/speckit-clarify` → `/speckit-plan` → `/speckit-tasks` 核对，避免重生成时口径漂移）：
  Edge Cases 由 12 条变为 **15 条**（M1 补 `http://h:0/` → `InvalidPort` 1 条，H2 补
  非法头名 / 头值含 CR·LF 2 条），plan 与 quickstart 的「13 条」计数（L2）随之改为
  15；新增公开类型仅 `HeadersError`（H2），scheme 侧公开面不增（N2-A 复用上游
  `@http.Protocol`；若改选 N2-B/C 则 +1 枚举与映射）；spec 新增 2 条 FR（N3-A），
  FR 总数由 11 变为 13。**N4 已定 A，增量不变**（FR-013 仍一条、Edge Cases 仍 15 条），
  仅 T018 冻结清单多一个显式逃生口方法（`debug_unredacted` 类命名 tasks 期定）；
  可配置掩码 flag 走 deferred-items 挂钩 M3，不进本包 FR。

---

# 待办

| ID | 类别 | 严重度 | 位置 | 一句话摘要 | 阻塞 implement? |
|----|------|--------|------|------------|------------------|
| C1 | 宪法合规 | CRITICAL | spec FR-006(L150-151)、data-model §2、tasks T014/T018、plan 检查表(L43-51) | HeadersV 的 `derive(Debug)` 会原样打印 Authorization/Cookie 头值，违背宪法「敏感信息自动掩码」MUST，且该条款从未进入宪法检查表 | 是 |
| H1 | 覆盖/可测性 | HIGH | SC-003(L191-192)、tasks T015(L186-187) | 折叠属性测试命题自相矛盾：重复名折叠后 `get` 必为 `"a,b"` ≠ `"a"`，按字面写不可通过 | 是 |
| H2 | 覆盖缺口 | HIGH | spec 全文无锚；contracts/headers.md 条款6、tasks T003/T013 | 头名 token 校验 + 头值 CR/LF 拒绝（防头注入）与新增公开类型 `HeadersError` 只存在于 tasks/contracts，spec 零 FR，违反 SDD 单向同步 | 是 |
| H3 | 不一致 | HIGH | contracts/http-url.md L36,L42 vs spec FR-002、tasks T009/T018 | 契约引入公开枚举 `Scheme`（`scheme()`/`default_port()` 签名），spec/plan/tasks/T018 冻结清单全无该实体，零任务覆盖 | 是 |
| M1 | 不一致 | MEDIUM | spec L119、T003/T006(`< 0`) vs data-model L28、T009、contracts L38(`1..=65535`) | 端口下界口径冲突，`http://h:0/` 无锚定用例 | 否 |
| M2 | 欠规格 | MEDIUM | FR-004、data-model L62、contracts/headers.md L21 vs spec US-3 场景1、T013 | `values` 契约返回 `Iter[String]`，验收与测试按数组 `["a","b"]` 断言，不可直接 `assert_eq` | 否 |
| M3 | 不一致 | MEDIUM | plan L91-92 vs tasks T007/T015 | `percent_wbtest.mbt`、`headers_fold_test.mbt` 由任务创建但不在 plan 源码结构清单 | 否 |
| M4 | 宪法合规 | MEDIUM | plan L49、research R7、M1 README D9(L85)、deferred-items F9 | 宪法 V 要求 wasm-gc「必须提供明确报错 stub」；实质已登记 D9/F9→M5 延期，但 plan 标为「✅ 通过」而非例外跟踪 | 否 |
| M5 | 不一致 | MEDIUM | FR-006 vs contracts/method-error.md(`derive(Debug, Show, Eq)`)、T003/T004 | FR-006 要求全部公开类型可哈希，错误类型无 `Hash`；`HeadersError` 的 derive 组合未声明 | 否 |
| M6 | 欠规格 | MEDIUM | spec A3、plan L33、research R4 | A3「plan 阶段评估是否惰性化 path 段」的条件在 plan 中无评估结论，悬空未闭环 | 否 |
| L1 | 术语漂移 | LOW | spec FR-002/FR-004(`defaultPort`/`toString`) vs contracts/tasks/quickstart(snake_case) | spec 用 OkHttp camelCase，下游用 MoonBit snake_case | 否 |
| L2 | 事实性偏差 | LOW | plan L48、quickstart L22 vs spec Edge Cases | 两处称「13 条边界用例」，实际 12 条 | 否 |
| L3 | 不一致 | LOW | T002 vs research R10、quickstart 前置3 | `moon.pkg` import 写法两种（`moonbitlang/async/http` 与 `.../async/@http`） | 否 |
| L4 | 重复 | LOW | spec L16、FR-009(L159-162)、Edge Cases L127、A5(L212-214) | HttpUrlError 四变体在 4 处重述，规范源不唯一 | 否 |
| L5 | 歧义 | LOW | T002 括注 | 「若空包检查报错，同时放置空的 `error.mbt` 占位」条件式兜底未定案 | 否 |
| L6 | 边界缺口 | LOW | spec Edge Cases、contracts resolve 条款 | RFC 3986 的 query-only（`?x=1`）、仅 fragment（`#f`）、base 无 path 合并分支未锚定 | 否 |
| N1 | 工具链口径 | MEDIUM | spec FR-006/SC-004、contracts/method-error、tasks T004/T009/T014/T018 | `derive(Eq, Hash, Debug)` 触发 `implicit_impl_as_method` 警告 [0079]，`pub extend` 配套写法与「`moon check` 零警告」口径未定；`@debug` 又不可作用户工程依赖 | 是 |
| N2 | 类型选型 | HIGH | contracts/http-url.md L36,L42 vs 上游 `@http.Protocol`（async `request.mbt:17-25`） | H3 勾选「自立 `Scheme` 且 `HTTP`/`HTTPS` 大写」与上游已有 `Protocol` 语义重复，`default_port` 将出现两份真相 | 是 |
| N3 | 本报告缺陷 | LOW | 本文件 C1 推荐项 A 与 H2 推荐项 A（同写「新增 FR-012」） | 两条独立 MUST 撞同一 FR 编号，划分与排序未定 | 否 |
| N4 | 宪法合规/公开面 | MEDIUM | 本文件 C1/N3（FR-013）、tasks T014/T015/T018、宪法掩码条款与「opt-in 暂不立条」段 | 用户提议「默认掩码 + flag 可关」的开关形态待定：derive 读不到开关、开发期不脱敏会把明文写进 `.snap`、全局 flag 即包级可变状态 | 否 |

**第二轮复跑（2026-10-14）新增待办**——第一轮条目已全部定案并落地，下表为本轮
新发现，全部**待勾选**：

| ID | 类别 | 严重度 | 位置 | 一句话摘要 | 阻塞 implement? |
|----|------|--------|------|------------|------------------|
| R2-D1 | 宪法合规 | **CRITICAL** | spec FR-006(L178-183) + Key Entities(HeadersVBuilder) + tasks T014 ↔ data-model §2「调试输出」行、contracts/headers.md 脱敏段、constitution.md:113-114 | FR-006 把可变的 `HeadersVBuilder` 也要求 `derive(Debug)`，Builder 持有原始名/值对，调试输出直出 `Authorization`/`Cookie` 明文；第一轮 C1 只关闭了 HeadersV 一侧，掩码 MUST 仍有旁路 | **是** |
| R2-F1 | 不一致 | **HIGH** | spec SC-004(L246-247)、plan L32、tasks T018 ↔ plan L34/L54（V 行，M4 锁定）、research R7、quickstart L73 | 「四个目标 `moon check` 零错误零警告」与「wasm-gc 显式不支持」互斥：`moon check --target wasm-gc` 是编译失败而非警告，质量门按字面必红 | **是** |
| R2-C1 | 欠规格 | MEDIUM | contracts/headers.md:10 ↔ spec FR-004/Key Entities、data-model §2、tasks T014/T018、quickstart L44-49 | 构造入口 `HeadersV::builder()` 只存在于契约；spec 未指定如何取得 Builder，T018/quickstart 的 `.mbti` 冻结清单也不含它 → 审视必现「清单外公开面」 | 否 |
| R2-B1 | 歧义 | MEDIUM | tasks T014 ↔ quickstart L47-48、spec SC-004 | 手写 `impl Debug` 是否同样需要 `pub extend HeadersV with Debug::{to_repr}` 未定；与 R2-D1 的 Builder 取舍必须一起定，否则冻结清单无法逐条核对 | 否 |
| R2-E1 | 覆盖缺口 | MEDIUM | spec FR-011 ↔ tasks 全文、quickstart L74 | FR-011「本包无网络 IO 与执行逻辑」是 MUST，却零验收任务，只在 quickstart 列为「已知不验证项」 | 否 |
| R2-C2 | 欠规格 | MEDIUM | spec SC-005 + tasks T013/T019 | 现有测试任务全为 `assert_*`，无任务产出 `.snap`；T019 的 `git grep .snap` 可能因「无文件」平凡通过，掩码形态也缺回归固化 | 否 |
| R2-B2 | 歧义 | LOW | spec FR-013(L203) ↔ FR-006/SC-004 的 `Show` 禁令 | FR-013 的「调试与**展示**输出」在本包无对应 API（全包禁 `Show`、无 `to_display`），易被实现成多一处公开面 | 否 |
| R2-A1 | 术语 | LOW | spec FR-006、quickstart L44 ↔ data-model §2 | 可变的 `HeadersVBuilder` 被归入「值类型」，与 data-model「不可变值」叙述混用；正是 R2-D1 的推导要害 | 否 |

**第三轮（2026-10-14·对齐宪法 v1.1.0）新增待办**——本轮起因是**宪法已被人工修订到
v1.1.0（最近修订 2026-10-14），脱敏条款相对 1.0.0 放宽**，以及 R2 八条已勾选后
暴露的宪法侧冲突。第一/二轮条目按当时条文成立，作为历史留痕**不改写**：

| ID | 类别 | 严重度 | 位置 | 一句话摘要 | 阻塞 implement? |
|----|------|--------|------|------------|------------------|
| R3-C1 | 宪法合规（agent 不可关闭） | **CRITICAL** | 用户 R2-F1 决策「目标只保留 native/wasm，js/wasm-gc 目前不需要 check」↔ constitution.md:127-129（js 门禁「至少 `moon check --target js` 通过且能力降级清单已同步」）、:69/:72/:73（原则 V 优先级与 js P1、wasm-gc P2 stub）、plan.md:54（M4 锁定 V 行） | R2-F1 的勾选不是 spec 内部矛盾，而是与**现行宪法未改的 target 条款正面冲突**；用户已明确「不允许修改宪法，将问题记录到报告中」，故该冲突只能由人工提修订（或回退勾选）关闭——宪法修订流程见 :138-141 | **是（须人工）** |
| R3-H1 | 上游依据漂移（四层产物仍写死脱敏） | **HIGH** | spec FR-006 末句/FR-013/SC-005/Edge Cases 第 15 条/Key Entities/A8；plan「技术约束与合规·敏感信息自动掩码 ✅」行与 Constraints；data-model §2「调试输出」行 + §5；contracts/headers.md 脱敏段；quickstart 步骤 3/4；research R13/R14；tasks T013/T014/T015/T018/T019 ↔ v1.1.0 :109-114 与 R2-D1/R2-B1/R2-C2 决策 | 四层产物把「HeadersV 默认脱敏 + 手写 `impl Debug` + 显式逃生口 + 零明文快照」写成 MUST，与所有者的新方向（P01 先用默认 `Debug`、脱敏另开专版）**方向相反**；规格类产物不得手改，必须走第三轮回改链 | **是** |
| R3-M1 | 宪法手续（展示敏感信息的确认留痕） | MEDIUM | v1.1.0 :109-114（「默认不得出现」仍是 MUST；「确需展示 MUST 事先主动汇报项目所有者、经人工确认后方可实现」）↔ R2-D1「Debug 先用默认实现」+ R2-C2「测试数据 `.snap` 不需要脱敏」 | 放宽的是**手段**（自动掩码不再机制性强制），不是**默认不展示**这个目标；采用默认 `Debug` 即走「确需展示」路径，必须留人工确认痕（本条即留痕位）并在 plan.md 记 `# 例外跟踪`（:136-137），脱敏实现另登记新欠账 | 是（手续，非代码） |
| R3-M2 | 验收自相矛盾 | MEDIUM | spec SC-005、tasks T019 ↔ R2-C2 决策 | 不脱敏后 SC-005「零明文泄漏」失去实现对象，而 T019 的 `git grep` 会**反向必红**（明文样例值恰恰就在测试与 `.snap` 里）；SC-005 须随 R3-H1 一并改写或删除，判据从「不含明文」改为「不含展示 API / 错误消息不整体回显输入」 | 是（随 R3-H1 关闭） |
| R3-M3 | 公开面收窄 | MEDIUM | tasks T014/T018、quickstart L44-49、contracts/headers.md 脱敏段 ↔ N4-A 的逃生口 | 默认 `Debug` 已出明文，N4-A 的「显式逃生口方法」（`debug_unredacted` 类）失去意义，应退出 P01 公开面（冻结清单净减一项）；R2-D1 的 Builder 旁路也随之自动闭合（无脱敏即无「绕过」） | 否 |
| R3-M4 | roadmap 侧交付物 | MEDIUM | docs/roadmap/deferred-items.md（F12）、deferred-items/deferred-items-m1.md、docs/roadmap/M1/P01-core-value-types.md | 「脱敏专版」需要新欠账项（建议 F13）承载并明确归属里程碑（M3 可观测与安全），P01 包摘要也要按「不含脱敏」改写；roadmap 文档非规格类产物，可在回改链之后直接编辑 | 否 |
| R3-L1 | 本报告自引用陈旧 | LOW | 本文件「分析范围」行（「对照 constitution.md v1.0.0」）与 R2 条目内的 `constitution.md:113-114` 行号 | 第一/二轮引用当时条文与行号无误，保留为历史留痕；第三轮起统一引用 1.1.0 现行行号（掩码段 :109-114、js 门禁 :127-129、原则 V :67-74、治理 :136-141） | 否 |

---

# 问题

## C1 HeadersV 调试输出的敏感头未脱敏（宪法 MUST 冲突，未记录）

**类别**：宪法合规 ｜ **严重度**：CRITICAL ｜ **位置**：spec.md:150-151（FR-006）、
data-model.md §2（判等/哈希与折叠行）、tasks.md T014（`derive(Eq, Hash, Debug)`）、
tasks.md T018（`.mbti` 冻结清单）、plan.md:43-51（Constitution Check 表）

**问题描述**：宪法「技术约束与合规·敏感信息自动掩码」（constitution.md:113-114）
是 MUST 级条款：日志、**调试输出**、EventListener、错误消息与错误上下文中的
`Authorization`、`Proxy-Authorization`、`Cookie`、`Set-Cookie`、URL 用户信息
**必须自动脱敏**。而 FR-006 要求本包全部公开类型「可调试输出（Debug）」，
T014 对 HeadersV `derive(Eq, Hash, Debug)`——derive 出来的 Debug 会逐条原样打印
名/值对，任何一次 `debug_inspect` 快照或测试失败回显都可能把 Authorization/Cookie
明文写入日志与 `.snap` 快照。三份产物与 contracts 中「脱敏」仅出现在**错误消息**
口径（data-model.md:90、method-error.md:42 的「只携带定位片段」），从未覆盖
HeadersV 的 Debug/Show；plan.md 的宪法检查表只列了核心原则 I–VII，
**根本没有「技术约束与合规」这一章的行**，因此该 MUST 从未被检查、也无例外记录。
按本命令约定，宪法冲突自动 CRITICAL，且只能改 spec/plan/tasks，不能靠淡化条款解决。

### 决策及建议

- **A.（推荐）在 spec 补脱敏 FR，并把「技术约束与合规」纳入检查表**：新增
  FR-012「HeadersV 的调试/展示输出 MUST 对 Authorization / Proxy-Authorization /
  Cookie / Set-Cookie 的值脱敏」（编号与 H2 的冲突见 **N3**）；HeadersV 改为手写
  `impl Debug`（或提供 `redacted_debug()`），T013/T015 增加脱敏断言，T018 冻结清单
  同步；plan 检查表增行并标 ✅。代价：HeadersV 不能纯 derive，实现量 +约 0.25 人日，
  但符合宪法且一次性闭环。（**脱敏之后要不要留明文路径、以什么形态留，见 N4**；
  无论 N4 选 A/B，本条「必须手写 `impl Debug`」的结论都不变。）
- **B. 显式声明本包不适用并登记例外**：在 spec A6/A7 记录「M1-P01 无日志/
  EventListener 管线，脱敏属门面层职责」，在 `docs/roadmap/deferred-items.md`
  新增 F 项挂钩到 P02（Request/Response 值对象）或门面包，plan 检查表该行标
  「⚠️ 例外（F?→P02）」。代价：M1-P01 期间 `.snap` 快照仍可能落盘明文头值，
  宪法条款在本包实际未满足，需以例外形式承担。
- **C. 折中：脱敏延后但禁止本包使用 Debug 快照**：不改 FR-006，规定本包测试
  一律用 `assert_eq` 断言语义、不得对 HeadersV 用 `debug_inspect` 快照（宪法 IV
  已允许），同时在 spec 记录 B 的例外。代价：规避而非实现，derive 的 Debug 仍在
  公开面上对外泄漏。

**人类选择**：A

---

## H1 SC-003 折叠属性测试命题不可满足

**类别**：覆盖/可测性 ｜ **严重度**：HIGH ｜ **位置**：spec.md:191-192（SC-003）、
tasks.md T015:186-187、contracts/headers.md 契约条款 4

**问题描述**：SC-003 原文「HeadersV 任意头列表折叠后，`get` 首个语义与折叠前一致
（属性测试）」。折叠定义（FR-005）把同名多值合并为单值：`add("X","a")` +
`add("X","b")` → 折叠后 Map 中该键值为 `"a,b"`。于是折叠后 `get("X")` = `"a,b"`，
而折叠前 `get("X")` = `"a"`——**凡存在重复名，该命题必然为假**。T015 照抄了同一
表述并计划用种子随机+循环生成头列表来跑属性测试，实现者要么写出一个必红的测试，
要么临场私自收窄口径（导致 SC-003 名义达成、实质未定义）。这属宪法 IV
「验收判据必须可测」的直接障碍。

### 决策及建议

- **A.（推荐）改为两个可满足的不变量**：把 SC-003 改写为①「无重复名的任意头列表，
  折叠后每个名字的 `get` 值与折叠前逐字节相等（折叠对单值名是恒等映射）」；
  ②「有重复名时，折叠值 = 按插入序以 `,` 无空格拼接，且该串再经 @http 响应侧
  parser 拆分可还原原名值序列（进出互逆）」。T015 的属性测试按①生成唯一名列表、
  另加确定性用例覆盖②。
- **B. 收窄为单值不变量**：只保留 A-①，删除互逆部分；互逆性由 T015 现有的
  `"a,b"` 逐字节对称锚点承担。代价：SC-003 强度下降，但最简单。
- **C. 保留原措辞并加限定语**：改为「`get` 首个语义在**无重复名**前提下折叠前后
  一致」。与 A-① 等价但只有一条，缺互逆保证。

**人类选择**：A

---

## H2 头校验（防头注入）与 HeadersError 无 spec 锚点

**类别**：覆盖缺口 ｜ **严重度**：HIGH ｜ **位置**：spec.md 全文（无对应 FR/场景/
边界用例）、contracts/headers.md 契约条款 6、tasks.md T003:60-61 与 T013:158-160、
method-error.md「Builder 头校验错误」节

**问题描述**：头名必须为非空 RFC 9110 token、头值不得含 CR/LF（**防头注入**）
这条安全行为只写在 contracts 与 tasks 里：spec 的 FR-001~FR-011 无一条涉及，
US-3 的三个验收场景只覆盖 add/set/相等性，Edge Cases 只提「空容器」「值为空串」，
**没有任何一条提到非法名或 CR/LF**。同时 `HeadersError` 这个**新公开类型**由
T003 直接落定（method-error.md 曾把它标为「tasks 阶段定」），公开面因此变成
5 值类型 + 2 枚举，而 spec Key Entities 仍只列 4 个实体。宪法「开发工作流与质量门」
明写：改需求必须回改 spec 再向下重新生成，**不得手改 tasks 使其与 spec 脱节**
（constitution.md:123）；当前 tasks.md 已经跑在 spec 前面。安全类需求缺失尤其危险，
因为 P02/P05 会把它当作已验收能力继承。

### 决策及建议

- **A.（推荐）回改 spec，再向下重生成**：新增 FR-012「HeadersV Builder MUST 拒绝
  非法头名（空名、非 token 字符）与含 CR/LF 的头值，raise 可判别的 `HeadersError`
  （`InvalidName`/`InvalidValue`）」（编号与 C1 的冲突见 **N3**）；Key Entities 增
  `HeadersError`；US-3 增验收
  场景「Given `add("Bad Name","v")` 或值含 `\r\n`，Then raise 可判别错误」；
  Edge Cases 增 2 条。随后 `/speckit-plan`（更新检查表与结构）→ `/speckit-tasks`
  （保持 T003/T013 锚定新 FR）。
- **B. 并入 HttpUrlError（method-error.md 原方案 a）**：不新增类型，校验失败归
  `HttpUrlError::MalformedUrl`，公开面不膨胀。代价：语义错位（URL 错误类型承载
  头错误），且 spec 仍需一条 FR 描述该行为；与宪法 VI 的「简洁」相容但与 III 的
  OkHttp `Headers.Builder` 语义偏离。
- **C. 维持现状，仅在 spec 加「范围说明」把校验记为计划外**：把校验声明为
  「实现期防御性细节，非 FR」。代价：防头注入属安全需求，宪法 III/IV 要求可审的
  验收场景，此选项实质是把安全行为留在文档盲区。

**人类选择**：A

---

## H3 契约引入未定义公开实体 Scheme，零任务覆盖

**类别**：不一致 ｜ **严重度**：HIGH ｜ **位置**：contracts/http-url.md:36
（`scheme() -> Scheme`）、:42（`default_port(scheme : Scheme) -> Int`）vs
spec.md FR-002/Key Entities、tasks.md T009:104-113、T018:212-217、plan.md:114-116

**问题描述**：`Scheme` 这个类型名**只出现在 contracts/http-url.md 的两处签名**，
在 spec.md、plan.md、data-model.md、tasks.md 中检索为零（全文其余 `Scheme` 命中
均为 `UnsupportedScheme` 变体名）。后果链条：①T009 把 scheme 建模为「仅 http/
https 小写」的**字段**（隐含 String 形态），与契约的枚举返回类型直接矛盾；
②T018 的 `.mbti` 公开面冻结清单和 plan 的「4 值类型 + 1 枚举」接口纪律核算
都不含 `Scheme`，若实现照契约写，SC-004 的人工审视会看到清单外泄漏；
③没有任何任务负责定义 `Scheme`，属需求→任务的覆盖断点；④`default_port` 在
契约里是「接收 Scheme 参数的静态形态」，在 FR-002/data-model 里是
「`defaultPort(scheme)`」，在 T009 里是「`default_port`（http=80/https=443）」，
三处签名互不相同。

### 决策及建议

- **A.（推荐）契约降级，scheme 用 String + 实例方法**：`scheme() -> String`
  （值为 `"http"`/`"https"`）+ `default_port(self) -> Int`（或
  `HttpUrl::default_port(scheme : String)`，择一并写进契约）。改动最小，
  与 T009/T018/plan 接口核算完全一致；判等仍由六字段结构保证。
- **B. 采纳 Scheme 并自上而下补齐**：`pub enum Scheme { Http; Https }`，
  写入 spec Key Entities 与 FR-002、plan 文件结构（并入 `http_url.mbt`）、
  T009 与 T018 冻结清单，并 derive Eq/Hash/Debug（联动 M5）。收益：类型面杜绝
  非法 scheme，访问器返回值可穷举匹配；代价：公开面 +1 类型，需重跑 plan/tasks。
- **C. 折中：Scheme 私有 + 公开字符串访问器**：内部用枚举规范化存储，
  公开 `scheme() -> String`，`.mbti` 不泄漏。实现细节自由但需 T009 明确说明，
  避免「私有枚举 + 公开 String」的往返转换成本写进热路径。

**人类选择**：B 但是 HTTP HTTPS 应大写
→ **讨论倾向（正式决策见 N2，待勾选）**：方向取 B（scheme 为封闭枚举、拒绝
String 弱类型），但倾向**不自立类型**——复用上游 `@http.Protocol { Http; Https }`
（`pub(all)`，值名即 `Http`/`Https`，与 async 惯用大小写一致；大写 `HTTP`/`HTTPS`
合法但非 MoonBit 惯例），`default_port` 一并复用上游方法。无论最终选 N2 的哪条，
`scheme()` 返回类型与 `default_port` 归属都须写进 spec FR-002 与 Key Entities、
T009/T018 冻结清单同步。

---

## M1 端口下界口径冲突（`< 0` vs `1..=65535`）

**类别**：不一致 ｜ **严重度**：MEDIUM ｜ **位置**：spec.md:119、tasks.md T003:57、
T006:90 vs data-model.md:28、T009:106、contracts/http-url.md:38

**问题描述**：spec Edge Case 与 T003/T006 写「port 越界（`< 0` 或 `> 65535`）」，
按此口径 `http://h:0/` 应被接受；data-model 不变量、T009 字段约束与契约访问器注释
一致写 `1..=65535`，按此口径 `:0` 必须报 `InvalidPort`。OkHttp 的
`HttpUrl` 端口合法域是 `1..=65535`（拒绝 0），故 spec/tasks 一侧偏离行为基准
（宪法 III）。**没有任何测试锚定 port=0**，实现期会随机取一侧。

### 决策及建议

- **A.（推荐）统一为 `1..=65535`**：改 spec.md:119 为「port 越界（`< 1` 或
  `> 65535`）」，T003/T006 同步 `< 1`，并新增一条边界用例 `http://h:0/` →
  `InvalidPort`（顺带补 L2 的「12→13 条」计数）。
- **B. 保留 `< 0`，显式接受 port=0**：需在 spec A6 记录「与 OkHttp 有意差异」并
  给理由。代价：无实际用途，且与基准偏离，不建议。
- **C. 只改测试不改 spec**：T006 补 `:0` 用例，spec 措辞不动。代价：spec/tasks
  仍互相矛盾，SDD 追溯性未修复。

**人类选择**：A

---

## M2 values 返回类型 Iter 与验收数组断言口径不符

**类别**：欠规格 ｜ **严重度**：MEDIUM ｜ **位置**：spec.md FR-004(L144-146)、
data-model.md:62、contracts/headers.md:21 vs spec US-3 场景 1(L87-89)、tasks T013:155-156

**问题描述**：契约与 data-model 写 `values(name) -> Iter[String]`（保插入序全部），
而 US-3 验收场景写「`values("accept")` 得到 `["a","b"]`」、T013 也按数组断言。
`Iter` 不能直接 `assert_eq` 比较，且从不可变值逃逸的 `Iter` 借用语义（是否依赖
底层 Array 的生命周期）未定义；宪法 IV 要求断言优先 `assert_eq`，当前签名与验收
写法在 MoonBit 里难以两全。

### 决策及建议

- **A.（推荐）改为 `Array[String]`**：契约与 data-model 统一为
  `values(name) -> Array[String]`，保序、可直接 `assert_eq`，与 T013/US-3 现写法
  零冲突。代价：每次调用一次数组分配（头列表规模 <100 条，data-model「数据量假设」
  已界定，非热路径放大）。
- **B. 保留 Iter，另设数组便利方法**：`iter_values` + `values_array`，公开面
  +1 方法（联动 M5/T018 冻结清单）。代价：与宪法 VI 简洁性有张力。
- **C. 保留 Iter 并在 US-3/T013 写清收集方式**：断言用
  `Array.from_iter(values("accept"))`。代价：契约条款需补借用语义说明，
  验收文本仍不够直白。

**人类选择**：这里也许需要修改测试，Headers在Builder状态下是KV对，K可重复，build后固化为单一KV对，V为"a,b"，有疑义可以继续讨论
→ **讨论后定案**：**不采纳「build 时折叠」**，保持 Builder 持可重复 KV 对、
`build()` 产出**仍是同名多条的不可变序列**（合并只发生在 `to_http_map()` 进入
@http 管线时），返回类型取 **A（`values(name) -> Array[String]`）**。理由：
build 即折叠会同时推翻 US-3 场景 1（`values("accept")` = `["a","b"]`）、
FR-004 的多值语义，并与 M2 里程碑的多值需求（`Set-Cookie` 绝不能合并）冲突；
折叠的唯一理由只是 @http 的 `Map` 单值类型。

---

## M3 plan 源码结构清单缺两个测试文件

**类别**：不一致 ｜ **严重度**：MEDIUM ｜ **位置**：plan.md:91-92 vs tasks T007:96-98、T015:184

**问题描述**：plan 的 `src/core` 结构只列 4 个黑盒测试文件
（`http_url_parse_test` / `http_url_resolve_test` / `headers_test` /
`method_error_test`），而 T007 要创建 `percent_wbtest.mbt`（白盒，AGENTS.md 约定
`_wbtest.mbt`）、T015 要创建 `headers_fold_test.mbt`。任务引用了 plan/spec 未定义
的组件，`.mbti` 与包文件清单审视（SC-004）会与实际产物不符，也不便后续包复用
同一布局约定。

### 决策及建议

- **A.（推荐）在 plan 结构清单补两行**：`percent_wbtest.mbt`（白盒：编码集三口径）
  与 `headers_fold_test.mbt`（黑盒：折叠与属性测试），保持「任务↔结构」可追溯。
- **B. 合并测试文件**：`percent` 白盒并入既有测试文件、折叠用例并入
  `headers_test.mbt`，T007/T015 改写。代价：单文件变大，OkHttp 移植分组边界
  （SC-002 清单）不如分文件清晰。
- **C. 只改 T015 文件名对齐**：`headers_fold_test.mbt` → 用现有 `headers_test.mbt`，
  仅补 `percent_wbtest.mbt` 一行。折中方案，改动面最小。

**人类选择**：A

---

## M4 宪法 V 的 wasm-gc stub 例外在 plan 中标注失真

**类别**：宪法合规（已登记例外） ｜ **严重度**：MEDIUM ｜ **位置**：plan.md:49、
research.md R7、`docs/roadmap/M1/README.md` L85（D9）、
`docs/roadmap/deferred-items/deferred-items-m1.md` L28（F9）、constitution.md:77

**问题描述**：宪法 V 明文「wasm-gc 被 async runtime 阻塞，**必须**提供明确报错的
stub（P2，跟踪上游）」。本包按 M1 README D9 决定「M1 不建 wasm-gc stub」，并已
在跨里程碑欠账清单登记 F9 → M5/16-target-support，**实质是有意识、有归属的延期**，
不属于悄悄偏移。问题在于 plan.md 的宪法检查表把 V 行标为「✅ 通过」，
而宪法治理章要求「违背核心原则处必须显式说明理由并记录（**例外跟踪**）」
（constitution.md:138）——判定符号使 analyze 与后续 code review 无法据此定位例外，
例外只能靠读 R7/D9 反推。

### 决策及建议

- **A.（推荐）改判定为例外标注**：plan.md:49 的 V 行改为
  「⚠️ 例外（不建 stub，见 D9 / F9 → M5）」，理由与归属一并写在依据列；
  同时在 Complexity Tracking 之外新增一行「例外跟踪」指向 deferred-items。
  不改宪法、不改范围，只修可追溯性。
- **B. 本包补一个最小 wasm-gc 报错 stub**：满足宪法 V 原文，M1 内自足。代价：
  与 D9 里程碑边界冲突，重复建设后被 M5 替换，明显违反宪法 VI/YAGNI。
- **C. 走宪法修订**：把 V 的 stub 义务改为「按里程碑登记延后即可」。代价：
  治理动作，须 `/speckit-constitution` + 人工审阅，超出本包范围。

**人类选择**：这里不动
→ **定案**：plan.md 的 V 行**保持原样不重写**（已在「回写状态」节登记为例外留痕，
后续 analyze / code review 以本报告 + R7 + D9 + F9 为例外依据）。

---

## M5 FR-006「全部公开类型可哈希」与错误类型 derive 组合冲突

**类别**：不一致 ｜ **严重度**：MEDIUM ｜ **位置**：spec.md:150-151 vs
contracts/method-error.md（`derive(Debug, Show, Eq)`）、tasks T003:55、T004:63、T009、T014

**问题描述**：FR-006 写「本包**全部公开类型** MUST 可判等、可哈希、可调试输出
（Eq/Hash/Debug 相应组合）」。「相应组合」留下解释空间：HttpUrlError 只 derive
`Debug, Show, Eq`（无 Hash），Method 与值类型 derive `Eq, Hash, Debug(, Show)`，
而 **HeadersError 的 derive 组合在任何产物中都未声明**（T003 只写「同文件定义
`HeadersError`（`InvalidName`/`InvalidValue`）」）。错误对象不参与池键哈希，
实际无需 Hash，但 SC-004 的 `.mbti` 人工审视与宪法 VI 的接口纪律需要一个确定口径，
否则实现期各文件自行其是。

### 决策及建议

- **A.（推荐）收窄 FR-006 表述**：改为「值类型（HttpUrl/HeadersV/HeadersVBuilder/
  Method[/Scheme]）MUST Eq/Hash/Debug；错误类型（HttpUrlError/HeadersError）MUST
  Eq/Debug/Show，不参与哈希键」。T003 同步声明 HeadersError 的 derive 组合。
- **B. 严格要求全部类型可哈希**：错误类型也 derive Hash。代价：无语义收益，
  且把「错误可做集合键」这种未承诺能力暴露在公开面上。
- **C. 不改 FR，仅在 tasks 补 derive 清单**：把逐类型 derive 组合写进 T003/T004
  作为实现约定。代价：spec 与实现的口径差仍在，analyze 重跑会再次命中。

**人类选择**：A 但是 moonbit 没有 Show 操作，可见文档https://docs.moonbitlang.cn/_sources/language/derive.md，你指的是toString吗；另外Error也许也不需要Eq，应该类型判断足以
→ **讨论倾向（derive 的落地写法待 N1 勾选）**：取值类型 **Eq/Hash/Debug**、错误类型**仅 `Debug`**
（既不 derive `Show`——本工具链对 `derive(Show)` 报 deprecated_syntax 警告 [0027]，
`Show` 是「可 readback 的源码形态」而非 `toString`，序列化另有 `ToJson`；也不用
`Eq`/`Hash`——错误判别用 `is` 与模式匹配即够，且 `HttpUrlError::UnsupportedScheme`
携带 payload 时 Eq 需递归 derive）。因此 FR-006 收窄为：「值类型 MUST
Eq/Hash/Debug；错误类型 MUST 可调试输出（Debug）；本包一律不使用 `derive(Show)`」。
值类型须配套显式 `pub extend`（N1）以消除警告 [0079]，`moon check` 零警告并入 SC-004。

---

## M6 A3 的 path 段惰性化条件评估未闭环

**类别**：欠规格 ｜ **严重度**：MEDIUM ｜ **位置**：spec.md A3(L207-208)、
plan.md:33（Performance Goals）、research.md R4

**问题描述**：A3 写「path 段采用非惰性表示（YAGNI）；**若 plan 阶段评估发现**
每请求解析分配成为热点，再引入惰性化」。plan 的 Performance Goals 直接选择了
非惰性表示，却没有任何一处记录「评估已做、结论是不触发热点」及其依据
（解析频次、段数量级、与 P10 基准门禁的关系）。悬空条件在宪法 VI 下是可接受的
取舍，但在宪法 II「性能是一等交付物」下应留痕，否则后续包（P04 池键、P10 基准）
无法判断该决定的前提是否仍成立。

### 决策及建议

- **A.（推荐）在 plan 补一行评估结论**：在 Performance Goals 追加「plan 期评估：
  每请求一次解析、path 段数量级个位~十位，非热路径放大点；惰性化不进入 M1，
  如 P10 基准显示 path 分配为热点再评估」，并引用 R4/宪法 II 的 P10 归口。
- **B. 登记为跨里程碑欠账**：在 `deferred-items-m1.md` 增一条「path 段惰性化
  视 P10 基准结论回补」。代价：把一个明确不做的 YAGNI 决定变成欠账噪声。
- **C. 删除 A3 的条件句**：直接声明非惰性表示为定案。代价：丢失未来再评估的钩子。

**人类选择**：A

---

## L1 defaultPort/toString 与 snake_case 命名漂移

**类别**：术语漂移 ｜ **严重度**：LOW ｜ **位置**：spec.md FR-002/FR-004
（`defaultPort`）vs contracts/http-url.md:42、tasks T009/T018（`default_port`、
`toString` 与 `to_string` 混用）

**问题描述**：spec 沿用 OkHttp 的 camelCase 语义名，contracts/tasks 用 MoonBit
snake_case；同时 T018/quickstart 的 `.mbti` 冻结清单仍写 `toString`，与契约的
`to_string` 不同。MoonBit 公开面惯例是 snake_case，`derive(Show)` 等也不接受
camelCase 方法名混用。不影响功能，但影响 SC-004 审视时的名称核对。

### 决策及建议

- **A.（推荐）spec 保语义、下游统 snake_case**：spec 增注「实现名以 snake_case
  为准，`.mbti` 冻结为权威」；把 T018/quickstart 的 `toString` 改为 `to_string`，
  与契约一致。
- **B. 全链统一 camelCase 引用 OkHttp 名**：代价：与 MoonBit 惯例与 `moon fmt`
  生态相悖，不可取。
- **C. 不做处理**：接受噪声。代价：`.mbti` 人工核对时名称对不上。

**人类选择**：A moonbit中，方法命名多为下划线命名，则应该是保留default_port和to_string

---

## L2 「13 条边界用例」实际为 12 条

**类别**：事实性偏差 ｜ **严重度**：LOW ｜ **位置**：plan.md:48、quickstart.md:22 vs
spec.md:117-130（Edge Cases 共 12 条）

**问题描述**：plan 与 quickstart 都称「13 条边界用例」，`grep -c` 核实 spec
Edge Cases 为 12 条。quickstart 把它当作验收核对基准（SC-001），计数错误会让
「全部有对应断言」的核对无法闭合。

### 决策及建议

- **A.（推荐）改为 12，或与 M1-A 合并补第 13 条**：若采纳 M1 的 `port=0` 用例，
  则两处「13 条」自动变为真，一举两得。
- **B. 只把数字改对（12）**：不动 Edge Cases。代价：与 M1 决策需二次同步。

**人类选择**：A

---

## L3 moon.pkg import 写法两处不一致

**类别**：不一致 ｜ **严重度**：LOW ｜ **位置**：tasks T002:41（
`import { "moonbitlang/async/http" }`）vs research R10、quickstart 前置 3
（`moonbitlang/async/@http`）

**问题描述**：`moon.pkg` 的 `import` 路径写的是包目录路径（`moonbitlang/async/http`），
`@` 前缀只在引用处作为命名空间使用。两处表述混用，实现 T002 时可能写出
`"moonbitlang/async/@http"` 这种非法路径而报错。

### 决策及建议

- **A.（推荐）统一 import 写法**：R10 与 quickstart 的 import 项统一为
  `"moonbitlang/async/http"`，并在描述代码引用时写作 `@http.CaseInsensitiveString`。
- **B. 反向：R10/quickstart 不动，T002 改为 `@http`**：代价：T002 直接执行会失败。

**人类选择**：A

---

## L4 HttpUrlError 变体粒度在 4 处重述

**类别**：重复 ｜ **严重度**：LOW ｜ **位置**：spec.md:16（Clarifications）、
FR-009(L159-162)、Edge Cases(L127)、A5(L212-214)

**问题描述**：四变体 `InvalidHost`/`InvalidPort`/`MalformedUrl`/`UnsupportedScheme`
在 4 处各写一遍，A5 还保留「原三变体默认被取代」的历史叙述。规范源不唯一，未来
变体调整需改 4 处，易漏。

### 决策及建议

- **A.（推荐）FR-009 为唯一规范源**：A5 收敛为「已由 FR-009 固化」，
  Edge Cases 只引用变体名不重定义。
- **B. 保留现状**：代价：维护成本随每次变体调整线性增加。

**人类选择**：A

---

## L5 T002 的空包占位条件未定案

**类别**：歧义 ｜ **严重度**：LOW ｜ **位置**：tasks.md T002:43（「若空包检查报错，
同时放置空的 `error.mbt` 占位」）

**问题描述**：条件式兜底把「空包能否 `moon check`」的判断留给执行者临场验证。
既然 T003 必定创建 `error.mbt`，占位与否其实无差别。

### 决策及建议

- **A.（推荐）取消条件**：T002 直接同时创建 `src/core/moon.pkg` 与空的
  `error.mbt` 占位，T003 填充。
- **B. 保留条件**：代价：无谓的判断分支。

**人类选择**：A

---

## L6 RFC 3986 部分 resolve 分支未锚定

**类别**：边界缺口 ｜ **严重度**：LOW ｜ **位置**：spec.md US-2 场景/Edge Cases、
contracts/http-url.md「相对引用解析」节、tasks T011/T012

**问题描述**：resolve 的锚点只覆盖 `../up`、`/root`、`//b.com/x`、绝对 location、
空串五类；RFC 3986 §5 的 query-only（`?x=1`）、fragment-only（`#f`）、
base 无 path 时的合并三个分支未锚定，目前只能靠 T011 移植的 OkHttp resolve 组
兜底——而 OkHttp 移植组的取舍清单（SC-002/T017）也未点名这三项。

### 决策及建议

- **A.（推荐）在 contracts 锚点表补 3 行**：`?x=1`、`#f`、base 为
  `http://a.com`（无 path）+ `../up`，并在 T011 断言与 T017 移植清单中对应标注。
- **B. 仅依赖 OkHttp 移植组**：不显式锚定。代价：这三类若 OkHttp 组未覆盖则无测试。
- **C. 记为 deferred**：转 M2/M4（缓存键计算时再补）。代价：P06 重定向在 M1 就要用
  resolve，延后偏晚。

**人类选择**：A

---

## N1 derive 触发 [0079] 警告，「`moon check` 零警告」缺实现路径

**类别**：工具链口径（回写期实测） ｜ **严重度**：MEDIUM ｜ **阻塞 implement**：是 ｜
**位置**：spec.md FR-006(L150-151)/SC-004(L196-197)、contracts/method-error.md、
tasks.md T004/T009/T014/T018、plan.md 检查表 VI 行与 L127-130 质量门口径

**问题描述**：为把 C1/M5 的 derive 口径写进产物，回写期用临时工程
（工具链 `moon 0.1.20260920`）实测了三件事：

1. `derive(Eq, Hash, Debug)` 生成的是 **impl 而非方法**，一旦按本包契约的写法调用
   （`a.equal(b)`、`debug_inspect(x)`），`moon check` 就报
   `implicit_impl_as_method` **警告 [0079]**；补上显式
   `pub extend T with Eq::{not_equal, equal}` / `T with Hash::{hash, hash_combine}` /
   `T with Debug::{to_repr}` 后警告消除。
2. `derive(Show)` 在本工具链直接报 deprecated_syntax **警告 [0027]**——这坐实了 M5
   里「不使用 Show」的判断，但也意味着现有产物中所有 `derive(..., Show)`
   （contracts/method-error.md、T003/T004）与质量门「零警告」互斥。
3. `Debug` 在 core 是 `pub(open) trait Debug { fn to_repr(Self) -> Repr }`
   （`~/.moon/lib/core/debug/debug.mbt:17-20`），而 `@debug`
   （`moonbitlang/core/debug`）**无法作为用户工程依赖 import**（实测解析失败），
   所以「手写 `impl Debug` 复用上游脱敏工具」这条路不可直接走。

结论：spec/plan/tasks 三处都只写了 derive 组合，没有任何一处规定 derive 与
`pub extend` 的配套写法，也没有一处定义 SC-004 的「零警告」到底含不含 [0079]。
本包有 3 个值类型 + 1 个 Builder + 2 个错误枚举，实现期会一次性撞上。

### 决策及建议

- **A.（推荐）derive + 显式 `pub extend`，并把「零错误零警告」写进 SC-004**：
  每个 derive 的值类型紧随三行 `pub extend`（已回退的 C1 手写稿即此形，可作参考）。
  收益：警告面干净、
  `equal`/`hash`/`to_repr` 成为可调方法；代价：`.mbti` 会多出这些方法名，须并入
  T018 冻结清单逐条核对（宪法 VI「接口变化必须是有意识的决定」）。
- **B. 只 derive，SC-004 放宽为「零错误，允许 [0079]/[0027]」**：改动最小；
  代价：警告与真实问题混流，后续包（P04/P10）无法把警告当门禁，且 [0027] 是
  弃用信号，留着会在工具链升级时变红。
- **C. 不用 derive，全部手写 `impl Eq/Hash/Debug for T`**：零警告且脱敏可完全自控
  （与 C1 要求的手写脱敏 `Debug` 天然一致）；代价：HttpUrl 六字段与 HeadersV 的哈希手写，
  实现量与出错面明显上升，与宪法 VI 简洁性有张力。

**人类选择**：A

---

## N2 scheme 的最终类型：H3 勾选的自立 `Scheme` 与上游 `@http.Protocol` 重复

**类别**：类型选型（回写期上游核实） ｜ **严重度**：HIGH ｜ **阻塞 implement**：是 ｜
**位置**：contracts/http-url.md:36,42、spec.md FR-002/Key Entities、
tasks.md T009/T018、本文件 H3 条目

**问题描述**：H3 勾选「B 且 `HTTP`/`HTTPS` 大写」的前提是「本包需要自己的 scheme
枚举」。回写期核实上游后发现该前提不成立：`moonbitlang/async@0.22.4` 的
`@http.Protocol` 已是 `pub(all) enum Protocol { Http; Https }`，并带
`Protocol::default_port`（`E:/Project/async/src/http/request.mbt:17-25`），
还 derive 了 `Eq, Compare, Hash, ToJson`；而 `@http.Client::request` 的签名本就吃
`Protocol`（P02/P04 必然要映射一次）。于是三种走向的差别是**公开面与真相源数量**：

- 自立 `Scheme { Http; Https }`：+1 公开类型、+2 映射函数，与 `Protocol` 语义
  完全重叠，`default_port` 出现本包与上游两份真相。
- 自立 `Scheme { HTTP; HTTPS }`（H3 原勾选）：同上，且变体名与上游
  （`Http`/`Https`）和 MoonBit 惯例不一致——大写合法但不 idiomatic，文档要额外解释。
- 复用 `@http.Protocol`：封闭枚举收益全部拿到（无 `String` 弱类型、可穷举匹配），
  公开面 0 增项，`default_port` 直接是上游方法；代价是 P01 的编译图里本就依赖
  `@http`（宪法 I 已把 async 定为唯一底座），该耦合是有意接受而非新增风险。

**「复用上游解析」的实测边界**（本次核实 `E:/Project/async`，0.22.4 同源）：上游
**没有可复用的 URL 解析公开面**——`resolve_url`（`request.mbt:36-51`）与 `resolve_host`
（`:55-72`）都是 **priv，不在 `pkg.generated.mbti`**；且其能力远浅于 P01 需求：只按
`://` 与首个 `/` 切出 `(protocol, host, path)`，不拆 query/fragment、不 percent-decode、
不消解 `.`/`..`、不剥 IPv6 方括号（`http://[::1]:8080` 的 host 会连方括号一起进
`@socket.Tcp::connect_to_host`）、不规范化大小写、无 RFC 3986 resolve；端口守卫
`port is (1..<65536)` 也在 priv `resolve_host` 里且带 `#cfg(native|wasm)`。
公开的消费边界是 `Client::Client(uri)`（要求 path 必须为 `/`，即只管连接authority）
与 `Client::request(meth, path : StringView)`（收已切好的 path）。**因此可复用的公开面
只有 `@http.Protocol` + `Protocol::default_port`（本条正取此）**，HttpUrl 的解析/规范化
必须本包自建，上游源码只可「读以参考做法」而不可复制（宪法 I）。上游的
`1..<65536` 守卫同时为 M1-A 的 `1..=65535` 口径提供了实证。

另注：契约的 `default_port(scheme : Scheme) -> Int` 是静态形态，FR-002/data-model 写
`defaultPort(scheme)`，T009 只写「http=80/https=443」，三处签名互不相同——无论选哪条
都要收口（H3 已记），差别只在上游 `Protocol::default_port` 是否直接替本包承担该方法。

### 决策及建议

- **A.（推荐）复用 `@http.Protocol`，MUST NOT 自立 scheme 枚举**：
  `scheme() -> @http.Protocol`；默认端口直接用上游 `p.default_port()`，本包不再包一层
  （若要保留便捷入口，至多是 `HttpUrl::default_port(self) -> Int` 的实例转发）。
  spec FR-002/Key Entities 显式写明「复用上游类型」，T009/T018 冻结清单同步。
- **B. 自立 `Scheme { Http; Https }`**：类型面自洽、可脱开 `@http` 单测；
  代价：+1 公开类型与双向映射，`default_port` 两份真相，P02 起每个消费方都要转换。
- **C. 自立 `Scheme { HTTP; HTTPS }`**（H3 勾选原文）：满足大写偏好；代价同 B，
  另需文档解释与上游命名风格的偏离。
- **D. 降级 `scheme() -> String` + `default_port(self) -> Int`**（H3 原推荐 A）：
  改动最小、零新增类型；代价：放弃封闭枚举收益，非法 scheme 在参数位无法表达。

**人类选择**：A

---

## N3 头校验与调试脱敏撞同一 FR 编号（本报告推荐项的自身缺陷）

**类别**：报告缺陷 ｜ **严重度**：LOW ｜ **阻塞 implement**：否 ｜
**位置**：本文件 C1「决策及建议 A」(L71-76) 与 H2「决策及建议 A」(L138-143)、
spec.md FR 清单（现止于 FR-011）

**问题描述**：C1-A 写「新增 FR-012『HeadersV 的调试/展示输出 MUST…脱敏』」，
H2-A 写「新增 FR-012『HeadersV Builder MUST 拒绝非法头名…』」——**两条独立 MUST
占同一编号**。回改 spec 时若照抄，要么编号重复，要么被迫把「Builder 校验 raise」与
「调试输出脱敏」两个不相干义务塞进一条 FR（后者可测性是快照断言、前者是 raise 断言，
analyze 重跑会判为复合需求）。

### 决策及建议

- **A.（推荐）拆两条并按主题就近排序**：头校验（属 US-3 行为、P0 安全）在前，
  调试脱敏（属输出面约束、挂钩宪法掩码条款）在后，即 FR-012=头校验 +
  `HeadersError`、FR-013=HeadersV 调试输出脱敏；两条各自进 Key Entities /
  Edge Cases / plan 检查表引用（已回退的手写稿即此形）。
- **B. 合并为一条「HeadersV 的安全行为」FR，内含两个 MUST 子项**：条目少；
  代价：一个 FR 两种验收口径，SC/FR 追溯粒度变粗。
- **C. 头校验进 FR，脱敏只进 spec 假设（A6/A7）+ 宪法检查表行**：
  代价：脱敏是宪法 MUST，写成假设等于 C1 未真正关闭（不建议）。

**释义（A/B 的实质差别只在「几条 FR、几个追溯锚」，不在功能）**：

- 选 A 后，FR-012 的验收断言是 **raise 断言**（`add("", "v")` →
  `HeadersError::InvalidName`），FR-013 的验收断言是**脱敏断言/快照**
  （含 Authorization 的容器 debug 输出不含明文）。两者测试形态不同、下游继承
  对象不同（P02 的 Request/Response 要分别继承「校验」与「脱敏」两条义务），
  所以各有独立编号才能逐条追溯到任务与检查表行。
- 选 B 后只有一条 FR、编号不变，但它同时含「Builder MUST raise」与
  「Debug MUST 脱敏」两个 MUST 子项，粒度变粗：P02 只能整条继承或整条丢弃，
  且 analyze 重跑会把它判为复合需求（与 H1 同类的可测性模糊）。
- 无论 A/B，FR-013 的**内容形态**由新增的 **N4**（掩码开关提议）决定，
  与编号划分互不影响。

**人类选择**：A（定案：FR-012 头校验、FR-013 调试脱敏，两条就近排序）

---

## N4 调试脱敏的开关形态（用户提议：默认掩码 + flag 可关）

**类别**：宪法合规 / 公开面 ｜ **严重度**：MEDIUM ｜ **阻塞 implement**：否
（不阻塞 P01 交付，但决定 FR-013 措辞与 T018 冻结清单是否多一个公开面） ｜
**位置**：本文件 C1（决策 A）与 N3 的 FR-013、contracts/headers.md 条款、
tasks T014/T015/T018、constitution.md:113-114（敏感信息自动掩码 MUST）与
「不安全配置 opt-in 等安全条款留待后期补充，暂不立条」段

**提议原文（2026-10-13 对话）**：「在开发的调试中可以不用脱敏，最后完成的库的
debug 模式中，增加掩码 flag，默认启用敏感信息掩码，可以通过 flag 禁用掩码方便
特殊调试」。方向与宪法一致（默认开掩码），差别在「开发期可以不脱敏」和
「用什么形态提供关掉的路径」。

**必须先固定的三条技术事实**：

1. **`derive(Debug)` 读不到任何开关**——要脱敏就必须手写 `impl Debug`
   （C1-A 已计入该代价）。因此开关形态之争**不改变实现量下限**，只决定
   「脱敏之后要不要留一条明文路径」以及那条路径是几行公开面。
2. **「开发期默认不脱敏」的危险面恰好就是 C1 的泄漏面**：P01 阶段 Debug 输出的
   主要消费者是本包自己的测试与 `debug_inspect` 快照，而 `.snap` 会提交进仓库。
   「开发中不脱敏」＝明文头值落盘进版本库，正是宪法要防的，且提交后难以追回。
   真正需要明文的是「调试一次」，不是「整段开发期」。
3. **全局 flag 在本包只能做成包级可变状态**：它全库共享、跨用例泄漏
   （A 用例关了掩码会改变 B 用例的快照），且 native / wasm / wasm-gc / js
   四个目标（宪法 V）对可变全局的语义并不一致；`@debug` 已实测**不可**作为
   用户工程依赖引入，无法借用其全局配置面。值对象包自带可变全局开关，与
   宪法 VII 的接口纪律相冲突。

### 决策及建议

- **A.（推荐）P01 只交付「默认脱敏 + 显式逃生口方法」，全局 flag 归 M3**：
  FR-013 只承诺「HeadersV 的 Debug/展示输出 MUST 对
  `Authorization`/`Proxy-Authorization`/`Cookie`/`Set-Cookie` 的值脱敏」；
  另提供一个**必须主动调用**的逃生口方法（形如 `HeadersV::debug_unredacted()`，
  最终命名 tasks 期定）用于特殊调试，不加参数、不加包级开关；同时规定
  **测试与快照 MUST NOT 使用逃生口**（否则退回事实 2）。可配置的掩码开关随
  M3 的 Logger/EventListener 管线落地，届时一并补宪法「不安全配置 opt-in」
  条款并在 `docs/roadmap/deferred-items.md` 新增挂钩项。代价：零额外公开面，
  FR-013 仍是 1 条，Edge Cases 不增加。
- **B. 本包即提供包级全局开关**：多一处公开可变面（T018 冻结清单要加一行），
  并承担上述事实 3 的测试隔离与跨目标语义风险。
- **C. 借「开发期不脱敏」把脱敏整体推后**：等于 C1 重开（CRITICAL 未关闭），
  不建议。

**人类选择**：A（定案）。用户提议的「默认启用掩码 + 可关」采纳其方向，但 P01 的
关掉路径取**显式逃生口方法**而非包级 flag；全局/可配置掩码开关与宪法
「不安全配置 opt-in」条款一并归 **M3**（随 Logger/EventListener 管线），
在 `docs/roadmap/deferred-items.md` 挂钩。「开发调试期不脱敏」不采纳——
明文会写进提交的 `.snap` 快照，正是 C1 要防的泄漏面。
*（本条与 N3 在 Auto Mode 下按推荐项定案，用户可事后纠正。）*

---

## 第二轮复跑新发现（2026-10-14）

**范围与前提**：回改链 `/speckit-clarify` → `/speckit-plan` → `/speckit-tasks`
已走完，19 项决策（C1–M6、L1–L6、N1–N4）在 spec/plan/tasks/data-model/
contracts/quickstart/research 七处逐条核查**全部一致**（含 plan V 行逐字未改、
import 键统一 `moonbitlang/async/http`、scheme 复用 `@http.Protocol`、derive 与
`pub extend` 口径、`percent_wbtest.mbt`/`headers_fold_test.mbt` 两侧一致、
L5-A 不放空占位、N4 的可配置开关已登记 F12）。以下 8 条为**本轮新出**，
不重复第一轮任何已闭环条目。

## R2-D1 HeadersVBuilder 的 derive(Debug) 构成掩码旁路（宪法 MUST 冲突）

**类别**：宪法合规 ｜ **严重度**：CRITICAL ｜ **阻塞 implement**：是
（直接决定公开面形状与 SC-005 的验收面，留到实现期必然返工） ｜
**位置**：spec.md:178-183（FR-006 值类型清单含 `HeadersVBuilder`）、
spec.md:221-223（Key Entities 列 `HeadersVBuilder` 为公开实体）、
tasks.md T014（写死 `derive(Eq, Hash, Debug)` + `pub extend`）↔
data-model.md §2「调试输出」行（只约束 HeadersV）、
contracts/headers.md「调试输出与脱敏」段（只给 `HeadersV` 的手写 impl）、
constitution.md:113-114（敏感信息自动掩码 MUST，覆盖「调试输出」全类）

**问题描述**：第一轮 C1 的裁决把 **`HeadersV`** 一侧的 `derive(Debug)` 换成手写
`impl Debug` 做脱敏，N1-A/M5-A 同时定「值类型 = `HttpUrl`/`HeadersV`/
`HeadersVBuilder`/`Method` 一律 `derive(Eq, Hash, Debug)`」。两条裁决在
Builder 上相撞：

1. `HeadersVBuilder` 是**可变**容器，`add`/`set` 后其内部持有未经脱敏的原始
   `(名, 值)` 对——包括 `Authorization: Bearer secret`。
2. 对它 `derive(Debug)` 得到的 `to_repr` 是逐字段原样打印；T014 还要求紧随
   `pub extend ... Debug::{to_repr}`，即**明文路径进入 `.mbti` 冻结清单**。
   使用侧 `debug_inspect(builder)` 或任何 `Debug` 消费（M3 的 Logger 尚未存在，
   当前消费者是本包测试与调试会话）都会把明文写进输出。
3. 宪法条款是无条件 MUST：「日志、**调试输出**、EventListener、错误消息与错误
   上下文中的 `Authorization`、`Proxy-Authorization`、`Cookie`、`Set-Cookie`、
   URL 用户信息等必须自动脱敏」。FR-013 的主体却只写 `HeadersV`。
4. 后果链：SC-005 的验收只断言「HeadersV 实例的调试输出不含明文」，Builder
   一侧**零断言**；`.snap` 扫描（T019）也扫不到 Builder 输出。即违宪项同时
   是验收缺口，按 analyze 规则宪法 MUST 冲突自动 CRITICAL。

**与第一轮的关系**：这不是 C1 未执行——`HeadersV` 的手写 `impl Debug`、逃生口、
测试禁用逃生口、F12 欠账全部落地。C1 当年的表述就限定了 HeadersV，Builder 一侧
从未被评估过。

### 决策及建议

- **A.（推荐）FR-006 的 Debug 义务按可变性收窄，Builder 不暴露 Debug**：
  FR-006 改为「**不可变**值类型（HttpUrl / HeadersV / Method）MUST 可判等、
  可哈希、可调试输出；`HeadersVBuilder` 作为可变构建器 MUST NOT 派生
  `Debug`（不暴露 `to_repr`），其内容不得成为调试/展示输出面」。代价：Builder
  排查只能经 `build()` 后看脱敏值，`.mbti` 少一个 `to_repr` 项；收益：违宪面
  从根上关闭，零额外实现量（少写而不是多写）。
- **B. Builder 也提供 Debug，但手写且只输出结构不输出头值**：形如
  `<HeadersVBuilder n=3 [Accept, Authorization, X-Y]>`——头名可以出（头名本身
  非敏感），头值一律不出。需同步把 FR-013 主体改写为「HeadersV 与
  HeadersVBuilder 的调试输出」，并各加一条断言。代价：+1 处手写 `impl Debug`
  （约 5–10 行）与 +1 条 Edge Cases/SC 断言；好处：Builder 仍可调试，接口更完整。
- **C. 立总则堵住同类复发**：FR-013 改写为「本包一切调试/展示输出 MUST 默认
  脱敏（含未来新增类型）」，Builder 具体采 A 或 B 任一。优点：M3 的
  Logger/EventListener 与 P02+ 的 Request/Response 值类型不会再复发同类旁路；
  缺点：spec 措辞改动面最大，且总则的验收需在 SC-005 里补「输出面清单」。
- **D.（不推荐）把 Builder 私有化**：与 FR-004「变更在配套可变 Builder 上」、
  H2-A/N3-A 已定的公开面直接冲突，等于推翻第一轮两条裁决。

**人类选择**：Debug可以先用默认实现，log脱敏等后续专开一个版本进行

## R2-F1 SC-004 的「四个目标 moon check」与 wasm-gc 不支持互斥

**类别**：不一致（兼可测性）｜ **严重度**：HIGH ｜ **阻塞 implement**：是
（质量门按字面必红，T018 无法通过） ｜ **位置**：spec.md:246-247（SC-004
「四个目标 `moon check` 零错误零警告」）、plan.md:32（Testing 同口径）、
tasks.md T018（照抄「四目标」）↔ plan.md:34（Target Platform：wasm-gc 不支持）、
plan.md:54（V 行，M4 定案逐字不可改）、research.md R7、quickstart.md:73
（「wasm-gc：不支持」列入已知不验证项）、M1 README D9、deferred-items F9

**问题描述**：SC-004 在回写 N1-A 时写成「四个目标 `moon check` **零错误零警告**」。
但 wasm-gc 的阻塞源是 `@http` 包本身未实现 wasm-gc（R7/D9）：`src/core` 一旦
import `moonbitlang/async/http`，`moon check --target wasm-gc` 得到的是
**编译失败**，不是零警告。同一条 spec 内部（SC-004 vs A1 与 V 相关表述）、
spec 与 plan（SC-004 vs Target Platform L34）、plan 与 quickstart（L32 vs L73）
三处口径互相打脸，且 T018 会把「跑四目标 check 全绿」写成实现期必红验收。
注意：plan 的 V 行按用户 M4「这里不动」定案逐字保留，所以修法只能落在
SC-004 / plan L32 / T018 三处。

### 决策及建议

- **A.（推荐）目标数改为三，并把 wasm-gc 写成显式排除**：SC-004 改为
  「**三个可编译目标（native / wasm / js）** `moon check` 零错误零警告；
  wasm-gc 依宪法 V 与 R7 **显式排除**（`@http` 未实现该 target，属编译图外
  阻塞，非本包警告项），其跟踪随 M1 README D9 与欠账 F9」；plan L32 与
  T018 随之下发。零新公开面、零实现代价，只消除自相矛盾。
- **B. 保留四目标，为 wasm-gc 建 stub**：触碰 M4 锁定行与 D9 裁决（M1 不建
  stub），需先推翻第一轮两项定案，代价最大。
- **C. 只改 tasks T018、spec 不动**：tasks 与 spec 脱节，违宪法 SDD 章
  「改需求必须回改 spec 再向下重新生成，不得手改 tasks」，排除。

**人类选择**：目标只保留 native/wasm ，wasm-gc/js 不在首先支持的平台中，目前不需要check

## R2-C1 Builder 构造入口只在契约存在，冻结清单不含

**类别**：欠规格 ｜ **严重度**：MEDIUM ｜ **阻塞 implement**：否
（实现期必然自造一个入口，但会与 `.mbti` 冻结清单打架，建议同轮定） ｜
**位置**：contracts/headers.md:10（`fn HeadersV::builder() -> HeadersVBuilder`）
↔ spec.md FR-004（只说「变更在配套可变 Builder 上」，未定如何取得）、
spec.md:221-223（Key Entities 列 HeadersVBuilder 无构造方式）、
data-model.md §2（Builder 操作行未列构造）、tasks.md T014（清单写
`add`/`set`/`remove`/`build`，未列 `builder`）、tasks.md T018 与
quickstart.md:44-49 的 `.mbti` 冻结清单（同样缺该项）

**问题描述**：US-3 场景 1 的验收写法是「**Given** Builder 依次
`add("Accept","a")`…后 `build()`」，隐含「先有一个空 Builder」这一步，但**如何
取得它**在 spec 层面没有任何表述，只有契约给了 `HeadersV::builder()`。
后果：① 实现者可能任选 `HeadersV::builder()` / `HeadersVBuilder::new()` /
`HeadersVBuilder::default()`，公开面形状由 tasks 期临时决定，违 SC-004
「清单逐条审视」的意图；② T018/quickstart 的人工审视必看到清单外符号，
只能临时补清单或改实现，二者都是返工；③ 契约与 spec 的双向一致性上，
这是本轮唯一「契约先于 spec」的反向漂移（第一轮 H2/H3 定案后其余新增公开面
都已自上而下）。

### 决策及建议

- **A.（推荐）采纳契约现状并上升级为 spec 口径**：FR-004（或 Key Entities 的
  HeadersVBuilder 条目）补一句「空 Builder 经 `HeadersV::builder()` 取得」，
  并把 `builder` 并入 T018/quickstart 的 `.mbti` 冻结清单。理由：与
  「HeadersV 是主类型、Builder 是配套」的叙述方向一致，OkHttp 也有
  `Headers.Builder()` 的对偶形态。
- **B. 改为 `HeadersVBuilder::new()`**：类型自解释、与 `build()` 对偶清晰；
  代价是契约要改写、且 Builder 类型多一处静态方法。
- **C. 只在 tasks 里补（spec 不动）**：同 R2-F1 的 C 项，违 SDD，排除。

**人类选择**：空builder应该使用`HeadersVBuilder::new()`,`HeadersV::builder()`只用于将已固化项转换成builder

## R2-B1 手写 impl Debug 是否仍要 pub extend 未定

**类别**：歧义 ｜ **严重度**：MEDIUM ｜ **阻塞 implement**：否（但决定 SC-004
的零警告与 T018 清单，属实现期第一天必须知道的事） ｜ **位置**：tasks.md T014
（「`derive(Eq, Hash)` + 紧随 `pub extend` 配套，但 **`Debug` 走手写
`impl Debug`**」）↔ quickstart.md:47-48（假定「各值类型 `pub extend` 暴露
`equal`/`not_equal`/`hash`/`hash_combine`/`to_repr`」）、spec.md SC-004、
contracts/headers.md:51-57

**问题描述**：[0079] `implicit_impl_as_method` 警告的成因是「以方法形式调用
impl」，与 impl 来自 `derive` 还是**手写**无关。T014 的措辞在 HeadersV 上把
Debug 单独摘出手写组，却没说 `pub extend HeadersV with Debug::{to_repr}` 要不要
保留；quickstart 的冻结清单又假定全部值类型都有 `to_repr`。于是实现期有两种
互斥写法：① extend（`h.debug_inspect()` 风格可用、无警告，但把 `to_repr`
暴露为方法）；② 不 extend（调用侧写 `debug_inspect(h)` 顶层函数或显式
`HeadersV::to_repr(h, ...)`，避免暴露但需逐处确认无 [0079]）。**且本条与
R2-D1 是同一枚硬币的两面**：D1 若选 A（Builder 不暴露 Debug），HeadersV 一侧
的 extend 口径就必须同时白纸黑字定下，否则 T018 无法逐条核对。

### 决策及建议

- **A.（推荐）统一「凡对外提供某类型的 Debug 输出，即紧随 `pub extend ...
  Debug::{to_repr}`」，手写 impl 同样 extend**；`Eq`/`Hash` 的 extend 保持现状。
  理由：口径唯一、SC-004 的零警告可机械验证、冻结清单与 quickstart 现状吻合；
  测试侧仍可用 `assert_true(h is ...)`/`debug_inspect` 两种风格。
- **B. 反向：Debug 一律不 extend**，调试输出只经顶层 `debug_inspect(v)`，
  冻结清单去掉全部 `to_repr` 项。代价：与 quickstart/SC-004 现有表述冲突，
  需两处回改，且 `Eq::{equal}` 与 `Debug::{to_repr}` 口径分裂成两套规则。
- **C. 交实现期定，T018 冻结时补**：即第一轮 L5 曾拒绝的「条件式兜底」形态，
  不建议再引入悬空项。

**人类选择**：优先使用默认Debug实现，有问题再回改

## R2-E1 FR-011（本包无网络 IO）零验收任务

**类别**：覆盖缺口 ｜ **严重度**：MEDIUM ｜ **阻塞 implement**：否 ｜
**位置**：spec.md FR-011（MUST 不含网络 IO 与请求执行逻辑）、quickstart.md:74
（列为「已知不验证项：网络 IO——本包无」）↔ tasks.md T001–T020（无任一条核对）

**问题描述**：FR-011 是 MUST 级结构约束，也是宪法 I「非侵入底座」与分层的
验收面（`client → core → async`）。当前三层产物里它只有需求表述、没有验收
载体：quickstart 反过来把它写成「不验证」，于是本轮按 FR↔任务映射重算覆盖率
为 **17/18**（第一轮曾记 100%，口径差在此）。它不阻塞功能，但「MUST 却无判据」
正是 analyze 要暴露的那类缺口。

### 决策及建议

- **A.（推荐）在 T018 增一条静态核对，不改 spec**：核对 ① `src/core/moon.pkg`
  的 import 仅 `moonbitlang/async/http`（无 client/连接层模块）；② `src/core`
  源码内 `git grep` 不出现 `Client`、`new_client`、`request(`、`async` 运行时
  构造等执行类 API；③ `moon info` 输出的 `.mbti` 无 IO 相关签名。判据机械、
  零实现代价，且与 T018 现有「冻结清单逐条审视」同处执行。
- **B. spec 侧把 FR-011 降级为「非目标」叙述**：MUST 失去门禁，不建议。
- **C. 接受零覆盖并以 `# 例外跟踪` 记录**：可行但留污点，收益低于 A。

**人类选择**：A

## R2-C2 SC-005 的 .snap 扫描可能空转通过

**类别**：欠规格（可测性）｜ **严重度**：MEDIUM ｜ **阻塞 implement**：否 ｜
**位置**：spec.md:252-255（SC-005「本包提交的 `.snap` 快照与测试输出中不含这些
值」）、tasks.md T019（`git grep` 扫 `.snap` 与测试期望串）↔ tasks.md
T013/T015（断言全为 `assert_eq`/`assert_true`，无快照任务）

**问题描述**：AGENTS.md 明确本项目使用快照测试（`moon test --update` 刷新
`.snap`），SC-005 也把 `.snap` 写进验收面。但当前任务集里没有任何产出 `.snap`
的动作——若实现期也按现状只写断言，则 `src/core` 无 `.snap` 文件，T019 的
`git grep` 对空集合平凡为真，**「快照不含明文」这条判据失去验证力**；同时
脱敏输出形态（占位串长什么样、敏感头是否统一掩码）没有回归固化，未来改动
`impl Debug` 时无人报警。第一轮 C1 想要的「掩码可审且稳定」缺了证据锚。

### 决策及建议

- **A.（推荐）让脱敏输出一份快照**：T013 增一条 `debug_inspect` 结果快照断言
  （敏感头样例值只出现在测试**输入**，绝不出现在 `.snap`），T019 的 `git grep`
  改为对该快照反查。一举两得：SC-005 快照侧有了实体验、掩码形态获得回归锁定。
  代价：新增一个 `.snap` 文件，需遵守「快照内禁明文」纪律（AGENTS.md 与
  contracts/headers.md 条款 5 已覆盖）。
- **B. 声明本包不使用快照测试**：SC-005 的验收面收窄为「测试源码与断言串无
  明文」，需 clarify 改写 SC-005 措辞并在 AGENTS.md 实践层留一句例外理由。
  代价：掩码形态无回归固化（改 `impl Debug` 只能靠断言兜）。
- **C. 现状不动**：把空转风险留给 code review，不建议。

**人类选择**：测试数据`.snap`不需要脱敏

## R2-B2 FR-013 的「展示输出」在本包无对应 API

**类别**：歧义 ｜ **严重度**：LOW ｜ **阻塞 implement**：否 ｜
**位置**：spec.md:203（FR-013「调试与**展示**输出 MUST 默认脱敏」）↔ FR-006
与 SC-004 的 `derive(Show)` 禁令、T018/quickstart 冻结清单（无展示类方法）

**问题描述**：「展示输出」在 MoonBit 里对应 `Show`（源码形态）或自定义
`to_display`/`to_string` 类方法，而本包**禁止** `derive(Show)`（[0027]）且
`HeadersV` 未规划任何 `to_string`。该措辞可能诱导实现者新增一处展示 API
以「满足 FR-013」，反而在 T018 冻结清单里多出一个未经审视的公开面。

### 决策及建议

- **A.（推荐）措辞收窄为可枚举的两处输出面**：「MUST 默认脱敏的输出面为
  `Debug`/`to_repr`（含 `debug_inspect` 消费者）与显式逃生口方法；本包不提供
  `Show` 实例或展示类方法」。与 FR-006 禁令、T018 清单完全对齐。
- **B. 保留「展示」并补一句「本包无展示 API」**：语义同样闭合，但把矛盾留给
  读者消解，不如 A 干净。

**人类选择**：A

## R2-A1 可变的 HeadersVBuilder 被归入「值类型」

**类别**：术语 ｜ **严重度**：LOW ｜ **阻塞 implement**：否 ｜
**位置**：spec.md:178（FR-006「值类型（HttpUrl / HeadersV / HeadersVBuilder /
Method）」）、quickstart.md:44（「4 值类型」）↔ data-model.md §2（Builder 可变、
HeadersV 才是不可变值）、spec.md:219-223（Key Entities 对 HeadersV 用「不可变」、
对 Builder 用「可变」）

**问题描述**：Builder 被称「值类型」而它恰恰是**唯一可变**的公开类型，判等/
哈希在其上并不恒稳——N1-A 把 Builder 一并纳入 `derive(Eq, Hash, Debug)` 的
推导链，正是靠这个误分类走通的（「值类型 ⇒ MUST Eq/Hash/Debug」）。它与
R2-D1 同源，但属独立的术语问题：即使 D1 定案，「值类型」一词仍会在后续包
（P02 的 Request 也有 Builder 形态）继续误导。

### 决策及建议

- **A.（推荐）改为「公开数据类型」并按可变性分列义务**：FR-006 拆两句——
  不可变值类型（HttpUrl/HeadersV/Method）MUST Eq/Hash/Debug 且判等哈希恒稳；
  可变 Builder 的 derive 义务由 R2-D1 的结论决定。quickstart 的「4 值类型」
  随之改「4 公开类型（含 1 可变 Builder）」。
- **B. 保留「值类型」并加括注「含可变 Builder」**：改动最小，但术语与事实相反，
  误分类风险仍在。

**人类选择**：不改动

---

## 第三轮：对齐宪法 v1.1.0（2026-10-14）

**范围与前提**：本轮不是对 P01 三层产物的独立复跑，而是**两条外部变更的连锁复核**——
① 项目所有者已把宪法人工修订到 **v1.1.0（版本行见 constitution.md:148，
「批准 2026-10-12 ｜ 最近修订 2026-10-14」）**，脱敏条款相对 1.0.0 **放宽**；
② R2 八条已由所有者勾选（见「第二轮登记表」）。因此本轮条目**不改写第一/二轮
正文**（那些结论在当时条文下成立，保留为历史留痕），只登记「依据变更后的新结论」。

**现行条文引用基准**（v1.1.0）：

- 掩码段 `:109-114`：「敏感信息**默认不展示**：日志与一切用户可见输出（调试输出、
  EventListener、错误消息与错误上下文等）默认**不得出现** Authorization、
  Proxy-Authorization、Cookie、Set-Cookie、URL 用户信息等敏感信息（**自动掩码只是
  达成「不展示」的可选手段之一，不作机制性强制**）；当某项开发或设计**确需展示**
  敏感信息时，**MUST 事先主动汇报项目所有者、经人工确认后方可实现**。（不安全配置
  opt-in 等安全条款留待后期补充，暂不立条。）」
- target 条款**未随之修改**：`:69` 优先级固定 native ≥ wasm > wasm-gc > js、
  `:72` js 走 fetch 适配层且降级清单必须明确记录（P1）、`:73` wasm-gc 必须提供
  明确报错 stub（P2）、`:127-129` 合入门禁含「js 至少 `moon check --target js`
  通过且能力降级清单已同步」。
- 治理：`:136-137`（违背核心原则必须显式说明理由并记录 `例外跟踪`）、
  `:138-141`（修订流程与语义化版本）、`:130-132`（agent 可 commit，push/合并须
  人工批准）。

## R3-C1 「P01 只跑 native/wasm」与现行宪法的 target 条款冲突（agent 不可关闭）

**类别**：宪法合规 ｜ **严重度**：CRITICAL ｜ **阻塞 implement**：是（**且只能由
人工关闭**） ｜ **位置**：用户对 R2-F1 的选择（本文件 R2-F1 条目的人类选择行「目标只保留
native/wasm，wasm-gc/js 不在首先支持的平台中，目前不需要 check」）↔
constitution.md:69/72/73/127-129、plan.md:54（第一轮 M4 定案「V 行逐字不动」）、
spec.md:246-247（SC-004）、quickstart.md 步骤 2、tasks.md T018、
docs/roadmap/M1/README.md D9、deferred-items F9

**问题描述**：R2-F1 原本被定性为「SC-004 四目标 vs wasm-gc 不支持」的内部矛盾，
推荐解是「改为三目标 + wasm-gc 显式排除」。所有者勾选把它推得更远——**js 也退出
验证面**。这一步不再是产物之间的措辞问题，而是与宪法两条未修改的强制项正面冲突：

1. `:127-129` 是**合入前质量门**，明确把「js 至少 `moon check --target js` 通过
   且能力降级清单已同步」列为门禁项。P01 若按勾选不跑 js，质量门在宪法层面即为红。
2. `:69` 把 target 优先级写成「固定」，`:72` 把 js 定为 P1 且要求降级清单，
   `:73` 把 wasm-gc 定为 P2 且要求明确报错的 stub。勾选的「js/wasm-gc 不在首先
   支持的平台中」实质是把 :69 的排序改为 native ≥ wasm >（js、wasm-gc 暂不验证），
   并让 :72/:73 的义务悬空。
3. **本条无法由 agent 关闭**：宪法修订流程 `:138-141` 要求「人工审阅通过后提交」，
   且所有者本轮已明确「不允许你修改宪法，将问题记录到报告中」。所以本条的
   「人类选择」列只能由所有者填，且其中至少一个选项需要所有者自己动手改文件。
4. 牵连第一轮 **M4 锁**：M4 定案要求 plan.md 的 V 行逐字保持「native/wasm ✅、
   js ⚠️（仅 check）、wasm-gc ❌」。勾选 js 不跑后，那一行文字必然失真——
   即 M4 的「这里不动」约束需要**人工显式作废**，不能由 agent 自行松开。

**可行性事实**（供决策参考，非建议淡化）：js 侧成本其实极小——P01 是纯值类型包
（HttpUrl/HeadersV/Method/percent），**不含任何 target 特定代码**，
`moon check --target js` 只是一条命令；真正被 js 拖累的是后续带 socket/TLS 的包
（那属于 M3/M5 的事）。宪法 `:65` 另有一条：「网络行为测试必须基于可控本地服务端」，
与 P01 无涉。

### 决策及建议

- **A. 人工提宪法修订（项目级正解，代价最大）**：由所有者按 `:138-141` 流程修订
  target 条款（草案文本见本文件末尾「附录 A：宪法 target 修订草案」，**未写入
  宪法文件**），把「native/wasm 为合入门禁，js/wasm-gc 在 M5 前不验证、仅要求
  target 矩阵显式标注并挂欠账」写入。落地后需同步作废 M4 锁，并把 SC-004、
  plan L32/L34/L54、quickstart 步骤 2、research R7、tasks T018、M1 README D9
  一次性改为两目标口径。**版本判据由所有者定**：只动质量门 `:127-129` 可论证为
  MINOR（1.2.0）；若连 `:69` 的「固定优先级」与 `:72/:73` 的 P1/P2 义务一并重定义，
  按 `:140` 属「原则删除或重新定义」→ MAJOR（2.0.0）。
- **B.（P01 最小代价，推荐用于解阻塞）回退勾选的一半**：js 仍按现行宪法跑
  `moon check --target js`（**只 check 不 test**，与 plan V 行现状文案吻合，
  M4 锁无需作废），wasm-gc 采 R2-F1 原推荐 A 项「三目标 + wasm-gc 显式排除」。
  零宪法风险、零代码代价，P01 可立即进入回改链→implement；「js 退出支持面」的
  意愿留待 A 路径在项目级一次性处理。
- **C.（不推荐）保持冲突 + `# 例外跟踪`**：`:136-137` 允许显式记录例外，但那是为
  「违背核心原则但理由充分」准备的；此处省下的只是一条 check 命令，却要宪法 MUST
  门禁留污点、并让 plan V 行与质量门两处失真，收益不成比例。

**人类选择**：（待勾选 A/B/C——本条涉及宪法文件改动，agent 不得代执行）

## R3-H1 四层产物仍把「默认脱敏」写成 MUST，与所有者新方向相反

**类别**：上游依据漂移（宪法条款变更导致规格口径失效）｜ **严重度**：HIGH ｜
**阻塞 implement**：是 ｜ **位置**：spec.md FR-006 末句、FR-013（:203 附近）、
SC-005（:252-255）、Edge Cases 第 15 条（脱敏输出）、Key Entities、A8；plan.md
「技术约束与合规·敏感信息自动掩码 ✅」行与 Constraints 段；data-model.md §2
「调试输出」行 + §5「无包级可变状态」；contracts/headers.md「调试输出与脱敏」段
（手写 `impl Debug` + `debug_unredacted`）；quickstart.md 步骤 3/4；research.md
R13/R14；tasks.md T013/T014/T015/T018/T019 ↔ 用户对 R2-D1、R2-B1、
R2-C2 三条的勾选原文与 constitution.md:109-114

**问题描述**：第一轮 C1-A 与 N4-A 的裁决依据是 1.0.0 的「敏感信息**必须自动脱敏**」
机制性 MUST，据此在四层产物里写死了四件事：`HeadersV` 手写 `impl Debug` 做默认
脱敏、显式逃生口方法、测试与 `.snap` 禁用逃生口、SC-005 零明文泄漏 + T019 `git grep`
验收。v1.1.0 把其中**机制**部分降级为「可选手段之一」，而所有者对 R2 三条的勾选
方向是「P01 先用默认 `Debug`，脱敏等后续专开一个版本」「`.snap` 不需要脱敏」。
两组结论不能共存：

1. 现状 spec 是 **MUST 脱敏**，勾选后的实现是 **P01 不脱敏**——按宪法 SDD 章
   （:121-122）「改需求必须回改 spec 再向下重新生成，不得手改 tasks 使其与 spec
   脱节」，这是必须走 clarify 的需求变更，不是可以在 tasks 层消解的口径。
2. 反过来看也不该放任：spec 比宪法更严是允许的（自愿承诺），但本例是所有者
   **主动放宽**方向的选择，继续沿用旧措辞等于替所有者做了一个他已经否决的决定。
3. 影响面是**七个产物文件 + 五个任务 + 一处公开面**（详见 R3-M2/R3-M3），
   必须一次性回改，否则第三次 analyze 仍会报同一处。

### 决策及建议

- **A.（推荐，即 R2 勾选的规范化）P01 不实现脱敏，脱敏另开专版**：
  - FR-013 改写为「本包 MUST NOT 提供日志、展示或序列化输出类 API；除 `Debug`
    外无用户可见输出面。P01 **不承诺敏感头脱敏**，脱敏输出随可观测性专版
    （M3 Logger/EventListener 管线）交付，登记为欠账」。
  - FR-006 的 Debug 义务改为全部公开类型 `derive(Debug)` **默认实现**，删除
    「`HeadersV` 手写 `impl Debug`」与「显式逃生口方法」两处（见 R3-M3）。
  - SC-005 改写（见 R3-M2）；Edge Cases 第 15 条（脱敏输出）删除或改为
    「敏感头明文输出为已知延后能力」；A8 与 Key Entities 随之更新。
  - plan 的「技术约束与合规·敏感信息自动掩码」行从 ✅ 改为 **⚠️ + `# 例外跟踪`**，
    理由引用 R3-M1 的人工确认留痕（`:136-137` 要求的正是这个动作）。
  - quickstart 步骤 3/4 与 contracts/headers.md 脱敏段随 clarify → plan → tasks
    重生成，不手改。
- **B. 保留第一轮脱敏裁决，回退 R2-D1/B1/C2 勾选**：`HeadersV` 手写 impl +
  逃生口 + 快照纪律全部维持，Builder 侧按 R2-D1 的 A/B 补口。代价约 10 行手写
  `impl Debug` 与一条快照断言；收益是「默认不展示」在包内立即达成、不需要
  `例外跟踪`。**注**：implement 尚未启动（`src/core` 还不存在），所以「已写完
  不想返工」的成本论据在本条不成立，纯取舍问题。
- **C.（不成立）保持 spec 不动、实现按默认 `Debug`**：tasks 与 spec 脱节，
  直接违宪法 :121-122，排除。

**人类选择**：（待勾选；A 为 R2 勾选的规范化，B 为回到第一轮）

## R3-M1 「确需展示敏感信息」的人工确认留痕（宪法手续）

**类别**：宪法合规（程序性 MUST）｜ **严重度**：MEDIUM ｜ **阻塞 implement**：是
（手续项，本文件即可完成） ｜ **位置**：constitution.md:112-113（「确需展示
MUST 事先主动汇报项目所有者、经人工确认后方可实现」）↔ 用户对 R2-D1、
R2-C2 的勾选原文，以及 plan.md 的 `# 例外跟踪`（尚无该节）

**问题描述**：v1.1.0 放宽的是**手段**（自动掩码不再是机制性强制），没有放宽
**目标**（「默认不得出现敏感信息」仍是 MUST），并新增了一条程序性 MUST：确需展示
时**事先汇报所有者 + 人工确认**。采用默认 `Debug` 与明文 `.snap`，走的正是这条
路径。好消息是所有者在本轮对话中已明示该意愿，且本项目所有者即当前对话用户
（git user: Tang），因此**确认已实际发生**，缺的只是把它落成可审计记录——
否则 `:142` 的合规审查（code review 与 analyze 必须验证宪法符合性）无据可查。

### 决策及建议

- **A.（推荐）双处留痕**：① 本条正文作为人工确认的留痕源，原文引用所有者
  2026-10-14 的勾选（「Debug 可以先用默认实现，log 脱敏等后续专开一个版本进行」
  「测试数据 `.snap` 不需要脱敏」），并写明由此引入的**残留风险**——明文样例
  凭证会随 `.snap` 与测试源码进入版本库（不可逆：提交后需 rewrite history 才能
  清除），故约定「样例值必须是明显合成的占位串，禁止使用任何真实/可用凭证」；
  ② R3-H1-A 落地时在 plan.md 新增 `# 例外跟踪` 节，一行说明「敏感头 `Debug`
  输出不脱敏，依据宪法 1.1.0 的展示例外程序（本报告 R3-M1），脱敏实现挂欠账
  F13/M3」。
- **B. 只做 plan 的例外跟踪，报告不留原文**：留痕链断裂，`git grep` 审查时
  无法回答「谁批准的」，不建议。
- **C. 不做脱敏也不留痕**：违 `:112-113` 的程序性 MUST（且宪法的展示例外是
  1.1.0 **新增强制**，比 1.0.0 更明确），排除。

**人类选择**：（待勾选 A——本条同时需要所有者确认「合成占位串」纪律）

## R3-M2 SC-005 与 T019 在不脱敏下反向必红

**类别**：验收自相矛盾（可测性）｜ **严重度**：MEDIUM ｜ **阻塞 implement**：是
（随 R3-H1 一并关闭） ｜ **位置**：spec.md:252-255（SC-005）、tasks.md T019
（`git grep` 扫 `.snap` 与测试期望串）、quickstart.md 步骤 4 ↔ R2-C2 的勾选原文

**问题描述**：R2-C2 的原问题是「不产出 `.snap` 时扫描空转平凡为真」。勾选
「测试数据 `.snap` 不需要脱敏」后，风险**反了过来**：一旦按默认 `Debug` 出快照，
`.snap` 里就**必然含明文敏感头**（这是被允许的形态），T019 的 `git grep` 于是
从「空转」变成「必红」。即 SC-005 当前的表述（「本包提交的 `.snap` 快照与测试
输出中不含这些值」）在 P01 的新形态下**不可能满足**，而它仍是 spec 的 MUST 级
成功判据。

### 决策及建议

- **A.（推荐）改写 SC-005 的判据对象**：从「输出不含明文」改为「**本包不含
  展示类输出面与日志 API**」——具体判据三条：① `.mbti` 无 Logger/`Show`/
  `to_display`/序列化输出类签名；② 错误消息只携带定位片段、不整体回显原始输入
  （`contracts/method-error.md` 条款 3 已写，且这条与脱敏无关，属最小信息暴露，
  **不因 1.1.0 放宽而撤销**）；③ `HttpUrl::to_string` 不输出 userinfo（由
  FR-008 结构性保证，同样不撤销）。T019 随之改为「静态核对输出面清单」，
  与 R2-E1-A 的 T018 核对项合并，避免两条任务做同一件事。
- **B. 删除 SC-005**：SC 从 5 条回到 4 条，R2-C2 的快照问题随之消失（明文被允许
  即无需扫描）。代价：宪法「默认不展示」在 P01 的检查表彻底失去验收载体
  （只剩 A 项的 ③ userinfo 一条），`:142` 的合规审查更难举证。
- **C. 保留 SC-005 原文**：与 R3-H1-A 直接矛盾、T019 必红，不可。

**人类选择**：（待勾选 A/B）

## R3-M3 逃生口方法在默认明文下失去意义

**类别**：公开面收窄 ｜ **严重度**：MEDIUM ｜ **阻塞 implement**：否 ｜
**位置**：N4-A 与第一轮 C1-A 在 tasks.md T014/T018、quickstart.md L44-49、
contracts/headers.md 脱敏段留下的「显式逃生口方法（`debug_unredacted` 类）」
↔ R3-H1-A 的默认 `Debug` 形态

**问题描述**：逃生口的存在理由是「默认关、按需开」；默认即明文时它成为恒等操作，
是宪法 VI（YAGNI、接口纪律）意义上的死公开面，还会在 T018 冻结清单里占据一行
未审视的符号。**同时**，R2-D1 的「Builder `derive(Debug)` 构成掩码旁路」在这一
形态下自动闭合——没有默认掩码，就没有旁路，Builder 不再需要单独裁决。净效果：
公开面减一项、R2-D1 的严重度从 CRITICAL 降为「已由依据变更消解」。

### 决策及建议

- **A.（推荐）删除逃生口**，M3 专版一并设计「默认脱敏 + 按需展示」的完整形态
  （连同 N4 的可配置开关欠账 F12），避免现在留半截 API、M3 再改一次名。
- **B. 保留但语义反转**（默认明文、显式请求脱敏，如 `debug_redacted()`）：
  仍是一处 P01 用不到的公开面，且与 M3 的 Logger 配置面重复，不建议。

**人类选择**：（待勾选 A/B）

## R3-M4 roadmap 侧欠账与包摘要需同步

**类别**：交付物影响 ｜ **严重度**：MEDIUM ｜ **阻塞 implement**：否 ｜
**位置**：docs/roadmap/deferred-items.md（F12 = 可配置掩码开关 → M3）、
docs/roadmap/deferred-items/deferred-items-m1.md、docs/roadmap/M1/P01-core-value-types.md、
docs/roadmap/M1/README.md（D9 target 差异）

**问题描述**：R3-H1-A 把脱敏整体推到专版，roadmap 侧目前**只有 F12（开关形态）**
被登记，没有承载「脱敏输出实现本身」的条目；owner 审阅 roadmap 时会看到
「P01 交付默认脱敏」的旧摘要（第一轮结论），与实际交付形态不符。这些文件不是
规格类产物（不经 speckit 生成），可在回改链**之后**直接编辑。

### 决策及建议

- **A.（推荐）新增 F13**：「`HeadersV`/调试输出的敏感信息脱敏专版——归 M3
  可观测与安全，随 Logger/EventListener 管线与 F12 一并设计」，并在
  `deferred-items-m1.md` 记明细、P01 包摘要改一句「P01 不含脱敏（见 F13）」。
  R3-C1 若选 A（宪法修订），D9/F9 的 target 表述同批更新。
- **B. 扩写 F12 一条承载两件事**：索引计数不变，但「开关」与「实现」混在一条，
  M3 拆包时易漏。
- **C. roadmap 不动**：跨里程碑账目与 P01 实际交付不一致，不建议。

**人类选择**：（待勾选 A/B/C）

## R3-L1 本报告及下游产物中的宪法引用需换版

**类别**：术语/引用陈旧 ｜ **严重度**：LOW ｜ **阻塞 implement**：否 ｜
**位置**：本文件「分析范围」行（「对照 constitution.md v1.0.0（批准 2026-10-12）」）、
第一轮 C1/N4 与 R2-D1 正文内的 `constitution.md:113-114` 引用、plan.md 的
宪法检查表依据行、contracts/method-error.md 对「敏感信息掩码」的引用

**问题描述**：宪法已升 1.1.0，掩码段行号从 113-114 变为 **109-114**，且条款语义
变更（机制性 MUST → 目标 MUST + 可选手段 + 展示例外程序）。第一/二轮正文引用
当时条文**在当时是正确的**，全部重写反而销毁决策留痕。

### 决策及建议

- **A.（推荐）历史条目不动**，只在本轮起统一引用 1.1.0 现行行号；R3-H1 落地时
  plan/contracts 的引用由重生成自然刷新，本文件「分析范围」行 的范围说明可在归档时加一句
  「v1.1.0 后的复核见第三轮段」。
- **B. 全量重写行号与版本**：销毁历史一致性证据，不建议。

**人类选择**：（待勾选 A/B）

---

# 决策登记表

关闭结论只需在本表打勾，明细见各条正文。C1/H1/H2/H3 与 N1/N2 为 implement 前置项。
**N1–N4 全部定案**（N1/N2 取 A；N3 取 A 拆两条 FR；N4 取 A，可配置掩码开关归 M3）。
**下表为第一轮登记表（已全部定案）；第二轮（2026-10-14）复跑的 8 条待勾选项见该表
之后的「第二轮登记表」，其 R2-D1/R2-F1 重新构成 implement 前置项。**

| ID | 严重度 | 建议首选项 | 人类选择 | 影响产物 | 需重跑的命令 |
|----|--------|------------|----------|----------|--------------|
| C1 | CRITICAL | A | **A** | spec、plan、tasks、contracts/headers | `speckit-plan` → `speckit-tasks` |
| H1 | HIGH | A | **A** | spec(SC-003)、tasks T015 | `speckit-tasks`（或手改 T015 文本） |
| H2 | HIGH | A | **A** | spec、data-model、plan、tasks T003/T013 | `speckit-plan` → `speckit-tasks` |
| H3 | HIGH | A | **B→定案 N2-A** | contracts、spec/plan/tasks | `speckit-specify` → `speckit-plan` → `speckit-tasks` |
| M1 | MEDIUM | A | **A** | spec、tasks T003/T006 | `speckit-tasks` 或手改 |
| M2 | MEDIUM | A | **A（不折叠）** | contracts/headers、data-model、tasks T013 | `speckit-plan` 复检 |
| M3 | MEDIUM | A | **A** | plan、（选 B/C 时）tasks | — |
| M4 | MEDIUM | A | **不改动** | plan（判定行）不改，仅本报告留痕 | — |
| M5 | MEDIUM | A | **A→定案 N1-A** | spec FR-006/SC-004、tasks T003/T004 | `speckit-plan` → `speckit-tasks` |
| M6 | MEDIUM | A | **A** | plan Performance Goals | — |
| L1 | LOW | A | **A（snake_case）** | spec 注、tasks T018、quickstart | — |
| L2 | LOW | A（与 M1 合并） | **A** | plan、quickstart | — |
| L3 | LOW | A | **A** | research R10、quickstart | — |
| L4 | LOW | A | **A** | spec A5 | — |
| L5 | LOW | A | **A** | tasks T002 | — |
| L6 | LOW | A | **A** | contracts/http-url、tasks T011/T017 | — |
| **N1** | MEDIUM | A | **A** | spec FR-006/SC-004、contracts、tasks T004/T009/T014/T018 | `speckit-plan` → `speckit-tasks` |
| **N2** | HIGH | A | **A** | spec FR-002/Key Entities、contracts/http-url、tasks T009/T018 | `speckit-specify` → `speckit-plan` → `speckit-tasks` |
| **N3** | LOW | A | **A**（拆两条 FR-012/FR-013） | spec FR 清单（新增条目的划分与编号） | `speckit-clarify` |
| **N4** | MEDIUM | A | **A**（默认脱敏 + 显式逃生口；全局 flag 归 M3） | spec FR-013、contracts/headers、tasks T014/T015/T018、deferred-items | `speckit-clarify` → `speckit-plan` → `speckit-tasks` |

## 第二轮登记表（2026-10-14 复跑，**已全部勾选**）

R2-D1 与 R2-F1 原为 implement 前置项。勾选已完成（原文见各条正文与本表「人类选择」
列）；**其中 R2-D1/R2-B1/R2-C2 的结论在勾选后被宪法 v1.1.0 的放宽所改写，R2-F1 的
勾选升级为与宪法 target 条款的冲突——三条均转入第三轮重议（见 R3-H1/R3-M1/R3-C1）**。
「需重跑的命令」按 spec 层是否变动给出：凡涉 spec 措辞者必须走
`/speckit-clarify` → `/speckit-plan` → `/speckit-tasks`，不得手改规格类产物。

| ID | 严重度 | 建议首选项 | 人类选择 | 影响产物 | 需重跑的命令 |
|----|--------|------------|----------|----------|--------------|
| **R2-D1** | ~~CRITICAL~~ → 由 R3 重议 | A（Builder 不暴露 Debug） | **原文「Debug 可以先用默认实现，log 脱敏等后续专开一个版本进行」**——不采 A/B/C/D 任一项，等于宣布 P01 不做脱敏；在 1.1.0 下旁路问题自动消解，但规格措辞需第三轮回改（R3-H1） | spec FR-006/FR-013/Key Entities/SC-005、data-model §2、contracts/headers、tasks T014/T018、quickstart | `speckit-clarify` → `speckit-plan` → `speckit-tasks` |
| **R2-F1** | HIGH → **CRITICAL（R3-C1）** | A（三目标 + wasm-gc 显式排除） | **原文「目标只保留 native/wasm，wasm-gc/js 不在首先支持的平台中，目前不需要 check」**——比 A 更激进：js 也退出口径，与宪法 :69/:72/:127-129 冲突，需人工修订或回退一半（见 R3-C1 的 A/B/C） | spec SC-004、plan L32/L54（**M4 锁需人工作废**）、quickstart 步骤 2、tasks T018、research R7、M1 README D9 | 人工宪法修订 → `speckit-clarify` → `speckit-plan` → `speckit-tasks` |
| R2-C1 | MEDIUM | A（`HeadersV::builder()` 上升为 spec 口径） | **原文「空 builder 应该使用 `HeadersVBuilder::new()`，`HeadersV::builder()` 只用于将已固化项转换成 builder」**——非 A 非 B，是**双入口并存**：`new()` 造空、`builder()` 做不可变→可变回转；回转是否重跑 FR-012 校验本条未定，审阅结论第 4 点给出建议（不重校验） | spec FR-004/Key Entities、contracts/headers、data-model §2、tasks T014/T018、quickstart 冻结清单 | `speckit-clarify` → `speckit-plan` → `speckit-tasks` |
| R2-B1 | MEDIUM | A（手写 impl 同样 `pub extend ... to_repr`） | **原文「优先使用默认 Debug 实现，有问题再回改」**——A/B 二选一被绕过：不再手写 impl，`HeadersV` 走 `derive(Debug)`；[0079] 的 `pub extend ... Debug::{to_repr}` 口径对全部值类型统一适用（本条随之闭合） | tasks T014/T018、quickstart L47-48、contracts/headers | `speckit-tasks` |
| R2-E1 | MEDIUM | A（T018 加静态核对，spec 不动） | **A**（按推荐项） | tasks T018、quickstart L74 | `speckit-tasks` |
| R2-C2 | MEDIUM | A（脱敏输出留一份快照） | **原文「测试数据 `.snap` 不需要脱敏」**——快照仍要做（AGENTS.md 的 `debug_inspect` 惯例），但取消「快照禁明文」纪律；后果是 SC-005/T019 反向必红（R3-M2） | spec SC-005、contracts/headers 条款 5、tasks T013/T019 | `speckit-clarify` → `speckit-plan` → `speckit-tasks` |
| R2-B2 | LOW | A（收窄为两处输出面） | **A**（按推荐项；「两处输出面」的具体清单随 R3-H1/R3-M2 改写） | spec FR-013、contracts/headers | `speckit-clarify` |
| R2-A1 | LOW | A（改「公开数据类型」+ 按可变性分列） | **不改动**（保留「值类型」称谓，接受术语与可变性的既有混用） | — | — |

## R2 裁决审阅结论（2026-10-14，agent 审阅；涉宪法部分已按 v1.1.0 重推）

1. **三条（D1/B1/C2）合起来是一次需求变更，不是三个口径修补**：P01 交付形态从
   「`HeadersV` 手写脱敏 `impl Debug` + 逃生口 + 快照禁明文」变为「全部公开类型
   `derive(Debug)` 默认实现 + 允许明文快照」。规格类产物不得手改，故必须经第三轮
   `/speckit-clarify` 编码进 spec 再向下重生成——即 R3-H1。
2. **在 v1.1.0 下合规定性变了**：1.0.0 的「必须自动脱敏」是机制性 MUST，当时明文
   `Debug` 直接违宪（故 C1/R2-D1 定 CRITICAL）。1.1.0 改为「默认不展示」+「自动掩码
   只是可选手段」+「确需展示 MUST 事先汇报所有者并经人工确认」（:109-114）。放宽的是
   **手段与实现自由度**，**没有**放宽「不展示」这个目标；所以本选择仍属「展示敏感
   信息」情形，需要走程序性确认——所有者本轮已明示，缺的是可审计留痕（R3-M1：
   本报告原文 + plan.md `# 例外跟踪`，后者是 :136-137 的强制动作）。
3. **不因放宽而撤销的三条**（结构约束/独立安全义务，与掩码无关）：FR-008 拒绝
   userinfo、FR-012 头名 token 校验与头值 CR/LF 拒绝（防头注入）、错误消息只携带
   定位片段不整体回显输入。审阅特别提示：**「不做脱敏」≠「不校验」**，回改 spec 时
   不得把这三条连带削弱。
4. **R2-C1 的双入口需补一条语义**（勾选原文未写，属 agent 补全，可纠正）：
   `HeadersV::builder()` 是「不可变→可变」回转，源数据在首次 `build()` 前已由
   FR-012 校验过，回转**不应**重跑校验（否则可能出现「合法值经 build 后反而不可
   再 build」的病态分支）；`new()` 与 `builder()` **两个入口都进 T018 冻结清单**。
5. **R2-F1 的勾选已越出规格层**：js 与 wasm-gc 双双退出口径意味着宪法 :69 的
   「固定优先级」与 :127-129 的 js 门禁被否弃。所有者已指令「不允许修改宪法，
   将问题记录到报告中」，故该条只能人工关闭：提修订（附录 A 草案）或回退一半
   （js 只 check、wasm-gc 显式排除）。同时 **M4 锁（plan V 行逐字不动）需所有者
   显式作废**，agent 不自行松开。
6. **implement 前置门更新**（取代第二轮结论）：① R3-C1 人工处置；
   ② R3-H1/R3-M2/R3-M3 走第三轮回改链；③ R3-M1 留痕 + plan `# 例外跟踪`。
   三者全部关闭后才可 `/speckit-implement`。

## 第三轮登记表（2026-10-14·对齐宪法 v1.1.0，**全部待勾选**）

R3-C1 只能由**人工**关闭（涉宪法文件，agent 不得代执行）；R3-H1/R3-M2 为 implement
前置项；R3-M1 是所有者的确认留痕动作；R3-M3/M4/L1 建议同轮一并定，避免第四次回环。

| ID | 严重度 | 建议首选项 | 人类选择 | 影响产物 | 需重跑的命令 |
|----|--------|------------|----------|----------|--------------|
| **R3-C1** | CRITICAL（人工专属） | B（P01 解阻塞最小代价：js 仍 `check`、wasm-gc 显式排除）；A 为项目级正解（人工提宪法修订，草案见附录 A） | （待勾选 A/B/C） | 宪法 :69/:72/:127-129（人工）、plan L54 + M4 锁作废、spec SC-004、quickstart 步骤 2、tasks T018、research R7、M1 README D9 | 人工修订 → `speckit-clarify` → `speckit-plan` → `speckit-tasks` |
| **R3-H1** | HIGH | A（P01 不实现脱敏，脱敏另开专版；plan 记 `# 例外跟踪`） | （待勾选 A/B） | spec FR-006/FR-013/SC-005/Edge Cases 第 15 条/Key Entities/A8、plan 检查表 + Constraints、data-model §2/§5、contracts/headers、quickstart 步骤 3/4、research R13/R14、tasks T013/T014/T015/T018/T019 | `speckit-clarify` → `speckit-plan` → `speckit-tasks` → `speckit-analyze` |
| **R3-M1** | MEDIUM（手续） | A（报告原文留痕 + plan `# 例外跟踪` + 合成占位串纪律） | （待勾选 A；需同时确认「`.snap`/测试只用合成占位凭证值」） | 本文件、plan.md（新增 `# 例外跟踪` 节）、contracts/headers 条款 | — |
| R3-M2 | MEDIUM | A（SC-005 判据改为「无展示类输出面 + 错误不整体回显 + 无 userinfo」，T019 并入 T018） | （待勾选 A/B） | spec SC-005、quickstart 步骤 4、tasks T018/T019 | 随 R3-H1 |
| R3-M3 | MEDIUM | A（删除逃生口，M3 专版统一设计） | （待勾选 A/B） | spec FR-013、contracts/headers、tasks T014/T018、quickstart 冻结清单 | 随 R3-H1 |
| R3-M4 | MEDIUM | A（新增 F13 + P01 包摘要改写） | （待勾选 A/B/C） | docs/roadmap/deferred-items.md、deferred-items-m1.md、M1/P01-core-value-types.md、（选 A 时）M1/README.md D9 | 回改链后直接编辑（非规格类产物） |
| R3-L1 | LOW | A（历史条目不动，第三轮起引用 1.1.0 行号） | （待勾选 A/B） | 本文件「分析范围」行、下游引用行号（重生成时自然刷新） | — |

---

# 下游动作

1. **收集决策**：已完成——本文件「决策登记表」的「人类选择」列全部填写，
   C1–M6、L1–L6 与 N1–N4 **均已定案（N1–N4 均取推荐项 A）**。下一步是把决策
   编码进 spec，不得手改规格类产物。
2. **回改上游（宪法 SDD 要求，不得手改 tasks 使其与 spec 脱节）**：
   - 涉 C1(+N4)/H2/H3(+N2)/M1/M5(+N1)/N3 的 spec 修改 → 走 `/speckit-clarify`
     （把决策作为裁决追加进 Clarifications）或 `/speckit-specify`
     （更新 spec.md，保留既有 Clarifications 记录）。
   - spec 变更后 → `/speckit-plan`（刷新 Constitution Check 表，新增「技术约束
     与合规」行与例外跟踪）→ `/speckit-tasks`（重新生成，保持锚点指向新 FR）。
   - 仅涉 M3/M4/M6/L 项的 plan/tasks/contracts 文案修正可直接编辑，无需上游重生成。
3. **复跑校验**：`/speckit-analyze` 二次确认 CRITICAL=0、HIGH=0。
   **（2026-10-14 已复跑：19 项决策全部落地，但结果 CRITICAL=1、HIGH=1，
   未达判据——新出 R2-D1/R2-F1 等 8 条，implement 前置条件重新打开。）**
4. **进入实现**：仅当 C1/H1/H2/H3 与 N1/N2 关闭后才跑 `/speckit-implement`
   （N1/N2 直接决定公开面形状与 `moon check` 门禁，留到实现期必然返工）；
   若决定不关闭而接受风险，须以 `# 例外跟踪` 形式在 plan.md 显式记录理由与归属
   （宪法治理章要求），不得静默推进。
5. **本文件归档**：决策落地后建议保留本文件作为 M1-P01 的 analyze 留痕，
   或在 spec.md 的 Clarifications 区引用其结论摘要。

---

## 第二轮之后的动作（2026-10-14，复跑后新增）

1. **勾选 R2 八条**：在「第二轮登记表」的「人类选择」列填写。最小闭环只需
   **R2-D1 + R2-F1**（两条 CRITICAL/HIGH 均为 implement 前置）；强烈建议同轮
   把 R2-C1/R2-B1/R2-E1/R2-C2/R2-B2/R2-A1 一并定案——它们与 D1/F1 落在同一批
   产物（FR-006/FR-013/SC-004/SC-005/T014/T018/quickstart 冻结清单）上，
   分轮改会造成第三次回环。
2. **第三轮上游回改**：追加 `### Session 2026-10-14` 的 Clarifications
   （保留既有 14 条不动），涉 spec 措辞的条目为 R2-D1/R2-F1/R2-C1/R2-B2/R2-A1
   （+ 选 B 时的 R2-C2）→ `/speckit-clarify`；随后 `/speckit-plan`
   （**M4 约束仍生效：V 行逐字不动**；「技术约束与合规」行需按 R2-D1 结论把
   Builder 一侧的落地写进去）→ `/speckit-tasks`（T013/T014/T018/T019 与
   冻结清单随之改写）。R2-E1 若选 A（只加 T018 静态核对）与 R2-B1 若判为
   tasks 期口径，可在 tasks 层落地，不动 spec。
3. **第三次复跑校验**：`/speckit-analyze` 确认 CRITICAL=0、HIGH=0；届时
   FR 覆盖率应达 **18/18**（R2-E1 补 FR-011 判据）。
4. **进入实现**：仅当上述两项前置关闭后才跑 `/speckit-implement`。若决定接受
   R2-D1 的违宪风险而暂不关闭，必须以 `# 例外跟踪` 形式在 plan.md 显式记录
   理由与归属（宪法治理章），不得静默推进——但宪法 MUST 的掩码条款属不可
   妥协项，不建议走这条路。
   **（2026-10-14 第三轮注**：本节第 1–2 步的前提已被两件事改变——R2 已勾选完毕，
   且宪法升到 v1.1.0 使 R2-D1 的违宪定性失效。以下「第三轮之后的动作」取代表述。）

---

## 第三轮之后的动作（2026-10-14·对齐宪法 v1.1.0）

1. **人工关闭 R3-C1（唯一的硬阻塞，agent 不可代执行）**：在 A（提宪法修订，草案见
   附录 A）与 B（回退勾选的一半：js 仍 `moon check --target js`、wasm-gc 显式排除）
   之间选一个，并同时决定是否**作废 M4 锁**（plan.md 的 V 行「逐字不动」约束）。
   选 B 时规格层只需把「四目标」改「三目标 + wasm-gc 显式排除」，plan V 行可原样
   保留，回改面最小。
2. **勾选 R3-H1（决定 P01 是否交付脱敏）**：选 A 即把 R2-D1/B1/C2 的意愿规范化；
   选 B 即回到第一轮 C1-A/N4-A 形态。**必须先有 1 的结论**，否则 clarify 会把
   target 与脱敏两条未定口径一起写进 spec，第四轮还要再回环。
3. **完成 R3-M1 的留痕手续**：确认后在本条打勾，并在 `/speckit-plan` 时把
   `# 例外跟踪` 节写进 plan.md（`:136-137` 治理章强制）。同时确认
   「`.snap`/测试只用合成占位凭证值」这条纪律——明文一旦提交进版本库，
   清除需要 rewrite history，属不可逆动作。
4. **第三轮上游回改链**（仅在 1/2/3 就位后执行，规格类产物不得手改）：
   `/speckit-clarify`（追加 `### Session 2026-10-14`，保留既有 14 条不动）→
   `/speckit-plan`（刷新检查表：掩码行按结论改 ✅/⚠️+例外跟踪；target 行按
   R3-C1 结论处理，M4 锁若作废则一并改写）→ `/speckit-tasks`（T013/T014/T015/
   T018/T019 与 `.mbti` 冻结清单随之改写：删逃生口、补 `HeadersVBuilder::new()`
   与 `HeadersV::builder()` 双入口、并入 FR-011/输出面静态核对）→
   `/speckit-analyze`（判据：**CRITICAL=0、HIGH=0、FR 覆盖 18/18**）。
5. **roadmap 同步（非规格类产物，回改链之后直接编辑）**：按 R3-M4 的勾选新增
   F13、改写 `docs/roadmap/M1/P01-core-value-types.md` 摘要；若 R3-C1 选 A，
   同批改 `docs/roadmap/M1/README.md` 的 D9 与 deferred-items F9 表述。
6. **进入实现**：仅当 R3-C1/R3-H1/R3-M1/R3-M2 全部关闭、且第三轮 analyze 达标后，
   才可跑 `/speckit-implement`。宪法修订、push 与分支合并仍须人工执行/批准
   （`:130-132`）。

## 附录 A：宪法 target 条款修订草案（**仅供人工审阅，agent 未写入宪法文件**）

**动机**：所有者 2026-10-14 对 R2-F1 的决策「目标只保留 native/wasm，js/wasm-gc
不在首先支持的平台中，目前不需要 check」，与现行宪法 v1.1.0 未同步修改的 target
条款冲突（见 R3-C1）。M1 阶段（尤其 P01 纯值类型包）跑 js/wasm-gc 不产生任何
有效信号：`moon check --target wasm-gc` 因 `@http` 未实现该 target 而**编译失败**
（非警告），js 侧则无任何 target 特定代码可验证。

**影响范围**：原则 V（`:67-74`）、合入前质量门（`:127-129`）；下游连带
`docs/roadmap/M1/README.md` D9、deferred-items F9、各包 plan 的 Target 策略行与
Target 矩阵标注口径、M5（target 收口）里程碑的定义。**不改动**：原则 IV（测试
先行）、VI（接口纪律）、VII（中文表达）与掩码条款。

**拟改文本（最小版本，仅动质量门）**：

```text
:127-129 现文
- 合入前质量门：`moon info && moon fmt` 干净、`moon test --target native` 与
  `moon test --target wasm` 双双全绿、js 至少 `moon check --target js` 通过且
  能力降级清单已同步、`.mbti` diff 已审视、性能改动附基准数据、宪法合规已自查。

拟改为
- 合入前质量门：`moon info && moon fmt` 干净、`moon test --target native` 与
  `moon test --target wasm` 双双全绿、`.mbti` diff 已审视、性能改动附基准数据、
  宪法合规已自查。js 与 wasm-gc 在 M5（target 收口）之前不作为合入门禁，仅要求
  每项能力的 target 矩阵显式标注「暂不验证」并挂欠账跟踪；M5 起 js 恢复
  「至少 `moon check --target js` 通过且能力降级清单已同步」门禁。
```

**拟改文本（完整版本，另动原则 V）**——若要把「js/wasm-gc 暂不支持」升为项目级
策略而不只是门禁豁免：

```text
:69 现文   target 优先级固定为 native ≥ wasm > wasm-gc > js。
拟改为     target 优先级固定为 native ≥ wasm > js = wasm-gc；M5 之前 js 与 wasm-gc
           均不在验证面内，只要求显式标注与欠账跟踪。

:72 现文   - js 走 fetch 适配层，能力降级清单必须明确记录（P1）。
拟改为     - js 走 fetch 适配层；能力降级清单在 M5（target 收口）建立并同步，
           M5 之前记为「未验证」而非「已降级」（P1，交付点移至 M5）。

:73 现文   - wasm-gc 被 async runtime 阻塞，必须提供明确报错的 stub（P2，跟踪上游）。
拟改为     - wasm-gc 被 async runtime（`@http` 编译图）阻塞，M5 之前不建 stub，
           仅跟踪上游进度并保留显式排除说明（P2）。
```

**版本判据（由所有者定）**：只动 `:127-129` 属「质量门实质性扩充/收窄」→ **MINOR
（1.2.0）**；若连 `:69` 的「固定优先级」排序与 `:72/:73` 的 P1/P2 义务一并改写，
按 `:140` 属「原则删除或重新定义」→ **MAJOR（2.0.0）**。

**流程要求（`:138-141`）**：提出修订（本附录已含动机 + 影响范围）→ 更新版本行
（`**:版本**：x.y.z | 批准日期 | 最近修订`）→ 在文件顶部生成 Sync Impact Report →
人工审阅通过后提交，**提交前删除该报告**。本文件的顶部遗留 TODO 注释块
（不安全配置 opt-in / F12、OkHttp 5.5.0 delta 核对等）应在新修订中一并核对是否
需要跟进。**该文件的修改与提交只能由所有者执行。**
