# 03 连接管理：Address/Route 抽象 + 连接池（ConnectionPool）

> 结论：**非侵入可实现，且是全项目最大的性能杠杆**（既有实测：新建连接 ≈10ms/请求 → 复用 ≈0.42ms → 池化并发 ≈0.18ms，47–56×）。
> 本篇是"提高请求性能"的主战场，与 `14-performance` 互引。

## 1. OkHttp 行为规格

- 三层抽象：**URL → Address**（静态配置：host/port/TLS 设置/协议偏好）**→ Route**（动态：具体 IP、代理、TLS 版本）。
- **ConnectionPool**：按 Address 复用 HTTP/1.x 连接；HTTP/2 连接多路复用（见 13）；闲置驱逐（默认 keepAlive 5 分钟、maxIdle 5 条）；用完归还。
- 连接建立：直连 / CONNECT 隧道（HTTP 代理上的 HTTPS）/ 直连 TLS；失败换路由重试。
- **Fast Fallback（RFC 6555 Happy Eyeballs）**：并发尝试多条路由，IPv6/IPv4 交替竞速，仅在胜者上做 TLS。
- 代理选择：`ProxySelector`（系统代理/直连/显式代理）。

## 2. async/http 现状（证据）

| 项 | 现状 | 证据 |
| --- | --- | --- |
| 单连接复用 | ✅ `Client` 顺序 keep-alive（request→end_request→request…），但**严格单请求在途**（sender.mode 状态机 + `request_method` 可变字段） | `src/http/client.mbt:23-31`、`send.mbt:16-23` |
| 顶层便捷函数 | 每请求一条新连接并 `defer close()` | `src/http/request.mbt:84-96` |
| 连接池 | ❌ 无任何池化设施（全仓 grep） | 探索代理核实 |
| Happy Eyeballs | ✅ **已有**：getaddrinfo 全量结果并发 `spawn_bg` 竞速、250ms 固定间隔、首个成功者保留；`FavorV4/V6` 为"先跑完一族再跑另一族"的串行 fallback | `src/socket/happy_eyeball.mbt:30-106` |
| TCP_NODELAY | ✅ connect/accept 时无条件开启 | `src/socket/tcp.mbt:283,193,213` |
| TCP keepalive | API 有（`enable_keepalive(idle_before?, count?, interval?)`）但 `Client` 不暴露内部 socket，**够不着** | `tcp.mbt:257`、`client.mbt:16-19`（`ClientTransport` 为 priv） |
| DNS | getaddrinfo 走线程池（native），**无缓存**；`Addr::resolve(host, port~, protocol?)` 与 `Tcp::connect(Addr)` 均公开，可上层自组 | `src/internal/event_loop/network.mbt:25`、`socket/pkg.generated.mbti:30,51-52` |
| 代理 | `proxy? : Client` 恒走 CONNECT 隧道（http 与 https 同样）；代理即另一个 Client，支持代理认证（向代理 Client 发 407 处理由上层处理） | `client.mbt:48-53` |
| TLS 会话复用 | ❌ 无显式 API（TLS1.3 ticket 仅单连接内自然发生） | 探索代理核实，tls 包 0 命中 |
| 闲置连接死活检测 | ❌ 无 aliveness 查询；只能读失败后感知 | — |

## 3. 实现方案

### 3.1 Address（池键）

```moonbit
pub(all) struct Address {
  scheme : Scheme                // http/https
  host : String                  // 已剥 IPv6 括号（01 §3.2）
  port : Int
  // 以下参与键指纹，等价 okhttp Address 的 proxy/tls/protocols 字段
  proxy : ProxyConfig?           // Direct / Http{addr, auth?} / None
  trust : TrustFingerprint       // SystemRoot | NoVerification | CustomPemFile(hash)
}
fn Address::key(self) -> String  // 或 derive(Hash, Eq)；建议直接 derive
```

- Route 层（具体 IP）**不进键**：async 的 Happy Eyeballs 藏在 `connect_to_host` 内部，L1 不感知 IP 选择；路由重试语义由 02 §3.3 的整体重试覆盖。若未来要 OkHttp 级 RouteSelector（每 IP 独立池化/统计），需侵入 socket 暴露地址列表——**列为可选侵入项，不建议 M1 做**。

### 3.2 池数据结构与租约

```moonbit
pub struct ConnectionPool {
  max_idle : Int                 // okhttp 默认 5
  keep_alive : Int               // ms，okhttp 默认 5min
  inner : Mutex[PoolInner]       // 事件循环单线程，Mutex 主要防 re-entrancy/未来多线程
}
priv struct PoolInner {
  idle : Map[Address, Array[IdleLease]]   // 每地址空闲栈（LIFO：热连接优先，okhttp 同款）
  per_host_total : Map[Address, Int]      // 观测用（06）
  evict_timer : Timer?                    // 周期清扫
}
priv struct IdleLease { conn : @http.Client, idle_since : Int64 /*ms*/ }

pub struct Lease {              // 租约：一次 exchange 的连接句柄
  addr : Address
  conn : @http.Client?
  pool : ConnectionPool
  mut poisoned : Bool
}
```

核心流程（全部非侵入，用 `Client::connect` 公开 API）：

```
acquire(addr):
  1. idle[addr].pop() 命中 → 返回 Lease（LIFO，最热连接最可能仍活着）
  2. 未命中 → 新建：
     let conn = with_timeout(connect_timeout) {
       match proxy {
         None     => @http.Client::connect(host, protocol=scheme, trust~)
         Some(p)  => 经代理 Client CONNECT（p 作 proxy~ 参数，client.mbt:48-53）
       }
     }
  3. （可选）DNS 缓存命中时：绕过 connect_to_host，用缓存的 Addr 列表自组竞速（见 3.5）

release(lease):
  body 已消费完 ∧ !poisoned ∧ idle[addr].len < max_idle → push 回 idle 栈
  否则 → conn.close()
```

- **独占语义**：`Client` 单请求在途状态机（现状证据）⇒ 租约期间该连接只属于当前 exchange，池本身无需 per-connection 锁；池的 Mutex 只保护 idle 栈的取放（临界区内无 IO，符合"IO 时不持锁"）。
- **归池前提**：响应体读完（或 `skip_response_body()`）且 `end_request` 已返回——由 01 §3.6 的 StreamBody 析构路径保证；**未读完即被丢弃 → 毒化**（连接上有残数据，复用必错）。

### 3.3 驱逐与清扫

- 空闲超时：`Timer` 周期（如 keep_alive/2 或固定 1s）扫描 `idle_since`，超 `keep_alive` 的 `close()`。runtime `Timer::cancel/refresh/wait`（`src/pkg.generated.mbti:105-108`）够用；Timer 挂在 HttpClient 的 TaskGroup 上，client 析构时取消。
- `evictAll()` / 惰性关闭：全量 close；`Client::close` 幂等（`client.mbt:142-151`），重复安全。
- **被动检测为主、主动探测为辅**：OkHttp 不主动探测空闲连接，靠取出后失败的 stale-retry 兜底（02 §3.3）。我们同样如此——**这是池化正确性的关键设计**：闲置连接被服务端/中间设备静默关闭是常态，必须有"首读失败→毒化→新连接重放"的闭环。

### 3.4 毒化路径汇总

| 场景 | 处理 |
| --- | --- |
| stale-retry 命中（02） | close，不回池，`pool.stale_evictions += 1` |
| Call.cancel / 超时取消 | close（半途请求状态不可复用） |
| 响应体未消费完即弃 | close（残数据） |
| `Connection: close` 响应头 | 读完 body 后 close（HTTP/1.1 语义；注意读响应头后检查 `headers["Connection"]`） |
| 协议错误（BadRequest 等） | close |

### 3.5 DNS 缓存（可选增强，仍非侵入）

现状每次新建连接都 getaddrinfo（无缓存）。池化本身已把 DNS 次数降到与新建连接数同阶。若进一步优化：

- L1 维护 `Map[String, (Array[@socket.Addr], Int64 /*expiry*/)]`，TTL 取 resolver 返回的 min TTL（不可得时默认 30s）。
- 命中时绕过 `connect_to_host`（它内部必做 getaddrinfo）：取缓存 Addr 列表，用 `@async.any` + `Tcp::connect(addr)` + 250ms 错峰复刻竞速（`happy_eyeball.mbt:30-106` 的同款语义，~40 行）。
- 未命中时 `Addr::resolve` 填缓存。**注意**：绕过 connect_to_host 后失去其内部的错误分类，需自行包装。
- 侵入替代（更好但需动上游）：在 `connect_to_host` 内加进程级缓存——**【侵入 async/socket，~30 行】**，收益是所有用户共享；建议以 PR 形式回馈上游，L1 先用非侵入版本。

### 3.6 代理形态

- 现状 `proxy? : Client` 要求调用方先自建代理 Client 且恒走 CONNECT（`client.mbt:48-53`）。L1 包装：`ProxyConfig::Http{addr, auth?}` → L1 持有/池化"到代理的 Client"（本身也进一个代理连接池），CONNECT 隧道建立后包装成目标 Address 的连接。
- **http over proxy 的 absolute-form**：OkHttp 对 http（非 https）代理不建隧道、直接发 `GET http://origin/path`。非侵入做法：连接到代理 host，`Client::request` 的 `path` 传完整绝对 URL 字符串。**已知缺陷**：`Client::connect` 已把 `Host` 写进持久头（`client.mbt:58`），extra_headers 再传 Host 会**重复发送两个 Host 头**——处理：L1 不走 `Client::connect` 的自动 Host，改为自己拼（不可行，Host 在 connect 内强制写入）→ **【侵入 async/http，~5 行】在 `Client::connect` 增加 `set_host? : Bool = true` 或允许 headers 覆盖 Host**；非侵入替代：absolute-form 场景接受 `Host: proxy`（多数代理容忍但违反 RFC 9110 §7.2）或 M1 不支持 http-over-proxy absolute-form（CONNECT-only，多数现代代理支持）。**建议：标记为已知限制，M2 提上游 PR。**
- 系统代理（ProxySelector 等价）：native 读环境变量 `http_proxy/https_proxy/no_proxy`（纯上层）；Windows 注册表/系统设置不在 M 范围。

### 3.7 与 OkHttp 语义差异清单（明确告知用户）

1. 无 HTTP/2 多路复用 ⇒ 每 host 并发 = 连接数（OkHttp 同站默认 5 连接上限由 Dispatcher 间接造成，行为接近；13 补齐后语义对齐）。
2. Route 不进池键（见 3.1）。
3. 无连接级 keep-alive 帧探测（OkHttp 亦无）。

## 4. 侵入性清单

| 项 | 级别 | 说明 |
| --- | --- | --- |
| 池/租约/驱逐/毒化 | **非侵入** | 全部经 `Client::connect/close/skip_response_body` 公开 API |
| TCP keepalive 开关 | 【侵入 async/http，~10 行】 | `ClientTransport` 为 priv，需加 `Client::enable_keepalive()` 透传 `tcp.mbt:257`。非侵入替代：纯靠应用层驱逐（OkHttp 默认也不开 TCP keepalive）→ M1 不做 |
| DNS 缓存 | 非侵入（L1 自组）/【侵入 async/socket ~30 行】（上游 PR） | 见 3.5 |
| http-over-proxy absolute-form 的 Host 覆盖 | 【侵入 async/http，~5 行】 | 见 3.6；M1 以 CONNECT-only 降级 |
| TLS 会话复用（握手加速） | 【侵入 async/tls，深】 | 需 OpenSSL `SSL_CTX` session cache / Schannel / moonrun 宿主三处改造，见 07/14；列为长期项 |
| Route 级选择器 | 【侵入 async/socket】 | 暴露 resolve 结果列表；不建议 |

## 5. Target 支持矩阵

| target | 支持 | 说明 |
| --- | :-: | --- |
| native | ✅ | 全功能（含 CONNECT 代理、DNS 缓存） |
| wasm | ✅ | socket = moonrun 宿主 TCP 直通（非 websocket 桥接，`ffi.wasm.mbt`）；TLS = 宿主 Rust TLS。池逻辑同源；宿主 socket 语义差异（如 RST 行为）需在 stale-retry 测试覆盖 |
| js | ⭕ 无意义 | fetch 连接由浏览器管理；池层在 js 后端退化为空实现（Lease=Client 直通）；Dispatcher/缓存层仍有意义 |
| wasm-gc | ❌ | runtime 级缺口（16） |

## 6. 性能影响（量化）

既有实测（`../../round1-fresh-vs-reuse.raw.md`、`round2-connection-pool.raw.md`、`round3-chunked-verification.raw.md`，loopback、Python 服务端）：

| 场景 | 每请求延迟 | 相对新建连接 |
| --- | --- | --- |
| 每请求新建连接 | ≈10,029–10,047 µs | 1× |
| 单连接顺序复用 | 415–431 µs | ~24× |
| 池 K=16 并发 | 178–196 µs | **47–56×**（5,100+ req/s） |

- 生产环境收益更大：真实 RTT 下 TLS 握手 + TCP 握手 ≈ 2–3 RTT，跨区域 30–100ms/连接。
- 池开销本身：Map 查找 + 栈弹出 + Mutex 取放 ≈ 亚微秒级，可忽略（事件循环单线程，临界区无 IO）。
- 内存：每空闲连接持有 Reader 缓冲 + 1KB send_buf（`send.mbt:85`）+ TLS 上下文；max_idle=5 默认下峰值内存增量 ~几百 KB 量级。

## 7. 工作量与依赖

- 依赖：01（Address 材料）、02（毒化/stale-retry 闭环，互相引用）。
- 估计：池核心+租约+驱逐 ~2 人日；stale-retry 集成 ~1（计入 02）；代理池化 ~1；DNS 缓存 ~1（可选）；测试（含对拍 `examples/http_server_benchmark` 与 Python 夹具）~2。**~5–7 人日**。

## 8. 测试方案

- 基准复刻 round2：本池 vs 每请求新连接，K∈{1,4,16,64}，断言加速比量级；长跑（≥10k 请求）无泄漏（池内 idle 数守恒、fd 不增长）。
- 驱逐：空闲超时后 idle 清空；`evictAll` 幂等。
- 毒化表（3.4）逐行：用可控服务端（`test_programs` 已有 cancellation 基建，commit 5c2d2ea）制造半关/RST/残 body。
- 并发正确性：同 host 高并发下无串响应（响应体串号检测：每个请求带唯一 id，body 回显校验）。
