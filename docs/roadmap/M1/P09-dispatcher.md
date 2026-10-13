# P09 Dispatcher 与 enqueue（异步并发控制）

> 里程碑：M1 性能核心 ｜ 前置依赖：P05 ｜ 人力估计：~1.5 人日
> 来源：`proj-init-docs/okhttp-on-async-http/10-timeouts-dispatcher/README.md` §3.3/§8、
> `01-calls/README.md` §3.5（enqueue 部分）
> 侵入性：非侵入（Semaphore/AQueue/TaskGroup 原语接线）｜ 建议特性 slug：`m1-p09-dispatcher`

## 功能描述（speckit 输入种子）

交付 moonhttp 的异步发射面 **enqueue 与 Dispatcher**（OkHttp Dispatcher 等价物）：
`enqueue(call, on_response, on_failure)` 将 Call 交由 `HttpClient` 的 TaskGroup
spawn 执行，受**双闸并发上限**约束——全局在途上限（默认 64）与每 host 上限
（默认 5），超出的进 FIFO 就绪队列排队；公平性由队列串行化出队保证
（Semaphore 无 FIFO 保证，`try_acquire` 探测两闸均可用才出队）。
同步 `execute` 不经 Dispatcher（OkHttp 同语义，只受池约束）。
README 差异 D2：enqueue 与 Dispatcher 合并本包交付（闸门在链首，天然一体）。

## 范围

包含：

- `Dispatcher`：`max_requests`（默认 64）/`max_requests_per_host`（默认 5）可配；
  `global : Semaphore`；`hosts : Mutex[Map[host_key, Semaphore]]`（懒创建）；
  `queue : AQueue[PendingCall]`（FIFO）。
- `HttpClient::enqueue(call, on_response, on_failure)`：入队/spawn；
  出队算法顺序固定 global→host（避免双信号量死锁）：仅当两闸均 `try_acquire`
  成功才 pop 下一个（AQueue 串行化出队保证 FIFO，与 OkHttp
  readyAsyncCalls/promoteCalls 同构）。
- enqueue 返回**可取消句柄**：未出队的直接从队列摘除；已出队的走 P05 的
  Call.cancel 协程取消通道。
- 执行完成后双 release（finally 语义，异常路径不泄漏闸位）。
- 与连接池的关系说明：`max_requests_per_host=5` + 池 `max_idle=5` ⇒ 同 host
  并发第 6 个请求开新连接或排队，行为与 OkHttp 相同（10 §3.3，spec 记录）。

非目标（显式排除）：

- 同步 execute 的闸门（不经 Dispatcher）；route 维度上限（Route 不暴露，03 §3.1）；
- OkHttp 的 `runningSyncCalls` 统计面（观测随 M3/06 EventListener 落地）；
- js 上的池语义（连接由浏览器管理，但 Dispatcher 闸在 js 仍有意义——保留）。

## 用户故事种子

### US-1 全局上限与 FIFO（P1）

作为使用者，100 个并发 enqueue 在 max_requests=10 下：在途峰值 ≤10，
其余按提交顺序排队依次放行。

**独立测试**：P03 echo 夹具 + 服务端观测在途并发。

**验收场景**：

1. Given max_requests=10 + 100 个 enqueue（每个请求夹具侧 sleep 50ms），
   Then 夹具观测峰值在途 ≤10、总完成 100。
2. Given 提交顺序带序号（请求体含序号），Then 完成开始时刻的顺序与提交序
   单调一致（FIFO；完成顺序可乱序——网络时序，判据为「开始执行」序）。

### US-2 双闸（全局 × 每 host）（P1）

作为使用者，per_host 与全局两闸同时生效且无死锁。

**验收场景**：

1. Given max=64/per_host=2 + 向 3 个 host 各提交 4 个请求，Then 每 host 同时
   在途 ≤2、总在途 ≤6（受 per_host 联合约束）。
2. Given 双闸下随机交错提交/完成 ≥1000 次，Then 无死锁（全部完成）、闸位
   计数归零（无泄漏）。

### US-3 enqueue 取消（P2）

作为使用者，我取消已 enqueue 的 Call：排队中的被摘除（回调收到 `CallCancelled`），
执行中的走协程取消。

**验收场景**：

1. Given 队列中等待的 Call（闸满），When cancel，Then 该 Call 以 `CallCancelled`
   回调 on_failure、不再执行（夹具无对应请求到达）。
2. Given 已出队执行中的 Call，When cancel，Then 按 P05 US-3 语义终止。

### US-4 同步不受限（P2）

作为使用者，`execute` 不经 Dispatcher 闸：enqueue 排队时 execute 仍立即执行。

**验收场景**：

1. Given 闸满、队列有等待者，When 同步 execute，Then 立即完成（不等闸）。

### US-5 异常路径闸位归还（P1）

作为使用者，enqueue 的请求失败（网络错误/超时）不泄漏并发额度。

**验收场景**：

1. Given max=2 + 持续提交注定失败的请求（P03 故障端口）×N，Then 后续好请求
   仍能获得闸位执行（finally 双 release 生效）。

## 边界用例

- host 键的等价类（同 host 不同 port/scheme 是否同一闸——澄清 C1，OkHttp 语义
  为按 URL.host 不分端口）；队列中 cancel 与出队竞争（摘除幂等，不 double-执行）；
  Dispatcher 关闭/HttpClient 生命周期与在途队列的关系（M1 语义：进程生命周期，
  spec 记录）；enqueue 已 cancelled 的 Call（立即回调失败不入队）。

## 需求种子

- **FR-001** enqueue MUST 受双闸约束，出队顺序固定 global→host。
- **FR-002** FIFO 公平性 MUST 由 AQueue 串行化出队保证（非 Semaphore 语义）。
- **FR-003** 执行结束（成功/失败/取消）MUST 双 release（无闸位泄漏）。
- **FR-004** 未出队取消 MUST 队列摘除并回调 `CallCancelled`。
- **FR-005** 同步 execute MUST NOT 经 Dispatcher。
- **FR-006** max_requests/max_requests_per_host MUST 可配（builder 面，与 P08 合并）。

## 关键设计要点

- 出队算法（10 §3.3）：Semaphore 是计数信号量无 FIFO 保证——公平性不能靠
  acquire 队列语义，必须由 AQueue 串行化 + `try_acquire` 探测实现。
- 双闸 acquire 顺序固定 global→host，杜绝交叉死锁。
- spawn 进 HttpClient 的 TaskGroup（复用 P05 骨架），Dispatcher 闸在链首
  （OkHttp 语义位）。
- host 键材料来自 P01 HttpUrl 规范化 host（大小写/IPv6 归一后判定）。

## 侵入性与宪法合规

- 非侵入：Semaphore/Mutex/AQueue/TaskGroup 全公开原语（10 §2 证据表）。
- 宪法 III：与 OkHttp 差异（无 route 维度闸、host 键口径）在 spec 记录。
- 宪法 VI：Dispatcher 面最小化（无 OkHttp 的 maxRequests 热改/统计回调面，
  留 M3/06）。

## target 矩阵

| target | 支持 | 说明 |
| --- | :-: | --- |
| native / wasm | ✅ | 原语全 target |
| js | ⚠️→✅ | Dispatcher 闸与 FIFO 在 js 有意义（并发 fetch 受限）；连接池语义不适用但闸门仍生效 |
| wasm-gc | ❌ | 上游 runtime 缺口 |

（对照原 10 §5「js ✅（降级）」：本包在 js 的降级仅体现在无池语义，闸门本身可用。）

## 性能影响

两次信号量 acquire ~几十 ns，不构成瓶颈（10 §6）；enqueue 路径无分配放大
（PendingCall 壳 + 句柄）。

## 测试方案

- US-1/2/5 基于 P03（echo/故障注入/在途计数）；FIFO 判据用「开始执行序」。
- 死锁压测：随机交错 ≥1000 次（伪随机种子固定，可复现）。
- native + wasm 双绿；js `moon check`（闸门逻辑纯原语，编译面覆盖）。

## 澄清问题种子

- **C1** host 闸键口径：OkHttp 按 URL.host（不分端口/协议）——遵 OkHttp 还是将
  port/scheme 纳入（影响同机多端口夹具的测试断言值）。
- **C2** `on_failure` 回调的执行上下文（spawn 协程内 vs 独立 spawn）与异常逃逸
  策略（回调抛错的界定）。
- **C3** enqueue 返回句柄类型（复用 Call 自身 vs 独立 Cancellable）——与 P05 的
  Call.cancel API 合流方式。
- **C4** 就绪队列的无界性（OkHttp 同样无界——确认不设上限，文档声明）。

## 验收判据（包级 DoD）

1. US-1–US-5 验收场景测试全绿（native/wasm 双 target）。
2. 死锁压测用例稳定通过（固定种子、CI 可复现）。
3. `moon info && moon fmt` 干净；`.mbti` 新增面（Dispatcher/enqueue/取消句柄）
   经审视。

## 参考

- `10-timeouts-dispatcher/README.md` §3.3（结构与出队算法）、§8（测试方案）。
- `01-calls/README.md` §3.5（enqueue 语义、Dispatcher 闸在链首）。
- 下游引用方：P08（builder 面合并）、P10（并发场景基准经 enqueue 驱动）、
  M3/06（EventListener 挂点）。
