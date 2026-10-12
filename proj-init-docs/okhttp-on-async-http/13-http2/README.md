# 13 HTTP/2（多路复用 + 并发模型）

> 结论：**技术上可行但双高**（工作量大 + 依赖一处关键侵入）。分两条路线：
> **路线 A（非侵入，h2c/先验知识）**：H2 帧层 + HPACK 自建，跑在 `Client::enter_passthrough_mode` 的裸流上——可行，但公网 https 场景几乎不可用（无 ALPN 协商不出 h2）。
> **路线 B（侵入 async/tls：ALPN，三后端）**：https 上协商 `h2`——真实世界的 H2 前提。
> 建议：M5 启动，且 ALPN 上游 PR 先行。

## 1. OkHttp 行为规格

- 连接池自动多路复用 H2 连接（同 Address 并发流共享一条连接）。
- 协议协商：ALPN（https）优先 H2、回退 HTTP/1.1；`protocols` 配置。
- 并发模型（设计文档）：应用线程阻塞式 API + 每 socket 专职**共享读线程**（只分发帧，永不跑应用代码）+ do-stuff-later 池；三把锁（Connection/Stream/Writer）与锁序约束。

## 2. async 现状（证据）

- `@http` 硬编码 HTTP/1.1（`parser.mbt:369,409` 版本串白名单），`HttpVersionNotSupported` 其他。
- **无 ALPN**（`@tls` 全仓 0 命中，探索代理核实）→ https 上无法协商 h2。
- 可用的地基：
  - `Client::enter_passthrough_mode`（`client.mbt:351-355`）：HTTP 层之上拿裸 TCP/TLS 流——**帧层可完全跑在其上，非侵入**；
  - runtime 单线程事件循环——**okhttp 并发模型中的"共享读线程 + 三锁"可以整体消解**（见 §3.3）；
  - 参考实现：reqbest 的 HPACK/Huffman + H2 帧（prior-knowledge、单流），Apache-2.0，可移植（既有研究 §4：'HPACK/Huffman、帧编解码可复用'；移植署名合规见其 §8）。

## 3. 实现方案

### 3.1 分层与接入点

```
L1 Connect 层：lease = pool.acquire(addr, protocol=H2PriorKnowledge | negotiated)
  ├─ H2PriorKnowledge：passthrough Client → H2Connection
  └─ negotiated（需 ALPN，路线 B）：Tls::client(..., alpn=["h2","http/1.1"]) → 按结果分流
H2Connection（连接拥有者协程）：
  ├─ 帧读写器（FrameReader/FrameWriter over @io.Reader/Writer）
  ├─ HPACK 编解码（动态表、Huffman 可选开关）
  ├─ 流表 Map[StreamId, H2Stream] + 流量控制窗口（连接级+流级）
  └─ 对接 03 池：一条 Lease 支持多并发流（池语义扩展：lease.refcount）
```

### 3.2 帧层与 HPACK（工作量主体）

- 帧：HEADERS(+CONTINUATION)/DATA/SETTINGS/ACK/PING/GOAWAY/RST_STREAM/WINDOW_UPDATE/PRIORITY(仅解析忽略)。
- 状态机：流 open/half-closed/closed；连接 preface `PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n` + SETTINGS 首交换。
- HPACK：静态表 61 项 + 动态表（FIFO 4096 上限可协商）；整数/字符串编码（Huffman 解码必需、编码可先 literal——多数服务端接受非 Huffman 编码，性能损失小）。
- 移植评估：reqbest 的 hpack/h2 已实现单流先验知识版本（既有研究），**复用其 HPACK 全量 + 帧编解码大部分**，新增多流调度——预计省 40% 工作量。署名合规按既有研究 §8 清单执行。

### 3.3 并发模型（单线程事件循环版，替代 okhttp 三锁设计）

- **无锁**：事件循环单线程天然串行；okhttp 的"共享读线程"角色 = 连接拥有者协程：
  ```
  owner_loop: for { frame = framer.read(); dispatch(frame) }   // 只做分发，不跑用户代码
    HEADERS/DATA → stream.mbuf 写入 + stream.waiter 唤醒（aqueue/callback）
    WINDOW_UPDATE → 更新窗口（可能唤醒被流控阻塞的写者）
    PING(ack=0) → 自动回 ACK；GOAWAY → 标记 draining，新流拒绝、存量读完
  ```
- **写侧防交错**：单一发送 aqueue——用户写 DATA 入 `H2Stream.outbound`，连接写协程按流轮转取块（避免大流独占：每流每轮 ≤ min(max_frame_size, 窗口)）。okhttp 的 `Http2Writer` 锁在此退化为队列串行化。
- **流控**：发送侧——窗口不足则挂起（窗口更新唤醒）；接收侧——读累积超过窗口一半自动回 WINDOW_UPDATE（okhttp 同策略）；SETTINGS_INITIAL_WINDOW_SIZE 协商。
- **与池/租约的集成（03 扩展）**：`Lease` 增加流计数（`refcount`）；归还条件 = 流 closed 且 refcount==0；GOAWAY/RST 后连接标 draining 不再接新流、存量自然排空后关闭。Dispatcher 的 per-host 并发上限在 H2 下由"流并发"承担（连接数少）。

### 3.4 ALPN（路线 B，【侵入 async/tls，三后端】）

1. `Tls::client` 增加 `alpn? : Array[String]` 参数 + `Tls::alpn_negotiated() -> String?` 查询；
2. OpenSSL：`SSL_CTX_set_alpn_protos` + `SSL_get0_alpn_selected`（loader 补 2 个符号）；
3. Schannel：`SEC_APPLICATION_PROTOCOLS` 扩展（Win8.1+；需在 `InitializeSecurityContext` 前挂 buffer——schannel.c 改造中等）；
4. wasm：moonrun 宿主 `tls/connection/*` FFI 扩展（**外部依赖 moonrun 发版**）。
- native 侧 ~2–3 人日；moonrun 排期不可控 → **先做 native，wasm H2 后置**。

### 3.5 降级与共存

- 协商失败/对端 GOAWAY → 自动回落 HTTP/1.1（连接池按协议分桶，03 §3.1 的 Address 键加 protocol 维度）。
- `protocols` 配置面：`[Http1_1]`（默认）/ `[H2, Http1_1]` / `[H2PriorKnowledge]`——对齐 okhttp `protocols`。

## 4.1 HTTP/3（附件隐含项）：不做

OkHttp 本体不含 H3（仅经第三方 Cronet transport 提供）；MoonBit 生态唯一的 H3/QUIC 实现是 reqbest 的实验路径（自研 TLS1.3 栈），既有研究 §6 已指出其 RNG 弱（仅 `@async.now()` 种子）与证书链校验不完整，不可对外暴露。结论：**H3 明确排除在范围外**，与 OkHttp 本体对齐；待上游出现生产级 QUIC + TLS1.3 栈后另行立项。

## 5. 侵入性清单

| 项 | 级别 | 说明 |
| --- | --- | --- |
| h2c/先验知识 H2（路线 A 全部：帧+HPACK+多流+池集成） | **非侵入** | passthrough 之上自建 |
| ALPN（https 协商） | 【侵入 async/tls：openssl_loader ~1 天 + schannel ~1.5 天 + moonrun 外部依赖】 | §3.4；**H2 的硬前提**，建议最早提上游 |
| `@http` 内嵌 H2 | 不做 | 保持 @http 纯 H1；H2 全在 L1（降低对底座侵入，符合本报告主旨） |

## 5. Target 支持矩阵

| target | 支持 | 说明 |
| --- | :-: | --- |
| native | 路线 A ✅ / 路线 B 待 ALPN | ALPN PR 后全量 |
| wasm | 路线 A ✅ / 路线 B 阻塞 moonrun | h2c 可先用 |
| js | ⭕ | fetch/浏览器自带 H2/H3——L1 无需实现；流语义由 ReadableStream 天然提供 |
| wasm-gc | ❌ | runtime 级缺口（16） |

## 6. 性能影响

- 多路复用：同 host 高并发下连接数骤减（N 请求 1 连接 vs 池 K 连接）——握手/TLS 摊薄到 ~0；round2 实测池 K=16 为 178µs/req，H2 预期再降（无连接建立争用、HPACK 头压缩 ~90% 头字节）。
- 流控/队头阻塞：H2 TCP 级队头阻塞仍存在（丢包阻塞全部流）——okhttp 同样；HQUIC 不在范围。
- 单线程分发：owner_loop 每帧一次 dispatch（µs 级），吞吐上限远高于 H1 路径。

## 7. 工作量与依赖

- 依赖：03（池/租约扩展）、04（Connect 层协议分流）、ALPN PR（路线 B）。
- 估计：HPACK 移植+补测 ~1.5 周；帧层+状态机 ~1 周；多流调度+流控 ~1.5 周；池集成+降级 ~0.5 周；测试（含 nghttpd/h2load 对拍）~2 周。**~6.5 人周**（不含 ALPN 上游工作）。

## 8. 测试方案

- 规范对拍：h2spec（Go 工具）跑合规子集；`h2load` 压测（对比 round2 的 H1 池数据）。
- 帧/流语义：CONTINUATION 合并、流控窗口耗尽阻塞与恢复、SETTINGS 协商、PING/GOAWAY 排空、RST 后流表回收、并发 100 流响应不串号（唯一 id 回显）。
- 降级：协商失败回 H1；GOAWAY 后新请求换连接。
- 内存：流表/动态表上限（SETTINGS_MAX_HEADER_LIST_SIZE 拒超）。
