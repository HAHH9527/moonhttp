# P08 四类超时与 per-call 配置（builder 派生）

> 里程碑：M1 性能核心 ｜ 前置依赖：P05、P06（P07 建议先行）｜ 人力估计：~2 人日
> 来源：`proj-init-docs/okhttp-on-async-http/10-timeouts-dispatcher/README.md` §3.1/§3.2/§3.4/§8
> 侵入性：非侵入（runtime 原语 `with_timeout`/`Timer` 接线）｜ 建议特性 slug：`m1-p08-timeouts`

## 功能描述（speckit 输入种子）

为 P05 管线叠加 OkHttp 的**四类超时**：connect（连接伞，覆盖 DNS+TCP+TLS+隧道）、
write（按写操作，含 header 写出）、read（按读操作，响应头/体每块重置）、
call（整个调用含 follow-up/重试的总伞）；超时以显式 `HttpTimeout{Connect/Write/
Read/Call}` 错误变体暴露（经 `with_timeout(error=)` 注入），超时点伴随连接毒化。
同时交付 **per-call 配置面**：`HttpClient::new_builder()`（共享 pool/未来
dispatcher，仅覆盖标量）与 `Request::new_builder()`（OkHttp newBuilder 等价）。

## 范围

包含：

- `Timeouts` 配置：connect_ms/write_ms/read_ms 默认 10s，call_ms 默认 0（不限）。
- 四级接线（时序叠加在 P05 单轮 + P06/P07 循环上）：
  - ④ callTimeout：Timer 包全程（follow-up/重试含在内），到期取消整个执行；
  - ① 连接伞：`with_timeout(connect_ms, pool.acquire(addr))`；
  - ② 写：header 写与每 body 块（16–64KB 分块）各包 `with_timeout(write_ms)`；
  - ③ 读：`end_request` 与流式 body 每次底层读各包 `with_timeout(read_ms)`。
- 按操作重置的实现选择：M1 用每块一个 `with_timeout`（简单正确，Timer 创建/取消
  ~百 ns 级）；单 Timer + `Timer::refresh` 方案留待基准驱动（14 跟踪，M2 决策）。
- `HttpTimeout` suberror 四变体；超时抛出点伴随 `lease.poison()`（与 Call.cancel
  同一毒化通道）。
- `HttpClient::new_builder()`：浅拷贝共享 pool（引用语义）+ 覆盖 timeouts 等
  标量；`Request::new_builder()`：headers/tag 保留，可换 url/method/body/timeouts
  覆盖。
- `followRedirects`/`followSslRedirects` 关闭跟随开关（builder 配置位；
  P06 spec 非目标与映射表钦定归入本包——M1 恒跟随＝OkHttp 默认 true
  行为面；开关关闭后 3xx 一律终态透传。2026-10-28 review 修复批补登，
  deferred-items F21 同源）。

非目标（显式排除）：

- Dispatcher 并发闸（P09）；connect 阶段 DNS 的可取消性（侵入 socket 线程池，
  10 §4 明确不做——超时后 getaddrinfo 后台跑完仅占线程，不阻塞正确性）；
- js 上的按操作超时（fetch 路径降级为 callTimeout 经 AbortController + Dispatcher
  闸，10 §5）；refresh 方案优化（基准驱动后）。

## 用户故事种子

### US-1 四类超时各自触发（P1）

作为使用者，慢连接/慢写/慢读/慢全程各自在对应阈值触发，错误类型可判别。

**独立测试**：P03 慢速夹具（延迟响应头/延迟体/慢接收）。

**验收场景**：

1. Given connect_ms=500 与「accept 后挂起不完成」对端，Then ~500ms 内 raise
   `HttpTimeout::Connect`（耗时边界 ±50ms）。
2. Given read_ms=500 与「延迟 2s 回响应头」夹具，Then `HttpTimeout::Read`。
3. Given write_ms=500 与慢速接收对端 + 大 body，Then `HttpTimeout::Write`。
4. Given call_ms=1000 与「每阶段都快但总链路 3 跳×慢」夹具，Then `HttpTimeout::Call`
   （覆盖 follow-up 全程）。

### US-2 read 按操作重置（P1）

作为使用者，慢速但持续滴数据的 body 不触发 read 超时；静默中断则触发。

**验收场景**：

1. Given read_ms=1000 与每 200ms 滴 1KB 的 body（总 3s），Then 无超时、读完整。
2. Given read_ms=1000 与滴 2 块后静默的 body，Then ~1s 后 `HttpTimeout::Read`。

### US-3 超时后连接不回池（P1）

作为池的正确性守护，超时异常抛出点的连接被毒化。

**验收场景**：

1. Given read 超时触发，Then 池内 idle 不含该连接、池计数守恒（毒化路径）。

### US-4 per-call 配置派生（P2）

作为使用者，我用 `new_builder` 派生客户端（共享连接池）改超时，只影响新调用；
Request 级 builder 保留 headers/tag。

**验收场景**：

1. Given client A（默认超时）派生 B（call_ms=300），When 经 B 的调用遇慢夹具，
   Then B 超时而 A 不受影响；A、B 的请求复用同一池（连接计数共享）。
2. Given `Request::new_builder()`，Then headers 逐项保留、可换 method/url/body。

### US-5 与取消/重试的交互（P2）

作为使用者，超时与取消/重试语义正交：callTimeout 覆盖重试轮、取消优先级不降。

**验收场景**：

1. Given call_ms=1s + 「先 stale 后成功但每轮 600ms」场景（P03 组合），Then 两轮
   总计 1.2s → call 伞触发 `HttpTimeout::Call`（覆盖重试）。
2. Given 超时与 cancel 几乎同时，Then 二者之一有序终结，无悬挂协程（TaskGroup
   收敛断言）。

## 边界用例

- call_ms=0 不限（默认）；阈值极小（1ms）的退化行为（快速失败不 panic）；
  写阶段 header 与首块间超时归属（header 写归 write）；1xx 响应阶段的 read 计时；
  超时错误经拦截器/重试层时不被误吞（M1 无拦截器，重试层 P07 对 HttpTimeout
  不重试——超时属不可重试分类，spec 记录）。

## 需求种子

- **FR-001** 四类超时 MUST 独立可配、默认 connect/write/read=10s、call=0。
- **FR-002** read/write MUST 按操作重置（每块一个计时窗），非整段限时。
- **FR-003** callTimeout MUST 覆盖 follow-up 与重试全程。
- **FR-004** 超时 MUST 以 `HttpTimeout` 四变体之一暴露（可判别）。
- **FR-005** 超时抛出点 MUST 毒化连接（不回池）。
- **FR-006** `new_builder` MUST 共享 pool（引用语义）、仅覆盖标量配置。
- **FR-007** connect 伞 MUST 含 DNS（与 OkHttp 差异：OkHttp connectTimeout 不含
  DNS——我们合并为一个伞，更严；spec 与用户文档写明，10 §3.2 注）。

## 关键设计要点

- 接线时序严格叠加在 P05 的单轮时序图上（acquire→request→写块→end_request→
  读块），不改变管线结构——超时是包裹层不是流程层。
- 取消底座：runtime 取消水平触发，超时后的连接必须毒化不能回池（10 §2）。
- with_timeout 的 `error=` 参数注入分类错误（`pkg.generated.mbti: L48`）。
- 每块超时开销预算：Timer 创建/取消 ~百 ns，块 ≥16KB 时占比 <0.1%（10 §6），
  超出则在 P10 基准暴露后转 refresh 方案。

## 侵入性与宪法合规

- 非侵入：全部 runtime 公开原语接线（10 §4 表）。
- 宪法 III：超时归属与错误分类对齐 OkHttp（`SocketTimeoutException` 判别用法），
  两处有意差异（connect 含 DNS、取消/超时用显式变体）在 spec 显式记录。
- 宪法 II：超时包装的性能开销属热路径，P10 的「超时开/关」对比场景量化。

## target 矩阵

| target | 支持 | 说明 |
| --- | :-: | --- |
| native / wasm | ✅ | Timer/Semaphore 全 target |
| js | ⚠️ | 降级：connect/read/write 并入浏览器行为，L1 仅落实 callTimeout（AbortController 已在 @http js 后端接入）+ Dispatcher 闸；按操作超时静默降级为 call 级（降级清单记录） |
| wasm-gc | ❌ | 上游 runtime 缺口 |

## 性能影响

每块读写一个 with_timeout 的成本进入热路径（预算见上）；P10 量化。callTimeout
若 M2 转 refresh 方案则每请求 1 个 Timer、O(1)。

## 测试方案

- 每类超时一个触发用例（P03 慢速夹具），断言错误类型与耗时边界 ±50ms。
- read 按块重置两态用例（US-2）；超时毒化池计数断言；builder 派生共享性断言；
  超时×重试×取消交错用例。
- native + wasm 双绿；js `moon check` + （可行时）node 冒烟 callTimeout。

## 澄清问题种子

- **C1** 耗时边界断言的 CI 稳定性（±50ms 在共享 runner 上的抖动容忍；必要时
  放宽或标记为长测）。
- **C2** `Timeouts` 是否进 `Request`（per-request 覆盖）还是仅 call 级
  （OkHttp 在 client 与 request 两级——10 §3.1 提到 request 级覆盖，确认 M1 面）。
- **C3** HttpTimeout 与 P07 不可重试分类的交互声明（超时一律不可重试）。
- **C4** 1xx 阶段与响应头间隙的 read 计时归属（归 end_request 窗）。

## 验收判据（包级 DoD）

1. US-1–US-5 验收场景测试全绿（native/wasm 双 target；耗时边界按 C1 结论）。
2. js 降级清单（按操作超时→call 级）写入 spec 与用户文档。
3. `moon info && moon fmt` 干净；`.mbti` 新增面（Timeouts/HttpTimeout/new_builder）
   经审视。

## 参考

- `10-timeouts-dispatcher/README.md` §3.1（配置面）、§3.2（四级接线）、§3.4
  （builder 派生）、§5（js 降级）、§8（测试方案）。
- 下游引用方：P09（Dispatcher 复用 builder 面）、P10（超时开销量化场景）。
