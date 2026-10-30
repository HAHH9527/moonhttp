---
description: "Tasks for M1-P08 timeouts-builder"
---

# Tasks: 四类超时与 per-call 配置（M1-P08）

**Input**: Design documents from `/specs/008-m1-p08-timeouts/`
（plan.md + spec.md v2 + research.md R1–R12 + data-model.md +
contracts/timeout-api.md）

**Prerequisites**: P01–P07 已交付（007 分支链 tip 0fd273a）；分支
`008-m1-p08-timeouts`；moon.pkg 零改动（research R12）；T0 基线＝
native/wasm 全绿（306/306）、js check 基线红（13 既有错误，过门＝
零新增）。

**Tests**: 宪法 IV 测试先行——每个故事先写失败测试（红）再实现
（绿）；命名 `P08-<域><序> 描述`；断言优先
`assert_eq`/`assert_true(err is …)`；计时带不对称带（C1：native
[阈值−50, +300]ms、wasm [−50, +1000]ms，测量原点＝窗建立点，证据行
钉 δ）；睡眠预算每 target ≤10s（R9 表）。

**Organization**: 按用户故事分组；US-1/US-2/US-3 为 P1（先做），
US-4/US-5/US-6 为 P2；Foundational＝类型骨架/族落点/夹具变体
（阻塞全部故事）。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 可并行（不同文件、无未完成依赖）
- **[Story]**: US1..US6（对应 spec 用户故事）

## Phase 1: Setup（基线取证）

**Purpose**: 六门基线快照 + 落点行号快照；全部故事的前置

- [ ] T001 基线取证（只记录不改代码）：①六门现状快照——`moon test
      --target native|wasm` 用例计数、`moon check --target js` 错误
      数（基线 13）、client/core `.mbti` 当前公开面（FR-012 对账基
      线）；②落点行号快照——execute 组结构（http_client.mbt:190-227）、
      BodyPlan 枚举与分派（scripted_server.mbt:67-71）、PeerProgram
      指令枚举与 run 兜底（raw_peer.mbt:42-53/:259-262/:288/:466-468）、
      ensure_lease acquire 调用点（follow_up.mbt:220）、read_checked
      收口（body_bridge.mbt）、exchange 四调用点（exchange.mbt:127-147）
      ✅ 证据：①六门现状——native `moon test --target native` =
      306/306 全绿（exit 0）；wasm = 306/306 全绿（exit 0）；
      `moon check --target js` = 9 warnings, 13 errors（基线 13 持平，
      exit 1 为既有红）。`.mbti` 对账基线＝git HEAD
      （72e5edc）client/core pkg.generated.mbti 现状（FR-012 冻结前）。
      ②落点行号快照（2026-10-30 实测，与 plan/contracts 引用一致）：
      execute 组结构 http_client.mbt:190-227（with_task_group :190、
      Cancelled 收尾 :222-227）；BodyPlan 枚举 scripted_server.mbt:67-71
      （Framing :40-43，分派 serve_script :548）；PeerProgram 枚举
      raw_peer.mbt:42-53、run 兜底 :259-262/:288（with_timeout_opt 包裹）/
      :466-468（超时收尾 close）；ensure_lease acquire 调用点
      follow_up.mbt:220；read_checked 收口 body_bridge.mbt:137-161
      （内层读 :150）；exchange 四调用点 exchange.mbt:126（header
      request）/:132（Bytes write_once）/:139（Stream filler）/:147
      （end_request）

**Checkpoint**: 基线数字钉死（对照收尾 T028）；落点行号与 plan/
contracts 引用一致

## Phase 2: Foundational（类型骨架/族落点/夹具，阻塞全部故事）

**Purpose**: 类型与接缝就位 + FR-008 判定器承接 + 夹具两变体

- [ ] T002 类型骨架（http_client.mbt + follow_up.mbt）：①
      `HttpTimeout` suberror（四变体，derive(@debug.Debug) +
      extend to_repr 两件式）；② `Timeouts` struct（四 Int 字段带缺
      省 10_000/10_000/10_000/0，derive(Debug)）；③ HttpClient priv
      字段三枚（timeouts/follow_redirects/follow_ssl_redirects，
      `HttpClient::new` 签名不变、字面量补缺省）；④ Call priv 字段
      `call_timeout_fired`（new_call 初始化 false）；⑤
      follow_up_request 增 `follow_redirects~/follow_ssl_redirects~`
      参数（缺省 true 直通——现行为逐位不变）+ exchange_loop 调用点
      从 self.client 透传；`moon check` 双 target 零错误零新增警告、
      js check 与基线对账零新增
      ✅ 证据：实现落地（http_client.mbt：HttpTimeout 四变体两件式
      derive+extend、Timeouts pub(all) 四字段 + default() 包内缺省
      单点、HttpClient priv 三字段、Call.call_timeout_fired 入态清零
      + Cancelled 收尾标记选择〔骨架期标记恒 false ⇒ 现状逐位〕；
      follow_up.mbt：follow_up_request 增两参缺省 true 直通 + 调用点
      透传）。`moon check --target native` = 0 errors / 4 warnings
      （骨架过渡：unused 构造 Connect/Write/Read ×3 + timeouts 字段
      未读 ×1——均随 T007–T013 接线自灭，最终态零告警）exit 0；
      `--target wasm` 同 0 errors / 4 warnings exit 0；
      `moon check --target js` = 13 errors（基线 13 持平零新增）；
      `moon test --target native` = 306/306 全绿（INV-T5 首证——缺省
      直通零扰动）。【现场订正】data-model 实体 1 的
      `connect_ms : Int = 10_000` 字段缺省值语法不被本工具链支持
      （moon 0.1.20261023 实测 parse error）——语义不变，缺省改由包内
      `Timeouts::default()` 单点落地（HttpClient::new/new_builder/
      builder() 构造点引用；与 004 DEFAULT_MAX_IDLE 常量先例同形），
      结构体改 pub(all) 供调用方字面量构造（builder .timeouts() 派生
      面原料）
- [ ] T003 [P] [红] 判定器族落点矩阵 WB 入 src/client/recover_wbtest.mbt
      （P08-WB①..，S6 收敛口径）：`HttpTimeout` 四变体 × 可达段——
      Connect∧Connect→ConnectFailure（可重试族）、Send∧Write→Other、
      ReadHead∧Read→Other、Call 变体×任意段→Other（伞取消不经
      catch，结构保证）；不可达格（Connect∧{Write,Read,Call}、
      Send∧Connect、ReadHead∧Connect）断言族=Other（钉不回归）；预
      期红（error_family 无 HttpTimeout 分支 ⇒ Connect∧Connect 格落
      Other，红恰 1 格）
      ✅ 红证据：`moon test --target native -p
      hahh9527/moonhttp/client` = **exit 2，Total 138, failed 1**——
      失败恰为 P08-WB① 首断言格「Connect∧HttpTimeout::Connect →
      ConnectFailure」（error_family 无 HttpTimeout 分支 ⇒ 落 Other，
      红恰 1 格与预期一致）；P08-WB② 不可达格 7 断言全绿（现状落
      Other 钉位）；Send∧Write/ReadHead∧Read/Call×3 段共 6 断言现状
      已 Other（绿伴随）。
- [ ] T004 [绿] 实现 error_family HttpTimeout 分支（src/client/
      recover_family.mbt）：`err is HttpTimeout` 时按变体分派——
      Connect 且 stage=Connect ⇒ ConnectFailure，余 ⇒ Other（插入位
      置在既有 Protocol 首判之后、具体类型并集之前——qod-2 零遮蔽
      核实）；decide 零改动——T003 全绿
      ✅ 绿证据：recover_family.mbt 增 `err is (HttpTimeout::Connect |
      Write | Read | Call)` 分支（Connect∧stage=Connect ⇒
      ConnectFailure，余 ⇒ Other；decide 零改动）。`moon test --target
      native -p client` = 138/138（exit 0，T003 红格转绿）；`--target
      wasm -p client` = 138/138（exit 0）；`moon check --target js` =
      13 errors 基线持平；全量 `moon test --target native` = 308/308
      （306 既有 + 2 新增 WB，既有回归零失败——INV-T5 复证）
- [ ] T005 [P] 夹具两变体（contracts §3 落点）：①
      scripted_server.mbt BodyPlan 增 `DripHang(block_bytes, blocks,
      interval_ms)`——按 Drip 节奏滴 blocks 块后 sleep 保持（保持时
      长 ≥ 客户端读窗 + 断言余量，与每操作超时保护协调）；②
      raw_peer.mbt PeerProgram 增 `SilentReader`——极慢读请求体、程
      序存活期内不主动关连；fixtures 包内最小自测各一（DripHang 滴
      后保持可观测、SilentReader 存活期内连接不关）；
      `moon test --target native -p …fixtures` 绿
      ✅ 证据：DripHang 落点 BodyPlan（serve_script 分派臂 + 承诺口径
      Fixed=blocks+1 块/Chunked 不发终止块；保持形态=阻塞 read_request
      等下一请求/EOF——「sleep 保持」会拖 serving.wait() 至兜底到期，
      违背睡眠预算，行为判据不变：滴后零字节下发、存活期不关连，
      R8/S8 权衡落点如实注记）；SilentReader(interval_ms) 落点
      PeerProgram（8B/interval 慢读、零 close——收尾只经对端 EOF 或
      run 兜底）。最小自测各一：P08-FIX①「滴 K 块后静默保持（读超时
      而非 EOF）」（滴流段 2048B 累计收齐 + 600ms 静默 None 判据）；
      P08-FIX②「SilentReader：极慢读、存活期内连接不关」（600ms 读
      超时 None 非 EOF + 零关连 note）。`moon test --target native -p
      internal/fixtures` = 48/48（exit 0，46 既有 + 2 新增）；
      `--target wasm -p internal/fixtures` = 48/48（exit 0）。
      【现场订正】read_some 片边界不与块边界对齐（首片实测
      983+41=1024 两片）——自测以累计总量判据，不假设片=块

**Checkpoint**: 骨架编译双 target 绿、js 零新增、族落点矩阵全绿、
夹具变体自测绿；全部既有用例回归绿（缺省直通零扰动——INV-T5 首证）

## Phase 3: User Story 1 - 四类超时各自触发（Priority: P1）🎯 MVP

**Goal**: 慢读/慢写/慢全程在对应阈值触发且变体可判别（连接伞为判
定器单元级+白盒伴随口径，R3）

**Independent Test**: B-01 头延迟/SilentReader/301 链 × 阈值配置 →
`err is` 命中对应变体且 C1 计时带内

- [ ] T007 [P] [红] [US1] 读窗收头场景入 src/client/call_test.mbt
      （P08-US1②）：B-01 头延迟 2000ms + read_ms=500 → `err is
      HttpTimeout::Read`、计时带 [450, 800]ms（C1）；1xx+慢头共享收
      头单窗钉用例（C4/S9：F-8 interim 后接 head_delay，总收头超窗
      ⇒ Read——单窗语义反证「每读重置」）；预期红（end_request 未
      包窗 ⇒ 无 Read 变体）
      ✅ 红证据：红批（T007/T009/T012 共 5 用例）同批落笔后
      `moon test --target native -p hahh9527/moonhttp/client` =
      **exit 2，Total 146, failed 5**（141 过=既有零扰动）。本任务
      两用例红因：①US1② 读窗——`终态应恰为 HttpTimeout::Read` 失败
      （无窗 ⇒ 慢头 200 正常返回）；②US1② C4/S9——`收头单窗（含
      1xx 跳读）终态应恰为 Read` 失败（同上）
- [ ] T008 [绿] [US1] exchange.mbt 收头接点：`end_request` 调用外包
      `with_timeout(read_ms, ..., error=HttpTimeout::Read)`（单窗含
      1xx 跳读，C4；last_stage=ReadHead 既有前置赋值不变）——T007
      全绿
      ✅ 绿证据：exchange.mbt 收头接点落地（read_ms>0 ∧ 协程非取消态
      ⇒ with_timeout(read_ms, end_request, error=HttpTimeout::Read)
      单窗；0 不建窗）。`moon test --target native -p client` =
      146 中 **143 过 / 3 红**（3 红恰为未实现的写窗 US1③与 call 伞
      US1④×2——T009/T012 预期红保持）；US1② 两用例（慢头/1xx+慢头）
      转绿，变体 Read + C1 带内。【δ 首片实测】execute 总耗时
      514ms ⇒ **δ(入口→读窗建立)=14ms**（native，回环夹具；含
      ensure_lease 建连+折叠+发头）。【上游适配取证】红转绿过程中
      发现并修复一处上游交叠锐边：协程已处取消态（用户 cancel 自
      filler 内同步发出）时构造 with_timeout 组触发上游运行时
      PanicError(0xc0000409)——probe 三连取证（纯 with_timeout 正常/
      f 同步抛错正常/真实 end_request×取消态崩溃）后，窗条件加
      `!@async.is_being_cancelled()`（此际 end_request 直调即抛取消
      ——与 T008 前逐位一致）；P07-US3⑤ 裸 CallCancelled 回归钉
      证明。关联窗口（写窗/连接伞/call 伞）同款防护随 T010/T011/T013
      落地。
- [ ] T009 [P] [红] [US1] 写窗场景入 src/client/call_test.mbt
      （P08-US1③）：SilentReader（run timeout_ms 覆盖 > 写窗+余量）
      + Stream 体分块 filler + write_ms → `err is HttpTimeout::Write`
      + 计时带；**首片定标义务**（B2③/S8）：体量/节奏/write_ms 满
      足三段不等式（停滞填满 < write_ms < 夹具兜底），红因判据=未
      停滞或 OSError 误现，定标结论回填 research R9 表；预期红
      ✅ 红证据：同上红批 run（exit 2，146 中 failed 5）。本用例
      红因=OSError 误现：无写窗 ⇒ 客户端停滞至夹具兜底 3s 关连 ⇒
      P07 (Send,Stale) 判定（Stream 不可重放 ⇒ Fail）⇒ OSError 透传
      ⇒ `终态应恰为 HttpTimeout::Write` 断言失败——红因判据与预期
      逐字吻合（停滞成立、无 OSError 误判为「未停滞」）。
      ✅ 绿证据：T009 写窗场景转绿（同 T010 证据行）：SilentReader(50)
      + Stream 64 块×16KB=1MB 分块 filler + write_ms=500 ⇒ Write 变体
      C1 带内触发。**首片定标（B2③/S8 三段不等式）**：体量 1MB ≫
      回环 socket 缓冲（~64KB 量级，停滞毫秒级填满） < write_ms=500ms
      < 夹具兜底 run timeout_ms=3000ms；红因判据复核=停滞成立且绿路
      无 OSError 误现（Write 变体直达）。定标结论回填 research R9 表
      （US-1-3 行：~0.6s/场景）。
- [ ] T010 [绿] [US1] 写窗三接点：①新建 src/client/timeout_writer.mbt
      ——priv 门面实现 `@io.Writer` 三方法（全覆写），各包
      `with_timeout(write_ms, ..., error=HttpTimeout::Write)` 后委
      托内层 conn 自身方法（单窗无嵌套，R3 注记）；②exchange.mbt：
      header `request` 包窗、Bytes `write_once` 包窗、Stream
      `filler(门面)` 实参替换——T009 绿（门面委托 WB 断言入
      timeout_wbtest.mbt）
      ✅ 绿证据：①新建 src/client/timeout_writer.mbt——priv 门面
      TimeoutWriter 实现 @io.Writer 三方法全覆写（阻断缺省实现经门面
      write_once 的递归嵌套），各包 with_timeout(write_ms, ...,
      error=HttpTimeout::Write) 后经 `@io.Writer::write*(inner, ...)`
      显式 trait 调用委托内层 conn 自身方法（单窗无嵌套——R3 注记）；
      ②exchange.mbt 三接点：header request 包窗 / Bytes write_once
      包窗 / filler(TimeoutWriter) 实参替换（write_ms=0 不建窗——
      INV-T1；取消态直调——T008 上游适配同款）。US1③ 写窗场景转绿
      （Write 变体 + C1 带内；三段不等式定标：停滞填满（回环缓冲
      ~64KB，毫秒级） < write_ms=500 < 夹具兜底 3000——回填 research
      R9 表）。【连带修复（取消映射，FR-002a 对称面）】写窗使「写中
      取消」路径可能先见真实错误（cancel 同步 poison_release 关连后
      窗体内挂起写以 conn closed 失败）而非取消——exchange_loop 两
      捕获分支 Fail 路按取消态归一裸 CallCancelled（P05-US3②/P05-
      WB⑩ 回归钉转绿；P08 前取消沿 await 原生传播，本映射恢复既有
      可观测行为，decide 取消优先语义不变）。`moon test --target
      native -p client` = 146 中 144 过 / 2 红（红=US1④×2 call 伞
      T012 预期红保持）
- [ ] T011 [P] [US1] 连接伞接线 + R5 竞态收敛白盒：①follow_up.mbt
      ensure_lease 的 `pool.acquire(addr)` 外包
      `with_timeout(connect_ms, ..., error=HttpTimeout::Connect)`
      （FR-002 有界例外②；每 attempt 新伞）；②timeout_wbtest.mbt
      竞态收敛断言（US-1-1/US-3-3 载体）：极小 connect_ms × 真实回
      环 acquire 竞速循环——终态二择一（成功 ∨ `HttpTimeout::Connect`）
      + 池计数守恒每轮成立（INV-T3，含锁等待支——S3）；接线伴随=
      结构审判据注记（OCR 检查项，R3 诚实边界）；触发面不可注入
      口径保持（端到端 Connect 无断言义务）
      ✅ 证据：①follow_up.mbt ensure_lease 连接伞落地（connect_ms>0 ∧
      协程非取消态 ⇒ 伞包裹 acquire；0 不建窗；每 attempt 新伞）。
      ②timeout_wbtest.mbt P08-WB⑥ 竞速收敛白盒（connect_ms=1ms ×
      真实回环 ×10 轮 ×双 target）。**【R2 机制 implement 级订正——
      WB⑥ 实证抓漏】**：research R2 原定 `with_timeout` 整包
      acquire 形态存在 R5 孤儿租约竞态——伞到期取消 body 时，
      acquire 若已越过末个暂停点（记账锁无竞争 fast-path）则同步
      记账尾不可中断 ⇒ 记账完成而租约被组丢弃 ⇒ borrowed 悬挂
      （白盒第 8/4 轮实测复现，native/wasm 双现，恰为「US-3-3 收敛
      断言兜底行为面」设计用途）。订正为看门者同型（R1 三步序伞侧
      镜像）：子任务跑 acquire + 定时器到期 child.cancel() + wait()
      交付——**记账完成 ⇒ 租约必达**（wait 拿到值，连接照常使用）；
      **建连在途被截断 ⇒ WaitedTaskAlreadyCancelled ⇒
      HttpTimeout::Connect**（记账零发生：记账锁 await 取消安全
      mutex.mbt:39-41 + 建连 await 构造器 errdefer 清理）——INV-T3
      两支恒成立，FR-006/US-3-3「副作用必达或显式撤销」闭合。真实
      建连失败沿 wait 原样透传（P07 建连族判定不受影响）。
      【判据口径（spec Edge Cases 退化阈值条款）】终态有序（成功 ∨
      HttpTimeout 变体之一）+ 池守恒每轮 + 无 borrowed 悬挂——不赌
      计时赢家（满载下 1ms 伞可整轮 Connect；已交付连接的后续段可
      被读窗收束——客户端行为合规，端到端 Connect 无断言义务，R3）。
      `moon test -p client` 双 target 连续两轮 **145/147**（余 2=
      T012 call 伞预期红保持）；夹具 serve 窗 60s（负载形态登记：
      夹具寿命 MUST 覆盖最坏轮程）。
- [ ] T012 [红] [US1] call 伞场景入 src/client/call_test.mbt
      （P08-US1④）：「3 跳 301 × 每跳 head_delay 600ms」+ call_ms=
      1000 → `err is HttpTimeout::Call`、计时带 [950, 1300]ms；单
      轮慢对照（head_delay 2000ms + call_ms=1000 < read_ms 缺省）
      同判 `Call` 非猴 `Read`（阈值互不重叠的归属判别，B5 修订口
      径）；预期红（无看门者 ⇒ 3 跳正常完成）
      ✅ 红证据：同上红批 run（exit 2，146 中 failed 5）。两用例
      红因：①3 跳链——`call 伞到期终态恰为 HttpTimeout::Call` 失败
      （无看门者 ⇒ 三跳 ~1.8s 正常完成 200）；②单轮慢对照——`阈值
      互不重叠时终态应恰为 Call` 失败（无看门者 ⇒ 2s 慢头正常返回）。
      ✅ 绿证据：T013 看门者落地后两用例转绿：3 跳链 Call 变体 C1 带
      内；单轮慢对照同判 Call（归属判别——call_ms=1000 < read_ms 缺省
      10s，终态恰为 Call 非 Read）。【测试编写订正】首版链路
      Location 误指 /final（实为 1 跳慢 612ms 完成——伞未到期属正确
      行为）；订正为 /a→/b→/c→/final 真三跳（1.8s > call_ms）。
- [ ] T013 [绿] [US1] http_client.mbt 看门者 + 收尾变体选择（FR-002
      有界例外①）：execute 组内 `call_ms > 0` 派看门者（`sleep(
      call_ms) → call_timeout_fired = true → task.cancel()` 三步
      序——置位先于取消）；Cancelled 收尾分支（含
      WaitedTaskAlreadyCancelled 映射路）按标记选变体：真 ⇒
      `HttpTimeout::Call`、假 ⇒ 裸 `CallCancelled`（用户取消路径逐
      位不变——反向隔离）；标记一次性无复位（I-1）——T012 绿；看
      门者三步序 WB 断言入 timeout_wbtest.mbt（P08-WB：正常交付路
      看门者被组取消不算失败、标记不被置位）
      ✅ 绿证据：http_client.mbt execute 组内看门者落地（call_ms>0
      才派生；`sleep(call_ms) → 置位 call_timeout_fired → task.cancel()`
      三步序——置位先于取消；no_wait=true 即发即忘——组退出不收留
      睡眠中的看门者）；Cancelled 收尾分支按标记选变体（T002 骨架期
      已接线，标记恒 false 行为不变）。T012 两用例转绿；P08-WB⑦
      「正常交付路标记不被置位」绿（call_ms=5000 快请求交付 + priv
      直读标记=false——组取消不算失败的结构依赖证）。【骨架订正】
      T002 的入态清零移除（I-1「一次性无复位」口径——看门者写入点
      在场后 mut 有真实使用）；no_wait 遗漏由 WB⑦ 5s 悬挂+标记误置
      实证抓出（waited 看门者使组收尾拖满 call_ms）。`moon test
      --target native` = 321/321（exit 0）；`--target wasm` = 321/321
      （exit 0）——US1 全绿。

**Checkpoint**: US1 四变体触发全绿（native/wasm）；判定器矩阵与看
门者 WB 绿；计时带证据行含 δ 钉定；睡眠预算 ≤10s 复核（R9 表回填）

## Phase 4: User Story 2 - read 按操作重置（Priority: P1）

**Goal**: 持续滴流零超时、静默一窗触发——FR-003 按操作计时的行为
级证明

**Independent Test**: Drip（既有）/DripHang（新变体）× read_ms →
两态分野

- [ ] T015 [P] [红] [US2] 滴流两态场景入 src/client/call_test.mbt
      （P08-US2①②）：①read_ms=500 + Drip 5 块×200ms（总 ~1s）→
      完整读、零超时、内容逐字节一致；②read_ms=500 + DripHang 2 块
      后静默 → 一个读窗后 `err is HttpTimeout::Read`（计时带 C1）
      ；预期红（体读无窗 ⇒ 静默态不产 Read 变体）
      ✅ 红证据：（implement 回填）
- [ ] T016 [绿] [US2] body_bridge.mbt read_checked 内层读包窗
      `with_timeout(read_ms, ..., error=HttpTimeout::Read)`（毒化免
      费复用既有读错误路径——S5 零新增接线；`_get_internal_buffer`
      直通面不入判据——S4 注记）——T015 全绿
      ✅ 绿证据：（implement 回填）

**Checkpoint**: US2 两态全绿（native/wasm）；滴流场景耗时 ~1s 量级
（S8 预算内）

## Phase 5: User Story 3 - 超时后连接不回池（Priority: P1）

**Goal**: 任一超时触发点毒化守恒（US-3-1/2）+ 连接伞×建连竞态守恒
（US-3-3/R5）

**Independent Test**: 池计数断言（004 INV-5 + idle 不含 + 夹具连接
计数）；竞态收敛白盒（T011 已建，本故事钉守恒断言组）

- [ ] T017 [US3] 守恒断言组入 src/client/call_test.mbt（P08-US3①②
      ③）：①US1② 场景后断言 idle 不含该连接、borrowed→closed、
      借出+空闲+已关=累计新建（INV-5）、同址再请求建新连接（夹具侧
      计数）；②US2② 场景后同组断言（体读毒化——read_checked 路径
      生效证）；③写窗场景后毒化断言（轮级 errdefer 逸出路径）；与
      T011 竞态收敛白盒共同覆盖 INV-T3/T4；native/wasm 双绿
      ✅ 证据：（implement 回填）

**Checkpoint**: US3 守恒断言全绿；毒化四伞覆盖面闭合（写/收头/体读
/call 伞——call 伞毒化经取消链 poison_release，R4 结构保证，断言随
T022 竞争组）

## Phase 6: User Story 4 - per-call 配置派生（Priority: P2）

**Goal**: builder 双入口派生（共享池、标量覆盖）+ Request 派生保留

**Independent Test**: A/B 双 client 同池隔离断言 + Request 保留性断
言

- [ ] T018 [P] [红] [US4] 配置面 WB/单测入 src/client/timeout_wbtest.mbt
      + src/core/request_test.mbt（P08-US4 单元）：build() 负值
      abort（C5）、全缺省矩阵（FR-001）、builder() 派生继承快照（标
      量=被派生方当前值）、new_builder(pool) 全缺省、
      Request::new_builder 保留性（headers 逐项/tag 保留、换
      url/method/body、无超时位——C2）；预期红（HttpClientBuilder/
      Request::new_builder 未建）
      ✅ 红证据：红测试落笔后首查 `moon check --target native` =
      **exit 1（9 errors）**——编译级红（HttpClientBuilder/
      validate_timeouts/TimeoutConfigError/Request::new_builder 未建
      ⇒ unbound identifier 类错误；另含测试自身两处语法订正：
      struct update 用 `..` 非 `with`、Timeouts/ConnectionPool 无 Eq
      ⇒ 改逐字段对账/行为面对账）。
- [ ] T019 [绿] [US4] 实现配置面：①http_client.mbt `HttpClientBuilder`
      （字段全 priv）+ 双入口（`HttpClient::new_builder(pool)` 全缺
      省 / `HttpClient::builder()` 自派生——pool 引用共享、标量快
      照）+ 链式 setter 四枚 + `build()` 负值校验单点（abort，C5/
      004 先例）；②core/request.mbt `Request::new_builder`（同包字
      面量：headers 经 builder() 防御性回转、tag 保留——R6）——
      T018 全绿
      ✅ 绿证据：http_client.mbt 增 HttpClientBuilder（字段全 priv）+
      双入口（new_builder(pool) 全缺省 / builder() 自派生快照）+
      链式 setter 四枚 + build() 负值校验单点（validate_timeouts 纯
      函数 raise ⇒ build 捕获 abort，C5/004 先例）；core/request.mbt
      增 Request::new_builder（同包字面量 + headers.builder() 回转）
      **及 RequestBuilder::url setter**（「url 可换」的最小承载——
      既有 Builder 仅构造期收 url，US-4-2 验收强制可换；归 FR-012 ④
      派生面语义项组成部分，T028 对账时登记）。`moon test --target
      native` = 314/314（exit 0，310 既有 + 3 WB + 1 core）；
      `--target wasm` = 314/314（exit 0）；`moon check --target
      native` = 0 errors / 3 warnings（余 unused 构造 Connect/Write/
      Read——随 T008/T010/T016 接线自灭）
- [ ] T020 [US4] 派生隔离/共享黑盒入 src/client/call_test.mbt
      （P08-US4①②③）：A 默认 + B=builder 派生 call_ms=300 → 慢夹
      具（B-01 1s）B 触发 `Call`、A 正常完成；连接计数同池共享
      （A、B 顺序请求 per_host_total 单调不重复建连）；retry_on_
      connection_failure=false 覆盖仅影响 B（P07 ServeSequence：B
      遇 stale 透传、A 重试成功）；native/wasm 双绿
      ✅ 证据：（implement 回填）

**Checkpoint**: US4 全绿；冻结面③④语义面可对账（.mbti 终审在 T028）

## Phase 7: User Story 5 - 与取消/重试的交互（Priority: P2）

**Goal**: call 伞覆盖重试轮、取消优先不降、零误增、反向隔离

**Independent Test**: P07 ServeSequence × B-01 组合 + 取消时序对照

- [ ] T021 [红] [US5] stale×call 组合场景入 src/client/call_test.mbt
      （P08-US5①）：ServeSequence（先 stale 后成功）× 每轮 head_delay
      600ms + call_ms=1000 → `err is HttpTimeout::Call`（覆盖重试
      轮）+ `stale_evictions` 恰 1（零误增——FR-008 观测面）；预期
      红（无看门者 ⇒ 两轮后 200 正常返回；与 T012 同红批）
      ✅ 红证据：（implement 回填）
- [ ] T022 [US5] 取消竞争 + 反向隔离组入 src/client/call_test.mbt
      （P08-US5②）：①cancel@300ms + call_ms=1000 → 裸
      `CallCancelled`（反向隔离硬断言）；②cancel 于伞到期后注入 →
      `HttpTimeout::Call`；③竞争循环组（cancel 与伞到期近同时，N
      轮）→ 终态二择一 + TaskGroup 收敛（无悬挂协程）+ 池计数守恒
      每轮成立；T013 后全绿（T021 随之转绿）
      ✅ 证据：（implement 回填）

**Checkpoint**: US5 全绿；`stale_evictions` 零误增与反向隔离双断言
闭合（P07 承接三件套之二）

## Phase 8: User Story 6 - 跟随开关（Priority: P2）

**Goal**: 两开关关闭方向语义（F21 回补）；缺省路径逐位回归

**Independent Test**: 301 两态矩阵端到端 + 跨 scheme 决策级单元

- [ ] T023 [P] [红] [US6] 决策表两门 WB 入 src/client/
      follow_up_wbtest.mbt（P08-WB 门序矩阵，5.5.0 对拍）：follow_
      redirects=false × {301, 302, 307, 3xx 无 Location} → 一律
      Terminal；follow_ssl_redirects=false × {同 scheme 跟随、跨
      scheme Terminal}；门序断言（follow_redirects 门先于 Location
      门——resolve 不执行）；缺省 true 直通回归格（现行为钉死）；
      预期红（T002 直通骨架 ⇒ false 断言全红）
      ✅ 红证据：（implement 回填）
- [ ] T024 [绿] [US6] follow_up_request 两门实现（follow_up.mbt，
      5.5.0 门序：码集命中后、Location 门之前判 follow_redirects；
      resolve 成功后判 sameScheme——`target.scheme != request.url.
      scheme && !follow_ssl_redirects` ⇒ Terminal）——T023 全绿
      ✅ 绿证据：（implement 回填）
- [ ] T025 [US6] 301 两态端到端入 src/client/call_test.mbt
      （P08-US6①③）：follow_redirects=false + 301 夹具 → 301 终态
      返回（Location 头保留、`Response::prior() is None`——S7 判据
      载体、响应正常返回即跳数零消耗）；缺省 true 对照（现 301 场
      景零改动=回归保护）；跨 scheme 端到端不可达口径（M1 明文测
      试面）——判定级已由 T023 覆盖；native/wasm 双绿
      ✅ 证据：（implement 回填）

**Checkpoint**: US6 全绿（native/wasm）；F21 验收面闭合；缺省路径零
扰动复证（INV-T5）

## Phase 9: Polish & Cross-Cutting（收尾与跨切面）

- [ ] T026 文档回写四处：①docs/roadmap/M1/P08-timeouts-builder.md
      种子偏差 D 表八项逐项订正（spec Assumptions D 表）；②
      docs/roadmap/deferred-items.md + deferred-items/deferred-items-m1.md
      F21 状态→已回补（指向本包）；③specs/006-m1-p06-redirects/spec.md
      映射表行加注（开关已由 008 交付）；④README 超时配置段 + js
      降级注记（FR-011 用户文档面）
      ✅ 证据：（implement 回填）
- [ ] T027 [P] codemap 订正：src/client/codemap.md（timeout_writer/
      看门者/四伞接缝/族落点）+ 根 codemap.md 如需；`.slim/codemap.json`
      update 固化
      ✅ 证据：（implement 回填）
- [ ] T028 六门全量（quickstart.md 清单执行）：moon info && moon fmt
      干净、`.mbti` diff 恰 contracts §1 四项（FR-012/SC-010 对账）、
      native/wasm 全量绿（含既有回归——R11 预期零回归，意外逐条登
      记）、js check 错误数=13 基线零新增、断网复跑 native 全量
      （SC-009）、grep 审计（无外部地址、无敏感信息输出）
      ✅ 证据：（implement 回填）
- [ ] T029 converge 评估（speckit-converge 对 spec/plan/tasks 与实现
      一致性；缺口按裁决回改 spec 再传导）
      ✅ 证据：（implement 回填）
- [ ] T030 open-code-review 收尾（全量 diff 审查；发现按severity 回
      修或登记已知问题）
      ✅ 证据：（implement 回填）

## Dependencies & Execution Order

### Phase Dependencies

- **Setup（T001）**：无依赖，立即开始
- **Foundational（T002–T006）**：依赖 T001 落点快照；T002（骨架）→
  T003（红）→ T004（绿）串行；T005 夹具与 T003/T004 并行
- **US1（T007–T013）**：依赖 Foundational 完成；组内红绿交替——
  T007→T008（读窗）、T009→T010（写窗）、T011（连接伞，T004 后可
  行）、T012→T013（call 伞）；T007/T009/T012 红批可同批编写
- **US2（T015–T016）**：依赖 T005（DripHang）+ T008 无依赖冲突——
  体读窗与收头窗接点不同文件，可与 US1 后段并行
- **US3（T017）**：依赖 T008/T010/T016（毒化路径就位）+ T011（竞态
  白盒）
- **US4（T018–T020）**：依赖 T002 骨架；与 US1–US3 无语义依赖，可
  并行（文件不相交：http_client.mbt 例外——T013 看门者与 T019
  builder 同文件，串行避让）
- **US5（T021–T022）**：依赖 T013（看门者）+ P07 ServeSequence
- **US6（T023–T025）**：依赖 T002 骨架（增参直通）；与 US1–US5 并
  行可行（follow_up.mbt 与 T011 连接伞同文件——串行避让）
- **Polish（T026–T030）**：依赖全部故事完成；T029/T030 为包级收尾

### Parallel Opportunities

- 红批同批编写：T003、T007、T009、T012、T015、T018、T021、T023（各
  自文件不相交者标 [P]）
- 绿实现按接点分文件并行：T008（exchange）/T010（timeout_writer+
  exchange——与 T008 同文件串行）/T016（body_bridge）/T019（http_
  client+core）/T024（follow_up）
- 同文件串行避让对：T008→T010（exchange.mbt）、T011→T024（follow_
  up.mbt）、T013→T019（http_client.mbt）

## Implementation Strategy

### MVP First（US1 为 MVP）

1. Phase 1–2：基线 + 骨架 + 族落点 + 夹具（Checkpoint：零扰动复证）
2. Phase 3：US1 四变体触发 → 独立验证（四伞接线闭合）
3. STOP：US1 全绿后复核 INV-T1/T2（0=无窗、变体恰达）

### Incremental Delivery

1. Foundational → US1（MVP）→ US2 → US3（P1 三故事闭环）
2. US4 → US5 → US6（P2 配置面与交互）
3. Polish：回写 → codemap → 六门 → converge → OCR

### 红绿纪律（宪法 IV）

- 每故事先红后绿；红证据留 tasks 证据行（失败用例数/退出码）
- 不可注入分支（端到端 Connect）以判定器矩阵+竞态收敛白盒覆盖
  （R3/R5 口径），不建竞态注入夹具
- 计时带断言只入 US 层黑盒（WB 不断言耗时——防抖动侵蚀）

## Notes

- [P] 任务＝不同文件、无未完成依赖；同文件任务严格串行
- 计时带/定标类证据（δ、write_ms 三段不等式）必须落证据行（C1/S8
  义务）
- js 面零改动预期（R12）——若 implement 中出现 js 新增错误即回查新
  引用是否引入锁定包类型
- 每故事 Checkpoint 后可 commit（Conventional Commits 中文描述）
