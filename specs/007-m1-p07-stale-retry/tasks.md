---

description: "Tasks for M1-P07 stale-retry"
---

# Tasks: 连接失败重试 stale-retry（M1-P07）

**Input**: Design documents from `/specs/007-m1-p07-stale-retry/`
（plan.md + spec.md + research.md R1–R11 + data-model.md + contracts/retry-api.md）

**Prerequisites**: P01–P06 已交付（006 分支链）；分支
`007-m1-p07-stale-retry`；T0 基线＝native/wasm check+test 全绿
（276/276）、js check 基线红（13 既有错误，过门＝零新增）。

**Tests**: 宪法 IV 测试先行——每个故事先写失败测试（红）再实现
（绿）；命名 `P07-<域><序> 描述`；断言优先
`assert_eq`/`assert_true(err is …)`。

**Organization**: 按用户故事分组；US-1/US-3 为 P1（先做），US-2/US-4
为 P2。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 可并行（不同文件、无未完成依赖）
- **[Story]**: US1/US2/US3/US4（对应 spec 用户故事）

## Phase 1: Setup（共享基建）

**Purpose**: 骨架文件 + moon.pkg + 语义钉用例；全部故事的前置

- [x] T001 探针：核实 `Capture` 变体 canned 200 帧形态（读
      src/internal/fixtures/raw_peer.mbt:302-313 与 canned_response
      构造），确认带 Content-Length 且无 `Connection` 头 ⇒ R7 优先
      路径（两跳 run()）成立；不合则后备路径（新增变体）并回记
      research R7。仅记录结论，不改代码
      ✅ 证据：raw_peer.mbt:147 `canned_response = b"HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n"`——带 CL:0、无 Connection 头 ⇒ R7 优先路径成立；Capture 分支（:302-313）serve→close 即静默关闭形态。结论：US-1①②③ 走优先路径；T010④ 需 conn2 服务 301，Capture 帧源不可达 ⇒ 引入 ServeSequence 变体（spec Assumptions 夹具扩展授权，备注见 T010）
- [x] T002 创建判定器骨架三文件——src/client/recover.mbt（SendStage/
      ErrFamily/RetryDecision 枚举 + `decide` 存根恒 Fail）、
      src/client/recover_family.mbt（`error_family(stage, err)` 存根
      恒 Other）、src/client/recover_family.js.mbt（同签名降级恒
      Other）；src/client/moon.pkg 增 3 个上游包 import + 新增
      `options(targets: ...)` 表将 recover_family.mbt 锁
      [native, wasm]（recover_family.js.mbt 由后缀自动锁 js）；
      `moon check --target native` 与 `--target wasm` 零错误零警告
      ✅ 证据：三文件 + moon.pkg（3 import + targets 表）落位；`moon check --target native|wasm` 0 错误；警告 7 条均为骨架期 unused（decide/error_family/枚举变体 lib 侧未接线，T004/T006 红测试先行消费后剩余项在 T008/T009/T011 接线点归零）——零警告门随 T011 接线达成，无抑制豁免
- [x] T003 [P] 白盒钉用例：errdefer 正方向语义（内层 `for ;;` 逸出
      raise 触发轮级 errdefer、continue 不误触发）入
      src/client/follow_up_wbtest.mbt（P07-WB⑨，qod-2 探针的仓内
      固化；预期直接绿——钉语义非测新行为）
      ✅ 证据：P07-WB⑨ 落笔即绿（钉语义）；`moon test --target native` 退出码 0，287/287（红批同跑：283/287，4 红恰为 T004/T006 的 Retry 期望组 WB③⑥⑦⑩）

**Checkpoint**: 骨架编译绿、js 错误数与基线 diff 为零、语义钉用例绿

## Phase 2: Foundational（判定器与字段基建，阻塞全部故事）

**Purpose**: 决策函数全分支可测 + 字段/入口就位

- [ ] T004 [P] [红] 判定矩阵白盒测试入 src/client/recover_wbtest.mbt
      （P07-WB①..⑧）：按 data-model 实体 3 全分支——cancel 优先、
      开关关、attempts≥2、Protocol、Other、`replayable` 门（None/
      Bytes 恒真、Stream∧entered 假、Stream∧¬entered 真）、
      Connect∧{Stale,ConnectFailure}→Retry、Send∧Stale→Retry、
      ReadHead∧Stale→Retry、收尾兜底行 Fail；用 @io.ReaderClosed/
      @os_error.OSError 可构造值；预期红（decide 存根恒 Fail）
- [ ] T005 [绿] 实现 `decide`（src/client/recover.mbt）按
      data-model 实体 3 矩阵（含 replayable 辅助）——T004 全绿
- [ ] T006 [P] [红] 族检测直测（可构造族）入
      src/client/recover_wbtest.mbt：ReaderClosed/OSError ×
      stage∈{Connect,Send,ReadHead} → ConnectFailure/Stale 归类、
      未知错误 → Other；预期红（存根恒 Other）
- [ ] T007 [绿] 实现 `error_family`（src/client/recover_family.mbt）：
      Protocol 首判（@http.BadRequest/HttpVersionNotSupported/
      IncorrectBodyLength）→ Connect 段 {OSError, ResolveHostnameError,
      TlsError, ConnectionClosed}→ConnectFailure → Send/ReadHead 段
      {ReaderClosed, OSError, ConnectionClosed, TlsError}→Stale →
      Other；js 文件保持恒 Other；T006 全绿。诚实边界注释：TLS 族/
      ResolveHostnameError 分支跨包不可构造（pub 非 pub(all)），M1
      无注入通道，集成侧不可达（research R4）
- [x] T008 字段与入口：src/client/http_client.mbt——`HttpClient::new`
      增尾随可选参 `retry_on_connection_failure~ : Bool = true` +
      HttpClient priv 字段 + Call 构造传入；Call 增 priv 字段
      `last_stage : SendStage`/`stream_body_entered : Bool`；
      src/client/client.mbt 增 priv `ConnectionPool::note_stale_hit`
      （`sync_lock_or_abort` 锁形态，锁内 `inner.stale_evictions += 1`，
      无 IO 无 await）；`moon check` 双 target 绿（既有 72 处
      HttpClient::new 调用点零改动兼容）
      ✅ 证据：`moon check --target native|wasm` 0 错误（尾随可选参零改动兼容实测——全部既有调用点未动）；警告 8 条均为 T011 消费项（note_stale_hit/三字段/Retry/Fail/decide/error_family 未接线）；`HttpClient::new` 新形态零回归
- [x] T009 阶段标记插桩：src/client/exchange.mbt——request(:122)/
      write_once(:127)/filler(:129)/end_request(:135) 四调用点前置
      `self.last_stage = …` 赋值；filler 调用前置位
      `self.stream_body_entered = true`（R3 保守口径：调用即置位）；
      逸出行为零变化；`moon test --target native` 既有 276 用例
      全绿（零回归证据）
      ✅ 证据：四调用点前置赋值 + filler 置位落位（逸出行为零变化，纯 O(1) 赋值）；`moon test --target native` 退出码 0，287/287（基线 276 + P07-WB 11 全绿，零回归）

**Checkpoint**: 判定器全分支绿、字段/入口就位、零回归

## Phase 3: User Story 1——陈旧连接自动恢复（P1）🎯 MVP

**Goal**: 预热→静默关闭→execute 自动换新连接重放成功；
stale_evictions==1；池守恒；重放字节一致

**Independent Test**: `moon test --target native` 过滤 `P07-US1`——
仅凭本故事即验证闭环（M1 判据之二）

### Tests for User Story 1 ⚠️ 先红后绿

- [x] T010 [红] [US1] 集成测试入 src/client/call_test.mbt
      （P07-US1①..④）：①预热（execute+读尽体回池）→
      `ScriptedPeer` run1（Capture serve→close 静默关闭）→ 二次
      execute 自动重试 → run2 承接新连接 → 终态响应正确、无错误暴
      露（编排约束按 research R7：串行、timeout_ms 放宽、读尽回
      池）；②`stale_evictions()==1`、旧连接未回池、守恒恒等式
      （per_host_total/idle/closed 计数）；③两次 CapturedRequest
      逐字节一致（SC-004）+ `fold_count` 白盒断言不变（同代次零重
      折叠）；④重试+301 叠加：stale 恢复后跟随 301 → 终态正确、
      prior 链深 1、跳数语义与 P06 一致（SC-006）；预期红（子循环
      未接线，二次 execute 直接抛 ReaderClosed）
      ✅ 红证据：`moon test --target native` 退出码 2，291 用例 4 红——P07-US1①②③④ 全红，二次 execute 抛 OSError("connection aborted"，Windows 宿主静默关闭读形态，R1/E5 观测清单口径，与 ReaderClosed 同入 Stale 族）
      ✅ 绿证据：`moon test --target native` 退出码 0，291/291；`moon test --target wasm` 退出码 0，291/291（US-1 边界双 target）
      📝 备注①（夹具增量，spec Assumptions「夹具扩展」授权）：T010④ 需同一重试新连接先回 301 再回 200，Capture 单帧 200 形态不可达 ⇒ fixtures/raw_peer.mbt 新增 `ServeSequence(Array[Bytes])` 变体（同连接 keep-alive 逐帧上线、耗尽即静默 close，.mbti 增量随 T019 对账）；R7 优先路径仍完整承载 ①②③（探针结论见 T001）
      📝 备注②：②的「探针第三次 execute 判旧连接未回池」不可达——Capture 每连接 serve 后即静默关闭，回池的 conn2 亦为死连接；旧连接未回池与三集合守恒改由白盒伴随用例 P07-WB⑫ 精确判别（idle 1/closed 1/borrowed 0 == per_host_total 2）
      📝 备注③：③的 fold_count 断言为 priv 字段（call_test.mbt 黑盒作用域不可达）——由 P07-WB⑫ 白盒承载（R10「fold_count 白盒断言或捕获对端」的后者+前者分解）
      📝 备注④：④的 follow-up 取证改 `raw_text().find("GET /b")`——ServeSequence 多请求捕获的 raw 为累计字节（assert_matches 的 0 位前缀判据只适用单请求 run）

### Implementation for User Story 1

- [x] T011 [US1] [绿] 轮内尝试子循环接线：src/client/follow_up.mbt——
      轮级 errdefer 上移至取消 guard 之后子循环之前（单点登记）；
      `for ;;` 子循环体首行复位 `last_stage`/`stream_body_entered`
      + attempt 级取消 guard；ensure_lease 段 try/catch
      （family→decide→Retry continue / Fail raise）；exchange 段
      try/catch（Retry 分支：`poison_release()` →
      `(ReadHead∧Stale)` 时 `note_stale_hit()` → continue；Fail：
      `raise err` 原样）；不触碰 follow_ups/gen/决策表/prior 链；
      T010 全绿 + 既有 276 用例零回归
      ✅ 证据：接线按 R1 伪码落地（errdefer 上移/体首行复位/attempt guard/两捕获段 family→decide→分支次序）；`moon test --target native` 291/291（含既有 276 零回归）、`--target wasm` 291/291；`moon check --target native|wasm` 0 警告 0 错误（T002 骨架期未接线警告全部归零）
      📝 备注（P07 语义更新波及的既有用例适配，2 处）：P05-US5⑥ 与 P05-WB⑯（AcceptClose 单连接断连注入）——stale 族断连现触发重试，单 run 编排会令重试尝试连入无 accept 的监听队列而悬挂（F18 串行 accept 约束），且「毒化路径不新建 per_host_total==1」断言与 FR-005 重试换新连接直接冲突；两用例按「串行双 run + 两尝试耗尽透传 + 每尝试 +1 守恒口径」更新并注记，判据意图（错误透传/毒化不回池）保留

**Checkpoint**: US-1 独立可验（M1 闭环判据达成）

## Phase 4: User Story 3——不可重试分类（P1）

**Goal**: 不可安全重放的失败原样透传，毒化照常、零误计

**Independent Test**: `moon test --target native` 过滤 `P07-US3`

### Tests for User Story 3 ⚠️ 先红后绿

- [x] T012 [红] [US3] 集成测试入 src/client/call_test.mbt
      （P07-US3①..⑥）：①B-11 PartialResponse MidHeaderLine →
      `err is @http.BadRequest` 原样透传、对端仅见一次发送尝试、
      毒化（同址后续请求建新连接）、`stale_evictions()==0`；
      ②B-11 Nothing/15B/17B 三形态 → ReaderClosed 重试成功（F17
      实测口径）；③Stream 体 + AcceptClose → 已进入发送 ⇒ 不重
      试、错误 ∈ {ReaderClosed, OSError} 透传、对端单连接；④
      Content-Length 谎报 → `IncorrectBodyLength` 透传 + 毒化；
      ⑤execute 中 cancel → 裸 `err is CallCancelled`（含重试轮间
      cancel：第一次 stale 后、第二次尝试前取消）；⑥预算耗尽：强
      制两次失败 → 透传最后一次原始错误、attempts 恰 2；预期红
      ✅ 红证据（红重放，git checkout 48403eb -- follow_up.mbt 后同批用例实跑）：`moon test --target native -p .../client -f "P07-US3*"` 退出码 2——②红（execute 抛裸 ReaderClosed，无重试）、⑥红（stale_evictions==0≠1）；①③⑤ 同跑即绿＝护栏用例（Protocol 封锁/Stream 封锁/取消优先在 P05 既有语义已成立，本批钉「机器上线后不破」），红证据由 T004/T006 判定层矩阵与 T010 集成层红承载（US-3 与 US-1 共用同一子循环机器，宪法 IV 红绿对账见 R10）
      ✅ 绿证据：`moon test --target native` 退出码 0，298/298；`moon test --target wasm` 退出码 0，298/298（US-3 边界双 target）
      📝 备注①：④注入通道实测订正——Bytes 谎报在 core 构造期即拒（C3 裁决，不达发送段）；实际通道＝Stream 体 content_length=Some(99) 实写 3 ⇒ 发送期 @http.IncorrectBodyLength **原样透传**（P05 发送路径无映射，FR-008 透传原始错误值口径）；族检测 @http.IncorrectBodyLength→Protocol 正确承接
      📝 备注②：⑤的「第二次尝试前取消」进程内确定注入不可得（两尝试之间为同步代码段、无 await 交错点）——构造等价性归约（P06-WB④c 先例口径）：其观测面（裸 CallCancelled＋不入重试分支＋零计数）由⑤的填充器同步 cancel 端到端钉住（decide 首条件），不静默偏离语义

### Implementation for User Story 3

- [x] T013 [US3] [绿] 差距修补（T011 机制已覆盖大半）：核对 Fail
      分支逸出路径 errdefer 毒化、cancel 在捕获分支的优先（decide
      首条件 + attempt guard）、`BadRequest` 判别形态按编译实况
      （`err is @http.BadRequest` 先例 scripted_peer_test.mbt:122）；
      T012 全绿
      ✅ 证据：核对结论——Fail 分支逸出毒化＝轮级 errdefer 单点（US3①④ 的探针新建判别通过即毒化在场）；cancel 优先＝decide 首条件（US3⑤ 端到端通过：裸 CallCancelled＋零新建＋零计数）；判别形态 `err is @http.BadRequest` 编译实况通过（US3①）；零代码修补需求——T011 机制全量覆盖，T012 全绿（native/wasm 298/298 双绿）

**Checkpoint**: US-1 与 US-3 同时独立可验（P1 完成）

## Phase 5: User Story 2——连接建立失败重试（P2）

**Goal**: 建连失败按预算重试、耗尽透传、池状态零变化

**Independent Test**: `moon test --target native` 过滤 `P07-US2`

### Tests for User Story 2 ⚠️ 先红后绿

- [x] T014 [红] [US2] 集成+元测试入 src/client/call_test.mbt
      （P07-US2①..③）：①无监听端口 execute → 透传最后一次原始
      错误（先行断言收窄：原始错误 + 池状态零变化 + 恰 2 次尝试——
      尝试计数以白盒 attempts 断言或观测代理）；②拒绝形态双 target
      观测记录（FR-015 同款元测试：native/wasm 各记录实际错误类
      型，钉定后补类型断言）；③`decide(Connect, ConnectFailure,…)`
      白盒已盖（T004），此处补 EnsureLease 捕获分支的接线断言（重
      试无毒化、`per_host_total` 不增长）；预期红
      ✅ 证据：`moon test --target native` 退出码 0，302/302（P07-US2①②③＋P07-WB⑬ 白盒伴随全绿）；US2② 观测打点＝native 实测 `OSError(ECONNREFUSED)`（R8 预期形态，wasm 形态随 wasm 套件运行补录）
      📝 备注①（红证据归属，显式记录）：US2 集成面无可黑盒观测的红形态——耗尽路径的透传/零状态断言在 P05 既有语义下即成立，1 次 vs 2 次拒绝在无服务端侧无可观测差（R2：先拒后收不可确定注入）；US2 的红证据＝T004 WB⑦（decide 层 Connect∧ConnectFailure→Retry 格）＋P07-US3⑥（恰 2 次尝试的服务端计数观测），集成用例定位为接线护栏（落笔即绿，宪法 IV 对账见 R10）
      📝 备注②：恰 2 次尝试的确定性观测代理＝US3⑥（双失败模式 + per_host_total==2 + 计数恰 1），本用例按 R8 先行断言收窄为「原始错误透传＋池状态零变化」

### Implementation for User Story 2

- [x] T015 [US2] [绿] 建连段捕获分支落实（T011 已含框架，补缺口：
      ensure_lease 重试 continue 路径与租约 None 断言）；T014 全绿
      ✅ 证据：核对结论——ensure_lease 段 Retry→continue 路径由 T011 接线承载（US2① 两尝试耗尽端到端走通）；租约 None 断言＝P07-WB⑬（call.lease is None + 三集合零污染，白盒直读）；零代码修补需求——T014 全绿（302/302）

**Checkpoint**: US-2 独立可验

## Phase 6: User Story 4——计数与观测（P2）

**Goal**: 计数精度（K 次注入恰 K）+ 开关面

**Independent Test**: `moon test --target native` 过滤 `P07-US4`

### Tests for User Story 4 ⚠️ 先红后绿

- [x] T016 [红] [US4] 集成测试入 src/client/call_test.mbt
      （P07-US4①..③）：①K=2 次独立 execute 各命中 stale 一次 →
      `stale_evictions()==2`（跨代次形态可选：stale 恢复后 301 再
      stale）；②非 stale 路径对照（BadRequest/Stream/耗尽/预算耗
      尽各 ≥1 次）→ 计数零误增；③开关
      `retry_on_connection_failure=false`：stale 注入 → 不重试、
      原错误透传、计数为 0；预期红
      ✅ 证据：`moon test --target native` 退出码 0，306/306；`moon test --target wasm` 退出码 0，306/306；US4② 元测试双 target 观测打点齐备（native+wasm 实测均 `OSError(ECONNREFUSED)`）
      📝 备注（红证据归属，显式记录）：US4 的计数/开关行为随 T011 一次成形（decide 首条件与计数单点同批接线），集成面无可分离的红形态——红证据＝T004/T006 判定层矩阵红（WB①②取消/开关格、WB③预算格）＋T010/T012 集成层红；US4 用例定位为计数精度与开关面的回归护栏（落笔即绿，跨代次 301 形态已由 US1④ 承载故①取 K 次独立 execute 主形态）
- [x] T017 [US4] [绿] 开关接线核对（decide `!enabled` 首条件已盖，
      补 `HttpClient::new` 参数传递链断言）；T016 全绿
      ✅ 证据：参数传递链断言＝P07-WB⑭（缺省 true/显式 false 落字段直读，priv 白盒）；端到端开关面＝US4③（零新建+零计数判别面）；T016 全绿（native/wasm 306/306 双绿）

**Checkpoint**: US-1..US-4 全部独立可验

## Phase 7: Polish & Cross-Cutting（收尾）

- [ ] T018 跨文档修订：specs/006-m1-p06-redirects/data-model.md D-2
      行加注（errdefer 唯一毒化归属点限于**错误逸出路径**，P07 修正
      2026-10-30）；src/client/codemap.md 订正「两错误变体」漂移 +
      补 recover 三文件职责
- [ ] T019 质量门全套（quickstart.md 六门）：`moon info && moon fmt`
      干净；`.mbti` diff 对账（恰为 HttpClient::new 可选参数一项，
      contracts §1）；`moon test` native+wasm 双绿；`moon check
      --target js` 与基线错误集 diff 零新增；结果证据行回填本文件
- [ ] T020 收尾提交（Conventional Commits 中文描述；汇报列明 commit
      范围）——后续 converge + open-code-review 由编排层执行

## Dependencies & Execution Order

- Phase 1 → Phase 2 →（US1 → US3 → US2 → US4）→ Phase 7
- T004/T006 与 T005/T007 是红绿对（先红后绿）；T010↔T011、
  T012↔T013、T014↔T015、T016↔T017 同理
- T002 先于一切编译相关任务；T001 仅影响 T010 的夹具路径选择
- US 间严格串行（同一批文件、同一段循环，无真并行写面）

## Parallel Opportunities

- [P] 任务：T003（钉用例）与 T004/T006（红测试）互不依赖可并行；
  T004 与 T006 同文件不同用例组，可同批编写
- 单实现者场景下按序执行即可；本包无双写面 lane 可拆

## Implementation Strategy

- MVP＝Phase 1+2+3（US-1 闭环，M1 判据之二达成即可独立演示）
- 每个红绿对内先跑红证据（失败输出留痕）再实现；绿后立即
  `moon test --target native` 防回归，US 边界处加跑 wasm
- 任务内改动超预期（如 MoonBit 语法与伪码偏差）→ 停下回改
  plan/research 并记录，不得静默偏离 spec 语义
