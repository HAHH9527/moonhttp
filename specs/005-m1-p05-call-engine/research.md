# Research: Call 执行骨架与取消（M1-P05）

**Date**: 2026-10-24 | **Status**: 全部 NEEDS CLARIFICATION 已解决（C1/C2 为
spec 移交的 plan 核实项，本文 R1/R3 裁决并回记 spec）
**方法**：全部结论以本仓 `.mooncakes/moonbitlang/async@0.22.4` 源码与
`src/{core,client}` 冻结面为证据（路径:行号），不凭记忆断言。

## R1 上游取消底座（C1 裁决：子任务组 + Task 句柄）

**Decision**：取消底座采用 `@async.with_task_group` + `TaskGroup::spawn`
（返回 `Task[X]` 句柄）；`Call::cancel()` 调 `Task::cancel`（同步、公开、
幂等）；取消错误判别用非弃用的 `@async.handle_cancellation`（正常取消返回
`None`），将取消映射为显式 `CallCancelled`。

**Rationale / Evidence**：

- 取消语义＝水平触发持久标记：`.mooncakes/.../async/AGENTS.md`（"persistent
  mark … subsequent asynchronous operations will still get cancelled
  immediately"）与 `src/task_group.mbt` 结构化语义（组等全部子任务终止；子
  任务失败/组终止时自动取消其余子任务）。
- 公开面：`src/pkg.generated.mbti:46` `with_task_group`、`:95` `spawn ->
  Task[X]`、`:87` `Task::cancel(Self) -> Unit`（同步）、`:19` `handle_
  cancellation(async () -> X) -> X?`、`:32` `protect_from_cancel`。
- `handle_cancellation` 语义（`src/async.mbt` 文档块）：`Some(result)` 正常
  返回 / `None` 正常取消 / `raise err` 其他错误；返回 `None` 后后续未保护
  async 操作仍立即取消——**映射为 CallCancelled 后的收尾必须只用同步操作**
  （`Lease::poison/release`、`Client::close` 均同步，见 R4）。
- 弃用面规避（--deny-warn 门）：`is_cancellation_error`、`with_cancellation_
  handler`、`Timer`/`TaskCancelled` 别名均 `#deprecated`
  （`src/pkg.generated.mbti:24/:43/:59-64`），本包零引用。

**Alternatives considered**：

- `Semaphore`/`CondVar` 自造取消标记：需手工扩散到每个 await 点，违背
  「后续 async 操作立即失败」的 runtime 语义，复杂度违宪（VI）。否决。
- `Timer::cancel` 充当取消通道：语义是定时器不是协程取消。否决。
- 弃用 API + 局部 `#warnings` 抑制：003/004 先例为零弃用门。否决。

**组生命周期硬约束（R3/R4 的依据）**：`task_group.mbt:105-110`——
"**No matter what the value of no_wait is**, `with_task_group` will only
return after all child tasks terminate"；`spawn_coroutine`（:55-57）对已终止
组 spawn 直接 abort。⇒ **execute 的组不能在返回后收留 Dropped 触发的
skip**，该结论把 C2 逼向 R3 的 dispose 裁决。

## R2 @http 单次 exchange 现状（管线逐拍锚点）

**Decision**：exchange 管线全程只用 `@http.Client` 既有公开 API，零侵入。

**Evidence**（`src/http/pkg.generated.mbti` 与 `client.mbt`）：

| 管线步 | API | 锚点 |
| --- | --- | --- |
| 每连接客户端 | `Client::Client(uri, …)`（P04 池已封装于 Lease） | http mbti:64 |
| 发请求头 | `Client::request(RequestMethod, StringView, extra_headers?)` | http mbti:79 |
| 发 body | `Client as @io.Writer`：`write/write_once/write_reader/flush` | http mbti:82-84 |
| 收响应头（含 1xx 跳过） | `Client::end_request(on_informational_response?) -> Response` | http mbti:67 |
| 1xx 语义 | 100/102..<200 自动跳过并回调（回调缺省则仅跳过），最终响应返回；**101 不在跳过集**，end_request 原样返回 101（归 M5 透传，本包零特判） | `client.mbt:225-253`（spec 锚点逐字核实；:243 跳过模式 `100 \| 102..<200`） |
| 读 body | `Client as @io.Reader`：`read_some/read_exactly` | http mbti:74-77 |
| 排空 body | `Client::skip_response_body(Self) -> Unit`（async） | http mbti:80 |
| 关连接 | `Client::close(Self) -> Unit`（同步） | http mbti:65 |
| 帧形态 | Content-Length 覆写→SendingFixed；删除→上游 chunked | core `conversion.mbt:18-23/:64-68`（P02 判定，本包不改写） |

- `on_informational_response?` 参数即 1xx 回调挂点：**C3 裁决（owner
  2026-10-24 确认不暴露）落地为「不传该参」**——跳过语义照常生效，回调
  不进本包公开面。
- 归池前提锚点核实：`client.mbt:345-355` 为 passthrough 的 clean-state
  文档（"Unread data … will be discarded"）；响应体未读完时连接留有残数据，
  复用必错——毒化/skip 二选一（03 §3.2 口径）。

## R3 响应体生命周期（C2 裁决：显式异步收尾 API `dispose`）

**Decision**：触发 FR-015 预留支点——语言层析构时机问题经核实为**不存在
（比"不可靠"更强）**：MoonBit 无 finalizer 机制，P02 先例即显式
`ResponseBody::drop()` + 状态查询（`response_body.mbt:236-239`，Abandoned
"仅由 P04/P05 所有者按 consumed()/dropped() 查询结果触发"）。同时
`drop()`/`on_event` 为同步（`response_body.mbt:59/:239`），而
`skip_response_body` 为异步，且 R1 证明结构化组不能在 execute 返回后收留
协程 ⇒ 「未读完即弃→skip→回池」必须落在**显式异步收尾 API**上：

- core 增面（形状归本 plan 裁决，按 FR-015 回记 spec）：
  `ResponseBody::stream` 增可选参 `on_dispose? : async () -> Unit raise`；
  新增 `pub async fn ResponseBody::dispose(Self) -> Unit raise`——已消费则
  no-op；否则置 dropped/触发 `Dropped` 后 `await on_dispose()`（P05 注入
  skip→release / 失败→毒化）。
- 弃读首选 `dispose()`（OkHttp `body.close()` 的异步对应物）；`drop()` 保留
  P02 语义（纯状态标记，不收尾——仅 drop 不 dispose 为租约滞留，文档化为
  调用方责任）。

**Rationale**：保住 US-5 场景 2/SC-005 的「skip 清理回池」验收（毒化保底
方案会砍掉 owner 已批准的验收路径）；`dispose` 在消费者协程上同步推进，
测试零 sleep、零竞态；client 包冻结面（FR-014）零变化。

**Alternatives considered**：

- drop() 内联 skip：同步回调无法 await。不可能。
- execute 的组收留 skip 子任务：R1 组生命周期硬约束否决（组返回即终止，
  no_wait 也不豁免）。
- drop()→毒化保底（03 §3.2 严格口径）：违反 FR-005/US-5-2/SC-005 已批准
  口径，且丧失「丢弃后复用」杠杆。否决（映射表记 03/01 报告口径差异，
  以 spec 为准）。
- 惰性 skip（下次 acquire 前清）：租约滞留窗口内池计数失真，测试需 sleep。
  否决。

## R4 取消三通道落点（FR-002 的机制级细化）

**Decision**：

1. **标记**：`Call.cancelled : Bool`；execute 前检查（US-3-1 零网络动作）；
   body 读适配器每个读边界检查（body 阶段的取消以边界失败呈现）。
2. **在途协程取消**：execute 将单次 exchange `spawn` 进 `with_task_group`
   子任务，`Call` 持 `Task` 句柄；`cancel()` 调 `Task::cancel`——子协程内
   读写立即失败；`handle_cancellation` 捕获 `None` → raise `CallCancelled`
   → 随后收尾只用同步操作（poison/release/close）。
3. **毒化**：exchange 子任务 cleanup（catch/收尾）对租约 poison+release
   （P04 幂等，double-release no-op）；body 阶段 cancel：`cancel()` 直接
   `poison + release`（release 同步关 socket——停摆读立即失败，OkHttp cancel
   即关连的对齐点），并清空 Call 的租约引用 ⇒ FR-012 迟到 cancel 竞争安全
   （已归池连接不再被触碰）。

**Evidence**：P04 冻结面 `Lease::release/poison` 同步幂等
（`src/client/pkg.generated.mbti:35-36`；pool-api.md §2）；`Task::cancel`
同步（R1）。

## R5 折叠缓存与接缝（FR-004/FR-006）

**Decision**：`Call` 缓存 `folded : Map[CaseInsensitiveString, String]?`，
首跑在 exchange 内经 `HeadersV::to_http_map()`（`src/core/pkg.generated.mbti:50`，
P02 转换层产物）折叠一次并复用；内部函数 `Call::exchange_once` 为接缝
（租借→折叠→发送→收头→构建→归还），execute 只调一轮；wbtest 以桩接缝
直调 N 次做重放断言（US-4）。折叠计数 `fold_count` 白盒可断。

## R6 夹具适配（P03 零扩展假设 + 一处待核）

**Decision**：US-1/2/3/5 全部由 P03 现有面承载（`src/internal/fixtures/
pkg.generated.mbti`：`BodyPlan::Echo/Drip`、`SlowReceive`、`PartialResponse
(CutPoint,Bool)`+`close_after_response`（skip 失败注入）、`accepted_total/
conn_request_counts/peak_concurrent`、`PeerProgram::Capture`（字节比对））。
**待核（F-8 候选）**：1xx-then-200 组合响应可能超出 `ResponseScript` 单响应
模型（status=100 的合法性与序列推进语义未核实）；若不支持，按 P04 先例做
最小夹具扩展并逐处归因 FR-010（implement 首片核实，零风险兜底：夹具层
裸写状态线）。

**F-8 核实结论（P05 T002，2026-10-25 implement 首片）**：**不支持**，已按
兜底扩展。证据：`serve_script`（scripted_server.mbt）对每次 `read_request`
恰应答一次（`send_response`+`end_response`）；`RouteScript::Sequence` 是
跨请求命中序（serve_connection 按 route_hits 取第 i 个脚本），单请求内无
1xx→200 序列推进。status=100 的合法性确认无校验门（`reason_of` 兜底）。
最小扩展（归因 FR-010）：`RouteScript` 增 `InterimThen(Int32,
ResponseScript)` 变体 + `ScriptedServer::mount_interim`——最终应答前经
公开 API `send_response(interim, "Continue")+end_response()` 发一条 1xx
interim（1xx 无体，end_response 仅 flush 状态线；上游
utils_for_test.mbt:90 同款形态；raw write 状态线会撞 Sender SendingHeader
guard 而 abort，故走公开 API）。元测试 `P05-FIX①`（scripted_server_test.mbt）
native+wasm 双绿；`.mbti` 增面（RouteScript 变体 + mount_interim）逐处归因
FR-010。

## R7 js 口径（D14/F9）

**Decision**：本包零 `#cfg(js)` 分支（P04 先例）；js 仅 `moon check --target
js` 编译验证 + 可行时 node 冒烟，不入门禁。AbortController 已在 @http
js 后端接入（`src/js_async/pkg.generated.mbti:18-32`；01 §测试方案），归池/
毒化语义不适用 js——维持 spec 欠账登记。

## R8 测试组织

**Decision**：命名 `P05-<域><序> 描述`；黑盒 `call_test.mbt`（US-1/2/3/5
场景 + FR-007/009/011/012），白盒 `call_wbtest.mbt`（桩接缝重放/折叠计数/
状态机/竞争），`-p` 全包名 + `Total tests` 非 0 假验证警示沿 004（quickstart
§0）。断言优先 `assert_eq`/`assert_true(pattern is …)`；错误判别一律
`err is CallCancelled` / `err is CallStateError`（FR-003）。
