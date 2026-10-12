# 06 事件与可观测性（EventListener）

> 结论：**非侵入可实现**。所有事件点都在 L1 执行管道与连接池的既有阶段上，打桩即可。

## 1. OkHttp 行为规格

- `EventListener` 采集 HTTP 调用度量：调用规模/频率、网络层性能。
- 完整事件序列：`callStart` → `dnsStart/End` → `connectStart` → `secureConnectStart/End`（TLS）→ `connectEnd`（或 `connectFailed`）→ `connectionAcquired/Released` → `requestHeadersStart/End` → `responseHeadersStart/End` → `responseBodyStart/End` → `callEnd`（或 `callFailed`）。
- `EventListener.Factory`：每 Call 创建独立 listener（per-call 状态与采样，如只统计 10%）。
- 重试/follow-up 下事件重复语义：每次网络交换重复 connect/request/response 系列；callStart/End 每调用一次。
- 公共 API 自 3.11 起提供，未来可能新增事件（接口需前向兼容）。

## 2. async/http 现状（证据）

- 零可观测性 API（无 listener/hook/metric，探索代理核实）。
- 阶段可分性（打桩点是否存在）：
  - DNS/连接/TLS 阶段被 `Client::connect` 整体封装（`client.mbt:40-85`）——**事件粒度受限**：dnsStart/End 与 connectStart/TLS 分界不可见（见 §4）；
  - requestHeaders/responseHeaders/body 各阶段由 L1 自己调 `client.request/write/end_request/read`（01 §3.5），粒度完整；
  - 连接取出/归还 = 池事件（03），完整；
  - 时钟：`@async.now()`（runtime 提供，毫秒精度）。

## 3. 实现方案

### 3.1 类型（函数字段 struct，全部带默认 no-op）

```moonbit
pub struct EventListener {
  call_start            : (CallStart) -> Unit
  dns_start / dns_end   : (DnsEvent) -> Unit          // 仅非侵入模式粗粒度可用（§4）
  connect_start / connect_end / connect_failed : (ConnectEvent) -> Unit
  secure_connect_start / secure_connect_end     : (SecureConnectEvent) -> Unit
  connection_acquired / connection_released    : (ConnectionEvent) -> Unit
  request_headers_start / end                  : (HeadersEvent) -> Unit
  response_headers_start / end                 : (HeadersEvent) -> Unit
  response_body_start / end                    : (BodyEvent) -> Unit
  call_end              : (CallEnd) -> Unit
  call_failed           : (CallFailed) -> Unit         // 携带错误类型
}
pub struct EventListenerFactory { create : () -> EventListener }   // okhttp Factory：per-call 实例
// 事件结构统一携带：call 标识、时间戳（@async.now()）、地址、耗时（end 事件 = now - start）
// ConnectionEvent 附加：Lease 信息（Address；TLS 证书 DER 经 get_peer_certificate 已挂，07 §3.3）
```

- 挂点（全部在 L1 已有代码路径）：execute 入口（callStart）、`pool.acquire` 前后（connectionAcquired/Released——含"从池取出"与"新建"两种来源，事件字段 `reused : Bool` 对齐 okhttp）、每次写头/写体块、读头/读体首块、终态/异常（callEnd/callFailed）。
- 采样：Factory 里掷随机（10% 采样示例写进 README）；未配置 listener 时字段为 no-op 函数——每事件一次间接调用 ~ns 级。

### 3.2 与重试/follow-up 的重复语义

- 每次 follow-up（02）走完整网络交换 → request/response 系列重复；connect 系列仅当新连接建立时重复（连接复用时不发 connect 事件，但 connectionAcquired 每次租借都发——okhttp 同语义）。
- `call_failed` 在 follow-up 链中途失败时携带：发生阶段、follow-up 深度、底层错误（`Error`）。

### 3.3 内建消费者（增值组件，对齐生态调试工具）

- `MetricsCollector`：聚合 p50/p95 延迟（dns/connect/tls/ttfb/total 分桶）、吞吐、错误率分类——内存环形桶，暴露 `snapshot() -> Json`。
- `LoggingEventListener`：结构化日志行（对齐 okhttp-tls-island 的调试输出），接 15 的日志门面。

## 4. 侵入性清单

| 项 | 级别 | 说明 |
| --- | --- | --- |
| 全部事件类型与挂点（L1 粒度） | **非侵入** | — |
| dnsStart/End、connect/TLS 分界事件 | 侵入 async/http（**中度**） | `Client::connect` 内部封装 DNS→TCP→TLS（`client.mbt:40-85`）。两种做法：①【侵入 ~20 行】`Client::connect` 加 `on_event? : async (ConnectStage) -> Unit` 回调（DnsStart/DnsDone/TcpConnected/TlsHandshaking/TlsDone 五档），**建议提上游 PR**（对 06/13/14 三篇都有价值）；②非侵入近似：connect 整体计为 connect_start..connect_end 一段，`reused` 池事件区分新建——**M1 采用 ②**，事件语义文档标注粗粒度 |
| ns 级时间戳 | 侵入 async（可选） | `@async.now()` 毫秒精度；快事件对（requestHeadersStart/End）会显示 0ms。ps 级需 runtime 计时器增强，不做；文档标注精度 |

## 5. Target 支持矩阵

| target | 支持 | 说明 |
| --- | :-: | --- |
| native / wasm | ✅ | 同路径（毫秒精度） |
| js | ⭕ | fetch 层无 DNS/connect 粒度（浏览器不暴露）；request/response/body/call 系列可用 |
| wasm-gc | ❌ | runtime 级缺口（16） |

## 6. 性能影响

- no-op 监听：每调用 ~20 次函数指针调用 + 结构体构造（仅当字段非 no-op 才构造事件——实现时用"全局无监听则整段跳过"的快路径），<1µs/调用。
- MetricsCollector 环形桶：每事件 O(1) 更新，无分配路径（预分配桶）。
- 采样率是运行时配置（Factory 内实现），无重编译。

## 7. 工作量与依赖

- 依赖：01/03/04（挂点在执行管道上成型后打桩）。
- 估计：事件类型+挂点 ~1.5 人日；重复语义+失败语义 ~1；MetricsCollector ~1；测试 ~1。**~4.5 人日**（可与 02–05 并行，管道稳定后收口）。

## 8. 测试方案

- 事件序列断言（对齐 okhttp EventListener 顺序）：全新调用（含新建连接）的完整序列；复用连接的序列（无 connect 系列）；3 跳重定向的重复序列；stale-retry 的 connectFailed→重连序列；取消/超时的 callFailed。
- Factory per-call 隔离（并发下事件不串号）。
- 采样正确性（10% 采样下总量守恒）。
