# Research: M1-P08 四类超时与 per-call 配置

**Branch**: `008-m1-p08-timeouts` | **Date**: 2026-10-30
**Spec**: [spec.md](spec.md)（v2，qod-1 八阻断 + 十二建议已采纳）

> 本文承载全部源码级证据与设计决策（R1–R12）；plan.md/data-model.md/
> contracts 引用不重复。取证日期除注明外均为 2026-10-30。

## R1 call 伞逸出形态：看门者 + 标记位 + 取消收尾选变体（Shape C）

**Decision**: call 伞不采用 `with_timeout(call_ms, execute)` 包裹，而在
execute 既有 `with_task_group` 组内增派看门者子任务：
`sleep(call_ms) → 置位 Call.call_timeout_fired → task.cancel()`；execute
取消收尾分支（`Cancelled =>`，含 `WaitedTaskAlreadyCancelled` 映射路）
按标记选终态变体：标记真 ⇒ `raise HttpTimeout::Call`，否则裸
`CallCancelled`（现状不变）。

**Rationale（证据链，qod-1 B1/B2 取证）**：
- `with_timeout` 实现＝`with_task_group` + timer 子任务先 `raise error`
  再取消全组（`async.mbt:96-118`）。若包 execute：到期时组态
  `Fail(HttpTimeout::Call)` → 取消在途协程 → execute 外皮取消收尾
  `raise CallCancelled`（普通 raise）→「取消处理中抛其他错误按失败
  计」且组 worker catch 对 Fail 态**无条件覆盖**（`task_group.mbt:78-91`
  else 分支 `state = Fail(err)`）→ 终态被 `CallCancelled` 覆盖，注入变
  体确定性被吞。FR-004 的「终态恰为 Call」在此形态下机械不可能。
- Shape C 时序准确：`sleep` 到期即 cancel（任务级取消直达任意在途
  await，包括 end_request 读等待中）⇒ C1 计时带可达；变体由标记位选
  定 ⇒ 恰为 `HttpTimeout::Call`；用户 cancel 时标记假 ⇒ 裸
  `CallCancelled`（反向隔离自然成立，US-5-2）。
- 看门者生命周期安全：正常交付路径组退出时组机制自动取消仍在睡眠的
  看门者（取消不算失败，`task_group.mbt:116-119`）；call_ms=0 不派看
  门者（FR-001「0=不建窗」）。

**Alternatives considered**:
- `with_timeout` 包 execute——B2 取证否决（变体被吞）。
- 标记位但不在取消点逸出（阶段边界轮询）——head_delay 封在 end_request
  读窗内、边界到不了 ⇒ 触发迟到落出 C1 带（B2 形态 2）否决。
- 改上游 task_group 语义——宪法 I 否决。

**结构审判据（WB）**：看门者 spawn 点、标记位置位点、收尾分支标记
三分支断言（FR-002 有界例外①位点）。

## R2 连接伞形态：看门者同型（ensure_lease 侧；WB⑥ 实证订正整包形态）

**Decision（2026-10-31 implement 订正）**: 连接伞在 `Call::ensure_lease`
的 `pool.acquire(addr)` 处采用**看门者同型**（R1 三步序的伞侧镜像）：
`with_task_group` 内子任务跑 `acquire`、`spawn_bg(no_wait)` 定时器到
期 `child.cancel()`、`child.wait()` 交付——记账完成 ⇒ 租约必达（wait
拿到值照常使用）；建连在途被截断 ⇒ `WaitedTaskAlreadyCancelled` ⇒
`HttpTimeout::Connect`（记账零发生）；真实建连失败（OSError 等）沿
wait 原样透传（P07 建连族判定不受影响）。`ConnectionPool`/`acquire`
签名零改动。

**订正记录（WB⑥ 实证，native/wasm 双现）**: 原决策 `with_timeout(
connect_ms, acquire)` 整包形态存在 R5 孤儿租约竞态——伞到期取消
body 时，acquire 若已越过末个暂停点（记账锁无竞争 fast-path 使同步
记账尾在取消生效前完成），记账完成而租约被组丢弃 ⇒ borrowed 悬挂，
违反 FR-006/US-3-3「副作用必达或显式撤销」。qod-1 B3 的担忧（编排
层 R2 调和时曾以「记账段无暂停点」论证排除）经白盒第 8/4 轮实测成
立——「取消只在 await 落」的前提对「末个 await 之后的同步尾 vs 取消
信号到达次序」不成立（fast-path 下同步尾可先于取消观察点完成）。
看门者同型以 wait 交付消除丢弃可能：INV-T3 两支恒成立（记账完成 ⇒
必达；截断 ⇒ 记账零发生——锁 await 取消安全 mutex.mbt:39-41 + 构造
器 errdefer 清理 client.mbt:49/:57）。

**Alternatives considered**:
- `with_timeout` 整包——WB⑥ 实测孤儿租约，否决（本条订正）。
- 包裹点入 acquire 内部（只包 Client 构造）——需给 acquire 传阈值
  （签名/字段手术，P04 增量），且与看门者同型在可观测行为上无差，
  否决。
- `with_timeout_opt`——丢弃成功结果的形态正是 R5 要排除的，否决。

## R3 写窗包装面：@io.Writer trait 门面（每次用户写调用一窗）

**Decision**: Stream 体写窗经 `@io.Writer` trait 门面达成——L1 构造
priv 门面结构体（包 `@http.Client` + write_ms），实现 `write_once`/
`write`/`write_reader` 三方法、各包 `with_timeout(write_ms, ...,
error=HttpTimeout::Write)` 后委托内层；`filler(门面)` 替代
`filler(lease.conn)`（exchange.mbt:141 现场签名 `async (&@io.Writer)
-> Unit` 收 trait 对象）。header 写（`conn.request`）与 Bytes 整写
（`conn.write_once`）各自直包一窗。

**Rationale**:
- trait 门面＝P02 计数 Writer 同款先例（request_body.mbt:118-134
  CountingWriter 在场），非侵入（宪法 I）。
- 每次用户写调用一窗＝OkHttp 逐 sink write 语义对齐（spec FR-003）；
  Bytes 单次 `write_once` 即单操作（单窗）＝其线上形态的诚实粒度
  （R6，分块不采纳）。
- **委托目标注记（qod-2 S9）**：门面 `write`/`write_reader` 委托目标
  ＝内层 conn 的对应方法（`@http.Client` 自身 `pub impl @io.Writer`
  面），非门面自身方法 ⇒ 单窗，无嵌套开窗。
- 写超时错误从 filler 内层写调用逸出 → exchange 段 `last_stage=Send`
  已置位（exchange.mbt:132 前置赋值）→ 判定器族落点 Other → 透传
  （FR-008）；逸出路径毒化＝轮级 errdefer 既有单点（follow_up.mbt:260）。

**取证**：`@io.Writer` trait 三方法签名（io/pkg.generated.mbti：
`write_once(Self, Bytes, offset~, len~) -> Int` / `write(Self, &Data)`
/ `write_reader(Self, &Reader)`，后两者有缺省实现——门面全部覆写）。

**Alternatives considered**:
- 传 `lease.conn` 原对象、在 filler 外整包一窗——Stream 整体限时、
  违 FR-003 per-op（上传持续进展也会触发），否决。
- 改 core filler 签名插桩——动 core 公开面，否决（P07 R3 同款纪律）。

## R4 读窗接线：end_request 单窗 + BodyBridge read_checked 内包体读

**Decision**: 收头窗＝`with_timeout(read_ms, () => lease.conn.end_request(),
error=HttpTimeout::Read)`（exchange.mbt:147 调用点外包，含 1xx 跳读，
C4）；体读窗＝BodyBridge `read_checked` 单点内对内层读调用包
`with_timeout(read_ms, ..., error=HttpTimeout::Read)`。

**Rationale**: read_checked 已是读边界取消/错误检查单点（body_bridge.mbt
头注：三入口委托拓扑 read_some/_direct_read ⇒ read_checked ⇒ 内层
read_some）——读窗与毒化免费获得（读错误路径既有 poison+release，
S5 零新增接线）；`_get_internal_buffer` 直通面绕过单点＝判据面外
（spec Edge Cases S4 登记）。1xx+慢头共享收头窗用例由 F-8 interim 能
力 × B-01 延迟组合（零夹具新增，S9）。

## R5 判定器族落点：HttpTimeout 三行接入 error_family

**Decision**: `recover_family.mbt`（native/wasm）增分支：`err is
HttpTimeout` 时按变体分派——`Connect` 变体且 stage=Connect ⇒
ConnectFailure（可重试族，走既有 `(Connect, ConnectFailure) => Retry`
格）；`Write/Read/Call` ⇒ Other（decide 既有 `family is Other → Fail`
透传格，零 decide 改动）。`recover_family.js.mbt` 零改动（js 恒 Other）。

**Rationale**: decide 六条件合取不变（FR-008 承接面＝族检测层）；族检
测按 stage 分派与既有段相关设计同构（P07 data-model 实体 2）。
`HttpTimeout` 为本包自有类型（src/client），族检测引用无新 import、
不触碰 recover_family.mbt 的 @os_error/@tls 锁定问题（targets 表不变，
moon.pkg 零改动）。

**WB 矩阵（S6 收敛口径）**：四变体 × {Connect, Send, ReadHead} 可达
格——Connect×{W/R/C}、Send×Connect、ReadHead×Connect 为不可达格（变
体与阶段一一对应，伞注入点决定），断言族落点而非全格。

## R6 配置面形态：HttpClient priv 标量 + HttpClientBuilder + Request::new_builder

**Decision**:
- `pub struct Timeouts { connect_ms : Int = 10_000, write_ms = 10_000,
  read_ms = 10_000, call_ms = 0 }`（字段缺省值即 FR-001 缺省；
  `Timeouts::{}` 构造）。构建期校验（负值 abort，C5）在 builder
  `build()` 单点（`HttpClient::new` 直连构造走全缺省、无非法输入面）。
- `HttpClient` 增 priv 字段：`timeouts : Timeouts`、
  `follow_redirects : Bool`、`follow_ssl_redirects : Bool`（缺省 true）；
  `retry_on_connection_failure` 既有字段保持。`HttpClient::new` 签名
  不变（FR-012），字面量补全缺省值。
- `pub struct HttpClientBuilder { priv pool, priv timeouts, priv
  follow_redirects, priv follow_ssl_redirects, priv retry_on_connection_
  failure }` + 双构造入口：`HttpClient::new_builder(pool)`（pool 根，
  全缺省）与 `HttpClient::builder()`（自既有 client 派生——pool 引用
  共享、标量缺省取被派生方当前值；OkHttp client.newBuilder() 同形。
  无此入口调用方无法从既有 client 派生共享池新 client——pool 为 priv，
  US-4-1 对真实用户不可达，故 YAGNI 否决、双入口定为裁决）+ 链式
  setter（`timeouts`/`follow_redirects`/`follow_ssl_redirects`/
  `retry_on_connection_failure`）+ `build() -> HttpClient`（负值校验
  单点）。派生链语义（A 派生 B 派生 C 逐级覆盖）经 `builder()` 天然
  达成（每级缺省=前一方当前值）。
- `pub fn Request::new_builder(self : Request) -> RequestBuilder`（core
  包，同包字面量构造：`{ url: self.url, method: self.method, headers:
  self.headers.builder(), tag: self.tag, body: self.body }`——headers
  经 `builder()` 防御性回转（P02 先例），五要素保三换：url/method/body
  可换、headers/tag 保留）。

**Rationale**: builder 链式形态＝P01 RequestBuilder 家法；`HttpClient::new`
不动＝FR-012 冻结底线；Timeouts 进 HttpClient（非 Call）＝P07 开关同
形态（Call 经 `self.client.timeouts` 同包直读）。

## R7 跟随开关接入：follow_up_request 决策表两门（5.5.0 顺序对拍）

**Decision**: `follow_up_request` 增 `follow_redirects~ : Bool`/
`follow_ssl_redirects~ : Bool` 参数（exchange_loop 调用点从
`self.client` 直读透传）；两门插入顺序严格对拍 5.5.0
buildRedirectRequest：① 3xx 码集命中后、Location 门之前判
`follow_redirects`（false ⇒ Terminal）；② Location resolve 成功后判
sameScheme（`target.scheme != request.url.scheme` 且
`!follow_ssl_redirects` ⇒ Terminal）。

**Rationale**: 5.5.0 实测取证顺序（qod-1 复核确认）：`!followRedirects
→ null` 在 Location 读取前；`!sameScheme && !followSslRedirects → null`
在 resolve 后。短路即终态 ⇒ prior 链不累积（prior_entry 不经过）、
follow_ups 零推进、跳数预算零消耗（INV-4 计数点在决策表之后，天然满
足）；判据载体 `Response::prior() is None` + 终态 3xx（S7）。缺省
true ＝ P06 行为面逐位不变（回归保护，US-6-3）。

## R8 夹具增量：两变体（fixtures 包内最小扩展；qod-2 B1/B2 修正落点）

**Decision**:
- **DripHang**（**BodyPlan** 新变体——现场 `Framing` 枚举仅
  Fixed|Chunked（scripted_server.mbt:40-43），三参滴流挂在 BodyPlan
  （:67-71））：`DripHang(block_bytes, blocks, interval_ms)`——按 Drip
  节奏滴 blocks 块后 sleep **保持时长 ≥ 客户端读窗 + 断言余量**
  （S1 下限口径；ScriptedServer 每操作超时保护与该保持时长协调，读
  窗先于夹具兜底到期）。US-2-2 载体。
- **SilentReader**（**raw_peer.mbt::PeerProgram** 新指令变体——现场
  ScriptedPeer/PeerProgram 全在 raw_peer.mbt（:42-53/:142），无
  scripted_peer.mbt）：对端按极慢节奏读请求体且程序存活期内不主动
  关闭连接。**与 run() 兜底的协调义务（qod-2 B2）**：`run(timeout_ms~
  = 5000)` 以 `with_timeout_opt` 包裹全程序、超时兜底显式 close
  （raw_peer.mbt:259-262/:288/:466-468）——SilentReader 场景 MUST
  声明 `run(timeout_ms~)` 覆盖值 > 客户端写窗 + 断言余量；编排纪律
  三段不等式：**体量/节奏填满停滞 < write_ms < 夹具兜底**（B2②）。

**Rationale**: 行为判据不变（spec Assumptions 登记）；复用既有编排骨
架（ScriptedServer BodyPlan 分派/PeerProgram 指令枚举各加一臂）；
US-1-4/US-5-1/US-6 全部由既有夹具参数化组合（301 链 × B-01 头延迟；
ServeSequence × B-01；301 两态矩阵），零新增类型。**定标纪律（B2③/
S8）**：US-1-3 的体量/节奏/write_ms 定标归 implement 首片红绿取证
（红因判据＝未停滞或 OSError 误现；R9 表 US-1-3 行随之回填）。

## R9 耗时预算表（C1/S8，每 target ≤10s）

【implement 定标回填（2026-10-31，native 首片实测）】US-1-3 定标：体量
1MB（64 块×16KB）≫ 回环 socket 缓冲（停滞毫秒级填满）< write_ms=500 <
夹具兜底 run timeout_ms=3000——三段不等式成立，场景墙钟 ~0.6s。
US-1-2 δ 首片：execute 总耗时 512ms ⇒ δ(入口→读窗建立)=12-14ms。

| 场景 | 睡眠量 | 累计（实测/定标后） |
| --- | --- | --- |
| US-1-2 read 超时 | 0.5s 窗 + 2s 头延迟（只等到窗） | ~0.51s（δ=12-14ms 实测） |
| US-1-3 write 超时 | 窗=write_ms=500（定标：1MB 体停滞填满 < 500 < 兜底 3000） | ~0.6s |
| US-1-4 call 超时（3 跳） | 1s 窗（第 2 跳 600ms 延迟内触发） | ~1.0s |
| US-2-1 滴流完整读 | 5 块 × 200ms | ~1.0s |
| US-2-2 滴后静默 | 2×100ms + 0.5s 窗 | ~0.8s |
| US-3-1/2 毒化守恒 | 复用 US-1-2/US-2-2 场景 + 第二次 execute | ~1.0-2.0s |
| US-4-1 派生隔离 | 0.3s 窗 + 1s 慢夹具 + warm | ~1.4s |
| US-5-1 stale×call | 1s 窗（stale 后重试轮内触发） | ~1.1s（+peer 兜底收尾） |
| US-5-2 取消×归属 | 0.5s 窗 + 迟到取消 0.9s；归属组 6×0.25s | ~0.9s / ~1.6s |
| 1xx+慢头（C4） | 0.5s 窗 + 2s 头延迟 | ~0.51s |
| US-6 开关矩阵 | 无睡眠 | ~0.1s |
| **合计** | | **~7-8s/target ✅（全量墙钟 native 40s / wasm 62s——含非睡眠并发与夹具收尾）** |

【编排纪律附注（T028 已知问题②）】全部 serve_n 场景 MUST exact-n
（n 大于实际连接数 ⇒ close() 留悬 pend accept ⇒ 上游 runtime 冻结）。

## R10 FR/US ↔ 元测试映射

| 需求 | 测试载体 | 域 |
| --- | --- | --- |
| FR-001 缺省/0/负值 | WB（Timeouts 构造 + build 校验）+ 黑盒全 0 场景 | 判定器/配置 |
| FR-002 两处有界例外 | WB 结构审判据（看门者 spawn/标记位/连接伞位点） | 接线 |
| FR-003 四窗粒度 | US-1-2/3、US-2 黑盒 + WB 门面委托 | 行为 |
| FR-004 call 伞 | US-1-4、US-5-1/2 黑盒 | 行为 |
| FR-005 四变体判别 | US-1 各场景 `err is` + WB 判定器矩阵 | 行为+单元 |
| FR-006 毒化/R5 竞态 | US-3 黑盒池计数 + WB 收敛断言 | 行为+白盒 |
| FR-007 连接伞含 DNS | WB 接线伴随（R3 边界） | 白盒 |
| FR-008 分类矩阵 | WB 矩阵（R5 口径）+ US-5-1 零误增 | 单元+行为 |
| FR-009 builder/Request 派生 | US-4 黑盒 | 行为 |
| FR-010 跟随开关 | US-6 两态矩阵 + WB 决策表扩展 | 行为+单元 |
| FR-011 js 降级 | js check 对账（非测试） | 门禁 |
| FR-012 冻结面 | moon info 对账 | 门禁 |

红-绿循环优先区＝R5 判定器矩阵（先红：喂 HttpTimeout 断言族落点）、
FR-010 两门（先红：false 断言 Terminal）、看门者标记位（先红：标记真
断言 Call 变体）。

## R11 既有回归面（DoD 4/S11）

新缺省窗（connect/write/read=10s、call=0）对既有用例的影响面：全量
既有测试走回环夹具（毫秒级完成），10s 窗远大于任何既有睡眠（最大
B-01 头延迟 ~500ms 量级）；call_ms=0 不建窗 ⇒ execute 零行为变化。
预期零回归；implement 首片跑全量复证，如有意外逐条登记。

## R12 moon.pkg / import 面

`src/client/moon.pkg` **零改动**：@async（with_timeout/sleep/
with_task_group）、@io（Writer trait 门面）、@core/@http/@debug 既有
导入覆盖全部新引用；targets 表不动（R5：HttpTimeout 为本包类型，族
检测新增分支不引入锁定包类型）。`src/core/moon.pkg` 零改动
（Request::new_builder 为同包字面量）。js 编译面：新增公开类型全
target 中性，P08 无需 .js.mbt 分文件（P07 的 os_error/tls 锁定问题
不复现）。

## 风险表

| 风险 | 等级 | 缓解 |
| --- | --- | --- |
| 上游构造器取消时半途 socket 清理形态 | 已证关闭（qod-2 S4） | `errdefer proxy.close()`/`errdefer transport.close()` 在场（http/client.mbt:49/:57）；US-3-3 白盒收敛断言继续兜底行为面 |
| 看门者与 execute 终态置位的竞争窗口 | 已证关闭（qod-2） | 单线程协作调度下数据竞争不存在，残余仅语义竞态——spec US-5-2 二择一口径已覆盖；标记先置后取消的顺序纪律保持 |
| wasm 计时器粒度劣于 native | 低 | C1 wasm 带放宽（+1000ms）登记于 tasks 证据行 |
| Writer 门面漏覆写缺省方法 | 低 | 三方法全覆写 + WB 委托断言；--deny-warn 门 |
| 计时带测量起点漂移（qod-2 S5） | 低 | 原点钉定＝各窗 with_timeout/看门者 sleep 的建立点；黑盒观测起点=execute 时刻、前置同步段 δ≈0（状态检查+spawn），tasks 证据行以首片实测钉 δ 上界 |
