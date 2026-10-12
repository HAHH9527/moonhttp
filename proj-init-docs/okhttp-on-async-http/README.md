# 基于 async/http 实现 OkHttp 能力——完整可行性报告

> 研究问题：能否在 `moonbitlang/async` 的 `@http`（0.22.4-dev，E:\Project\async）之上，**以非侵入修改为主**实现 [OkHttp 能力全景](../okhttp-capabilities-summary.md) 的全部功能并**提高请求性能**；实现语言 MoonBit；target 优先级 `native ≥ wasm > wasm-gc > js`。
>
> 证据来源：async 仓库源码逐行核对（本报告所有行号可回查）、支撑模块调查（socket/tls/io/gzip/websocket/js_async/原语包）、既有实测（`../round1-3 *.raw.md`、`../moonbit-okhttp-foundation-comparison.md`）。
> 本报告是该对比研究的 **async/http 路线展开**（原研究比较了三个底座；本次按既定决策锁定 async/http）。

## 0. 总结论

1. **可行**。OkHttp 15 项能力中，除"HTTP/2 多路复用（协商版）"与"TLS 精细控制（ConnectionSpec/客户端证书）"依赖对 async 上游的深水区侵入外，**其余全部可以在不修改 async 源码的新包（下称 `easyhttp`）中实现**——包括：Calls/取消、重定向重试、连接池、双层拦截器、RFC 缓存、事件可观测、证书固定、自定义信任、认证、四类超时、Dispatcher、CookieJar、请求体全家桶、WebSocket 门面、调试日志。
2. **性能提升有实测背书**：连接池化 47–56×（既有 round2 数据），叠加定长帧/头块缓存/DNS 缓存等非侵入优化；两处高价值小改动（发送缓冲 1KB→16KB、DNS 缓存）建议以 PR 回馈上游。
3. **target**：native 与 wasm 共享同一路径、能力等价（P0）；js 走 fetch 适配层、能力降级清单明确（P1，成本 ~2 人日）；**wasm-gc 被 async runtime 整体阻塞**（连 `@http` 都未实现），L1 提供 stub 明确报错（P2 观察上游）。
4. **规模**：除 HTTP/2 外约 **60 人日（~12 人周）**，可按 6 个里程碑交付；HTTP/2 另计 ~6.5 人周 + ALPN 上游工作。

## 1. 总体架构（非侵入基线）

```
easyhttp 门面    拦截器链：[应用拦截器] → RetryAndFollowUp(02) → Bridge(01/11) → Cache(05)
                                              → Connect(03:池租借/07:pinning) → [网络拦截器] → CallServer/WebSocket(12)
                Dispatcher(10) · EventListener(06) · Logger(15) · Timeouts(10)
   │
easyhttp/core   HttpUrl · Request/Response/RequestBody(09) · HeadersV 有序头 · Call/取消
   │  唯一底座耦合面 ↓ 仅 import 公开 API，零 fork
moonbitlang/async   @http.Client(单连接状态机) · @socket(Happy Eyeballs) · @tls(SNI/自定义CA/DER)
                    @io · @async(fs/timer/with_timeout/Semaphore/TaskGroup/aqueue) · @websocket · @gzip
```

- 请求发射统一走流式 `Client`（便捷 `get/post` 每请求新建连接且恒 chunked，弃用）；已知长度 body 经 `extra_headers~{Content-Length}` 进 `SendingFixed`（round3 机制）。

## 2. 特性目录与裁决矩阵

| 文件夹 | OkHttp 能力 | 裁决 | 侵入需求 | 人力 | target（n/w/js/gc） |
| --- | --- | --- | --- | --- | --- |
| [01-calls](01-calls/) | Request/Response/Call/自动头/取消 | ✅ 非侵入 | 无 | 4.5d | ✅✅⚠️❌ |
| [02-redirects-retries](02-redirects-retries/) | 重定向/路由重试/stale-retry | ✅ 非侵入 | 无 | 3d | ✅✅⚠️❌ |
| [03-connection-pool](03-connection-pool/) | Address/Route/连接池/驱逐 | ✅ 非侵入 | 可选 3 项（见 §3） | 5–7d | ✅✅⭕❌ |
| [04-interceptors](04-interceptors/) | 双层拦截器/Chain | ✅ 非侵入 | 无 | 3.5d | ✅✅⚠️❌ |
| [05-cache](05-cache/) | RFC 缓存/条件 GET/磁盘 LRU | ✅ 非侵入 | 无 | 10d | ✅✅⭕❌ |
| [06-events](06-events/) | EventListener 全事件 | ✅ 非侵入 | dns/connect 粒度可选 PR | 4.5d | ✅✅⚠️❌ |
| [07-tls-security](07-tls-security/) | 自定义信任/证书固定/cleartext | ✅ 非侵入 | ConnectionSpec/mTLS=深水 | 3.5d | ✅✅⭕❌ |
| [08-auth](08-auth/) | Authenticator/挑战/Basic | ✅ 非侵入 | 407 优雅化可选 PR | 3.5d | ✅✅⭕❌ |
| [09-request-bodies](09-request-bodies/) | Form/Multipart/流式/进度 | ✅ 非侵入 | fs stat 待验证 | 5d | ✅✅⚠️❌ |
| [10-timeouts-dispatcher](10-timeouts-dispatcher/) | 四类超时/Dispatcher/builder | ✅ 非侵入 | 无 | 3.5d | ✅✅⚠️❌ |
| [11-cookies](11-cookies/) | CookieJar/匹配/持久化 | ✅ 非侵入 | expires 预解析可选 PR | 3.5d | ✅✅⭕❌ |
| [12-websocket](12-websocket/) | WebSocket（listener/心跳） | ✅ 非侵入（底座已有） | 无（js 桥在 L1） | 4.5d | ✅✅✅❌ |
| [13-http2](13-http2/) | H2 多路复用/HPACK | ⚠️ 双路线 | ALPN=上游深水（三后端） | ~6.5w | A:✅✅—❌ |
| [14-performance](14-performance/) | （性能专项路线图） | ✅ 见杠杆表 | 2 处高价值小 PR | 含于各篇 | — |
| [15-debug-logging](15-debug-logging/) | 帧日志/TaskRunner 日志 | ✅ 非侵入 | 无 | 1.5d | ✅✅✅❌ |
| [16-target-support](16-target-support/) | （target 策略/降级清单） | — | wasm-gc=上游阻塞 | 3.5d | — |

图例：✅完整 ⚠️降级可用 ⭕语义退化/无意义 ❌不可用 | n/w = native/wasm，js，gc = wasm-gc

**OkHttp 能力全景的 N/A 项**（Java/Android 特有，不构成 MoonBit 工作项）：安全提供者体系（§7——我们的"provider"即 OpenSSL/Schannel/moonrun-RustTLS 三后端，见 07 §2）；R8/ProGuard（§13——无等价混淆管线）；版本支持窗口（§14）；生态集成（§15——对应 MoonBit 生态待建：mock server/类型安全客户端等，可作为后续 roadmap）。

## 3. 侵入点总表（全部备选，均不阻塞主线）

| # | 侵入点 | 位置 | 规模 | 必要性 | 出处 |
| --- | --- | --- | --- | --- | --- |
| I1 | 发送缓冲 1KB→16KB（上传 syscall ÷16） | async/http `send.mbt:85` | ~5 行 | **高价值**，建议立即 PR；无绕行 | 14 §3.1 |
| I2 | DNS 缓存 | async/socket `connect_to_host` | ~30 行 | 高价值 PR；L1 可非侵入自组 | 03 §3.5 |
| I3 | connect 阶段事件回调（dns/tcp/tls 分界） | async/http `client.mbt:40-85` | ~20 行 | 改善 06 粒度 | 06 §4 |
| I4 | CONNECT 407 挑战回调 | async/http `client.mbt:48-53` | ~15 行 | 08 的优雅化（现有绕行可用） | 08 §4 |
| I5 | Host 头覆盖（http-over-proxy absolute-form） | async/http `client.mbt:58` | ~5 行 | 解锁 http 代理不建隧道 | 03 §3.6 |
| I6 | `Client::enable_keepalive` 透传 | async/http | ~10 行 | 可选（okhttp 默认也不开 TCP keepalive） | 03 §4 |
| I7 | Cookie expires 预解析 | async/http `cookie.mbt` | ~10 行 | 可选 | 11 §4 |
| I8 | 响应头零拷贝解析 | async/http `parser.mbt:257-290` | 1–2d | 基准驱动 | 14 §3.2 |
| I9 | gzip 解压下沉线程池 | async/internal | 深 | 基准驱动 | 14 §3.5 |
| I10 | **ALPN** | async/tls 三后端（openssl_loader/schannel/moonrun） | 2–3d+moonrun 排期 | **HTTP/2(https) 的硬前提** | 13 §3.4 |
| I11 | TLS 会话复用 | async/tls 三后端 | 1–2w | 性能（量化后决策） | 07/14 |
| I12 | ConnectionSpec（版本/套件）/客户端证书 | async/tls 三后端 | 深 | okhttp 对齐缺口，记录不做 | 07 §3.4 |

处理原则：I1–I7 以 **PR 回馈上游**为目标（改动小、收益普适）；PR 合并前 L1 用非侵入替代或明确降级；I10–I12 是深水区，只有 H2(https)/TLS 精细控制依赖，单列里程碑不阻塞其他一切。

## 4. 里程碑（每期独立可用）

| 期 | 内容 | 交付判据 | 人力 |
| --- | --- | --- | --- |
| **M1 性能核心** | 01 core + 03 池 + 02 重定向重试 + 10 超时 + 杠杆 L2/L3 | round2 基准复刻 ≥20×；stale-retry 闭环；可控服务端全绿 | ~16d |
| **M2 完整门面** | 04 拦截器 + 09 bodies + 11 cookies + 08 auth + 上游 PR 包（I1/I2） | OkHttp recipes 全套可写；上传 syscall 达标 | ~16d |
| **M3 可观测与安全** | 06 events + 07 pinning/trust + 15 logging | 事件序列快照；pinning 对拍 openssl 工具链 | ~9.5d |
| **M4 缓存** | 05（先内存后磁盘） | okhttp CacheTest 场景移植通过 | ~10d |
| **M5 WebSocket 与 target 收口** | 12 + 16（js 适配/wasm-gc stub） | echo 全链路 + node/浏览器双跑 | ~8d |
| **M6 HTTP/2** | 13 路线 A（h2c）→ ALPN PR → 路线 B | h2spec 子集 + h2load 对比 H1 池 | ~6.5w+上游 |

累计（不含 M6）：**~60 人日**。

## 5. 性能账本（详见 [14-performance](14-performance/)）

| 杠杆 | 侵入性 | 收益 |
| --- | --- | --- |
| 连接池（M1） | 非侵入 | churn 10ms → 0.18–0.42ms/req，**47–56×**（实测） |
| 定长帧 + 头块缓存（M1） | 非侵入 | 线上字节/解析分支节省；重试重放零成本 |
| DNS 缓存（M2） | 非侵入自组 / 30 行 PR | 新建连接场景省 getaddrinfo 往返 |
| 发送缓冲 16KB（M2, I1） | ~5 行 PR | 上传 syscall ÷16 |
| 缓存命中（M4） | 非侵入 | 整个网络往返 + 服务端时间 |
| TLS 会话复用（I11） | 深水 | 短连接场景握手 1-RTT |
| HTTP/2（M6） | h2c 非侵入 / ALPN 侵入 | 同 host 并发连接成本→0，头字节 ~-90% |

## 6. 报告使用说明

- 每个特性文件夹统一结构：OkHttp 规格 → async/http 现状（行号证据）→ 实现方案（MoonBit API 草案与关键算法）→ **侵入性清单** → target 矩阵 → 性能影响 → 工作量/依赖 → 测试方案。
- 实现时先读 01/03/04（地基三篇），其余按里程碑引用。
- 所有对 reqbest（Apache-2.0）的移植（HPACK、br/zstd 协商参考）按既有研究 §8 的署名合规清单执行。
