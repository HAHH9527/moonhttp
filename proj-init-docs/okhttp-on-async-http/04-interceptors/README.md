# 04 拦截器（Interceptors）

> 结论：**非侵入可实现**。async/http 无任何扩展点，拦截器链完全建在 L1 的执行器内部——这正是 OkHttp 的结构：拦截器不是 http 引擎的功能，而是 Call 执行管道。

## 1. OkHttp 行为规格

- 核心原语：`chain.proceed(request)`；链按列表顺序执行，可监控/重写/重试/短路。
- **应用拦截器**（`addInterceptor`）：每次调用只执行一次（缓存命中也执行）；看到应用原始请求与最终响应（重定向后）；可短路、可多次 proceed（重试）、可改 per-call 超时。
- **网络拦截器**（`addNetworkInterceptor`）：对每次**网络交换**执行（含重定向中间响应）；缓存短路时不执行；可访问 `Connection`（路由/TLS 信息）。
- 典型用途：日志、请求体 gzip、改写响应头。
- okhttp 内建链序：`RetryAndFollowUp → Bridge → Cache → Connect → CallServer`，应用/网络拦截器分别包在外侧/内测。

## 2. async/http 现状（证据）

- 零扩展点：无 filter/hook/callback API；唯一执行入口是顶层函数与 `Client::request/end_request`（既有对比研究 §3.3 同结论）。
- 值得注意的底座行为：`Client` 上没有"请求值对象"概念（散装参数），因此拦截器的"被包对象"由 01 的 Request 提供；`end_request` 返回 Response、body 仍挂在连接上——**拦截器看到的 Response 必须是惰性的**（见 3.3）。

## 3. 实现方案

### 3.1 类型（函数字段而非 trait，规避 async trait 方法限制）

```moonbit
pub struct Interceptor {
  name : String
  intercept : async (Chain, Request) -> Response
}
pub struct Chain {
  call : Call
  index : Int                            // proceed 递进游标
  request : Request
  connection : Lease?                    // 仅网络侧链非空（03）
  mut timeouts : Timeouts                // per-call 超时覆盖（okhttp withConnectTimeout 同款）
}
pub async fn Chain::proceed(self, request : Request) -> Response {
  self.request = request
  // 递归进下一拦截器；末位是 CallServer 终端
}
```

- `async (Chain, Request) -> Response` 函数类型已在 async 体系内可用（`@http` 自身就以 `async (Response) -> Unit` 作参数，`client.mbt:234`）。
- 注册：`HttpClient::{add_interceptor, add_network_interceptor}`（内部 `Array[Interceptor]`）。

### 3.2 完整链序（对齐 okhttp RealCall）

```
[应用拦截器 ×N]
RetryAndFollowUp（02：重定向/stale-retry/认证 follow-up）
Bridge（01：自动头 Content-Length/Content-Type/Cookie 注入/Accept-Encoding 已由 @http 内建——见 §4 差异）
Cache（05：条件 GET/命中短路）
Connect（03：pool.acquire → Lease 挂到 Chain）
[网络拦截器 ×M]
CallServer（终端：client.request → write body → end_request；read/write 超时接线 10）
```

- 短路：任何层不调 proceed 直接返回 Response（Cache 命中即此）；应用拦截器因此"缓存命中也执行一次"✅。
- 网络拦截器看到中间响应：RetryAndFollowUp 的每轮 `chain.proceed` 都穿过 Connect→CallServer，天然满足✅。
- `Chain::connection`：应用侧恒 None；网络侧暴露 Lease（Address、TLS 信息——证书经 `@tls.Tls::get_peer_certificate`（`tls/mbti:33`）在 Connect 层抓取挂到 Lease，供网络拦截器/事件（06）读取）。
- 重试语义：应用拦截器多次 proceed = 其内部的 follow-up 循环再跑一轮；proceed 每次消耗一个连接租约（CallServer 末尾归还/毒化）。

### 3.3 Response 惰性体与拦截器的交互（关键正确性点）

- `Response.body` 是 `ResponseBody`（01 §3.6）：`buffered`（Bytes）或 `stream`（挂连接租约）。
- **应用拦截器默认拿到的是"未缓冲"的流 Response**——与 OkHttp 一致（okhttp Response.body 也是惰性流）。但应用拦截器若要读 body 再返回新 Response，必须用 `response.peek_body(max)` 类 API（okhttp `peekBody`）→ L1 提供：对 stream tee 一份到内存（`@io.pipe` + 后台拷贝），原流供终端消费。`@io.pipe` 存在（`io/mbti`，Pipe 类型）。
- RetryAndFollowUp 层对中间响应 body 必须 skip 后归还连接（02 §3.4）。

### 3.4 官方 recipes 移植示例（写进库 README）

1. 日志拦截器：proceed 前后打 request line/headers/耗时；body 打印需 `peek_body`。
2. **请求体 gzip**（OkHttp BridgesBodyCompression recipe）：`Interceptor` 内把 `RequestBody::Bytes` 用 `@gzip.Encoder`（`gzip/mbti:24-32`，flush/end 语义齐备）压成 Bytes、加 `Content-Encoding: gzip` 头——注意此时应同时删 Accept-Encoding 干预（@http 的自动解压只认响应的 gzip，`parser.mbt:307-315`，请求体压缩不受影响✅）。
3. 改写响应 Cache-Control（OkHttp sdnly 提供的典型网络拦截器）。

## 4. 侵入性清单

| 项 | 级别 | 说明 |
| --- | --- | --- |
| 双层拦截器/Chain/短路/重试 | **非侵入** | L1 内部结构 |
| Accept-Encoding 协商 | 非侵入（有细节） | @http 已内建 `gzip,identity` 自动协商+解压（`send.mbt:338-342`）。拦截器若改 Accept-Encoding（如加 br），`has_accept_encoding` 已置位、@http 不再自动解压——L1 的 Bridge 需自己解 br/zstd（接 `bikallem/compress`，Apache-2.0，参考 reqbest 实现），仍非侵入 |

## 5. Target 支持矩阵

| target | 支持 | 说明 |
| --- | :-: | --- |
| native / wasm | ✅ | 同一路径 |
| js | ✅（降级） | fetch 上无 Connection/网络层概念：网络拦截器在 js 后端退化为与应用拦截器同层（不执行多次——重定向由浏览器处理）；peek_body 可用 |
| wasm-gc | ❌ | runtime 级缺口（16） |

## 6. 性能影响

- 每层一次函数调用 + struct 透传；链长 ~6 时开销 ~十 ns 级，可忽略。
- **惰性 Response 是性能红线**：任何层不小心把 body 读成 buffered 都会毁掉流式语义与内存上界——库内除 Cache/peek_body 外一律零拷贝透传。

## 7. 工作量与依赖

- 依赖：01（Request/Response）、02/03/05 的层挂点（拦截器骨架先行，各层随特性补齐）。
- 估计：Chain/递归执行 ~1 人日；peek_body/pipe tee ~1；recipes 示例 ~0.5；测试 ~1。**~3.5 人日**（可与 02 并行开发）。

## 8. 测试方案

- 链序断言：注入顺序记录器，验证 应用→内建→网络 的进出栈顺序。
- 语义矩阵：缓存命中时应用执行 1 次/网络 0 次；3 跳重定向时应用 1 次/网络 3 次；短路不达网络层。
- 重写请求/响应头、body 替换、proceed 两次（重试）。
- peek_body 大 body 截断与原流无损。
