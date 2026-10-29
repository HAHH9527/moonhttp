# Round 8：P06 analyze 小修批次（履行 round7 判定）

- 执行者：Orchestrator（GLM-5.3-Flash），全新上下文，一切以磁盘产物
  为准；工单⑩（owner 已批准 2026-10-27）
- 依据：round7-opencode-verify.md 判「不通过需修（小修）」——W1/W2 +
  I1~I5 + C.1 出入项（Q-B3、round6 N-1）；**W1 owner 已亲自裁决取
  方案 B**（SC-003 跨 host 旧连接语义 =「干净回池、同址可复用」，
  与 INV-6/T013/data-model 现有口径对齐，只改 spec 离群断言并向下
  传导）。
- 方法：逐条先在盘面核实 round7 锚点属实、再落改；每条记录改前/
  改后原文与精确行号。
- 写入承诺：本批次共改 5 份产物（spec.md / plan.md / tasks.md /
  data-model.md / research.md）+ 本日志；零 git 写操作；未触碰
  src/、docs/、proj-init-docs/、.opencode/、.specify/、3 份
  `pkg.generated.mbti`、analyze/ 下历史报告（历史档案不回改）。

---

## 一、逐条处置

### W1（WARNING）SC-003 ↔ T013 跨 host 旧连接断言矛盾 —— ✅ 已修（owner 方案 B）

**核实结论**：属实。spec.md 改前 :298「旧连接不再被后续租借复用」与
tasks.md T013（改前 :246-249）「旧 host 连接干净回池（后续同 Address
租借可复用）」字面互斥；设计面（research R6 跨 host 换租「干净连接
回池」、data-model INV-6「排干 → release_lease」与租约三态图
「跨 host ──▶ release(干净回池)」）全数支持方案 B，离群断言确为
唯一离群点。

**改 1 —— spec.md US-6-2（改前 :155-156 → 改后 :155-157）**

- 改前：
  > 2. **Given** 跨 host 跳，**Then** 旧租约正确归还/关闭、新 host 新建
  >    连接（新建连接计数 +1）。
- 改后：
  > 2. **Given** 跨 host 跳，**Then** 旧租约干净归还回池（同址后续租借
  >    可复用）、新 host 新建连接（新建连接计数 +1；`Connection: close`
  >    中间响应的关闭分支归 FR-009/Edge Cases，不在本场景）。

**改 2 —— spec.md FR-007（改前 :256-257 → 改后 :257-259）**

- 改前：
  > 跨 host 跳 MUST 处置旧租约（归还或关闭，按 P04/P05 契约）并在新
  > host 建新连接。
- 改后：
  > 跨 host 跳 MUST 干净归还旧租约（回池、同址后续租借可复用）并在
  > 新 host 建新连接；`Connection: close` 中间响应的关闭处置是另一
  > 分支，见 FR-009。

**改 3 —— spec.md SC-003（改前 :297-299 → 改后 :299-302）**

- 改前：
  > - **SC-003**: 租约语义可证——3 跳同 host 链夹具侧新建连接数恰为 1
  >   （US-6-1）；跨 host 跳新建连接计数 +1 且旧连接不再被后续租借
  >   复用（US-6-2，池/夹具计数双断言）。
- 改后：
  > - **SC-003**: 租约语义可证——3 跳同 host 链夹具侧新建连接数恰为 1
  >   （US-6-1）；跨 host 跳新建连接计数 +1 且旧连接干净回池、同址
  >   后续租借可复用（US-6-2，池/夹具计数双断言；语义收窄见
  >   Assumptions W1 裁决）。

**改 4 —— spec.md Assumptions 新增裁决记录（改后 :342-345，插于
C4 裁决之后）**

- 新增：
  > - **W1 裁决（2026-10-27，工单⑩ owner 批准，方案 B）**：跨 host 旧
  >   连接语义 =「干净回池、同址可复用」——与 INV-6/T013/data-model
  >   租约三态图既有口径对齐，不采用跨 host poison；SC-003/US-6-2/
  >   FR-007 已按此收窄为唯一语义并向下传导。

**一致性检查（应零改动项——实测确实零改动）**：

- data-model INV-6（改后 :129-130）与租约三态图（改后 :153）：
  「干净回池」口径——一致，未动。
- research R6 跨 host 换租（改后 :193-195）：「干净连接回池，P04
  契约」——一致，未动（该文件行号因 Q-B3 插注整体 +5，见下）。
- tasks T013（改后 :249-256，断言句 :251）：「干净回池（后续同
  Address 租借可复用）」——与 SC-003 新文完全对齐，未动。
- tasks T017（改后 :305）：SC-001～007 逐条取证要求——SC-003 收窄
  后由 T013（P06-US6② + 补①）直接取证，无新缺口，未动。
- spec US-6 导语「跨 host 跳时旧连接被正确处置」（改后 :143）与
  Independent Test「跨 host 跳 + 新建连接计数」：伞形措辞、两种读法
  均兼容，语义由 US-6-2/FR-007/FR-009 定义，未动。
- FR-009/Edge Cases（Connection: close 关闭分支）：本就是独立分支，
  收窄后由新文显式互指，未动。

### W2（WARNING）.mbti 未提交漂移污染契约对账基线 —— ✅ 已钉口径

**核实结论**：属实。实测 `git status --porcelain` 仅 3 份
`pkg.generated.mbti`（client/core/fixtures）被修改、无任何 `.mbt`
源码伴随；`git diff` 抽样确认漂移为 `Int→Int32` 签名改写
（client `Address::hash/new(port~)/port`、core `HeadersV::hash`/
`HttpUrl.port` 等），与 round7 W2 归因（工具链再生成显示差异）一致。

**改 —— plan.md 新增小节「`.mbti` 对账基线口径（round8 W2 登记）」
（改后 :120-132，插于 Structure Decision 之后）**，要点：

1. contracts §2/§3「零 diff」对账基线 = **git HEAD 提交态**，不取
   工作区现状（§1 client 增量对账同理以 HEAD 为底）。
2. 工作区 3 份 `.mbti` 的 `Int→Int32` 改写 = 本地工具链 `moon info`
   再生成显示差异：未提交、无 `.mbt` 伴随、非 P06 任务产物。
3. 该漂移**不随 P06 交付、T001 不入账**：T001 建基线以 git HEAD
   版本为准记录（快照若含漂移须在 baseline.md 标注为工具链差异）；
   T017 收口六门以**提交时门复验**为准。
4. 仅登记口径，不改动任何 `.mbti` 文件（宪法 VI）。

**未采纳项**：无——本条就是「只登记口径、不碰文件」的执行。

### I1（INFO）plan 文件树/账目漏列 call_wbtest.mbt —— ✅ 已补

**核实结论**：属实。`src/client/call_wbtest.mbt` 在场（glob 实测），
内含 `exchange_once` 直调点；plan.md 改前 Scale/Scope（:56-59「改
4 文件」）与文件树（:102-107）均未列该文件，仅 :114-116 散文提及
适配。

**改 1 —— plan.md Scale/Scope（改后 :56-60）**：「改 4 文件」→
「改 5 文件」，括注补「call_wbtest.mbt 适配 exchange_once 直调点
——后三者 P05 已在场非新建，round8 I1 补账」。

**改 2 —— plan.md 文件树（改后 :107 新增行）**：
`│   ├── call_wbtest.mbt              # 改（P05 已在场，增补）：T003 适配 exchange_once 直调点（补 request 实参）`

**改 3（连带最小同步）—— tasks.md Path Conventions（改后
:39-40）**：门面包清单补「`call_wbtest.mbt` 适配（T003，P05 已在
场）」。理由：plan 账目补齐后，tasks 概览若仍缺该文件会成为新的
plan↔tasks 表面出入；此为同口径一行补列，非语义变更。

**核实补充观察（不改，登记备查）**：tasks.md T003（改后 :88）称
「5 处 `exchange_once` 补 request 实参」——实测 call_wbtest.mbt 内
`exchange_once` 字样共 5 处，其中**实际调用点 3 处**
（:366/:378/:633），另 2 处为注释与测试名。「5 处」系按字样计数。
不改动理由：属 INFO 级计数口径差、非本工单条目；适配发生在
implement 期、以实况调用点为准即可（Q-B3 口径同理）。

### I2（INFO）T010/T015 红测可能首跑即绿 —— ✅ 核实属实后已加注

**核实结论**：属实，两处前提均成立：

- T010：T005（改后 :139-140）明示「排干细则 US-6 深化，本任务单跳
  链可行即可」且 T005 已实现 resolve 门相对/绝对主路径（改后
  :136-138「resolve 门」+ catch 分支）——T010 的三形态/非法回退
  用例对已落实现，首跑即绿可能成立。
- T015：T002（改后 :77-87）已先行落地 Terminal 骨架，覆盖
  304/305/306/无 Location 3xx——T015 黑盒「预期 T002 Terminal 行
  直接命中」（其原文自述），首跑即绿可能成立。

**改 1 —— tasks.md T010 尾注（改后 :198-200）**：
> （round8 I2 纪律注记：本任务红侧存在首跑即绿可能——T005 已先行
> 落地 resolve 主路径；首跑颜色须实测记录，首跑即绿时在任务产出登记
> 「实现先行」归因备宪法 IV 审计，不得事后补造红灯）

**改 2 —— tasks.md T015 尾注（改后 :284-286）**：
> （round8 I2 纪律注记：本任务红侧存在首跑即绿可能——T002 Terminal
> 行已先行落地；首跑颜色须实测记录，首跑即绿时在任务产出登记
> 「实现先行」归因备宪法 IV 审计，不得事后补造红灯）

### I3（INFO）「剥两 头」空格笔误 —— ✅ 已修（含 round7 锚点订正）

**核实结论**：笔误属实，但 round7 所列锚点有一处漂移：

- data-model.md：实测笔误在 **:69/:70**（「剥两 头」×2）；
  **:73 现文为「（跨 host 剥）」，无笔误**——round7 所列
  data-model.md:73 系锚点误记，如实订正。
- research.md:277：「跨 host 字节不含两 头」——属实。

**改 1 —— data-model.md:71（改前 :69）**：「跨 host 剥两 头」→
「跨 host 剥两头」。
**改 2 —— data-model.md:72（改前 :70）**：「跨 host 剥两 头」→
「跨 host 剥两头」。
**改 3 —— research.md:282（改前 :277；因 Q-B3 插注整体 +5）**：
「跨 host 字节不含两 头」→「跨 host 字节不含两头」。

三处均为纯空格删除，零语义变化（语义 = FR-004 剥
`Authorization`/`Cookie` 两头）。

### I5（INFO）T005–T011 窗口 INV-2 无测试保护 —— ✅ 已登记（不新开任务）

**核实结论**：属实。T005（改后 :139-140）明示循环保留 T004 最小
advance，T012（改后 :249 附近）才以 `drain_intermediate` 替换；
INV-2（data-model 改后 :121-123）在该窗口仅由实现形态隐式满足、
无测试断言。属已声明的可接受 MVP 分期，登记即可。

**改 —— tasks.md Phase 9 Purpose 下新增分期注记（改后 :294-297）**：
> （round8 I5 分期注记）：T005–T011 窗口循环沿用 T004 最小 advance，
> INV-2（排干前置）在该窗口无测试保护、自 T012 `drain_intermediate`
> 起全量承载——implement 在该窗口不引入带体中间响应场景，带体排干
> 场景一律 T012 后落。

**落点选择说明**：工单给出「T014 或 polish 注记」二选一——取
polish 注记。理由：该风险窗口在 T005–T011（早于 T014），注记钉在
收口阶段作为分期事实与纪律提醒，比挂在语义无关的 T014（上限计数）
更不误导；tasks.md 全文先读后做，可见性足够。未新开任务（工单允许
前提「除非必要」不成立）。

### Q-B3（C.1 出入项）exchange_with_lease 记号 vs P05 实况签名 —— ✅ 已钉口径

**核实结论**：与 round7 C.1 判定一致。产物内四处记号已统一为
`exchange_*(request)`（research R3、data-model :17/:160-162、tasks
T003）；P05 实况为无 request 参的 `exchange_once(self)`
（exchange.mbt:78，读 `self.request`）与
`exchange_with_lease(self, lease : Lease)`（exchange.mbt:91-94）。
「产物间互斥」不可复现，残余仅为 implement 期适配口径。

**改 —— research.md R3 首条 Decision 追加记号口径（改后 :87-91）**：
> （round8 Q-B3 记号口径：产物内 `exchange_*(request)` 写法是参数化
> 后的目标形态记号；P05 实况为无 request 参的
> `exchange_once(self)`/`exchange_with_lease(self, lease)`、读
> `self.request`（exchange.mbt:78/:91）——实现以 exchange.mbt
> 实况签名为准做适配，本记号不回改。）

**落点选择说明**：工单给出「T004 或 research 适当处」——取
research R3。理由：R3 是参数化决策的记录地，T003（参数化实施）与
T004（循环消费）都会读它，单点覆盖两条任务；T004 单点钉注会漏掉
T003 的执行者。

### round6 N-1（INFO，历史唯一未闭环项）poison_release 字样读法约定 —— ✅ 采纳落笔（我的裁量）

**核实结论**：属实。data-model 归属注记尾原无该读法半句；
T012 红侧（改后 :238-243）「`skip_response_body` 失败 →
`poison_release` → 错误透传」等措辞按「可观测结果」读方能与
「drain 内不写毒化」相容。

**裁量：采纳（加半句注记），不保持 open。理由**：
1. 零语义变更、成本一行；
2. round7 阶段 B 恰好演示了独立校验方按字面机制读的复核路径——
   成文可阻断同类疑点重复登记；
3. 落笔后 16 项历史台账全部闭环，收口面干净。

**改 —— data-model.md 归属注记尾（改后 :48-50）**：
> ……重构必须保留。红侧/断言文本中的 `poison_release` 字样均
> 指**可观测结果**（连接被毒化关闭、不回池），不指调用位点——读法
> 约定成文（round6 N-1，round8 落笔）。

---

## 二、未采纳项与理由（汇总）

| 条目 | 未采纳内容 | 理由 |
| --- | --- | --- |
| W1 | 方案 A（「旧租约不被新 host 请求复用」改写） | owner 已裁决方案 B，与设计面一致 |
| I1 | 顺手订正 T003「5 处」→「3 处调用点」 | 非本工单条目；implement 期以实况为准即可，已登记观察 |
| I5 | 新开排干保护任务 | 分期已在任务中声明，注记足够（工单「除非必要」不成立） |
| N-1 | 保持 open | 见上裁量理由（选择采纳） |
| 全部 | 改动 analyze/ 历史报告、3 份 `.mbti`、src/ 等禁写面 | 工单硬约束 + 历史档案不回改惯例 |

## 三、交叉自查（改后）

- **spec ↔ tasks**：SC-003 新文「干净回池、同址可复用」↔ T013 :251
  断言句逐字同向；US-6-2/FR-007 收窄后与 T013 实现条款（advance
  `release_lease()`，INV-6/INV-7）一致；T017 对 SC-003 的取证路径
  成立（P06-US6② 双实例计数 + 同址租借复用断言）。
- **spec ↔ data-model**：INV-6/三态图/实体 1 伪码（:23 干净回池注释）
  与 SC-003/FR-007 新文同向；INV-2 窗口注记与 T005/T012 分期描述
  一致；真值表笔误修复后与 FR-004 剥头语义无歧义。
- **spec ↔ research**：R6 跨 host 换租「干净回池」、R6 备选②（跨
  host poison 否决）与方案 B 一致；R3 记号口径与 data-model/tasks
  的 `exchange_*(request)` 记号不再有未声明的签名差。
- **plan ↔ tasks**：改 5 文件账目（plan :56-60 + 文件树 :107）与
  tasks Path Conventions（:39-40）及 T003 适配条款一致。
- **SC 可取证性**：SC-001/002/004～008 取证路径不受本轮影响；
  SC-003 由 T013（+T012 毒化半边）直接取证——全部 SC 均有证据测试
  落点。
- **残留扫描**：旧措辞（「不再被后续租借复用」「归还或关闭」「归还/
  关闭」「剥两 头」「不含两 头」「改 4 文件」）在五份产物中零残留，
  仅存于 analyze/ 历史报告（按例不回改）。
- **行号漂移登记**：本轮落笔后 spec.md :155 后 +1、:299 后 +1、
  :342 前 +1；plan.md :56 后 +1、:107 后 +14；tasks.md T010 后 +4、
  T015 后 +4、Phase 9 注记 +6；data-model.md :48 后 +2（全文其后
  +2）；research.md :87 后 +5（全文其后 +5）。后续轮次引用行号须
  按此对账。

## 四、处置一览

| 条目 | 级别 | 处置 | 落点 |
| --- | --- | --- | --- |
| W1 | WARNING | ✅ 按 owner 方案 B 修（4 处） | spec.md :155-157 / :257-259 / :299-302 / :342-345 |
| W2 | WARNING | ✅ 钉口径登记（零文件改动） | plan.md :120-132 |
| I1 | INFO | ✅ 补账（plan 2 处 + tasks 1 处） | plan.md :56-60 / :107；tasks.md :39-40 |
| I2 | INFO | ✅ 核实属实后加注 ×2 | tasks.md :198-200 / :284-286 |
| I3 | INFO | ✅ 修笔误 ×3（含 round7 锚点订正：data-model :73 无笔误） | data-model.md :71/:72；research.md :282 |
| I5 | INFO | ✅ polish 注记登记（不新开任务） | tasks.md :294-297 |
| Q-B3 | C.1 | ✅ research R3 钉「以实况签名为准」 | research.md :87-91 |
| N-1 | round6 open | ✅ 裁量采纳，读法约定成文 | data-model.md :48-50 |

## 五、外溢申报

- 写入面：specs/006-m1-p06-redirects/ 下 5 份产物 + 本日志，共
  6 文件——均在工单授权范围内。
- 零 git 写操作；零 src/、docs/、proj-init-docs/、.opencode/、
  `.specify/`、`.mbti` 触碰。
- 无 owner 级冲突需回报；无超范围改动。
- 移交 implement 期的两个以实况为准口径：Q-B3 签名适配（research
  R3）、T003 直调点计数（本日志 §一 I1 观察）。

---

*日志结束。生成：Orchestrator（GLM-5.3-Flash）工单⑩ @ 2026-10-27。*
