# Specification Analysis Report（round2-qoder-review）— 006-m1-p06-redirects

- **特性**：自动重定向 follow-up 循环（M1-P06）
- **执行日期**：2026-10-27 ｜ **执行者**：qoder（独立交叉复核方，工单③）
- **命令**：qoder 侧 `speckit-analyze` 技能（基目录 `.qoder/skills/speckit-analyze`，非 opencode 的 `/speckit.analyze`）
- **分析对象**：`specs/006-m1-p06-redirects/` 全部产物（spec/plan/tasks/research/data-model/quickstart/contracts/checklists），对照 `.specify/memory/constitution.md`（v1.2.0）与仓内现状源码
- **程序顺序声明**：本报告 A 节为**先独立完成**的交叉分析；写 A 节前未读 round1 报告。B/C/D 节在读 `analyze/round1-opencode.md` 之后生成。
- **只读声明**：除本文件外零写入、零 git 写操作；未触碰工作区 3 个 `pkg.generated.mbti`（仅只读 grep/cat）。
- **预检结果**：`check-prerequisites.ps1 -Json -RequireSpec -RequireTasks -IncludeTasks` 实测返回 `FEATURE_DIR=E:\Project\moonhttp\specs\006-m1-p06-redirects`，`AVAILABLE_DOCS=["research.md","data-model.md","contracts/","quickstart.md","tasks.md"]`；`.specify/extensions.yml` 实测不存在（`ls` → No such file or directory），before/after 钩子均无。
- **取证限制（如实声明）**：①外部 OkHttp 取证仓 `E:\Project\moon-easyhttp-explore\okhttp` 在本会话被权限拦截（`git show parent-5.5.0:…` 被拒），故 research R1 / spec 映射表的全部 5.5.0 行号断言（RFU L104-109/L113-116/L228/L314-320/L326-331/L355 等）**本轮未独立复核**，仅核到「产物内部自洽」层；②未运行任何 `moon` 命令（避免 `_build` 与生成 `.mbti` 写入），凡「实测」均为读文件/确定性 grep。
- **级别口径**：沿用工单口径 CRITICAL/WARNING/INFO；与技能启发式映射 CRITICAL=CRITICAL，WARNING=HIGH/MEDIUM，INFO=LOW/记录性。宪法 MUST 冲突一律 CRITICAL。

---

## A. 独立发现总表（写 round1 对比前已完成）

| ID | 类别 | 级别 | 位置（文件:行号） | 摘要 | 建议 |
|----|------|------|-------------------|------|------|
| Q-A1 | 覆盖缺口 | **WARNING** | spec.md:221-223（FR-002「排干失败 MUST 毒化」）；research.md:273-277（R10 表 FR-001/FR-003/FR-005/FR-010/FR-009/SC-008 六行，无 FR-002 行）；tasks.md:218-226（T012 只断言成功排干：连接数=1、干净流、事件标记） | FR-002 失败半边（`skip_response_body` 失败 → 毒化 → 不回池 → 透传）无红绿对承载。夹具承载面已在场（fixtures mbti:87 `mount_truncated`） | 在 T012 或独立 WB 子项补排干失败用例（先红后绿），R10 表补 FR-002 行 |
| Q-A2 | 机制归属歧义（跨产物） | **WARNING** | data-model.md:13-31（实体 1 伪码：`errdefer poison_release()` 置于**轮级**，覆盖 `exchange_with_lease` 之后的 `drain_intermediate`/`release_lease`/计数 guard 诸步）；research.md:173-178（R6：「skip 失败 → `poison_release()` 后错误透传」把毒化放在 **drain 调用点内部**）；tasks.md:102-106（T004 实现口径同 data-model 轮级 errdefer） | 同一失败路径的处置归属两套写法并存：轮级 errdefer 兜毒化 vs drain 内显式 catch-and-poison。若按 data-model 字面实现，errdefer 会在「排干已成功、计数超限 raise」路径上再次触发 `poison_release`——现状实现下无害（`release_lease` src/client/body_bridge.mbt:68-76 先 `lease.release()` 再 `self.lease=None`；`poison_release` body_bridge.mbt:38-48 见 `lease is None` ⇒ no-op；`Lease::poison` client.mbt:313-318 见 `released` ⇒ no-op），但 INV-4「先排干后**干净**释放再 raise」的成立仅靠该实现细节兜住，且产物无一条白盒断言钉住它 | 在 data-model 或 R6 固定一句处置归属（推荐：轮级 errdefer 只覆盖单轮 exchange 段；advance 段显式 catch），并在 T014 白盒补「超限 raise 后连接干净回池（非关闭）」断言 |
| Q-A3 | 任务枚举 ↔ 映射表冲突 | **WARNING** | spec.md:43-48（US-1-4 PUT→302、US-1-5 DELETE→300 为 C2/300 修正的固化场景）；research.md:267（R10 记「US-1-4/5 → P06-US1 黑盒」）；tasks.md:119-144（T005 仅枚举 P06-US1①②、T006 ③、T007 ④——全链无 ⑤，且 ①② 均为 POST 起手）；spec.md:288-290（SC-001 要求决策表每行 ≥1 用例、含 300 有/无 Location 双形态） | US-1-4/US-1-5 两个黑盒场景在 tasks 任务枚举中无落点，与 R10 的归属声明直接矛盾（T016 白盒穷举可覆盖真值，但 SC-001 的黑盒场景口径与 tasks 落笔不一致） | 二选一：tasks T005/T007 补 ⑤（PUT→302→GET、DELETE→300→GET 黑盒），或 R10 该行改记「白盒穷举 T016」并同步 SC-001 判据口径 |
| Q-B1 | 契约↔实况漂移 | INFO | contracts/follow-up-api.md:20（`pub fn Call::execute(Self) -> @core.Response`）；src/client/pkg.generated.mbti:36（实况 `pub async fn Call::execute(Self) -> @core.Response`） | 事前契约漏 `async` 关键字；contracts 自称「SC-008 对账面」，逐字对账会误报 | 契约行改 `pub async fn`；或在对账口径中声明关键字不参与逐字比对 |
| Q-B2 | 论断失实 + 状态冗余 | INFO | research.md:88-90（R3「`lease_addr : Address?`（当前租约地址，**Lease 无 addr 访问器**——client mbti 核证」）；src/client/client.mbt:135-143（`Lease` 结构体第 3 字段即 `priv addr : Address`）；MoonBit priv 字段同包内可读（本包 follow_up.mbt/exchange.mbt 与 client.mbt 同包，先例：exchange.mbt:98 直读 `lease.conn`） | 「无 addr 访问器」仅对包外成立；同包私有字段可读，故 Call 侧新增 `lease_addr` + INV-6 双写同步并非唯一解，存在冗余状态面（宪法 VI） | implement 前定死口径：要么 `lease.addr` 同包直读、删 `Call.lease_addr`；要么保留字段并把 R3 该括注改写为「无公开访问器，同包直读可选」 |
| Q-B3 | 伪码签名漂移 | INFO | data-model.md:17（实体 1 伪码 `exchange_with_lease(request)`）；research.md:85（R3：`exchange_with_lease(request : @core.Request)` 参数化）；src/client/exchange.mbt:91-94（实况 `exchange_with_lease(self, lease : Lease)`） | R3 的参数化表述与实体 1 调用形态互斥：按 R3 落笔后该函数不再持 lease 入参，但轮级 `errdefer`/`ensure_lease` 叙述仍以「持租」为前提；两者只可取一 | plan/data-model 统一签名口径（推荐：保留 `lease` 入参，参数化只加 request；或改名 `exchange_round`） |
| Q-B4 | 未成文前提 | INFO | spec.md:218-220（FR-001「已取消或轮间取消 MUST 以裸 CallCancelled 终止」）；src/client/http_client.mbt:93-104（`cancel()` 同步 `poison_release`）；data-model.md:14（轮顶 guard 仅 raise，不写处置）；src/client/http_client.mbt:176-179（`body_delivered` 在 Delivered 分支才置 true） | 轮间取消的连接处置实由 `cancel()` 单点承担（`lease=None` ⇒ guard 路径 no-op），FR-001 未成文；guard raise 时 `body_delivered=false` ⇒ `fire_abandoned_if_orphaned`（body_bridge.mbt:56-64）不误触发，该「中间轮不触发 Abandoned」依赖亦未成文 | spec FR-001 或 contracts 行为表补一句「轮间取消的租约处置由 cancel 完成，guard 仅终止」；T004 白盒可顺带断言 `lease is None` |
| Q-B5 | 验收口径双轨 | INFO | quickstart.md:9-16（六门列法：门1 `moon info && moon fmt`、门2/3 `moon test --target native/wasm`、门4 js check、门5 coverage、门6 自查）；tasks.md:54-62（T001 的六门：`check --deny-warn` ×2 + `test` ×2 + `fmt --check` + `info`） | 同名「六门」在两产物中成员不同（T017「收口六门（对照 T001 基线）」未声明以哪套为准），执行期计数与验收记录口径可能漂移 | T017/quickstart 统一六门成员表，或改称「六门= T001 清单」并让 quickstart 对齐 |
| Q-B6 | 编号碰撞 | INFO | spec.md:239（FR-004 行内「—— C1 裁决，依据见 Clarifications 第 1 条」与 spec.md:310「**C1 裁决**（跨 host 剥 Cookie）」）与 spec.md:279-282（Key Entities「**TooManyFollowUps**：跳数超限的显式错误变体（FR-005）；与 `CallCancelled`（P05）同为 client 包错误面成员」处并无编号，但 spec.md:200-214 非目标段与 Clarifications 段各自使用「C1–C4」指代两类对象（澄清议题 vs 裁决记录），且 plan.md:119 (D-1) 亦复用 C 号 | 「C1」在本 spec 至少承载两义（澄清议题 C1=剥头范围；边界条款编号习惯），与宪法 v1.1.0 遗留段 F12 等交叉编号体系并存，后续 converge/回引易张冠李戴 | 澄清议题统一写「Clarifications 第 n 条」，裁决统一写「裁决 Cn」，避免同字面双指 |
| Q-B7 | 记录性注记 | INFO | research.md:216-220（R7 21 跳链构造：「`mount_sequence` 21 个重定向 + **终态 mount**」）；src/internal/fixtures/scripted_server.mbt:47-49、:314-315（`Sequence` 按命中序取 `min(i, len-1)`，**末位驻留**） | 超限在第 21 个仍需跟随的响应处 raise，序列末位（终态脚本）永不被消费——「+ 终态 mount」在该构造下是冗余布置（不影响判据，但构造叙述与夹具语义合取后可能误导 implement 的夹具布置） | R7 该句补注「末位驻留 ⇒ 终态项不被触达，可省」，或直接以 21 项全重定向构造 |
| Q-B8 | 记录性注记 | INFO | checklists/requirements.md:9、30（勾选「No implementation details (languages, frameworks, APIs)」「No implementation details leak into specification」）；同文件 :34-37（Notes 以「本库特性写法」自辩）；spec.md 通篇 FR-008/FR-010 点名 `HttpUrl::resolve`/`HeadersV`/`to_http_request` | 勾选项与 Notes 自述互相矛盾（Notes 已给出偏离理由，属 005 先例延续），记录性：该项在本仓口径下不具判别力 | 保留先例口径即可；建议 Notes 加一句「本项以 Notes 口径替代标准口径」，避免后续机械核对误报 |

**已核验为「非问题」的候选（如实登记，防止重复排查）**：

- ~~GET/HEAD + Stream 体在 300/301/302/303 被原样重放，偏离 5.5.0 one-shot 门而未登记~~ —— 撤回。实测 `src/core/request.mbt:119-124`（`build()` 对 `Get | Head` 带 body 一律 `raise MethodBodyMismatch`）⇒ 该组合在 M1 构造面不可达；在可达面上，四分支要么无体、要么降级为 GET（必无体），307/308 的 Stream 检查与 5.5.0 的 one-shot 检查**可达输入等价**，不构成未登记差异。（与 round1 U1 交叉印证，见 B 节）
- 静态测试计数基线：`grep -rnc "^\s*\(async \)\?\test\b"` 于 `src --include=*_test.mbt --include=*_wbtest.mbt` 实测 **240**，与 tasks.md:55「== 240」吻合（口径注：T001 写的是 PowerShell `Select-String` 口径，本人为 bash grep 等价式）。
- T003「P05 白盒直调 `exchange_once` 5 处」：实测 `src/client/call_wbtest.mbt:366,378,633` 三处直调 + `:350`（注释）`:353`（test 名）共 5 处引用，吻合。
- 其余锚点抽查全部命中：exchange.mbt `folded_headers` L60-72 / `exchange_once` L78-86 / Connection: close 块 L112-126（产物写 L112-124，微漂 ±2）；http_client.mbt 两件套 L11-26 / execute L126-187；core mbti `HttpUrl::resolve`:86、`HeadersVBuilder::remove`:64、`RequestBuilder` 五件套:138-145、`Response::from_http`(prior? 参):158、`Response::prior`:160、`HeadersV::builder`:44、`Request`(url/method/headers/tag/body 字段公开):110-116；上游 `.mooncakes/.../src/http/pkg.generated.mbti:80` `pub async fn Client::skip_response_body(Self) -> Unit`（宪法 I 公开面成立）；`Address derive(Eq, Hash)`（client mbti:22）；夹具 `mount`:84 / `mount_sequence`:86 / `mount_truncated`:87 / `conn_request_counts`:83 / `accepted_total`:81。
- 种子文件 `docs/roadmap/M1/P06-redirects.md` 与 D7/D9/D14 差异表：本轮未逐行核对（沿用 round1 声明，本人未独立复现该表行号，标记为「未复核」而非「已核实」）。

**Metrics（本人独立口径）**

- 总需求数：FR 12 ｜ SC 8 ｜ 验收场景 17（US-1:5、US-2:3、US-3:2、US-4:2、US-5:3、US-6:2）｜ Edge Cases 7
- 总任务数：18（T001–T018；红绿对行为任务 14）
- 覆盖：FR 12/12 有实现任务；测试级 10/12 全覆盖 + FR-002 半覆盖（Q-A1）+ FR-003 黑盒两场景落点缺失（Q-A3）；SC 8/8 有承载（SC-001 判据受 Q-A3 影响）
- 歧义计数：4（Q-A2/Q-A3/Q-B3/Q-B5）｜ 漂移计数：3（Q-B1/Q-B2/Q-B3）｜ 重复计数：0
- **CRITICAL：0 ｜ WARNING：3（Q-A1、Q-A2、Q-A3）｜ INFO：8**

**宪法对照（本人独立口径，MUST 项逐条）**

| 原则 | 结论 | 关键证据 |
|------|------|----------|
| I 非侵入底座 | ✅ | 仅公开 API：`skip_response_body` 上游 mbti:80 在场；js patch 方案显式否决（plan.md:66）；零 fork/vendor |
| II 性能优先 | ✅（记录性） | 防退化两项有验收断言；量化基准延后 P10，`docs/roadmap/M1/P10-benchmark-gate.md` 实测在场 |
| III OkHttp 语义对齐 | ✅（**本轮不可独立复核**） | 差异登记面自洽（spec.md:349-362 映射表 5 处「有意差异」标注 + C2/300 两处过时口径修正）；但 5.5.0 行号证据不可复核（见取证限制①），达成分支经实测闭合（上节撤回项） |
| IV 验收场景与测试先行 | ⚠️ 两处缺口 | Q-A1（FR-002 失败半边）、Q-A3（US-1-4/5 黑盒无落点）；红绿对编排口径本身合规（tasks.md:12-17） |
| V Target 策略 | ✅ | 矩阵显式（spec.md:364-370）；js 标「未验证」不入门禁、wasm-gc 排除说明在场 |
| VI 简洁与接口纪律 | ✅（1 条待钉） | 公开面增量=两件套（contracts §1 ↔ client mbti 现状吻合，除 Q-B1 关键字漂移）；`lease_addr` 冗余面见 Q-B2；C4 单槽 YAGNI 论证在场 |
| VII 中文表达 | ✅ | 八份产物全中文 |

---

## B. 对 round1 各条的核验意见

| round1 ID | 我的意见 | 理由与我的锚点 |
|---|---|---|
| **C1**（FR-002 排干失败毒化半边无测试承载，WARNING） | **认同**，定级认同 | 独立复现同一条（我方 Q-A1）。补充证据：R10 表实测仅六行（research.md:273-278），确无 FR-002 行；承载夹具 `mount_truncated` 实测在 fixtures mbti:87（round1 引「fixtures mbti:87、66」——`:87` 复核命中；`:66` 我未定位到对应条目，疑指 `RouteScript::Truncated` 结构面，未证实亦不否认）。**附加意见**：修复应连带处置归属歧义（我方 Q-A2），否则补的白盒用例断言面（毒化/关闭/回池三者之一）不确定 |
| **U1**（「HEAD/GET 带 body」构造面不可达，INFO） | **认同，且认为其价值高于 INFO** | 实测 `src/core/request.mbt:119-124` 拒体组 `Get | Head => if self.body is Some(_) raise MethodBodyMismatch`；`Request` 字段虽在 mbti:110-116 公开，但结构体未标 `pub(all)`，包外无法字面构造、唯一构造入口 `RequestBuilder::build`（mbti:139）⇒ 不可达论断成立。**该结论顺带闭合了我独立分析中的一个候选疑点**（one-shot 对齐是否漏登记，见 A 节「已核验为非问题」首条）：正因 GET/HEAD 不可能带体，决策表在可达输入上与 5.5.0 等价，无需新增差异登记。建议订正幅度亦大于 round1 所述「补一句」：spec.md:165-168 边界条「HEAD/GET 带 body 的异常形态 → 301/302/303/307/308 全部保持方法」与构造面冲突（该形态根本构造不出），宜标注为防御性/不可达而非行为条 |
| **I1**（plan 文件账目「新 call_test.mbt」失实，INFO） | **认同** | 实测 plan.md:105 标 `call_test.mbt # 新`；该文件已在场（src/client/call_test.mbt，P05 产物）；tasks.md:39 用「增补」口径，plan.md:56 写「增 1 文件 + 改 3 文件 + 测试 2 文件」。三处口径互斥，plan 侧失实。定级 INFO 认同（不改执行序） |
| **I2**（R10 FR-009 行记「P06-WB 黑盒」自相矛盾且与 T013 落位不符，INFO） | **认同** | 独立复现为我方候选清单第 6 项（research.md:277 实测记「P06-WB 黑盒」；FR-009 实际黑盒承载为 tasks.md:227-233 T013 的 P06-US6 补①；T012 的白盒 P06-WB⑤ 断言的是事件标记，非 FR-009 本体）。定级认同 |
| **D1**（宪法 II 量化延后 P10，非违宪 + 承接提醒，INFO） | **认同** | 实测 `docs/roadmap/M1/P10-benchmark-gate.md` 在场；spec.md:372-376 显式记录「量化归 P10 重定向场景基准」「本包测试不断言延迟数字」；宪法 II「性能相关改动必须附带基准数据」在此以延后 + 记录方式达成，MUST 面不成立冲突。提醒项（P10 须实际承接）合理 |
| **N1**（跨 host ∧ 超限双 release，幂等无风险，INFO） | **结论认同，分析不完整** | 双 release 在现状实现下确为 no-op，锚点核实一致（body_bridge.mbt:68-76 处置即置 `lease=None`；`Lease::poison` client.mbt:313-318 见 `released` 短路）。但 N1 只看了 `release_lease` 这一条边，**未识别轮级 `errdefer poison_release()` 也会在同一 raise 路径上二次触发**（data-model.md:16 与 :25 的作用域叠合）——该层歧义我列为 WARNING（Q-A2），见 D 节 D-2 |

**round1 锚点附录抽查（第 5 节）**：本人独立复核其中 14 项，全部命中（含 folded_headers L60-72、exchange_once L78-86、Call 两件套 L11-26、execute L126-187、core mbti 五处、Address Eq、夹具能力表、async@0.22.4 钉版、静态计数 240、白盒直调 5 处）。**两处不成立/过强**：①「contracts §1 与 client mbti 现状**逐项吻合**」——`Call::execute` 关键字不符（Q-B1）；②R3「Lease 无 addr 访问器」被 round1 附录照单接受，实测 `Lease` 持 `priv addr : Address`（client.mbt:141）且同包可读（Q-B2）。另 round1 引「spec.md:349-362 四处显式差异」——实测该区间内加粗标注「有意差异」**恰为 5 处**（:355 D7 行、:356 D7 行、:357 TooManyFollowUps、:358 Cookie、:362 js target 差异），plan.md:68 亦称「四处」；计数出入属记录性，不另立条目。

---

## C. round1 遗漏项（我方有、round1 无）

| 我的 ID | 级别 | 一句话 | round1 对应面 |
|---|---|---|---|
| **Q-A2** | WARNING | 轮级 `errdefer poison_release` 与 R6「drain 内显式毒化透传」两套处置归属并存；TooManyFollowUps 的「干净回池」仅靠 `release_lease` 先置 `lease=None` 的实现细节兜住，无白盒断言 | 部分被 N1 触及（只到双 release 幂等），未识别 errdefer 作用域层，未升为待钉歧义 |
| **Q-A3** | WARNING | US-1-4（PUT→302）/US-1-5（DELETE→300）黑盒场景在 tasks T005–T007 枚举中无落点，与 R10「P06-US1 黑盒」声明矛盾，影响 SC-001 判据 | 其覆盖矩阵 FR-003 行记「✅ 全覆盖（T005、T007、T016）」，未做场景级对账 |
| **Q-B1** | INFO | contracts §1 记 `pub fn Call::execute`，实况 `pub async fn`（mbti:36）——事前契约即对账面，关键字漂移 | 附录 :121 记「逐项吻合」，未捕获 |
| **Q-B2** | INFO | R3「Lease 无 addr 访问器」失实：`Lease.priv addr` 同包可读（client.mbt:141，先例 exchange.mbt:98 直读 `lease.conn`）；`Call.lease_addr` 非唯一解，冗余状态面涉宪法 VI | 附录照单接受该锚点 |
| **Q-B3** | INFO | `exchange_with_lease(request)`（R3/data-model:17）与实况/持租语义 `(self, lease)` 参数化互斥，签名口径未统一 | 未列 |
| **Q-B4** | INFO | 轮间取消的连接处置实由 `cancel()` 单点完成、guard 不写处置；「中间轮 `body_delivered=false` ⇒ 不误触发 Abandoned」为未成文前提 | 未列 |
| **Q-B5** | INFO | quickstart「六门」成员与 tasks T001「六门」成员不同（check --deny-warn×2 / test×2 / fmt --check / info vs info+fmt / test×2 / js check / coverage / 自查），T017 未声明以哪套为准 | 未列 |
| **Q-B6** | INFO | 「C1」在 spec 内双指（Clarifications 议题 C1 与裁决 C1/映射表 C1 混用体系），下游 converge/回引易张冠李戴 | 未列 |
| **Q-B7** | INFO | R7 21 跳链「+ 终态 mount」与夹具 `Sequence` 末位驻留（scripted_server.mbt:47-49/:314-315）合取后，终态项必不被消费；构造叙述易误导 | 其 C1 建议借用了 `mount_truncated`，但未复核 Sequence 驻留语义 |
| **Q-B8** | INFO | checklists 勾选项与 Notes 自述互斥（标准口径失效），记录性 | 未列 |

---

## D. 分歧清单（只列事实与双方证据，不代裁决）

### D-1：FR-003 决策表测试覆盖判定（round1「✅ 全覆盖」 vs 我方 Q-A3「WARNING 落点缺失」）

- **round1 证据**：analyze/round1-opencode.md:36（覆盖矩阵 FR-003 行「✅｜T002（WB①）、T005、T007、T008、T015、T016」）。
- **我方证据**：tasks.md:120-130（T005 只枚举「写 P06-US1①②」，①② 均 `POST /a` 起手）；tasks.md:131-137（T006 写 ③）；tasks.md:139-143（T007 写 ④，HEAD/GET 保持）；tasks.md 全文无「P06-US1⑤」；对照 spec.md:43-48（US-1-4 PUT→302、US-1-5 DELETE→300）与 research.md:267（R10 记 US-1-4/5 → 「P06-US1 黑盒」）。
- **焦点**：T016（tasks.md:265-270）白盒穷举含 PUT×302 / DELETE×300，故真值面可测；分歧在于 SC-001（spec.md:288-290）「每行至少一个用例」是否要求黑盒场景承载，以及 R10 与 tasks 的落点声明谁为准。round1 未在该行做场景级对账，故未判定。
- **是否定级分歧**：是（round1 无条 / 我方 WARNING）。

### D-2：排干/超限路径的处置归属（round1 N1「无实际风险，无需行动」 vs 我方 Q-A2「WARNING 需钉断言」）

- **round1 证据**：analyze/round1-opencode.md:22（N1：跨 host 分支与超限 guard 双 `release_lease`，「经核实既有处置单点已幂等，无实际风险」，建议「无需行动」）。
- **我方证据**：data-model.md:16（`errdefer poison_release()` 位于轮级）与 :20-25（advance 段内 `drain_intermediate` / `release_lease` / 超限 raise 均在 errdefer 作用域之后）；research.md:176-178（R6 把毒化写在 drain 内部「skip 失败 → `poison_release()` 后错误透传」）；幂等链本身双方认定一致（body_bridge.mbt:38-48/:68-76、client.mbt:313-318）。
- **焦点**：幂等 ⇒ 结果无风险（我方认同）；分歧在「两种机制并存是否构成需钉死的规格歧义」，以及 T014 是否应补「超限 raise 后连接干净回池（非关闭）」断言。round1 未覆盖 errdefer 这一条边，也未升为待钉项。
- **是否定级分歧**：是（round1 INFO/无需行动 / 我方 WARNING/建议补断言）。

### D-3：contracts §1 对账面的吻合度表述（round1 附录「逐项吻合」 vs 我方 Q-B1 关键字漂移）

- **round1 证据**：analyze/round1-opencode.md:121（「contracts §1『P05 冻结面零变化』基线：client pkg.generated.mbti 逐项吻合……execute:36 等」）。
- **我方证据**：contracts/follow-up-api.md:20 与 src/client/pkg.generated.mbti:36 的字面差为 `async` 关键字。
- **焦点**：该差异不影响 SC-008 语义对账（公开项集合一致），分歧仅在「逐项吻合」这一表述是否成立——contracts 自称 implement 后对账面，逐字对账会亮红灯。
- **是否定级分歧**：轻微（我方 INFO，round1 记为 ✅）。

### D-4：R3「Lease 无 addr 访问器」的可信度（round1 未质疑 vs 我方 Q-B2 判为失实）

- **我方证据**：src/client/client.mbt:141（`priv addr : Address` 为 Lease 字段）；同包私有可读先例 src/client/exchange.mbt:98（`lease.conn` 直读）。
- **round1 证据**：其锚点附录未把该条列入核实面（:117 仅核 `Address derive Eq`），故属「未复核」而非「复核后不同意」。
- **焦点**：由此派生 `Call.lease_addr` 是否为必要状态（宪法 VI 冗余面）。
- **是否定级分歧**：否（属遗漏差，列此供 host 参考）。

---

## E. Next Actions（本人不执行任何修复）

1. **待 host/opencode 处置的实质项**：Q-A1（=round1 C1，补 FR-002 失败半边红绿对 + R10 行）、Q-A2（钉死处置归属，建议 T014 加「干净回池」白盒断言）、Q-A3（US-1-4/5 黑盒落点：补 ⑤ 或改 R10/SC-001 口径）。
2. **文档级订正（低风险，可随修改轮一并）**：Q-B1（contracts 加 `async`）、Q-B2（R3 括注改写 + 定 `lease_addr` 去留）、Q-B3（签名口径统一）、Q-B4（FR-001 补租约处置归属一句）、Q-B5（六门成员表统一）、Q-B7（R7 末位驻留注记）。
3. **不可复核项须补一轮现场取证**：全部 5.5.0 行号断言（本会话外部仓被权限拦截）。若 host 认为宪法 III 达标必须独立取证，请在**允许访问 `E:\Project\moon-easyhttp-explore\okhttp` 的会话**中重跑该面，或由 owner 指定取证路径。
4. **未发现宪法 MUST 级违宪**；CRITICAL 计数 0，与 round1 一致。

---

## F. 与 round1 的计数对照

| 口径 | round1 | 本人（独立） |
|---|---|---|
| CRITICAL | 0 | 0 |
| WARNING | 1（C1） | 3（Q-A1 与 C1 同源、Q-A2、Q-A3） |
| INFO | 5（U1/I1/I2/D1/N1） | 8（Q-B1～Q-B8） |
| 双方共同实质项 | C1=Q-A1、U1（我方曾立候选后以构造面证据撤回并转认同）、I1、I2、D1、N1（部分=Q-A2 的子集） | |
| 我方独有 | Q-A2、Q-A3、Q-B1～Q-B8（共 10 条） | |
| round1 独有 | 无（六条均有对应或被我方独立复核确认） | |
| 分歧条数 | **2 条实质分歧**（D-1 覆盖判定、D-2 处置归属定级）+ 2 条表述分歧（D-3 吻合度、D-4 未复核锚点） | |

*报告结束。生成：qoder `speckit-analyze` 技能 @ 2026-10-27 ｜ 唯一写入：本文件。*
