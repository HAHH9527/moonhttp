# Round 7：P06 analyze 独立校验报告（双盲两段式）

- 校验者：OpenCode（GLM-5.3-Flash），全新上下文，与 round1–round6 无共享记忆
- 日期：2026-10-27；工单⑨（owner 已批准）
- 方法：**阶段A（双盲）**——未读 `analyze/` 下任何文件，仅对 spec.md / plan.md /
  tasks.md / research.md / data-model.md / contracts/follow-up-api.md /
  quickstart.md / checklists/requirements.md 做只读交叉一致性分析，并对盘面
  （`.mbti` 声明链、夹具能力、测试计数）做只读取证；**阶段B**——本报告 A 节
  写死后方读 round1–round6，逐条以磁盘现状核对历史发现，不采信报告间自述。
- 写入承诺：除本文件外零写入；零 git 写操作；src/、docs/、proj-init-docs/、
  `.specify/` 仅只读引用（宪法）。

---

## A 双盲发现总表

### A.0 判定概览

| 级别 | 数量 | 条目 |
| --- | --- | --- |
| CRITICAL | 0 | — |
| WARNING | 2 | W1、W2 |
| INFO | 6 | I1–I6 |

### A.1 五项专项核查结论（工单指定风险面）

1. **FR↔任务↔测试场景粒度对账**：✅ 对齐。US-1 五场景：①②④⑤→T005
   （tasks.md:124-133）、③→T007（tasks.md:151-155）；US-2 ①③→T008、
   ②→T009；US-3→T010；US-4→T011；US-5 ①→T014、②③→T015；US-6
   ①+补②→T012、②+补①→T013。research R10 映射表（research.md:268-286）
   与任务落点一致；US-1-4/5（PUT/DELETE 降级黑盒固化）落点 T005 与
   round3 D-1 注记自洽。FR-001～FR-012 每条均有任务/测试落点（FR-011 js
   仅编译检查，合宪法 V 未验证面定位）。
2. **处置归属口径五点互引**：✅ 一致。轮级 `errdefer poison_release()` 为
   唯一毒化归属 + `drain_intermediate` 纯透传不写 catch + 超限路径先干净
   `release_lease()` 再 raise（顺序承重、no-op 幂等为承重细节）——T004
   （tasks.md:104-107）、T012（tasks.md:241-243）、data-model 实体 1 注记
   （data-model.md:41-48）、R6（research.md:178-199）、T014 实现
   （tasks.md:272-274）五处口径完全一致。
3. **红绿对完整性**：✅（带缓冲注记，见 I2）。T002–T015 全部行为任务在
   任务内成对（先红后绿）；T001/T016–T018 为治理/收口任务无红绿对，与
   tasks.md:12-16 头部口径一致；T016 为纯测试收口任务由头部显式豁免。
4. **公开面声明链（contracts↔mbti）**：✅（带 1 条盘面事实，见 W2）。
   contracts §1 保留项与当前 `src/client/pkg.generated.mbti` 逐项一致
   （placeholder:10、CallCancelled 两件套:13-14、CallStateError:16-17、
   `HttpClient::new_call`:53、`Call::execute`:36、cancel/is_cancelled:35/37）；
   新增 `TooManyFollowUps` 尚未落盘——与任务全部未勾选（实现未开始）一致。
   core 面锚点全数在场：`HttpUrl::resolve`:86、`HeadersVBuilder::remove`:64、
   RequestBuilder 五件套:138-143、`Response::from_http(prior?)`:156、
   `Response::prior`:158；fixtures 面 `mount_truncated`:87（T012 引用精确
   命中）、`RouteScript::Truncated`:66、`PeerProgram::Capture`:45、
   `SlowReceive`:44、`accepted_total`:81、`conn_request_counts`:83、
   `CapturedRequest.raw` 字段:19（T008 引用成立）。
5. **宪法符合性**：✅（I/III/IV/V/VI/VII 通过；II 见 I4）。
   I：零 fork/零上游改动、全经公开 API（plan 宪法核查表显式否决①②，
   plan.md:67）；III：四处显式差异全部登记 spec 映射表（spec.md:353-366）；
   IV：红绿纪律 + 全本地夹具 + SC-007 断网可跑；V：target 矩阵显式标注、
   js/wasm-gc 不入门禁（spec.md:368-374）；VI：公开面增量=且仅=两件套 +
   Call 3 priv 字段全内部 + 「不设 lease_addr 镜像」订正一致
   （data-model.md:109-112）；VII：全文中文。

### A.2 发现明细

**W1（WARNING）SC-003 与 T013 对「跨 host 旧连接」的可观测断言相互矛盾**

- spec.md:297-299（SC-003）：「跨 host 跳新建连接计数 +1 且**旧连接不再被
  后续租借复用**（US-6-2，池/夹具计数双断言）」。
- tasks.md:246-249（T013）：「旧 host 连接干净回池（**后续同 Address 租借
  可复用**）」——按字面两者互斥：连接若干净回池，后续同址租借必然可复用；
  「不再被复用」只有关闭（poison）才成立，而设计面已显式否决跨 host poison
  （research.md:210-211 备选②、data-model.md:127-128 INV-6「干净回池」、
  三态图 data-model.md:151）。
- 连带：spec.md:155-156（US-6-2「归还/关闭」两可）与 FR-007
  （spec.md:254-257「归还或关闭」）均未收窄到唯一语义，SC-003 却写死了
  单向断言；T017（tasks.md:294-299）要求「SC-001～SC-007 逐条核对并记录
  证据测试名」——SC-003 后半句按现状无测试可取证（T013 断言的是其反面）。
- 影响：验收判据不可满足/不可取证；需回改 spec 收窄语义（如「旧租约不被
  **新 host** 的请求复用」或改为「干净回池、同址可复用」）后向下传导。
- 级别理由：不阻塞实现机制本身（设计与任务口径一致且合理），但 SC 是合入
  验收判据，字面矛盾会在 T017 收口对账时暴露，故定 WARNING。

**W2（WARNING）盘面存在未提交的跨包公开面类型漂移（Int→Int32），契约对账基线已被污染**

- 实测（2026-10-27 工作区）：`git status` 仅 3 份生成 `.mbti` 被修改
  （client/core/fixtures），**无任何 `.mbt` 源码改动**——漂移呈工具链再生成
  特征（`moon info` 以当前工具链重跑产出 `Int32` 签名），例：client
  `Address::hash/new(port~)/port`、core `HeadersV::hash`/`HttpUrl.port`/
  `Response.code`/`Response::from_http` 首参、fixtures
  `Drip/SlowReceive/ResponseScript.status/serve_n` 等全量 `Int→Int32`。
- 冲突：contracts/follow-up-api.md:15-17（§1 保留项零变化）、:47-53
  （§2 core 期望零 diff）、:55-58（§3 fixtures 期望零 diff）对照 git HEAD
  均已不成立；且该漂移非 P06 任务产物（tasks.md 全部任务未勾选）。
- 风险：若 T001（tasks.md:53-62）将脏盘面照抄为 baseline，该跨包公开面
  变化将随 P06 交付混入，绕过宪法 VI「对外接口的任何变化必须是有意识的
  决定，而非意外泄漏」（.specify/memory/constitution.md:82-83，另见
  :118-119「不保证兼容 ≠ 允许意外泄漏」）；T017 的 core/fixtures
  「零 diff」对账（tasks.md:295-297）也会因基线口径（git HEAD vs
  baseline.md）不同而结论相反。
- 级别理由：不属 spec 文本缺陷，属「当前磁盘状态 vs 声明链」的实质出入，
  须在动工前显式归因（工具链升级再生成 / 遗留未提交工作）并钉死基线口径，
  故定 WARNING。

**I1（INFO）plan 源码树与「改 4 文件」口径漏列 `call_wbtest.mbt`**

- plan.md:56-59（增 2 文件 + 改 4 文件）与 plan.md:102-107 文件树均未列
  `call_wbtest.mbt`；而 T003（tasks.md:87-89）需适配该文件 5 处
  `exchange_once` 直调。plan.md:114-116 有文字提及适配但文件清单缺失。
  零公开面影响，纯文档完备性。

**I2（INFO）T010/T015 的红测在实现已先行落地的情形下可能首跑即绿**

- T010（tasks.md:195-197）「T005 已落相对/绝对主路径……若发现实现缺口按
  先红后绿补」、T015（tasks.md:279-280）「预期 T002 Terminal 行直接命中」。
  宪法 IV（constitution.md:61）要求先写失败测试再实现；两任务自带缓冲注记
  属务实处理，但「红」对这部分用例无保证——建议 implement 时记录首跑实测
  （红/绿）以备纪律审计。

**I3（INFO）格式笔误（不影响语义；初稿锚点漂移指控已自行撤回）**

- 勘误：本报告初稿曾判 research.md:168-169 的 mbti 行号锚点
  （`from_http`=L158、`Response::prior`=L160）有 +2 漂移；经直接
  `Select-String` 实测当前盘面，`from_http` 恰在 :158、`Response::prior`
  恰在 :160——**锚点精确命中，初稿系本人对 git diff hunk 头算位错误，
  撤回该指控**。保留的发现仅为格式笔误：「剥两 头」多余空格
  （research.md:277、data-model.md:69、70、73）。
  其余抽核锚点（`remove` L64、`resolve` L86、fixtures mbti:87）同样精确命中。

**I4（INFO）宪法 II「性能改动必须附带基准数据」由 P06 显式推迟至 P10**

- spec.md:376-380 声明「量化归 P10 重定向场景基准」，并以 US-6 连接计数/
  干净流断言为防退化载体；constitution.md:130-132 合入门禁含「性能改动附
  基准数据」。属显式记录的推迟（非悄悄偏移），是否满足门禁由 owner 判断；
  P06 定位为行为特性、基准随 P10，口径自洽。

**I5（INFO）T005–T011 窗口 INV-2（排干前置）无测试保护**

- T005 明示「循环保留 T004 的 advance 最小路径（排干细则 US-6 深化，本任务
  单跳链可行即可）」（tasks.md:139-140），T012 才以 `drain_intermediate`
  替换（tasks.md:243-245）。该窗口内若中间响应携带非空体，INV-2
  （data-model.md:119-121）可能被违反而测试仍绿。分期排布已在任务中声明，
  属可接受 MVP 分期；提示 implement 勿在该窗口提前引入带体中间响应场景。

**I6（INFO）「六门」组成在 tasks 与 quickstart 两处不一致**

- T001（tasks.md:56-59）六门 = check native/wasm + test native/wasm +
  fmt --check + moon info；quickstart（quickstart.md:9-16）门1-6 = info+fmt /
  test native / test wasm / check js / coverage / 宪法自查。两组各自自洽但
  同名不同物；与宪法合入门禁（constitution.md:130-133）的映射各自成立，
  建议统一措辞以免 implement 误跑。

### A.3 双盲小结（阶段B 对账基准，写死于此）

文档体系整体高度自洽：工单指定五项风险面中，FR↔任务↔测试粒度对账、
处置归属五点互引、红绿对完整性三项直接闭环；公开面声明链在「事前契约 vs
当前 mbti」意义上闭环、但被盘面未提交漂移（W2）带保留；宪法符合性通过
（II 有显式推迟记录）。唯一实质性跨文档缺陷是 SC-003 与 T013 的断言矛盾
（W1）。

**双盲判定计数：CRITICAL 0 / WARNING 2 / INFO 6。**

---

## B 历史条目闭合核对表

> 工单指定清单：round1 C1/U1/I1/I2/D1/N1 + round2 Q-A1/Q-A2/Q-A3 +
> round4 C-1～C-5 + round6 N-1/N-2，共 16 项。以下判定全部为 round7
> 对**磁盘现状**的独立实测（2026-10-27），不采信报告间自述；历史自述仅作
> 对照。行号按 round5 §三登记的 tasks.md +2 漂移位对账。

| 来源 | ID | 历史摘要 | 磁盘实测（round7 锚点） | 闭合判定 |
|---|---|---|---|---|
| round1 | C1（WARNING） | FR-002 失败半边（skip 失败→毒化→不回池→透传）无红绿对；R10 无 FR-002 行 | tasks.md:230-245 T012 红侧含 P06-US6 补②（`mount_truncated`/`RouteScript::Truncated`→`skip_response_body` 失败→毒化→错误透传→连接不回池，fixtures mbti:87/:66 在场）；research.md:285 R10 新增 FR-002 行（T012 补②） | ✅ 已闭环 |
| round1 | U1（INFO） | 「HEAD/GET 带 body」未标注构造面不可达 | spec.md:167-172 注记在场（`MethodBodyMismatch`、core request.mbt:116-126、`Request` 非 `pub(all)`、不建夹具用例）；源码复核 request.mbt:116 拒体组注释在场 | ✅ 已闭环 |
| round1 | I1（INFO） | plan 文件账目「新 call_test.mbt」失实 | plan.md:56-59「增 2 文件 + 改 4 文件……call_test.mbt 增补——P05 已在场非新建」；plan.md:106「# 改（P05 已在场，增补）」 | ✅ 已闭环 |
| round1 | I2（INFO） | R10 FR-009 行「P06-WB 黑盒」自相矛盾 | research.md:284「P06-US6 黑盒（T013）」 | ✅ 已闭环 |
| round1 | D1（INFO） | 宪法 II 量化延后 P10（记录性 + P10 承接提醒） | spec.md:376-380 性能影响节在场（量化归 P10、测试不断言延迟数字）；`docs/roadmap/M1/P10-benchmark-gate.md` 实测在场（Test-Path=True） | ✅ 已闭环（记录性；P10 实际承接属下游动作） |
| round1 | N1（INFO） | 跨 host ∧ 超限双 release——幂等无风险、无需行动 | data-model.md:47-48 归属注记已把「`release_lease`/`poison_release` 的 no-op 幂等为承重细节，重构必须保留」显式钉住 | ✅ 已闭环（原「无需行动」项已被注记固化） |
| round2 | Q-A1（WARNING） | = C1 同源 | 同 C1 实测 | ✅ 已闭环 |
| round2 | Q-A2（WARNING） | 处置归属两套写法并存 + 缺「超限后干净回池」白盒断言 | data-model.md:41-48 归属注记四要件齐（轮级 errdefer 唯一毒化归属/drain 纯透传/guard else 先 release 后 raise/no-op 幂等承重）；research.md:181-184、:196-199 同口径；tasks.md:105-107（T004 括注）；tasks.md:264-274（T014 WB⑥ 干净回池断言 + Sequence 末位驻留/探针独立 plain-200 mount） | ✅ 已闭环 |
| round2 | Q-A3（WARNING） | US-1-4/5 黑盒场景无任务落点，与 R10 矛盾 | tasks.md:123-125（T005=「P06-US1①②④⑤」，编号=spec 场景号）+ :126-133（④ PUT→302、⑤ DELETE→300 红侧）+ :141-149（T006-prior 不占号）+ :150-155（T007③）+ research.md:274（R10「T005 落地」）；spec 零改与裁决方向一致 | ✅ 已闭环 |
| round4 | C-1（WARNING） | T012 实现条款残留「失败 poison_release 后透传」旧口径，与归属钉死互斥 | tasks.md:241-243 现文「失败纯透传——drain 内不写 catch/毒化，毒化由轮级 `errdefer poison_release()` 单点归属，data-model 实体 1 注记，round3 D-2；R6」 | ✅ 已闭环（round5 修复，实测确认） |
| round4 | C-2（INFO） | data-model:21 伪码注释「毒化透传」未随注记同步 | data-model.md:21 现文「// R6：conn 上 skip（失败纯透传，毒化由轮级 errdefer 归属——D-2 注记）」 | ✅ 已闭环 |
| round4 | C-3（INFO） | contracts mtime 12:33:39 落 round3 编辑窗 vs「零修改」申报（过程取证） | 内容面：contracts/follow-up-api.md:20 = `pub async fn Call::execute(Self) -> @core.Response`，与 src/client/pkg.generated.mbti:36 实测字面一致——现状无差异可查；过程归因（当次写入内容）磁盘不留痕、不可检验，round6 已降级为「不可判定的证据边界项」交 host | ✅ 现状层面已闭环（附注：过程归因项移交 owner，不改判内容结论） |
| round4 | C-4（INFO） | T005「对齐 1/2/4/5」与 T007「③=场景 3」表述互斥 | tasks.md:123-125「编号=spec US-1 验收场景号：①②③④⑤ 中 ①②④⑤ 落本任务，③ 见 T007」——单一口径 | ✅ 已闭环 |
| round4 | C-5（INFO） | round3 日志转引行号漂移（:288→:292 等） | round3 日志:50 现文含「spec.md:292」、:61 现文含「:41-48」，实测已刷新且 spec.md:292/data-model.md:41-48 现文吻合；出入③（「:279-282 非目标段」）经 round6 B-1③ 认负——系 round4 转述瑕疵（来源/段名双误标），round5 两项事实主张磁盘复核成立 | ✅ 已闭环 |
| round6 | N-1（INFO） | 「红侧/断言中 `poison_release` 字样=可观测结果」读法约定未成文（自判非必改、预防性） | data-model.md:41-48 注记尾**无**该补充半句；T012 红侧（tasks.md:235-240）措辞如旧 | ❌ 未闭环（open——round6 自判「非必改」，未落笔；留 owner/implement 期裁量） |
| round6 | N-2（INFO） | round4 两处转述/推断瑕疵的订正登记 | 订正载体即 round6 本体 B-1③/B-2 第 2 点（归档件按授权不回改，无可改对象） | ✅ 已闭环 |

**统计：16 项中 15 项闭环 / 1 项未闭环**（round6 N-1，自判非必改的预防性建议）。

**工单清单外的历史台账补充（如实登记）**：round2 Q-B1（=D-3）、Q-B2（=D-4）
已闭环——实测 contracts:20 `async` 在场；research.md:92-96 订正块 +
client.mbt:137 `priv addr : Address` + exchange.mbt:98 `lease.conn` 直读
先例 + 五文件「3 priv 字段/不设镜像」口径一致。round2 Q-B3～Q-B8 台账维持
open（round3 日志:91 明示未获授权未动），round7 实测：Q-B4（FR-001 租约
处置成文）未动（spec.md:222-224、contracts:44 均无该句）；Q-B5（六门双轨）
未动；Q-B6（「C1」双指）未动；Q-B7（research.md:224-227 R7 原句未改；
tasks.md:270-271 T014 末位驻留旁注部分缓解）；Q-B8（checklists Notes 未加
替代口径句）未动；Q-B3 见 C 节（与台账状态有出入）。

---

## C 与双盲结论的出入

> 只列事实与锚点，不自行裁决。

### C.1 判定分歧（2 条）

1. **W2（mbti 未提交漂移的定性）**：历史六轮一致视 3 个
   `pkg.generated.mbti` 未提交改动为「工作区噪音、与文档无耦合、不触碰」
   （round1:7/:126、round2:8、round3:7、round5:6、round6:6；round1 并判
   「行号与声明一致，噪音与文档无耦合」）。round7 实测漂移内容为跨包公开面
   类型改写（`Int→Int32`，client/core/fixtures 三包，无源码改动伴随），判
   WARNING——事实基底双方无分歧（行级锚点确未受影响），分歧在「零 diff
   契约（contracts §2/§3）对账基线取 git HEAD 还是 baseline.md、漂移归因
   是否须在 T001 前显式化」。
2. **Q-B3（exchange_with_lease 签名口径）**：历史台账记 open（round3 日志:91
   明示未动、round6:66 维持 open）；round7 实测产物内四处 notation 已统一为
   `exchange_with_lease(request)`（research.md:84-85、data-model.md:17 与
   :160-161、tasks.md:89-90），round2 所指「产物间互斥」在现盘不可复现，
   残余仅为与 P05 实况签名（exchange.mbt）的 implement 期适配细节。

### C.2 双盲新发现（历史六轮均未覆盖）

- **W1**（SC-003 ↔ T013 断言矛盾）：六轮均未做「SC ↔ 测试断言」方向的
  字面对账——round1 覆盖矩阵 SC-003 行记 ✅（T012/T013「连接计数双断言」），
  未检出 spec.md:298「不再被后续租借复用」与 tasks.md:248「干净回池可复用」
  的互斥。
- **I1**（plan 文件树/「改 4 文件」口径漏 `call_wbtest.mbt`）：round1 I1
  订正账目时未覆盖该文件；round2 复核 5 处直调锚点时未对 plan 树
  （plan.md:114-116 仅散文提及适配）。
- **I2**（T010/T015 红测可能首跑即绿）：历史红绿对审计止于「任务内成对
  编排」，未逐任务推演首跑颜色。
- **I3 格式笔误**（「剥两 头」空格，research.md:277、data-model.md:69/70/73）
  与 **I5**（T005–T011 窗口 INV-2 无测试保护）。
- 另：round4 C-3 过程项与 round6 的「不可判定」结论，round7 实测与其一致
  （contracts:20 现状字面相符），无新增疑点。

### C.3 与历史一致（无出入）

- round1/round2 的 WARNING 级三项（C1/Q-A1、Q-A2、Q-A3）与 round4 C-1 的
  闭环自述，经 round7 逐条磁盘复核**全部属实**。
- round7 I4 ≈ round1 D1、round7 I6 ≈ round2 Q-B5：独立重发现、判定一致
  （前者闭环、后者 open），不计分歧。
- round7 对自身一处初稿误判（I3 锚点漂移指控）已实测撤回并记于 A 节——
  历史锚点（from_http:158/prior:160）经直接行号实测确认精确。

---

## D 总结判

**不通过需修（小修）——两处 WARNING 修复后即可收口：**

1. **W1**：owner 澄清 SC-003 后半句意图并回改 spec（「旧连接不再被后续
   租借复用」与 T013/R6/INV-6 的「干净回池可复用」二选一对齐，同步传导），
   宪法「先审后跑」口径。
2. **W2**：T001 前钉死 3 个 `.mbti` 未提交漂移（Int→Int32）的归因与契约
   对账基线口径（git HEAD vs baseline.md），避免跨包公开面变化无意识地
   随 P06 交付（宪法 VI）。

其余面可收口：16 项历史条目实测 15/16 闭环（唯一未闭环 N-1 为历史自判
「非必改」的预防性登记）；双盲计数 CRITICAL 0 / WARNING 2 / INFO 6；无
宪法 MUST 级冲突、无 CRITICAL、无体系性缺陷。

---

*报告结束。生成：OpenCode（GLM-5.3-Flash）工单⑨ @ 2026-10-27 ｜ 阶段A
写死于读 round1–round6 之前（文件两次写入均为本文件：A 节先落盘、B/C/D
后补），除本文件外零写入、零 git 写操作。*
