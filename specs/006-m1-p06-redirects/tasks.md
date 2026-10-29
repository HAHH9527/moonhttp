# Tasks: 自动重定向 follow-up 循环（M1-P06）

**Input**: Design documents from `/specs/006-m1-p06-redirects/`

**Prerequisites**: plan.md（必读，宪法核查与源码树）、spec.md（Clarifications
七条裁决 + FR-001～012 + SC-001～008 + 5.5.0 映射表）、research.md
（R1–R10：5.5.0 对拍真值/落位点/重构形状/夹具核证/js/错误面/测试映射）、
data-model.md（六实体/七不变量/轮循环与租约三态图）、contracts/
follow-up-api.md（client 增量对账面 §1 + core 零 diff §2）、quickstart.md
（六门命令）

**Tests**: 本包**行为任务（T002–T015）**按宪法 IV「验收场景与测试先行」
执行——每任务的自证元测试与实现在**同一任务内成对出现（先红后绿）**；
「只写实现、测试另立任务补」为违规排布（003 tasks:7 / 005 tasks:11 口径）。
Setup 与收口任务（T001、T016–T018）为治理/对账任务，无红绿对。双 target
（native/wasm）为每对任务的默认验收；js 仅编译检查不入门禁（D14/F9）。
断言优先 `assert_eq`/`assert_true(err is …)`；禁 sleep 串联（P05 口径）。

**Organization**: 按用户故事分组（US-1～US-6，spec 优先级）；接缝参数化 +
决策表骨架 + 循环直通为 Foundational 阻塞项。**阶段顺序说明**：US-1 →
US-2 → US-3 → US-4 → US-6 → US-5。US-1 首拆循环跟随机制（降级行 +
Location 门 + prior 链）；US-2/US-3/US-4 消费同一机制（保持行/解析
形态/剥头）；US-6 扩展 advance 路径（排干/租约三态）；US-5（P2）收口
上限与不跟随集（其白盒 Terminal 行在 Foundational T002 先行落地，黑盒
场景本阶段钉死）。Story 标签与 spec 编号一一对应，优先级标注不受阶段
顺序影响。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 可并行（不同文件、无未完成依赖）
- **[Story]**: 所属用户故事（US1～US6，对应 spec 用户故事 1～6）
- 描述含精确文件路径

## Path Conventions

- 门面包：`src/client/`（P05 结构裁决延续——循环为 exchange 接缝的纯
  上层包裹，同包直读 Call/Lease 私有状态；新文件 `follow_up.mbt` +
  `follow_up_wbtest.mbt`，改 `http_client.mbt`/`exchange.mbt`/
  `body_bridge.mbt`，新测试 `call_test.mbt` 增补、`call_wbtest.mbt`
  适配（T003，P05 已在场）；`moon.pkg` 零改动预期）
- 零改动：`src/core/`（contracts §2：Location/头改写/重组/prior 装配
  全走 P01/P02 既有面）、`src/internal/fixtures/`（contracts §3 /
  research R7：mount_sequence/conn_request_counts/Capture 全能力在场；
  若 implement 期证实需要扩展，先红后绿最小扩展并逐处归因）
- 产物目录：`specs/006-m1-p06-redirects/`（baseline 快照入 `baseline.md`）

---

## Phase 1: Setup（共享基线）

**Purpose**: 动工前固化基线，供后续 diff 归因与回归对照

- [X] T001 记录动工前基线（只读测量，无代码改动）：静态测试计数
  `Select-String -Path (Get-ChildItem -Recurse src -Include *_test.mbt,*_wbtest.mbt).FullName -Pattern '^\s*(async\s+)?test\s'`
  当前实测 **== 240**（含 `#skip` 长跑条目，双 target 运行时基线以
  `moon test` 实测 `Total tests:` 为准记录）；再依次运行六门
  （`moon check --target native/wasm --deny-warn`、`moon test --target
  native/wasm --deny-warn`、`moon fmt --check`、`moon info`），将六门
  结果与 `src/client/pkg.generated.mbti`、`src/core/pkg.generated.mbti`、
  `src/internal/fixtures/pkg.generated.mbti` 快照存入
  `specs/006-m1-p06-redirects/baseline.md`（对照物：Phase 9 的 T017；
  动工时如遇数目漂移，以实测为准并记录新值与原因）

---

## Phase 2: Foundational（阻塞项：决策表骨架 + 接缝参数化 + 循环直通）

**Purpose**: 决策表纯函数与 `TooManyFollowUps` 变体被全部故事消费；
接缝参数化与代次缓存是循环的前提（data-model 实体 2/6）

**⚠️ CRITICAL**: 本阶段未完成前不得开始任何 US 行为任务

- [X] T002 [P] 决策表 Terminal 骨架 + 错误变体（先红后绿）：
  `src/client/follow_up_wbtest.mbt` 新建写 P06-WB①（红）——
  `follow_up_request` 对 304/305/306/401/407/408/200 及「3xx 无
  Location」恒判 `Terminal`（spec FR-003 行 4/5 + FR-008 白盒半边；
  真值表 data-model 实体 3）→ 实现 `src/client/follow_up.mbt` 新建：
  `FollowUp` 私有枚举（`Next(Request)`/`Terminal`）+ 决策表骨架（仅
  Terminal 路径）+ `src/client/http_client.mbt` 增
  `pub suberror TooManyFollowUps derive(@debug.Debug)` 与
  `pub extend TooManyFollowUps with @debug.Debug::{to_repr}`（R9 两件
  套先例）；`moon info` 核对 client `.mbti` 增面**恰好等于
  contracts §1 两件套且仅此**
- [X] T003 接缝参数化 + Call 内部字段 + 代次折叠缓存（先红后绿）：
  `src/client/follow_up_wbtest.mbt` 写 P06-WB②（红）——代次键化
  断言：同代次重放 `folded_headers` 复用同一 Map 实例（fold_count
  不变）、换代后首次发送重折叠恰一次（fold_count +1）；并适配 P05
  白盒直调点 `src/client/call_wbtest.mbt`（字面 `exchange_once` 5 处、
  实际直调 **3 处**——:366/:378/:633，另 2 处为注释与测试名；baseline.md
  实况对账注记同款口径，2026-10-28 review 修复批 M2 订正「5 处」表述）
  补 request 实参，语义零变化）→ 实现：`src/client/exchange.mbt`
  `exchange_once(request)`/`exchange_with_lease(request)` 参数化 +
  `folded_headers(request, gen)` 代次键化（R3：`folded_gen == gen ∧
  folded is Some` 复用，否则折叠并存 `{folded, folded_gen,
  fold_count+1}`）；`src/client/http_client.mbt` Call 增 3 priv 字段
  `gen`/`folded_gen`/`conn_close_seen`（data-model 实体
  6，初值 0/0/false；租约地址不设镜像字段，`lease.addr` 同包直读
  ——round3 D-4 订正）；公开面零变化复核
- [X] T004 循环直通 + 轮间取消 guard（先红后绿）：
  `src/client/follow_up_wbtest.mbt` 写 P06-WB③④（红）——③桩接缝
  单轮行为与 P05 等价（Terminal-only 循环 = 单轮 exchange，终态
  prior=None）；④轮间取消：桩在轮间置 `cancelled` → 循环顶 guard 以
  裸 `CallCancelled` 终止（`err is CallCancelled` 判别，FR-001；
  轮内取消走 P05 既有通道不重测）→ 实现 `src/client/follow_up.mbt`
  `exchange_loop`：循环顶 `guard !self.cancelled else raise
  CallCancelled` + `ensure_lease`（缺失 acquire；同 host 复用经
  `lease.addr` 直读判定）+ `errdefer poison_release()`（轮内失败
  毒化——轮内唯一毒化归属点；drain/超限路径不另写 catch，
  data-model 实体 1 注记，round3 D-2）+
  单轮 + Terminal 返回；`src/client/http_client.mbt` execute 的
  spawn 目标换 `exchange_loop`（`ExchangeOutcome` 外壳零变化）

---

## Phase 3: User Story 1 - 方法降级跟随（Priority: P1）

**Goal**: 300/301/302/303 对非 GET/HEAD 降级 GET（body 与三头去除），
GET/HEAD 全码保持；Location 门（相对/绝对 resolve）；prior 链记录
中间响应

**Independent Test**: P03 夹具 `mount`/`mount_sequence` 构造单跳与两跳
链；`conn_request_counts` 辅助；不经 P07/P08 完整验收

- [X] T005 [US1] 降级行 + Location 门 + 头改写（先红后绿）：
  `src/client/call_test.mbt` 写 P06-US1①②④⑤（编号=spec US-1 验收
  场景号：①②③④⑤ 中 ①②④⑤ 落本任务，③ 见 T007；④⑤为 C2/300
  修正固化黑盒——round3 D-1 补）
  （红）——①`POST /a` →
  `301 Location: /b`：follow-up 为 `GET /b`、捕获请求无 body 与
  Content-Length/Content-Type/Transfer-Encoding 头、终态 200 正确、
  prior 链长 1（夹具 `CapturedRequest`/`head_text` 断言）；②
  `POST /a` → `303` 同判；④`PUT /a` → `302 Location: /b`：
  follow-up 为 `GET /b`、body 丢弃、三头去除、prior 链长 1（C2
  修正固化）；⑤`DELETE /a` → `300 Location: /b`：follow-up 为
  `GET /b`（300 有 Location 即跟随，300 修正固化）→ 实现：
  `follow_up_request` 降级行（
  300/301/302/303 + 非 GET/HEAD → `RequestBuilder::new(target)`
  `.method(Get).headers(rewrite)` 无体 build，R4 矩阵边界）+ Location
  门（`response.headers().get("Location")` + `request.url.resolve`
  catch `HttpUrlError` → Terminal）+ `rewrite_headers` 降级三头
  `remove`（跨 host 剥离本任务不启用，US-4 落地）；循环保留 T004 的
  advance 最小路径（排干细则 US-6 深化，本任务单跳链可行即可）
- [X] T006 [US1] prior 链构建与挂链（先红后绿）：
  `src/client/call_test.mbt` 写 P06-US1-prior（红；机制测试不占
  spec 场景号——round3 D-1 编号对齐）——两跳链
  （`mount_sequence`）终态 `.prior` 链深 2、回溯顺序与夹具注入的 3xx
  序列逐项一致（code 断言）、prior 条目 `body()` 为 None（INV-5）→
  实现：`with_prior(response, prior, keep_body)` 助手（R5：
  `from_http(code, reason, headers.to_http_map(), cookies,
  body=keep_body ? 原体 : None, prior=prev)`）+ 循环内 prior 累积与
  终态挂链
- [X] T007 [US1] 方法保持行（先红后绿）：
  `src/client/call_test.mbt` 写 P06-US1③（红；spec 场景 3：
  HEAD→303 保持——round3 D-1 编号对齐）——`HEAD /a` → `303`
  follow-up 保持 HEAD（`permitsRequestBody` 门：GET/HEAD 不进改写
  块，R1 第 2 条）；`GET` → `301` 同判 → 实现：决策表 GET/HEAD
  保持分支（方法/头/体原样，跨 host 剥离仍留 US-4）

---

## Phase 4: User Story 2 - 方法保持与可重放判定（Priority: P1）

**Goal**: 307/308 保持方法与 body；Bytes 逐字节重放、Stream 不跟随
原样返回（对齐 5.5.0 one-shot，R1 第 5 条）

**Independent Test**: `ScriptedPeer Capture` 或 `ScriptedServer`+
`CapturedRequest` 比对两次请求字节；Stream 场景单跳断言

- [X] T008 [US2] 307/308 保持行 + Bytes 重放（先红后绿）：
  `src/client/call_test.mbt` 写 P06-US2①③（红）——①`POST` +
  `Bytes` body → `307 Location: /b`：对端两次捕获请求行与 body 字节
  逐字节一致（`CapturedRequest.raw`/`raw_text` 比对）；③`308` 同判 →
  实现：决策表 307/308 分支（保持方法 + `request.body` 原值搬移进
  `RequestBuilder::body`，R4 不可变性论证；跨 host 剥离留 US-4）
- [X] T009 [US2] Stream 不跟随（先红后绿）：
  `src/client/call_test.mbt` 写 P06-US2②（红）——`POST` + `Stream`
  body → `307`：不跟随（对端仅见一次请求）、调用方收到该 307 响应
  本体（code/headers 断言）、body 可正常消费且连接处置符合 P05 语义
  → 实现：决策表 `BodySource::Stream` → `Terminal`（含 prior 挂链
  路径，R5 第 4 条）

---

## Phase 5: User Story 3 - Location 解析（Priority: P1）

**Goal**: 相对/绝对/网络路径三形态 resolve 正确；缺失/非法 → 原 3xx
终态

**Independent Test**: `mount` 注入任意 Location 字符串形态，逐形态
断言 follow-up 目标

- [X] T010 [US3] Location 三形态与非法回退（先红后绿）：
  `src/client/call_test.mbt` 写 P06-US3①②（红）——①相对 `../b`、
  绝对 `/b`、网络路径 `//other.host/x`（对端双实例或同实例异端口，
  R7）三形态分别 resolve 到正确绝对 URL 后跟随（捕获请求行断言）；
  ②无 `Location` 头、非法值（`http://` 截断等 resolve raise 形态）→
  原 3xx 终态返回且零 follow-up 请求 → 实现：resolve 门三形态用例
  补齐 + catch 分支钉死（T005 已落相对/绝对主路径，本任务穷举形态并
  固化回退；若发现实现缺口按先红后绿补）。
  （round8 I2 纪律注记：本任务红侧存在首跑即绿可能——T005 已先行
  落地 resolve 主路径；首跑颜色须实测记录，首跑即绿时在任务产出登记
  「实现先行」归因备宪法 IV 审计，不得事后补造红灯）

---

## Phase 6: User Story 4 - 跨 host 头剥离（Priority: P1）

**Goal**: 跨 host（scheme/host/port 任一不同）剥 `Authorization`+
`Cookie`；同 host 保留（C1 有意差异，5.5.0 仅剥 Authorization——
spec 映射表）

**Independent Test**: `ScriptedPeer Capture` 字节级断言（剥头/保留
双向）

- [X] T011 [US4] 跨 host 剥头与同 host 保留（先红后绿）：
  `src/client/call_test.mbt` 写 P06-US4①②（红）——①带
  `Authorization: Bearer x` + `Cookie: a=1` 的 `POST` → `301` 跨
  host：捕获 follow-up 字节不含这两个头（大小写变体注入一例钉
  `remove` 不敏感性，research 附加核实第 3 条）；②同 host `301`：
  两头完整保留 → 实现：`rewrite_headers` 启用跨 host 分支
  （`Address(request.url) != Address(target)` Eq 判定，R1 第 7 条；
  `remove("Authorization")` + `remove("Cookie")`）；同 host 路径
  remove 不触达复核

---

## Phase 7: User Story 6 - 中间响应排干与租约保持（Priority: P1）

**Goal**: 同 host 多跳复用同一连接（零归还-重取）；中间 body 排干不
污染后续请求；跨 host 换租；中间 `Connection: close` 关闭不回池

**Independent Test**: 3 跳同 host 链 `conn_request_counts` 连接计数 +
终态后同连接干净流断言；跨 host 双实例新建连接计数

- [X] T012 [US6] 排干 + 同 host 租约保持 + 排干失败毒化（先红后绿）：
  `src/client/call_test.mbt` 写 P06-US6①（红）——3 跳同 host 链
  （每跳 1KB body）：夹具侧新建连接数恰 1（`accepted_total`/
  `conn_request_counts`）、终态响应体读完后同池连接的第 4 个请求
  读到干净流（无上一跳残帧）；中间响应未交付（无 Consumed/Dropped
  事件外泄——白盒侧 P06-WB⑤ 辅以事件标记断言）；另写 P06-US6 补②
  （红，FR-002 失败半边，round3 补）——中间响应体截断（夹具
  `mount_truncated`/`RouteScript::Truncated`，fixtures mbti:87
  在场，零扩展）→ `skip_response_body` 失败 → `poison_release` →
  错误透传（`err` 判别、非 panic/非静默）且连接不回池（后续同
  Address 租借新建连接 +1）→ 实现：`drain_intermediate`
  （`lease.conn.skip_response_body()` 直调，失败纯透传——drain 内
  不写 catch/毒化，毒化由轮级 `errdefer poison_release()` 单点归属，
  data-model 实体 1 注记，round3 D-2；R6）替换 T005 的最小 advance；
  `ensure_lease` keep 分支
  （`lease.addr` 同包直读相同零往返）
- [X] T013 [US6] 跨 host 换租 + 中间 close（先红后绿）：
  `src/client/call_test.mbt` 写 P06-US6② + P06-US6 补①（红）——
  跨 host 跳：旧 host 连接干净回池（后续同 Address 租借可复用）、新
  host 新建连接 +1（双实例计数）；中间响应 `Connection: close`：
  该连接关闭不回池（后续租借新建）、follow-up 走新连接 → 实现：
  advance 路径 `release_lease()`（跨 host / `conn_close_seen` 分支，
  INV-6/INV-7；标记复位在 `ensure_lease` 取新租）

---

## Phase 8: User Story 5 - 跳数上限与不跟随集合（Priority: P2）

**Goal**: 21 跳与循环链 `err is TooManyFollowUps`；304/305/306 与无
Location 的 300 终态透传

**Independent Test**: `mount_sequence` 21 跳链与 A→B→A 双路径夹具；
不跟随状态码逐个注入

- [X] T014 [US5] 上限计数与循环保护（先红后绿）：
  `src/client/call_test.mbt` 写 P06-US5①（红）——21 跳链 raise
  `err is TooManyFollowUps`（非 panic/非静默终态）；A→B→A 循环链同
  判；白盒侧 P06-WB⑥ 计数位置断言（排干后、发送前——20 个
  follow-up 实际发出、总请求 21，R1 第 8 条）+ 超限 raise 后连接
  **干净回池（非关闭）**断言（round3 D-2 补）：raise 后对同 host
  的下一请求复用池内连接（`accepted_total` 不增 /
  `conn_request_counts` 同连接计数 +1；`Sequence` 末位驻留语义
  ——探针请求走独立 plain-200 mount）→ 实现：advance 计数
  guard（`follow_ups += 1; guard follow_ups <= 20 else {
  release_lease(); raise TooManyFollowUps }`，INV-4）
- [X] T015 [US5] 不跟随集合黑盒收口（先红后绿）：
  `src/client/call_test.mbt` 写 P06-US5②③（红）——`304`/`305`/
  `306` 各自原样返回（终态透传，连接处置符合 P05 语义）；`300` 无
  Location 原样返回（US-3② 已钉非法/缺失回退，本任务固化 300 语义
  ——跟随/不跟随双形态，C2/300 修正闭环）→ 实现：预期 T002 Terminal
  行直接命中；若黑盒暴露缺口按先红后绿补并回记差异。
  （round8 I2 纪律注记：本任务红侧存在首跑即绿可能——T002 Terminal
  行已先行落地；首跑颜色须实测记录，首跑即绿时在任务产出登记
  「实现先行」归因备宪法 IV 审计，不得事后补造红灯）

---

## Phase 9: Polish & Cross-Cutting（收口与对账）

**Purpose**: 决策表穷举、六门、契约对账、js 非门禁项

（round8 I5 分期注记）：T005–T011 窗口循环沿用 T004 最小 advance，
INV-2（排干前置）在该窗口无测试保护、自 T012 `drain_intermediate`
起全量承载——implement 在该窗口不引入带体中间响应场景，带体排干
场景一律 T012 后落。

- [X] T016 [P] 决策表穷举真值矩阵（白盒收口）：
  `src/client/follow_up_wbtest.mbt` 写 P06-WB⑦——方法 × 状态码 ×
  Location × body 形态穷举表（九标准方法 × {300,301,302,303,307,308,
  304,401} × {有,无} × {Bytes,Stream,无}，R10 FR-003；纯函数无 IO
  逐行 `assert_true`），含 GET/HEAD 恒保持、降级三头去除、跨 host
  剥头纯函数断言（`rewrite_headers` 直驱）
- [X] T017 收口六门 + 契约对账（对照 T001 基线）：
  `moon info && moon fmt` 干净；`.mbti` diff 审视——client 增面恰好
  = `TooManyFollowUps` 两件套（contracts §1 对账，SC-008）、core/
  fixtures 零 diff（§2/§3）；`moon test --target native` 与
  `--target wasm` 双双全绿（SC-001～SC-007 逐条核对并在任务产出中
  记录每条 SC 的证据测试名）；baseline.md 对账记录收尾
- [X] T018 [P] js 编译检查 + 欠账复核（非门禁）：
  `moon check --target js` 零新增失败点（基线既有 13 errors 全在 P03
  夹具，baseline.md:26/:75 与 F9/M5 单点跟踪——原文「通过」系措辞
  失实，2026-10-28 随 Phase 10 订正；零 `#cfg(js)` 分支复核，R8）；
  spec target 矩阵/欠账表述与实现一致性复核（js 直通语义由浏览器
  行为保证的注释在场）

---

## Phase 10: Convergence（converge 欠账收口）

**Purpose**: 承接 2026-10-27 `/speckit-converge` 独立复核实测的 4 条
actionable findings（partial 3 / unrequested 1；HIGH 1 / MEDIUM 2 /
LOW 1）。2026-10-28 opencode 复核证据链并复跑门禁（native/wasm 各
270/270、fmt/check 干净、js 13 errors 与 baseline 同形、P06 测试
32 条与 SC 证据清单计数吻合、未勾选项 0）后落笔。

重复登记规避：js 门 `moon check --target js` exit 1（13 errors 全在
P03 夹具 raw_peer/scripted_server）不另发编号——baseline.md:26/:75
与 deferred-items-m1 F9（M5/16-target-support）单点跟踪；converge
契约无 `already_tracked` 出口，重跑会对其重复登记，按 owner
2026-10-16 墓碑口径处置。

非任务观察（不占编号）：attach_prior（follow_up.mbt）对每次 execute
重建终态 Response——data-model 实体 1 伪代码即此形，不算偏离；与
T020 相互咬合，量化落到 P10 后即暴露。

- [X] T019 补齐 SC-004「同 host 保留」半边的字节级证据 per SC-004 /
  FR-004 / research R10 US-4 行（partial，HIGH）：现证仅跨 host 字节级
  （call_test.mbt:1923）＋同 host 端到端走通（call_test.mbt:1983，注释
  自述夹具无请求头观测面）＋白盒纯函数代位
  （follow_up_wbtest.mbt:149 P06-WB④b）。观测面实测：ScriptedServer 无
  请求字节访问器（fixtures pkg.generated.mbti:80-90）、
  `Capture` 只回 canned 200 且单帧即关连（raw_peer.mbt:302-313）。
  出路二选一由 owner 分流：①按 Path Conventions「先红后绿最小扩展并
  逐处归因」扩 P03 观测面（同址 3xx→捕获 follow-up 字节）；②收窄
  SC-004 为「保留半边由纯函数断言承载」并回改 spec 再向下传导
  （产出 2026-10-28：owner 裁决①——ScriptedServer 增请求头观测面
  `captured_request_heads()`（一字段一捕获一访问器最小扩展，契约 §3
  登记性例外已记）；新用例 P06-US4②续「同 host 301：follow-up 凭证头
  保留」（观测面＝请求行+头表级——解析后重建，review 修复批 M7 按
  实况订正「字节级」措辞；真字节半边归跨 host CapturedRequest），
  红证据 [4015] 访问器缺失取证在案 → 绿，SC-004 双向断言闭合（分层
  口径见 spec SC-004 订正）；js 检查 13 errors 与基线同形零新增）
- [X] T020 [P] 登记 P06 性能量化的落地对象 per plan「性能影响」/
  spec 映射表（partial，MEDIUM）：docs/roadmap/M1/
  P10-benchmark-gate.md:23-33 场景矩阵无重定向/follow-up 场景、
  deferred-items-m1 F1–F19 无对应条目，致宪法 II 量化义务悬空；按
  roadmap 文档纪律入 M1 README D 表 ＋ deferred-items 总/分结构，
  P06 交付状态不进 roadmap
  （产出 2026-10-28：M1 README §3 新增 D17；deferred-items 总入口
  F20 行 + 子文档索引 20/20 + 速查「M1 内 P10」；deferred-items-m1
  F20 明细 + 速查行；P10 种子场景矩阵补 follow-up 场景行——单跳
  降级/多跳同 host 租约保持 vs 逐跳重建对照/跨 host 换租，含 prior
  链每请求一次装配重建的开销观测注记）
- [X] T021 [P] 登记 exchange.mbt:90 `#warnings("-unused_value")` 抑制
  per 宪法 VI / contracts §1 / plan Structure Decision（unrequested，
  MEDIUM）：specs/ 与 docs/ 对该抑制零命中（登记性缺口——成因已由
  源码「T017 收口注」写明：T004 后 `exchange_once` 在非测试源零调用
  点，仅 call_wbtest.mbt :366/:378/:633 白盒直调）。按
  `-reserved_keyword` 先例在 plan 例外跟踪留痕并回记 contracts §1
  接缝定位，或改为不需抑制的形状
  （产出 2026-10-28：择「登记」路——plan 宪法核查表增「零警告门依赖
  定点警告抑制 ⚠️ 例外跟踪」行 + 文末「例外跟踪」节（成因/为何不改
  形状/形态/002 先例）；contracts §1「明确不进公开面」回记
  exchange_once 接缝定位与抑制登记指引；抑制保留，形状零变化）
- [X] T022 补真实轮间取消用例 per FR-001 / T004「桩在轮间置
  cancelled」（partial，LOW）：P06-WB④
  （follow_up_wbtest.mbt:254）实为白盒直写标记后首轮 guard，未覆盖
  「轮 k 完成且租约在场、随后取消」。行为面已由 `Call::cancel` 同步
  `poison_release`（http_client.mbt:125）兜住，探针实测 errdefer
  作用域仅当前轮循环体 ⇒ 轮间 raise 不触发上一轮 errdefer；补用例
  断言裸 `CallCancelled` ＋ 连接处置（与 baseline.md R9-3 record 级
  成文义务同批收）。
  （产出 2026-10-28：P06-WB④c「轮 k 完成租约在场 → cancel → 裸
  CallCancelled + 毒化连接不回池」，确定性归约构造零 sleep；首跑即绿
  ——覆盖补齐/实现先行归因已入测试头注释；轮间取消租约处置成文于
  follow_up.mbt 循环顶 guard 注释，baseline.md R9-3 闭合注记已记；
  native/wasm 全绿【2026-10-28 review 修复批订正：当时实测应为
  272/272——238 基线 + P06 32 条 + T019 补 2 条，原记 271/271 漏计
  T019；「零 .mbti diff」措辞亦失实，.mbti 交付态见 baseline 订正节】）

- [X] T023 open-code-review（delegate 模式）修复批（2026-10-28）：
  34 文件全量审查结论逐条核对后修复——H1 Location 含逗号截断
  （`exchange_with_lease` 返回原始 `@http.Headers`、
  `follow_up_request`/`resolve_location` 原始头直读；WB⑧ + US3④ 钉死）；
  H2 `.mbti` 对账订正（baseline/plan 交付态口径，见 baseline 订正节）；
  M3 US6 补③ `derive_close=false` 毒化单点判别 + 错误断言收窄；
  M4 WB④d 循环内轮间 guard 位置 + 同 host 不归还身份判别（修复前
  guard 提到 while 外仍绿、release+reacquire 计数不变混淆均消除）；
  M5 FR-011 js「同形编译＋浏览器短路」口径订正（spec 三处 + 映射表）；
  M6 降级三头线上断言收窄为 CT 判别（CL/TE 线上缺席为结构性保证，
  去除行为由 WB⑦ 承载）；M7 SC-004/T019 观测面分层措辞（同 host 半边
  = 请求行+头表级，非原始字节）；M8 spec/plan/research `M3/11` →
  `M2/11-cookies` 对齐 roadmap；M1 followRedirects/followSslRedirects
  补登 P08 范围 + deferred-items F21；M2 codemap/文件头注释 spawn 换靶
  订正；Low：307/308 GET/HEAD Stream 判定前置（Edge Cases 对齐）、
  304/305/306 黑盒带 Location 判别、exchange.mbt FR-007→FR-009 引用
  订正、checklists/requirements.md 中文化（宪法 VII）。
  （产出 2026-10-28：native/wasm 各 **276/276** 全绿（272 + 本批新增
  WB⑧/WB④d/US6 补③/US3④ 四条，均先红后绿设计、首跑即绿——修复
  先于新断言落地归因已入各测试头注释）；`moon check
  --target native/wasm --deny-warn` 干净；js 13 errors 与基线同形
  （全在 P03 夹具 raw_peer/scripted_server 两文件，零新增失败点）；
  fixtures `.mbti` 语义增量 = `captured_request_heads`（T019）+
  `Truncated(ResponseScript, Bool)`/`mount_truncated derive_close?`
  （本批，contracts §3 第二次登记例外），随 P06 交付入库——宪法 VI
  有意识决定载体见 plan「`.mbti` 对账基线口径」订正节）

## Dependencies & Execution Order

```text
Phase 1 (T001 基线)
  └─▶ Phase 2 Foundational: T002 ─▶ T003 ─▶ T004     （接缝→循环直通，串行）
         └─▶ Phase 3 US1: T005 ─▶ T006 ─▶ T007        （降级→prior→保持行）
               ├─▶ Phase 4 US2: T008 ─▶ T009          （依赖 T005 决策表骨架）
               ├─▶ Phase 5 US3: T010                  （依赖 T005 resolve 门）
               ├─▶ Phase 6 US4: T011                  （依赖 T005 rewrite_headers）
               └─▶ Phase 7 US6: T012 ─▶ T013          （依赖 T004 advance 路径）
                     └─▶ Phase 8 US5: T014 ─▶ T015    （依赖 T012 排干/计数序）
                           └─▶ Phase 9: T016 ∥ T018 → T017（收口对账压轴）
                                └─▶ Phase 10: T020 ∥ T021（文档面）；
                                    T019/T022 代码面按 owner 分流串行
```

- **阻塞面**：Phase 2 未完成前不得开始任何 US 任务；T017 必须最后
  （六门对账）。
- **可并行窗口**：US2/US3/US4 三故事在 T005 完成后可并行（各自独立
  夹具场景、同包文件需按任务串行提交）；T016/T018 与彼此并行。
- **同文件约束**：`call_test.mbt` 多任务增补（T005–T015）按阶段顺序
  串行执行避免冲突；白盒 `follow_up_wbtest.mbt`（T002/T003/T004/
  T014/T016）同理。

## Implementation Strategy

- **MVP = Phase 1–3（T001–T007）**：US-1 交付「降级跟随 + prior 链」
  即为可用增量（决策表最高频行 + 循环机制 + 取消 guard 全部在场）。
- **增量交付**：每 Phase 收尾跑双 target `moon test` 绿后再进下一
  Phase；宪法 IV 红绿对在每个任务内闭合，不允许跨任务欠红。
- **对拍锚点**：实现期随手对照 research R1 行号锚点与 data-model
  真值表，禁止凭记忆写 5.5.0 行为（两处种子过时口径即前车之鉴）。
