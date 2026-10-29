# 复核对账（round4-qoder-verify-fixes）— 006-m1-p06-redirects

- **特性**：自动重定向 follow-up 循环（M1-P06）
- **执行日期**：2026-10-27 ｜ **执行者**：qoder（独立交叉复核方，工单⑤）
- **任务**：按 `analyze/round3-opencode-fixes.md` 逐条编号到磁盘对账（落盘真实性、与日志一致性、交叉矛盾）；对我方 Q-A1/Q-A2/Q-A3 与 D-3/D-4 给三态结论；对 @oracle 两条裁决只核「如实落笔」与「锚点成立」
- **只读声明**：除本文件外零写入、零 git 写操作；未触碰 3 个 `pkg.generated.mbti`（仅只读 grep）；未运行任何 `moon` 命令（避免生成物写入）
- **取证方法**：逐条 `awk/sed` 按行号读盘 + 全目录 grep 残留扫描 + `ls --full-time` 时间戳取证（时间戳仅作观察记录，不作改动归因）
- **沿用的取证限制**：外部 OkHttp 取证仓本会话仍不可达（工单②口径），5.5.0 行号断言仍属「产物内部自洽」面——本轮 round3 改动未新增任何依赖 5.5.0 源码的断言（data-model:34-39 对应段为 round2 前既有文本），故不扩大该限制

---

## A. 逐条对账表（round3 日志条目 → 实测 → 结论）

| # | round3 条目（日志行号） | 实测磁盘锚点（文件:行号，命令原文摘录级） | 落盘？ | 与日志一致？ | 交叉矛盾？ |
|---|---|---|---|---|---|
| 1a | C1/Q-A1：tasks T012 扩名 + 补②（日志:16） | tasks.md:229 任务名「排干 + 同 host 租约保持 + 排干失败毒化」；:234-239 红侧「另写 P06-US6 补②……`mount_truncated`/`RouteScript::Truncated`，fixtures mbti:87 在场……`skip_response_body` 失败 → `poison_release` → 错误透传……连接不回池（后续同 Address 租借新建连接 +1）」；夹具锚点复现：fixtures mbti:87 `mount_truncated`、:66 `Truncated(ResponseScript)` | ✅ | ✅（日志所称 :229-242 区间吻合；「零扩展」复核成立——两夹具面均已在场） | ⚠️ 有：T012 实现条款 tasks.md:240-241「失败 `poison_release` 后透传」与同批落笔的 D-2 归属钉死冲突（见 C-1） |
| 1b | C1/Q-A1：R10 补 FR-002 行（日志:17） | research.md:285 新行「FR-002（排干+毒化）｜P06-US6 黑盒（T012 补②）｜排干失败（`mount_truncated`）→ 毒化 → 不回池 → 透传；成功半边由 US-6① 承载」 | ✅ | ✅（行号 :285 精确；日志所引行文本与磁盘一致） | 无（断言口径与 C-1 连带：「毒化」触发点未点名 errdefer，措辞兼容第三方案） |
| 2 | U1：spec 边界条补不可达注记（日志:21） | spec.md:167-172：「**注**：该形态在 M1 构造面不可达——`RequestBuilder::build` 拒体组对 Get/Head 带 body 一律 raise `MethodBodyMismatch`（core request.mbt:116-126）……implement 不为其建夹具用例」；源码锚点复核：src/core/request.mbt:119-124 确为 `Get | Head => if self.body is Some(_) raise …MethodBodyMismatch` | ✅ | ✅（:167-172 精确；注记口径与我 round2 B 节「认同且价值高于 INFO」的建议一致） | 无（FR/SC 零改动属实：spec 其余段落未见联动修改） |
| 3a | I1：plan Scale/Scope（日志:25） | plan.md:56-58「增 2 文件（follow_up.mbt、follow_up_wbtest.mbt）+ 改 4 文件（http_client/exchange/body_bridge 小步重构、call_test.mbt 增补——P05 已在场非新建）」 | ✅ | ✅ | 无 |
| 3b | I1：plan Project Structure（日志:26） | plan.md:106「`call_test.mbt # 改（P05 已在场，增补）`」 | ✅ | ✅（:106 精确） | 无 |
| 4 | I2：R10 FR-009 行订正（日志:30） | research.md:284「FR-009（中间 close）｜**P06-US6 黑盒（T013）**」 | ✅ | ✅（:284 精确；落位与 tasks.md:243-249 T013 一致） | 无 |
| 5 | D-3：反驳「磁盘已对齐，零修改」（日志:32-35） | contracts/follow-up-api.md:20 现文 = `pub async fn Call::execute(Self) -> @core.Response`；src/client/pkg.generated.mbti:36 同文——**现状字面一致复核成立**；但 `ls --full-time`：contracts 的 mtime = **12:33:39**，与 plan.md 同值，落在 round3 编辑窗（spec 12:32:16 / data-model·plan·research·tasks 12:40:02-16 / round3 日志 12:42:42）之内 | 现状 ✅ | ⚠️ 「零修改」与 mtime 观察互斥（三解见 C-3，不自行裁决） | 无内容矛盾 |
| 6a | D-4：源码核实（日志:39） | src/client/client.mbt:134-141 `Lease` 结构体、:137 `priv addr : Address`（实测 awk 读盘）；同包可读先例 src/client/exchange.mbt:98 `lease.conn.request(...)` | ✅ | ✅（opencode 对我锚点「:141/:135-143 为区间微漂、字段实位 :137」的订正成立——我 round2 引的确实是结构体起止行） | 无 |
| 6b | D-4：R3 订正+删除（日志:42） | research.md:87-96（3 priv 字段 + 「不设 `lease_addr` 镜像字段」订正块）；:186 `lease.addr == addr`；:205-206「以 lease.addr 同包直读判定」 | ✅ | ✅（三处行号精确） | 无 |
| 6c | D-4：data-model 同步（日志:43） | data-model.md:15（ensure_lease 注记）、:23（`else if next_addr != lease.addr`）、:100-112（实体 6 表仅 gen/folded_gen/conn_close_seen 三行 + 订正注记）、:116-118（INV-1「租约地址仅经 `lease.addr` 同包直读，无镜像字段」） | ✅ | ✅ | 无 |
| 6d | D-4：tasks 同步（日志:44） | tasks.md:93-96（T003「增 3 priv 字段……不设镜像字段」）、:104-105（T004「同 host 复用经 `lease.addr` 直读判定」）、:242（T012「`lease.addr` 同包直读相同零往返」） | ✅ | ✅ | 无 |
| 6e | D-4：plan/contracts 同步（日志:45-46） | plan.md:72（VI 行「3 个 priv 字段……不设镜像字段——round3 D-4 订正」）、plan.md:102；contracts:33-35（「`Call` 新增 3 个 priv 字段……不设镜像——round3 D-4 订正」） | ✅ | ⚠️ 内容与日志一致；但 contracts 与 plan 的 mtime 同为 12:33:39（批次一），日志把二者归入批次二（12:40）——**批次归因与时间戳不符**（见 C-3） | 公开面一致性 ✅：Call 仍 `/* private fields */`（contracts:17 ↔ mbti:27-28 区段），spec FR-012/Key Entities 不含 priv 字段表述 ⇒ 删除不触公开面声明 |
| 6f | D-4：残留扫描（日志:96「无残留活引用」） | 全目录 grep `lease_addr`：产物侧仅 research.md:92、data-model:109 两处**订正注记**（负向表述），无活引用；grep「4 priv / 4 个 priv / 0/0/None/false」产物侧零残留（仅 analyze 冻结日志文本） | ✅ | ✅ | 无 |
| 7a | D-1 裁决落笔：T005 补 ④⑤（日志:52） | tasks.md:122-132：「写 P06-US1①②④⑤（编号对齐 spec US-1 验收场景 1/2/4/5）」+ ④`PUT /a`→`302 Location: /b`（GET 跟随、body 丢弃、三头去除、prior 长 1）+ ⑤`DELETE /a`→`300 Location: /b` | ✅ | ✅ | ⚠️ 轻微：T005:123-124 称「①②④⑤ 编号对齐 spec 场景 1/2/4/5」，而 T007:150 的 `P06-US1③` 恰为 spec 场景 3——「与 spec 同号」规则在两任务中的表述互斥（同号规则 vs 局部遗留编号），见 C-4 |
| 7b | D-1 裁决落笔：T006/T007 编号对齐、R10 闭合、spec 零改（日志:53-55） | tasks.md:141-142（`P06-US1-prior`「机制测试不占 spec 场景号」）、:150-151（`P06-US1③`「spec 场景 3：HEAD→303 保持」）；research.md:274（US-1-4/5 行「P06-US1 黑盒（T005 落地）」）；spec US-1 段（:34-48）与场景 3（:41-42）无改动痕迹 | ✅ | ✅ | 无（US-1-3 的 `GET→301` 断言仍在 T007 内、不占 spec 场景号，属超集非矛盾） |
| 7c | D-1 @oracle 锚点复核 | spec.md:292「SC-001: US-1–US-6 全部验收场景测试全绿」（日志引 :288——U1 注记插 4 行后下移）；spec.md:390 DoD-1；spec.md:382「决策表逐行基于 P03 重定向链夹具构造全部……」；tasks.md:285-290 T016 白盒「纯函数无 IO 逐行 `assert_true`」不走 execute 全链 | ✅ | ✅（四条锚点全部命中磁盘实况；行号偏移归因于本轮 spec 编辑，非锚点失实） | 无 |
| 8a | D-2 裁决落笔：data-model 归属注记（日志:61） | data-model.md:41-48「**处置归属（round3 D-2 裁决钉死）**」四要件齐：轮级 errdefer 唯一毒化归属点／`drain_intermediate` 不写 catch 纯透传／guard else 内 `release_lease()` 先于 `raise`（反序即毒化关闭）／no-op 幂等为承重细节 | ✅ | ✅（日志称 :41-50，实文 :41-48，:49 空行、:50 实体 2 标题——区间微漂，内容全在场） | ⚠️ 同块伪码 :21 行内注释「skip（毒化透传）」未随注记同步，仍可读出「drain 毒化」旧语义，注记 :43-44 的「R6 措辞按此口径读」只覆盖 R6 不覆盖伪码注释，见 C-2 |
| 8b | D-2 裁决落笔：R6 两处措辞（日志:62） | research.md:181-184「skip 失败 → 错误透传（……毒化由轮级 `errdefer poison_release()` 统一实现、drain 内不另写 catch——处置归属单点，见 data-model 实体 1 注记，round3 D-2）」；:196-199「→ raise `TooManyFollowUps`（先 release 后 raise，errdefer 随后 no-op——连接保持干净回池；round3 D-2）」 | ✅ | ✅ | 无（:189-190「skip 失败路径已 poison，不回池」与新口径兼容——失败透传后仍由轮级 errdefer 完成 poison） |
| 8c | D-2 裁决落笔：T004 括注 + T014 断言（日志:63-64） | tasks.md:105-107「`errdefer poison_release()`（轮内失败毒化——轮内唯一毒化归属点；drain/超限路径不另写 catch，data-model 实体 1 注记，round3 D-2）」；tasks.md:264-269「+ 超限 raise 后连接**干净回池（非关闭）**断言……`accepted_total` 不增 / `conn_request_counts` 同连接计数 +1；`Sequence` 末位驻留语义——探针请求走独立 plain-200 mount」 | ✅ | ✅ | ⚠️ 同 C-1：tasks.md:240-241（T012 实现条款）与 T004:106「drain……不另写 catch」直接互斥——同文件两任务口径不一 |
| 8d | D-2 @oracle 锚点复核 | data-model.md:16（轮级 errdefer）与 :25（超限 guard raise）——即改前 :16/:25 作用域叠合，现文仍在同位；src/client/body_bridge.mbt:102 `async fn Call::dispose_skip` 实测起于 :102（引文「L102-110」成立，:107 `errdefer poison_release()` 同段在场——注：该先例为 **errdefer 型**，非「drain 内 catch」型，与第三方案自洽）；src/client/exchange.mbt:84 `errdefer self.poison_release()` 在场 | ✅ | ✅ | 无 |
| 9 | 三、未采纳项：Q-B3～Q-B8 六项未动（日志:91） | 复抽：contracts/quickstart 六门口径、R7 末位驻留（research.md:217-221 区段未改）、INV 段之外无新增订正标记——六项均维持 round2 原状 | ✅（按日志声明未动） | ✅ | 无新增（原有 INFO 残留不变） |

**统计**：round3 日志共列 **15 个落笔/声明项**（1a/1b/2/3a/3b/4/5/6a-6f/7a-7c/8a-8d/9）。
- **属实（落盘+与日志一致+无交叉矛盾）：12 项**（1b、2、3a、3b、4、6a、6b、6c、6d、7a*、7b、7c、8a*、8b、8c*、8d、9 中扣除带 ⚠️ 者后——精确口径：完全干净 12，带瑕疵 4，不可证实 1，见下行）
- **与日志描述不符/带瑕疵：3 项**——① 1a/8c（T012 实现条款残留旧毒化口径，履行未收敛）；② 8a（data-model:21 伪码注释未随归属注记同步）；③ 7a（「①②④⑤=spec 场景号」表述与 T007③ 同号规则互斥）
- **不可证实：1 项**——5（D-3「零修改」声明 vs contracts mtime=12:33:39 落在编辑窗；现状层面无差异可查）

---

## B. 三态结论表（对我方 round2 提出的五条）

| 我方条目 | 处置方 | **三态结论** | 证据 |
|---|---|---|---|
| **Q-A1**（=C1，FR-002 失败半边无承载） | opencode 直接落笔 | **采纳** | tasks.md:229/:234-239 红绿对补②成立、夹具零扩展（fixtures mbti:66/:87）、research.md:285 R10 行补登。残留：C-1（实现条款措辞）不影响「承载在场」判定 |
| **Q-A2**（=D-2，处置归属歧义+缺断言） | @oracle 裁决 | **部分采纳**——定级（WARNING）与诉求（钉归属+补断言）全部采纳；我方具体修法（errdefer 收窄 exchange 段 + advance 显式 catch）被裁决否决，改用「轮级 errdefer 单点归属」第三方案 | 裁决落笔核验：data-model.md:41-48、research.md:181-184/:196-199、tasks.md:105-107/:264-269 四要件齐备且方向一致；**如实落笔判：基本成立，一处履行残留（C-1）+ 一处注释未同步（C-2）**；裁决锚点判：成立（8d） |
| **Q-A3**（=D-1，US-1-4/5 黑盒落点缺失） | @oracle 裁决 | **采纳**（裁决判我方成立） | tasks.md:122-132 ④⑤ 黑盒在场、编号与 spec 场景 1/2/4/5 对位；R10:274 可追溯链闭合；spec 零改与裁决「tasks→spec 对齐方向」一致；裁决锚点（SC-001:292、DoD-1:390、测试方案:382、T016 纯函数面:285-290）四条全部命中磁盘实况 |
| **D-3**（=Q-B1，contracts 漏 `async`） | opencode 反驳 | **认负（现状层面）** | 实测 contracts:20 与 src/client/pkg.generated.mbti:36 现均含 `pub async fn`，字面一致 ⇒ 我方「逐字对账会亮红灯」的前提在磁盘现状上不成立，如实认负。**但认负范围以磁盘现状为限**：contracts mtime=12:33:39 落在 round3 编辑窗内，与其「零修改」声明互斥（C-3），故「round2 时点磁盘即为 `pub fn`」这一事实本轮既不能证实亦不能证伪——过程问题移交 host，不改变我方内容认负结论 |
| **D-4**（=Q-B2，R3 括注失实+lease_addr 冗余） | opencode 核实+扩展处置（删字段） | **采纳（并超出我方建议）** | 我方仅建议「定死口径」，opencode 径行删除并 5 文件同步——六处锚点全部实测命中（6b-6e）、残留扫描干净（6f）；**与我方证据的一致性核验**：删除后公开面声明链无裂缝（contracts §1 Call 仍 `/* private fields */`、spec FR-012/Key Entities 不含 priv 字段、`.mbti` 对账集合不变、`Lease` 公开面未动 mbti:57-60 区段）；opencode 对我引行号的「区间微漂、字段实位 :137」的反向订正成立（client.mbt:134-141/:137 实测） |

---

## C. 残留/新增问题清单（本轮新发现，全部带锚点；均未修）

| ID | 级别（沿用口径） | 锚点 | 事实 |
|---|---|---|---|
| **C-1** | **WARNING（履行残留）** | tasks.md:240-241（T012「实现：`drain_intermediate`（`lease.conn.skip_response_body()` 直调，**失败 `poison_release` 后透传**——R6）」）↔ tasks.md:105-107（T004「轮内唯一毒化归属点；**drain/超限路径不另写 catch**」）↔ data-model.md:43-44（「`drain_intermediate` 内不写 catch/毒化，错误纯透传」）↔ research.md:181-184（R6 已订正为同一口径） | D-2 第三方案的同步范围漏了 T012 的实现条款——该句仍是修订前的 R6 旧口径（drain 内自毒化），round3 日志:65 自称「T012 补②与 D-2 同批落笔、依赖同一句归属钉死」，但只同步了红侧、未同步实现侧；同文件（tasks.md）内 T004 与 T012 现互相矛盾，implement 按 T012 落笔即造出第二毒化点（正是 @oracle 否决 qoder 方案的理由）。注：日志:44 明载 T012 本轮改过（:242 keep 分支），独漏 :240-241 |
| **C-2** | INFO（同步残留） | data-model.md:21（伪码行内注释「`drain_intermediate(response)` // R6：conn 上 skip（**毒化透传**）」）↔ 同文件 :43-44（归属注记：drain 内不写毒化） | 归属注记只声明「R6 措辞按此口径读」，未覆盖伪码自身的括号注释；「毒化透传」四字仍可独立读出旧语义。顺带一句同位残留：:21 措辞在 round2 即为歧义源（我 Q-A2 未点名它，此处补登记） |
| **C-3** | INFO（过程取证，不代裁决） | `ls --full-time` 实测：spec.md 12:32:16 / contracts 12:33:39 / plan.md 12:33:39 / data-model.md 12:40:02 / research.md 12:40:16 / tasks.md 12:40:16 / round3 日志 12:42:42（2026-10-27） | 三点观察：①contracts 在 round3 编辑窗被写入，与日志「D-3 零修改」及日志:7「未触碰」清单外的表述互斥——若该次写入即加了 `async`，则 opencode 的反驳前提（「磁盘本就对齐」）不成立且未申报改动；若写入仅是 :33-35（D-4 同步），则与 :20 在我 round2 读盘时为 `pub fn` 的观测冲突仍在。两种可能本轮均无法在磁盘现状上检验（specs/ 未跟踪、无历史快照）。②D-4 同步项（contracts:33-35、plan:72/:102）日志归入批次二（12:40），实测两文件 mtime 均为批次一（12:33:39）——批次归因与时间戳不符。③请 host 向 opencode 索取 12:33:39 那次 contracts 写入的内容归因；**本报告不据此改判 D-3 内容结论**（内容层面现状一致，见 B 节） |
| **C-4** | INFO（表述互斥） | tasks.md:123-124（「①②④⑤ 编号对齐 spec US-1 验收场景 1/2/4/5」）↔ tasks.md:150（T007「P06-US1③（红；spec 场景 3……）」） | 若「与 spec 场景同号」为统一规则，T005 括号应作「①②③④⑤ 中 ①②④⑤（③ 见 T007）」；现为「对齐 1/2/4/5」与「③=场景 3」两读并存。测试落点本身无缺口（场景 3 由 T007 承载），仅命名规约二义 |
| **C-5** | INFO（日志行号漂移） | round3 日志:21 引「spec.md:167-172」对改后文精确；但日志:50 转引 @oracle 的 spec.md:288（SC-001）/:279-282（非目标段）为 U1 插行前锚点，改后实位 :292/:283-286；日志:61 引 data-model「:41-50」实文 :41-48 | 归档转述层面的行号未刷新，后续轮引用会错位；无内容错误 |

**交叉一致性正证（round3 日志:94-99 自查项复核）**：
- T012 补② ↔ R10 FR-002 行（T012 补②）——一致（tasks.md:234 ↔ research.md:285）。
- T005 ④⑤ ↔ R10 US-1-4/5 行（T005 落地）——一致（tasks.md:129-132 ↔ research.md:274）。
- 3 priv 字段口径 5 文件一致——实测命中（research:87 / data-model:102-106 / tasks:93 / plan:72,:102 / contracts:33）。
- INV-4 原文（data-model.md:124-125「超限路径先排干后干净释放再 raise」）与归属注记 :44-46 成立条件——一致。
- 归属注记 ↔ R6 ↔ T004 三点互引——一致；唯 T012 实现条款在三角之外（C-1）。

---

## D. 总结判

**需再修（一处小修），修复后可进入新一轮独立校验。**

- 实质阻塞仅 **C-1** 一条：T012 实现条款（tasks.md:240-241）与本轮刚钉死的处置归属（data-model:41-48 / T004:105-107 / R6:181-184）在同文件互斥——属 @oracle 裁决的**履行未收敛**，不是新分歧；改法机械（该句「失败 `poison_release` 后透传——R6」→「失败纯透传，毒化由轮级 errdefer 统一实现」），一字即可闭环，spec/contracts/公开面零触达。
- C-2/C-4/C-5 为同步/表述级，可与 C-1 同批顺手订正，亦可并入 implement 期。
- C-3 不是内容问题，是**过程待澄清项**：contracts 在 round3 窗内被写却申报「零修改」，现状层面我已按工单要求认负（两处 `pub async fn` 字面一致，锚点 contracts:20 ↔ mbti:36 实测），但「零修改」声明与 mtime 的矛盾原样交回 host，不自行裁决。
- 我方五条三态收口：Q-A1 采纳、Q-A3 采纳、D-4 采纳（超出建议）、Q-A2 部分采纳（定级与诉求成立、修法被裁决替换且基本落笔）、D-3 认负（以磁盘现状为限）。
- 其余六项 INFO（Q-B3～Q-B8）round3 明示未获授权未动（日志:91），维持 open，不重复展开。

*报告结束。生成：qoder 工单⑤ @ 2026-10-27 ｜ 唯一写入：本文件。*
