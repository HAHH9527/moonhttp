# 02 自动重定向与重试（Retry and Follow-Up）

> 结论：**非侵入可实现**（依赖 01 的 Request/Call 与 03 的连接租借）。本特性是 OkHttp `RetryAndFollowUpInterceptor` 的等价物。

## 1. OkHttp 行为规格

- 自动跟随 3xx 重定向（`Location` 头）；规则：
  - `301`/`302`：POST → GET（浏览器历史兼容），body 丢弃；GET/HEAD 保持；
  - `303`：任何方法（除 HEAD/GET）→ GET，body 丢弃；
  - `307`/`308`：**保持方法与 body**——body 必须可重放，否则直接把 307/308 响应交给调用方；
  - `300`/`304`/`305`/`306` 不跟随（304 交给缓存层，见 `05-cache`）。
- 跨 host 重定向时剥离 `Authorization` 与 `Cookie`（Cookie 由 CookieJar 按新域重新计算）。
- follow-up 链上限 20；`Response.priorResponse()` 暴露链历史。
- 自动重试（`retryOnConnectionFailure`，默认开）：陈旧连接/路由失败时换一条路由重放；代理认证失败（407）与 401 走 Authenticator follow-up（见 `08-auth`）。

## 2. async/http 现状（证据）

- **无任何重定向跟随**：`Client` 原样返回 3xx（全仓 grep "redirect" 仅命中 process/shell，探索代理已核实）。
- **无重试**：连接失败直接抛错。runtime 有通用 `@async.retry`（`src/pkg.generated.mbti`）但 HTTP 语义的 stale-retry 需要连接池配合。
- 请求重放的硬件前提：`Client` 是严格单请求在途状态机（`client.mbt:283-291` + `sender.mode`），重放 = **换一条新连接重发**，旧连接毒化。
- Location 解析需要相对引用解析（`resolve_url` 只做顶层切分，`types.mbt:36-51`）→ 由 01 的 `HttpUrl::resolve` 提供。

## 3. 实现方案

### 3.1 follow-up 循环（在拦截器链的 RetryAndFollowUp 层，见 04）

```moonbit
// 伪代码：execute 内主循环（对齐 okhttp RealCall.execute 的 followUpRequest 循环）
let mut request = call.request
let mut prior : Response? = None
for follow_ups = 0; follow_ups < 20; follow_ups++ {
  guard! call.cancelled else { raise CallCancelled }
  let response = chain.proceed(request)          // 03 的连接租借 + 发送 + 收头
  let followup = follow_up_request(response, request, release_body)
  if followup is None {
    return response_with_prior(response, prior)  // 终态响应（body 惰性挂在连接租约上）
  }
  release_body(response)                         // 跳过/排干中间响应 body：client.skip_response_body()
  prior = Some(response_with_prior(response, prior))
  request = followup.unwrap()
}
raise TooManyFollowUps                           // 对齐 okhttp("Too many follow-up requests")
```

### 3.2 follow_up_request 决策表

| 响应 | 条件 | 动作 |
| --- | --- | --- |
| 301/302 | meth ∈ {Post} 且 Location 存在 | GET + 去 body + 去 Content-Length/Type |
| 303 | meth ∉ {Get, Head} 且 Location 存在 | 同上 |
| 307/308 | Location 存在 | 保持方法；body 可重放（`BodySource::Bytes/File`，01 §3.3）则重放，否则**返回该响应**（不跟随） |
| 401/407 | Authenticator 配置 | 见 08 |
| 408 | 用户开 `retryOn408`（OkHttp 无此默认） | 可选：重放（幂等时） |
| 其余 | — | None（终态） |

- Location 为相对引用 → `HttpUrl::resolve(base, location)`（01）。
- 跨 host（scheme/host/port 任一不同）：删 `Authorization`、`Cookie`；CookieJar 开启时 Cookie 头本来就由 Jar 注入（11），此处自然正确。
- Location 缺失/非法 URL：返回原响应（OkHttp 行为）。

### 3.3 连接失败重试（stale-retry，配合 03 的池）

判定"可重试的失败"（对齐 OkHttp `RetryAndFollowUpInterceptor.recover`）：

```
可重试 ⇔ retryOnConnectionFailure 开启
      ∧ 失败类型 ∈ { 连接建立失败(ECONNREFUSED/超时后新连), 陈旧连接(取出后首读即 EOF/Reset),
                     TLS 握手失败(可换路由) }
      ∧ 请求体可重放（Bytes/File，或 Stream 且尚未写出任何字节）
      ∧ 未收到任何响应字节（收到部分响应头即不可重放——语义已可能生效）
      ∧ 未被取消 ∧ 尝试次数 < max_attempts(默认 2，OkHttp 未暴露计数但内部同样有限)
```

- 实现要点：发送路径拆成两个可观测阶段——
  1. `client.request(...)` + 写 body（写失败且 `bytes_written == 0` → 可重试）；
  2. `client.end_request()` 读响应头（此阶段 `ReaderClosed`/连接重置且**尚未解析出状态行** → 判定陈旧连接，可重试；一旦解析出状态行后失败 → 不可重试）。
- 陈旧连接处理：毒化（close，不回池，见 03 §3.4），计数 `pool.stale_evictions` 供 06 观测。
- 路由维度：`connect_to_host` 内部已是 Happy Eyeballs 多地址竞速（`src/socket/happy_eyeball.mbt:30-106`），单次 connect 已含"换路由"；L1 额外的"整体重来一次"覆盖竞速全败后的瞬时故障。
- 退避：第一次立即重试（对齐 OkHttp——它不退避，靠路由切换）；若暴露 `max_attempts > 2` 则用 `@async.retry` 的退避参数。

### 3.4 与取消/超时的交互

- 每轮 follow-up 前检查 `call.cancelled`；循环全程处于 10 的 callTimeout 计时伞下。
- 中间响应 body 必须 `skip_response_body()`（`client.mbt:296-298`）后连接才能回池——**不可省**，否则下个请求会读到脏数据（连接状态机要求 clean state，`enter_passthrough_mode` 的 guard 同理，`client.mbt:351-355`）。

## 4. 侵入性清单

| 项 | 级别 | 说明 |
| --- | --- | --- |
| 重定向跟随/follow-up 链 | **非侵入** | 纯上层循环 |
| stale-retry | **非侵入** | 写路径阶段化由 L1 自身控制（L1 负责调 request/write/end_request，而非 @http 内部） |
| （增强）`end_request` 区分"零字节即断"与"响应头中途断" | 侵入 async/http（可选，低必要性） | 现有错误 `@io.ReaderClosed` 无法区分两种断点；L1 可用"响应头是否已解析出状态行"自判（在 L1 侧捕获错误时已知阶段），无需侵入 |

## 5. Target 支持矩阵

| target | 支持 | 说明 |
| --- | :-: | --- |
| native / wasm | ✅ | 同一代码路径 |
| js | ⚠️ | fetch **浏览器已自动跟随重定向**且不可关（Request redirect:"follow" 默认）——L1 在 js 上不实现自己的循环，`priorResponse` 不可用；手动模式（redirect:"manual"）需改 `client.js.mbt:226-237`（**侵入**，仅当需要 noop/js 一致行为时） |
| wasm-gc | ❌ | runtime 级缺口（16） |

## 6. 性能影响

- 重定向是**正确性/便利**特性，性能上反而要防退化：中间响应 body 必须 skip（本地内存搬运，O(body)）；Location 指向同 host 时**复用同一连接**（03 的池在同一 execute 内保持租约，不归还再重取）。
- stale-retry 把"陈旧连接导致的用户可见失败"变成 ~1 次额外 RTT 的延迟，是池化（03）的必要配套——池化不配 stale-retry 会让长闲连接场景错误率上升。

## 7. 工作量与依赖

- 依赖：01（Request/HttpUrl/Body 重放）、03（租约/毒化）、04（链位置）。
- 估计：follow-up 循环 + 决策表 ~1 人日；stale-retry 阶段化 ~1 人日；测试 ~1 人日。**~3 人日**。

## 8. 测试方案

- 决策表逐行：本地 `@http.Server` 夹具构造 301/302/303/307/308 + 相对/绝对/畸形 Location、跨域 Authorization/Cookie 剥离、20 跳上限、307+Stream body 不跟随。
- stale-retry：服务端 `accept` 后立即 `RST`（或 `close` 不回包）→ 断言自动换连接成功且响应正确；服务端回半截响应头 → 断言抛错不重试。
- prior 链深度与顺序断言。
