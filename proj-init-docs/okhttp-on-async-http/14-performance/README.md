# 14 性能专项（提高请求性能的完整路线图）

> 目标函数：单请求延迟（p50/p95）、吞吐（req/s）、每请求内存分配、连接建立成本。
> 结论：**池化 + 定长帧 + 头块缓存（全部非侵入）构成第一阶段杠杆，既有实测合计 25–56×**；第二阶段依赖 2 处高价值上游 PR（发送缓冲、TLS 会话复用）与 H2（13）。

## 1. 基线与既有实测（`../../round1-3 *.raw.md`，loopback + Python 服务端）

| 场景 | 每请求延迟 | 相对 |
| --- | --- | --- |
| 每请求新建连接（churn） | ≈10,029–10,047 µs | 1× |
| 单连接顺序复用 | 415–431 µs（async/http 430.8） | ~24× |
| 自研池 K=16 | 178–196 µs（5,113–5,631 req/s） | **47–56×** |

生产环境（真实 RTT）差距更大：churn 含 TCP+TLS 握手 ≈2–3 RTT，跨区域 30–100ms/请求。

## 2. 杠杆清单（按 ROI 排序）

| # | 杠杆 | 侵入性 | 预期收益 | 成本 | 出处 |
| --- | --- | --- | --- | --- | --- |
| L1 | **连接池**（复用+并发租借+驱逐） | 非侵入 | 24×→56×（实测背书） | ~5 人日 | 03 |
| L2 | **定长帧**：已知长度 body 走 `extra_headers~{Content-Length}` → `SendingFixed` | 非侵入 | 消除 chunked 每块 5+ 字节编码/解析与服务端分支；小请求体上数百字节/请求的线上字节节省 | ~0.5 人日 | 01 §3.3、round3 实测 |
| L3 | **头块预序列化缓存**：Request 头在 follow-up/retry 重放时零重排 | 非侵入 | 重定向/重试路径 CPU；每跳省一次 Map 迭代+逐段 blit（`send.mbt:292-311`） | ~0.5 人日 | 01 §6 |
| L4 | **DNS 缓存**（L1 自组 or 上游 PR） | 非侵入/侵入 30 行 | 高频新建连接场景省 getaddrinfo（thread pool 往返 ~100µs+） | ~1 人日 | 03 §3.5 |
| L5 | **上传路径发送缓冲 1KB→16KB**（syscall 放大修复） | 【侵入 async/http ~5 行】 | 大 body 上传写系统调用次数 ÷16（详见 §3.1，重要发现） | 半天 PR | §3.1 |
| L6 | **响应头解析零拷贝** | 【侵入 async/http，中】 | 每响应头每行省一个 UTF-16 String 分配（`parser.mbt:257-290` `read_until`） | 1–2 人日 | §3.2 |
| L7 | **TLS 会话复用** | 【侵入 async/tls，深（三后端）】 | 短连接高频场景省握手 1-RTT+非对称运算（~10–50ms 级） | 1–2 周 | §3.4 |
| L8 | **HTTP/2 多路复用 + HPACK** | 非侵入（h2c）/侵入（ALPN） | 同 host 并发下连接成本→0；头字节 ~-90% | ~6.5 周 | 13 |
| L9 | 透明解压扩展 br/zstd（Accept-Encoding 协商面加宽） | 非侵入（引 bikallem/compress） | 高压缩比场景传输时延 | ~1 人日 | 04 §4 |
| L10 | gzip 解压下沉线程池 | 【侵入 async/internal】 | 大 gzip 响应不阻塞事件循环（百 ms 级 CPU 段） | 中 | §3.5 |

## 3. 源码级热点分析（本仓库逐行核对）

### 3.1 上传写路径 syscall 放大（L5，新发现）

`Sender.send_buf` 固定 1KB（`send.mbt:85`）。三条写路径全部"填满 1KB 即 flush"：
- `write_once` 的 `SendingFixed/SendingBody` 分支：拷贝 `min(len, 1KB - send_len)` 后下次调用再 flush（`send.mbt:123-131`）；
- `write_reader` 的 `SendingFixed`：每读满 1KB `flush()` 一次（`send.mbt:188-205`）；chunked 同构（`send.mbt:221-239`）。

⇒ 上传 1MB body ≈ **1024 次 `writer.write` 系统调用**（每次 ≤1KB）。TCP_NODELAY 恒开（`tcp.mbt:283`）下即 ~1024 个小段。
**修复**：`send_buf` 扩到 16KB（或 `Sender::new` 参数化/按首次大写入增长）。上游 PR 极小（改一个 `FixedArray::make(1024,...)` + 预留逻辑常量），收益与 body 大小线性。L1 侧无绕行（Sender 为 priv，Client 不可注入 writer 包装）→ 必须上游。

### 3.2 响应头解析分配（L6）

`Reader::read_headers` 每行 `read_until("\r\n") -> String`（`parser.mbt:261`）：每头一次 UTF-16 String 分配 + 行内两次子串 `to_owned`（name/value，`parser.mbt:269,276-278`）。典型 15 头响应 ≈ 45 个字符串对象。
**非侵入缓解**：无（解析在 @http 内部）。
**侵入方案**：`read_headers` 直接在 `ReaderBuffer` 的字节域上扫描（现成的 `@io_buffer.Buffer` 视图，`parser.mbt:443` 已有 get_repr 通道），仅对最终保留的 name/value 做 `to_owned`——分配从 3n 降到 2n 且全 ASCII 快路径；HTTP/1.1 服务端（server.mbt 同函数族）同样受益。

### 3.3 请求头序列化（L3 的现状细节）

持久头已在连接建立时序列化为 `Bytes` 缓存（`send.mbt:64-90`，好设计）；但每请求的 `extra_headers` 走 Map 迭代 + 逐段写入（`send.mbt:292-311`），且 `sanitize_header_value` 对每个值做一遍 CRLF 扫描（快速路径免分配，`send.mbt:42-61`，尚可）。L1 的 Request 头块缓存（L3）把这部分从"每跳"变"每 call 一次"。

### 3.4 TLS 握手成本（L7）

无会话复用 API（07 §2）。池化后握手只在新建连接发生（好）；受影响场景：并发突刺（池扩容）、驱逐频繁、短生命周期进程。OpenSSL session cache（`SSL_CTX_set_session_cache_mode` + `SSL_SESSION` 复用）在 openssl_loader 路径可行；Schannel 需 `SCH_CRED` 会话缓存；moonrun 宿主随 ALPN 一起排。**量化后再决定优先级**（基准见 §5）。

### 3.5 事件循环阻塞点（L10）

大 gzip 响应解压在事件循环内（`parser.mbt:57-126` 解码循环）。>10MB 响应的解压 CPU 段会延迟其他协程。fs 已有 thread pool 先例（AGENTS.md：阻塞操作下沉线程池）；gzip 下沉需改 `gzip_internal` 与 parser 的接口（异步化 `gzip.write`）——侵入较深，仅在基准证明必要后做。

### 3.6 已达标项（无需动作）

- TCP_NODELAY 自动开启（`tcp.mbt:283`）✅
- Happy Eyeballs 建连竞速（`happy_eyeball.mbt:30-106`）✅（250ms 固定间隔 vs RFC 8305 动态——影响极小，不动）
- 持久头连接级缓存（`send.mbt:87`）✅
- 读侧缓冲内建（`ReaderBuffer`，io trait 设计）✅
- `CaseInsensitiveString` 比较哈希零分配（`case_insensitive_string.mbt:21-52`）✅

## 4. js/wasm 特有

- js：连接由浏览器管理，L1–L5 无意义；有效杠杆=缓存（05，浏览器 Cache API 或内存）、Dispatcher 合并、避免 body 多次缓冲（fetch 一次性 body——`client.js.mbt:196-202` 已缓冲，大上传注意内存）。
- wasm：全杠杆适用（moonrun 宿主 socket/tls）；syscall 概念映射到宿主调用，L5 同样有效。

## 5. 基准方法论（可复现）

1. 服务端：`examples/http_server_benchmark`（本仓库）或可控 Python 夹具（round1–3 同款，脚本在 `mio/_connmeasure/`）；
2. 场景矩阵：{churn, 复用, 池 K∈{1,4,16,64}} × {GET, POST 定长, POST chunked, 上传 1MB/100MB} × {gzip 响应开/关}；
3. 指标：p50/p95/p99、req/s、（native）进程 RSS 曲线、（可选）moon 编译期 alloc 检查；
4. 环境：loopback（与 round1–3 可比）+ 真实网络点（延迟分层：1ms/30ms/100ms）；
5. 验收门槛（写进库 CI 的性能门禁，防回归）：池化路径相对 churn ≥20×；上传 100MB 系统调用数 ≤ 每 16KB 一次（L5 落地后）。

## 6. 落地顺序建议

M1（随 03/01 交付）：L1+L2+L3 → 立即兑现 25–56×。
M2（上游 PR 包）：L5（半天、收益线性）+ L4（30 行）——**优先提交 async 仓库**，PR 期间 L1 用非侵入 DNS 缓存兜底。
M3：L9；评估 L6/L7 的基准数据决定是否推进。
M5：L8（13 全量）。
