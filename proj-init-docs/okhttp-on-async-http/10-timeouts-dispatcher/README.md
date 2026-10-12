# 10 超时与调度（Timeouts / Dispatcher / per-call 配置）

> 结论：**非侵入可实现**。runtime 原语（`with_timeout`/`Timer`/`Semaphore`/`all(max_concurrent=)`）齐备，缺的只是 HTTP 语义的分级接线。

## 1. OkHttp 行为规格

- 四类超时：**connect / write / read / full call**（默认 connect/write/read 10s，call 0=不限）。
- 语义细节：read/write 是**按操作**计时（每读到/写出一块即重置），不是整段限时；callTimeout 覆盖整个调用含重定向/重试。
- **Per-call 配置**：`client.newBuilder()` 共享连接池/Dispatcher、改超时等，针对单请求生效。
- **Dispatcher**：异步请求并发上限——按服务器（默认 5）与全局（默认 64），超出进 readyAsyncCalls 队列 FIFO；同步 execute 不受限（只受池约束）。

## 2. async/http 现状（证据）

- `@http` **无任何 timeout API**（全包 grep 零命中，探索代理核实；既有对比研究 §3.1 同结论）。
- runtime 已有（`src/pkg.generated.mbti`）：

```
pub async fn[X] with_timeout(Int, async () -> X, error? : Error) -> X      // L48：超时取消 f 并抛 TimeoutError
pub async fn[X] with_timeout_opt(Int, async () -> X) -> X?                 // L50
pub async fn[X] all(ArrayView[async () -> X], max_concurrent? : Int) -> Array[X]  // L14
pub async fn[X] any(..., max_concurrent? : Int, allow_failure? : Bool) -> X       // L17
pub fn Semaphore::Semaphore(Int, initial_value? : Int)                       // acquire/release/try_acquire
pub Mutex::{acquire, release, try_acquire}
Timer::{cancel(err?), refresh, wait}                                         // timer.mbt
```

- 取消是**水平触发**的（协程持久标记，后续 async 操作立即失败，AGENTS.md）——超时后的连接必须毒化（03 §3.4），不能回池。
- `Timer::refresh` 支持按进度重置——正是 OkHttp "每次读到数据重置 read timeout" 的形状。

## 3. 实现方案

### 3.1 超时配置面

```moonbit
pub struct Timeouts {
  connect_ms : Int = 10_000     // 覆盖 DNS + TCP + TLS + CONNECT 隧道（一个伞，见 3.2 注）
  write_ms   : Int = 10_000     // 每次写操作（含 header 写出）
  read_ms    : Int = 10_000     // 每次读操作（响应头/体）
  call_ms    : Int = 0          // 0 = 不限；覆盖整个 execute 含 follow-up/重试
}
// HttpClient::new_builder()：浅拷贝共享 pool/dispatcher/cookies，改 timeouts —— okhttp newBuilder 等价
// Request 级：Request::new_builder(headers+tag 保留) + call级 timeouts 覆盖
```

### 3.2 四级接线（L1 execute 内部）

```
execute(request):
  with_call_timeout(call_ms):                    // ④ callTimeout：Timer 包全程；到期取消整个协程组
    retry/follow-up 循环（02）:
      lease = with_timeout(connect_ms, pool.acquire(addr))   // ① 连接伞（DNS+TCP+TLS+隧道）
      with_timeout(write_ms, client.request(headers))        // ② header 写
      body 分块: with_timeout(write_ms, client.write(chunk)) // ② 每块重置（Bytes 分 16–64KB 块）
      with_timeout(read_ms, client.end_request())            // ③ 响应头
      body 流式: 每次底层 read 包 with_timeout(read_ms)       // ③ 每块重置
```

- **read/write 的"按操作重置"实现选择**：每块一个 `with_timeout` 的成本 = 每次 Timer 创建+取消（runtime 定时器轮，亚微秒级）——可行；更优是单 Timer + 每块 `refresh`（`Timer::refresh` 即为此设计）。M1 用 with_timeout（简单、正确），M2 若基准显示开销再换 refresh 方案（`14-performance` 跟踪）。
- 超时错误建模：`pub suberror HttpTimeout { Connect / Write / Read / Call }`，经 `with_timeout(error=)` 注入——拦截器/用户可按类型区分（对齐 OkHttp SocketTimeoutException 的判别用法）。
- **取消后清理**：超时异常抛出点一定伴随连接毒化（catch 中 lease.poison()）——与 Call.cancel 走同一条毒化通道（01 §3.5）。
- 注：OkHttp 的 connectTimeout 不含 DNS（其 DNS 有独立机制）；我们合并为一个伞（更严：DNS 慢也限时）。文档中写明该差异。

### 3.3 Dispatcher（enqueue 并发控制）

```moonbit
pub struct Dispatcher {
  max_requests      : Int = 64          // 全局在途异步请求上限
  max_requests_per_host : Int = 5       // 每 host 上限（route 维度不做，见 03 §3.1）
  global : Semaphore                    // 容量 max_requests
  hosts  : Mutex[Map[String, Semaphore]]// 每 host 信号量，懒创建
  queue  : AQueue[PendingCall]          // FIFO 公平性（两闸都拿到才出队）
}
pub fn HttpClient::enqueue(self, call, on_response, on_failure) -> Unit
```

- 出队算法（避免双信号量死锁，顺序固定 global→host）：`spawn { global.acquire; host_sem.acquire; try 执行 finally 双 release }`——注意 Semaphore 是计数信号量无 FIFO 保证，**公平性由 AQueue 串行化出队**保证：仅当两闸均 available 才 pop 下一个（`try_acquire` 探测）。这与 OkHttp 的 readyAsyncCalls/promoteCalls 结构同构。
- `enqueue` 返回可取消句柄（复用 01 的 Call.cancel：取消尚未出队的直接从队列摘除，已出走的走协程取消）。
- 同步 execute 不经 Dispatcher（OkHttp 同语义）。
- 并发上限与连接池的关系：`max_requests_per_host=5` + 池 max_idle=5 ⇒ 同 host 并发第 6 个请求会开新连接或排队——行为与 OkHttp 相同（OkHttp 每请求一条流，H1 下即新连接）。

### 3.4 per-call / builder 派生

- `HttpClient::new_builder()`：共享 pool/dispatcher/cookie_jar/interceptors（引用语义），仅覆盖标量配置——MoonBit struct 浅拷贝 + 共享引用字段天然满足。
- `Request::new_builder()`：okhttp 同名 API；headers/tag 保留，可换 url/method/body/timeouts 覆盖。

## 4. 侵入性清单

| 项 | 级别 | 说明 |
| --- | --- | --- |
| 四类超时 / Dispatcher / builder | **非侵入** | runtime 原语接线 |
| （性能）按操作超时的 Timer 复用 | 非侵入 | L1 内部优化，必要时侵入 `with_timeout` 上游加 reset 语义——不建议，refresh 方案已够 |
| （精度）connect 阶段的 DNS 不可取消 | 侵入 async/socket（thread_pool getaddrinfo） | 超时后 getaddrinfo 仍在后台线程跑完（`network.mbt:37-53`），不阻塞正确性仅占线程；上游改造大，不做 |

## 5. Target 支持矩阵

| target | 支持 | 说明 |
| --- | :-: | --- |
| native / wasm | ✅ | Timer/Semaphore 全 target |
| js | ✅（降级） | fetch 路径：connect/read/write 合并为浏览器行为，L1 仅落实 callTimeout（经 `AbortController`，`client.js.mbt:195-202` 已接）+ Dispatcher 闸；按操作超时在 js 上静默降级为 call 级 |
| wasm-gc | ❌ | runtime 级缺口（16） |

## 6. 性能影响

- 每块读写的超时包装：Timer 创建/取消 ~百 ns 级；块大小 ≥16KB 时占比 <0.1%。基准项进 `14-performance`。
- Dispatcher 闸：两次信号量 acquire ~几十 ns；不构成瓶颈。
- callTimeout 若用"每块 refresh"实现则为每请求 1 个 Timer，O(1)。

## 7. 工作量与依赖

- 依赖：01（Call/enqueue 骨架）、03（连接伞/毒化）。
- 估计：Timeouts+接线 ~1 人日；Dispatcher+AQueue 公平出队 ~1；builder 派生 ~0.5；测试 ~1。**~3.5 人日**。

## 8. 测试方案

- 每类超时：可控慢服务端（`test_programs` 修改版：延迟响应头/延迟体/慢接收）触发，断言错误类型与耗时边界（±50ms）。
- read 超时按块重置：慢速但持续滴数据的 body 不触发 read 超时，静默 3s 触发。
- 超时后连接不回池（池内计数断言）。
- Dispatcher：100 个并发 enqueue、max=10 → 观测在途峰值 ≤10、FIFO 顺序（对齐 OkHttp 行为测试思路）；per_host 与全局双闸无死锁（随机交错压测）。
- callTimeout 覆盖 follow-up 链（20 跳 + 每跳慢）。
