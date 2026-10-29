# 修改日志（round3-opencode-fixes）— 006-m1-p06-redirects

- **特性**：自动重定向 follow-up 循环（M1-P06）
- **执行日期**：2026-10-27 ｜ **执行者**：OpenCode（工单④，owner 已批准 2026-10-27）
- **输入**：`analyze/round1-opencode.md`（主链自审）+ `analyze/round2-qoder-review.md`（qoder 交叉复核）；一切以磁盘产物为准
- **裁决来源**：D-1/D-2 实质分歧由 @oracle 独立复核裁决（只读复核 spec/tasks/research/data-model/contracts/两份报告/宪法原文/源码锚点后给出），本方未预置倾向，采纳其结论落笔
- **只写声明**：本轮写入 = 本文件 + 下表所列 specs/006-m1-p06-redirects/ 产物文件；零 git 写操作；未触碰 3 个 `pkg.generated.mbti` 噪音、`src/`、`docs/`、`proj-init-docs/`、`.opencode/`、`.specify/`；未改 speckit command/skill 定义；round1/round2 报告本体为归档记录不回改
- **owner 裁决项**：未遇到需 owner 裁决的宪法级冲突；全程零功能面新增、零公开面变化（`.mbti` 零影响）、零夹具扩展

---

## 一、逐条处置明细

### 1. C1（round1）= Q-A1（round2）——FR-002 失败半边补红绿对承载 【已改】

- **tasks.md T012**（:229-242）：任务名扩为「排干 + 同 host 租约保持 + 排干失败毒化」；红侧新增 **P06-US6 补②**——中间响应体截断（夹具 `mount_truncated`/`RouteScript::Truncated`，fixtures mbti:87 在场，零扩展）→ `skip_response_body` 失败 → `poison_release` → 错误透传（`err` 判别、非 panic/非静默）且连接不回池（后续同 Address 租借新建连接 +1）。改前：T012 仅断言成功排干（连接数=1、干净流、事件标记）。
- **research.md R10 表**（:285，新增行）：`| FR-002（排干+毒化） | P06-US6 黑盒（T012 补②） | 排干失败（夹具 mount_truncated）→ 毒化 → 连接不回池（后续同址租借新建 +1）→ 错误透传；成功排干半边由 US-6① 干净流断言承载（round3 补行） |`。改前：R10 表六行、无 FR-002 行。

### 2. U1（round1）——spec 边界用例标注构造面不可达 【已改】

- **spec.md**（:167-172）：「HEAD/GET 带 body」边界条追加注记——**M1 构造面不可达**：`RequestBuilder::build` 拒体组对 Get/Head 带 body 一律 raise `MethodBodyMismatch`（core request.mbt:116-126），`Request` 非 `pub(all)`、包外不可字面构造；本条为防御性描述，implement 不为其建夹具用例。改前：该条无不可达标注。spec 其余 FR/SC 语义零改动（注记为信息性，无需向下同步）。

### 3. I1（round1）——plan 文件账目订正（增2改4 口径）【已改】

- **plan.md Scale/Scope**（:56-59）：「增 1 文件 + 改 3 文件 + 测试 2 文件」→「**增 2 文件**（follow_up.mbt、follow_up_wbtest.mbt）**+ 改 4 文件**（http_client/exchange/body_bridge 小步重构、call_test.mbt 增补——P05 已在场非新建）」。
- **plan.md Project Structure**（:106）：`call_test.mbt # 新` → `# 改（P05 已在场，增补）`。改前与磁盘现状及 tasks「增补」口径互斥。

### 4. I2（round1）——R10 表 FR-009 行落位订正 【已改】

- **research.md R10 表**（:284）：FR-009 行元测试「P06-WB 黑盒」→「**P06-US6 黑盒（T013）**」。消除「WB=白盒 又标黑盒」的自相矛盾，对齐 tasks T013 实际落位（P06-US6 补①）。

### 5. D-3（round2，= Q-B1）——contracts/mbti async 关键字对齐 【反驳：磁盘已对齐，零修改】

- **核实结果**：`contracts/follow-up-api.md:20` 磁盘实况为 `pub async fn Call::execute(Self) -> @core.Response`，与 `src/client/pkg.generated.mbti:36`（`pub async fn Call::execute(Self) -> @core.Response`）**字面一致**。qoder Q-B1/D-3 的前提（contracts 记 `pub fn`）与磁盘现状不符——疑为 qoder 会话内误读或读到中间态，以磁盘为准（工单④第 1 条口径）。
- **处置**：不采纳修改建议（无需加 `async`、也无需在对账口径中声明豁免）；SC-008 逐字对账面本就无漂移。

### 6. D-4（round2，= Q-B2）——「Lease 无 addr 访问器」核实与 `Call.lease_addr` 冗余裁定 【核实属实→订正+删除】

- **源码核实（host 直读）**：属实——`Lease` 于 `src/client/client.mbt:134-141` 持 `priv addr : Address`（:137）；MoonBit priv 同包可读，先例 `src/client/exchange.mbt:98` 直读 `lease.conn`。qoder 锚点实质成立（其引 :141/:135-143 为结构体区间边界微漂，字段实位 :137）。R3 原括注「Lease 无 addr 访问器——client mbti 核证」**失实**（仅对包外成立）。
- **冗余裁定（宪法 VI）**：`Call.lease_addr : Address?` 及其同步不变量（INV-6 字段同步、INV-1「lease_addr 同步」）构成冗余状态面——同包直读 `lease.addr` 零成本等价，且免去对 P05 处置单点（`release_lease`/`poison_release`）的改写义务。**裁定：删除 `lease_addr`，Call 新增 priv 字段 4→3（`gen`/`folded_gen`/`conn_close_seen`）**。
- **同步落笔（5 文件）**：
  - research.md R3（:87-96）：3 priv 字段 + 「不设 lease_addr 镜像字段」订正块（含失实根因与锚点）；R6 keep 判定（:186）`lease_addr == addr` → `lease.addr == addr`；R6 rationale（:203）「以 lease_addr 判定」→「以 lease.addr 同包直读判定」。
  - data-model.md：实体 1 伪码 ensure_lease 注记（:15）、跨 host 判定行（:23）`self.lease_addr` → `lease.addr`；实体 6 表删 `lease_addr` 行并加订正注记（:100-111）；INV-1 删「lease_addr 同步」、改「租约地址仅经 lease.addr 同包直读，无镜像字段」（:115-118）。
  - tasks.md：T003「Call 增 4 priv 字段…初值 0/0/None/false」→「增 3 priv 字段 `gen`/`folded_gen`/`conn_close_seen`，初值 0/0/false；租约地址不设镜像字段」（:93-96）；T004 `ensure_lease` 括注「缺失 acquire + lease_addr 同步」→「缺失 acquire；同 host 复用经 lease.addr 直读判定」（:105-106）；T012 keep 分支「lease_addr 相同零往返」→「lease.addr 同包直读相同零往返」（:242）。
  - plan.md：宪法对照 VI 行「Call 新增 4 个 priv 字段全内部」→「3 个…不设镜像字段——round3 D-4 订正」（:72）；Project Structure `http_client.mbt` 注记「增 4 priv 字段」→「增 3 priv 字段」（:102）。
  - contracts/follow-up-api.md：「明确不进公开面」节「Call 新增 4 个 priv 字段」→「3 个…不设镜像——round3 D-4 订正」（:33-35）。

### 7. D-1（实质分歧）——FR-003 决策表测试覆盖判定 【@oracle 裁决：qoder 成立（WARNING 维持），采用方案一 tasks 补黑盒】

- **@oracle 结论**：round1 的「✅ 全覆盖」在决策表**行粒度**成立，但其覆盖矩阵未做**场景粒度**对账，而 SC-001 第一分句（spec.md:292「US-1–US-6 **全部验收场景**测试全绿」）与 DoD-1 恰为场景口径；tasks T005–T007 全链无 PUT/DELETE 起手黑盒，与 R10「US-1-4/5 → P06-US1 黑盒」直接矛盾，属真实缺口。**不能退到方案二**（R10 改记白盒 + SC-001 降口径）：宪法工作流条款「改需求必须回改 spec 再向下重新生成，不得手改 tasks 使其与 spec 脱节」——spec 是事实源，方向只能 tasks→spec 对齐；且 US-1-4/5 是 C2/300 两处用户可见行为修正的固化场景，T016 白盒只验纯函数真值不走 execute 全链，spec 测试方案节明文「决策表逐行基于 P03 夹具构造」（黑盒既定方针）；补 ⑤ 后 SC-001「300 有/无 Location 双形态」黑盒闭环。成本零功能面（两 mount 场景、夹具零扩展）。
- **落笔（spec 零改）**：
  - tasks.md T005（:123-133）：枚举「P06-US1①②」→「**P06-US1①②④⑤**（编号对齐 spec US-1 验收场景 1/2/4/5；④⑤为 C2/300 修正固化黑盒）」；红侧补 ④`PUT /a`→`302 Location: /b`（follow-up `GET /b`、body 丢弃、三头去除、prior 链长 1）与 ⑤`DELETE /a`→`300 Location: /b`（follow-up `GET /b`，300 有 Location 即跟随）。
  - tasks.md T006（:141-142）：「P06-US1③」→「**P06-US1-prior**（机制测试不占 spec 场景号）」——消除任务局部编号与 spec 场景号错位（round1 漏判诱因之一）。
  - tasks.md T007（:150-151）：「P06-US1④」→「**P06-US1③（spec 场景 3：HEAD→303 保持）**」，同上对齐。
  - research.md R10 表 US-1-4/5 行（:274）：行尾补「（T005 落地）」闭合映射→任务可追溯链。

### 8. D-2（实质分歧）——排干/超限路径处置归属与断言补强 【@oracle 裁决：qoder 定级与诉求成立（WARNING 维持），机制修正为第三方案】

- **@oracle 结论**：①round1 N1 事实结论（幂等、现状无害）正确但分析不完整——只查了 `release_lease` 双调用边，漏了轮级 `errdefer poison_release()` 在 TooManyFollowUps raise 路径上的作用域叠合（data-model:16 与 :25），「INFO/无需行动」定级不足；②INV-4「先排干后**干净释放**再 raise」的成立完全押在 guard else 内 release 先于 raise 的书写顺序 + 处置函数 no-op 幂等两个**未成文、未断言**的实现细节上，反序即静默毒化关闭已排干连接，宪法 III「差异不得悄悄偏移」（对齐点无钉）、宪法 IV（不变量后半无判据承载）、宪法 II（干净回池=连接复用性能面无门禁）三重涉险，WARNING 成立；③**不采纳 qoder 的具体修法**（errdefer 收窄到 exchange 段 + advance 段显式 catch）——会引入第二个毒化归属点、机制变多违宪法 VI，且仓内有同构先例（`dispose_skip` body_bridge.mbt:102-110 的 errdefer 房型、`exchange_once` 自带 errdefer）；改为**钉死轮级 errdefer 为唯一毒化归属点**：行为等价前提下机制最少。
- **落笔（spec/contracts 零改）**：
  - data-model.md 实体 1 伪码后新增「**处置归属（round3 D-2 裁决钉死）**」注记（:41-48）：轮级 errdefer 为轮内唯一毒化归属点（exchange 段 P05 既有 errdefer 幂等叠合无害）；`drain_intermediate` 不写 catch/毒化、纯透传（R6 按此口径读）；guard else 内 `release_lease()` 必须先于 `raise TooManyFollowUps`（INV-4 成立条件，反序即毒化关闭）；`release_lease`/`poison_release` 的 no-op 幂等为承重细节、重构必须保留。
  - research.md R6（:182-184）：「skip 失败 → `poison_release()` 后错误透传」→「skip 失败 → 错误透传（毒化由轮级 errdefer 统一实现、drain 内不另写 catch——处置归属单点）」；R6 末条（:197-199）句尾补「（先 release 后 raise，errdefer 随后 no-op——连接保持干净回池）」。
  - tasks.md T004（:105-107）：errdefer 括注补「轮内唯一毒化归属点；drain/超限路径不另写 catch，data-model 实体 1 注记」。
  - tasks.md T014（:264-268）：白盒 P06-WB⑥ 增补**「超限 raise 后连接干净回池（非关闭）」断言**——raise 后对同 host 的下一请求复用池内连接（`accepted_total` 不增 / `conn_request_counts` 同连接计数 +1；`Sequence` 末位驻留语义——探针请求走独立 plain-200 mount）。
- **落地顺序约束**：本组修改与第 1 条（C1/Q-A1）同批落笔——排干失败用例断言「毒化→不回池→透传」半边，T014 断言「干净回池」半边，互补且依赖同一句归属钉死。

---

## 二、处置结果一览

| 条目（来源） | 内容 | 处置 |
|---|---|---|
| C1（round1）= Q-A1（round2） | FR-002 失败半边无红绿对 + R10 无行 | **已改**（tasks T012 补② + R10 补行） |
| U1（round1） | HEAD/GET 带 body 不可达未标注 | **已改**（spec.md:167-172 注记） |
| I1（round1） | plan 文件账目「增1改3测试2」失实 | **已改**（plan.md:56-59/:106，增2改4） |
| I2（round1） | R10 FR-009 行「P06-WB 黑盒」矛盾 | **已改**（research.md:284 → T013 黑盒） |
| D-3（round2）= Q-B1 | contracts 漏 `async` 关键字 | **反驳**（磁盘已对齐：contracts:20 与 mbti:36 均 `pub async fn`，零修改） |
| D-4（round2）= Q-B2 | R3「Lease 无 addr 访问器」失实 + lease_addr 冗余 | **核实属实→已改**（订正 R3；`Call.lease_addr` 按宪法 VI 删除，5 文件同步 3 priv 字段口径） |
| D-1（实质分歧）= Q-A3 vs round1 覆盖矩阵 | FR-003 场景级黑盒落点缺失 | **@oracle 裁决采纳**（qoder 成立/WARNING；tasks 补 ④⑤ 黑盒，spec 零改） |
| D-2（实质分歧）= Q-A2 vs round1 N1 | 处置归属歧义 + 缺「干净回池」断言 | **@oracle 裁决采纳**（qoder 定级成立/WARNING；机制用第三方案：轮级 errdefer 单点归属；data-model/R6/T004/T014 落笔） |

**@oracle 对 D-1/D-2 的一句话结论**：D-1——qoder 成立，round1 的 ✅ 在行粒度成立、在 SC-001 场景粒度漏判，修复方向是 tasks 向 spec 对齐（补 US-1-4/5 黑盒），不得阉割 SC-001 判据；D-2——qoder 的 WARNING 定级与「钉归属+补断言」诉求成立，但机制不采纳其「收窄 errdefer + 显式 catch」方案，改为钉死轮级 errdefer 为唯一毒化归属点并在 T014 补「超限 raise 后干净回池」断言。

---

## 三、未采纳项及理由

1. **D-3 修复建议（contracts 加 `async` / 对账口径豁免声明）**：不采纳——磁盘核实两处早已字面一致（见上表 D-3 行），前提不成立则修改无对象。
2. **D-1 方案二（R10 改记白盒 T016 + SC-001 判据降口径）**：@oracle 否决——宪法 IV 验收场景先行 + 「不得手改 tasks 使其与 spec 脱节」；spec 是事实源，方向只能 tasks→spec。
3. **D-2 中 qoder 的具体机制（errdefer 收窄到 exchange 段 + advance 段显式 catch）**：@oracle 否决——引入第二个毒化归属点、机制变多违宪法 VI；行为等价前提下采用机制最少的「轮级 errdefer 单点」钉法（其 WARNING 定级与补断言诉求仍全部采纳）。
4. **round2 Q-B3～Q-B8（exchange_with_lease 签名口径、FR-001 租约处置成文、六门成员表统一、「C1」编号双指、R7 末位驻留注记、checklists 勾选矛盾）**：工单④第 2 条明确列出的履行范围不含此六项（均 INFO 级），未获授权本轮不动；留待 owner 指定后续轮或 implement 期处置。
5. **round1/round2 报告本体回改**：不做——归档记录保持原样，供后续轮对账（@oracle 建议口径）。

## 四、交叉一致性自查

- 删除 `lease_addr` 后全仓 `specs/006-m1-p06-redirects/` 内（除 analyze/ 冻结报告与本日志）仅存「不设 lease_addr 镜像字段」订正注记，无残留活引用；4→3 priv 字段口径在 research R3 / data-model 实体 6 / tasks T003 / plan（两处）/ contracts 五处一致。
- T012 补② 命名与 R10 FR-002 行（T012 补②）一致；T005 ①②④⑤ 与 R10 US-1-4/5 行（T005 落地）一致；T007③/T006-prior 与 spec US-1 场景号对齐。
- D-2 归属注记（data-model 实体 1）为 R6 两处措辞与 T004 括注的唯一上游口径源，三处互引一致；spec/contracts 按 @oracle 裁决零改动（归属为实现级口径，不涉 FR/SC/公开面）。
- U1 为信息性注记，FR/SC 语义零变化，无需向下同步。
- 全程零 git 写操作、零 `pkg.generated.mbti` 触碰、零功能面新增、零公开面变化、零夹具扩展。

*日志结束。生成：OpenCode 工单④ @ 2026-10-27 ｜ 供 qoder 下一轮逐项复核。*

*round5 订正登记（工单⑥ @ 2026-10-27）：仅按 round4 C-5 刷新本日志两处转引行号——:50「spec.md:288」→「spec.md:292」（U1 插行后 SC-001 实位）、:61「:41-50」→「:41-48」（data-model 归属注记实测区间）；其余原文一字未动。C-5 所述「:279-282（非目标段）」在本日志全文不存在，无从刷新（核详见 round5-opencode-fixes2.md）。*
