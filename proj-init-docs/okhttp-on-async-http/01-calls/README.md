# 01 请求/响应模型（Calls）

> 系列报告之一：基于 `moonbitlang/async`（0.22.4-dev，E:\Project\async）的 `@http` 包实现 OkHttp 的 Calls 能力。
> 结论先行：**本特性 100% 非侵入可实现**——在 `@http` 之上新建独立包（下称 `easyhttp`），不修改 async 源码。

## 1. OkHttp 行为规格

- `Request` = URL + 方法 + 有序 Header 列表 + 可选 `RequestBody`（带 content-type 的流）；`Response` = 状态码 + Header + 可选 `ResponseBody`。
- `Call` 是"一次待执行的请求"：`execute()` 同步阻塞、`enqueue(callback)` 异步、任意线程 `cancel()`；`Call` 不可重复执行，重试/重定向在内部产生新的 follow-up（见 `02-redirects-retries`）。
- 自动补齐请求头：`Content-Length`/`Transfer-Encoding`/`Host`/`User-Agent`/`Connection`/`Content-Type`/`Accept-Encoding`（透明压缩）/`Cookie`；缓存命中时自动转条件 GET（见 `05-cache`）。
- 自动改写响应：透明解压后剥离 `Content-Encoding`/`Content-Length`；304 与缓存合并。
- Dispatcher 控制异步并发（见 `10-timeouts-dispatcher`）。

## 2. async/http 现状（证据）

| 项 | 现状 | 证据 |
| --- | --- | --- |
| Request 值对象 | **无**。请求参数散装：`Client::request(meth, path, extra_headers?)`，body 走 Writer | `src/http/client.mbt:283-291` |
| Response 值对象 | 有：`{code, reason, headers, cookies}`，无 body（body 由 Client 作 Reader 流出） | `src/http/types.mbt:47-56` |
| 自动头 | Host、User-Agent（`moonbit-http-client/1.1`）在连接时写入持久头；`Accept-Encoding: gzip,identity` + 响应 gzip 透明解压（剥 Content-Length）已实现 | `src/http/client.mbt:58-62`、`src/http/send.mbt:338-342`、`src/http/parser.mbt:331-335` |
| Content-Length/TE | 自动管理：`SendingFixed`/chunked 状态机；**已知长度的 body 只能经 `extra_headers~{"Content-Length": n}` 触发定长帧**，便捷路径一律 chunked | `src/http/send.mbt:292-350`（round3 实测，见 `../../round3-chunked-verification.raw.md`） |
| Cookie 头 | **无自动回发**。Set-Cookie 解析为 `Cookie` 结构存进 `Response.cookies`，但没有 Jar（见 `11-cookies`） | `src/http/parser.mbt:280-281` |
| 1xx | 自动跳过并回调 `on_informational_response`；101 透传 | `src/http/client.mbt:232-253` |
| 同步/异步 | async 体系里一切皆异步；无"同步阻塞"概念（单线程事件循环），OkHttp 的 execute/enqueue 差异退化为"是否 spawn" | — |
| 取消 | Client 无 cancel；但 runtime 取消是水平触发的（协程持久标记，后续 async 操作立即失败），是 cancel 的天然底座 | AGENTS.md：cancellation as persistent mark |
| Header 模型 | `Map[CaseInsensitiveString, String]`：**无序**（哈希序）、重复头逗号合并、`Set-Cookie` 特判进 cookies；比较/哈希免分配 | `src/http/types.mbt:29-37`、`parser.mbt:282-287`、`case_insensitive_string.mbt:21-52` |
| URL 解析 | `resolve_url` 极简：`protocol://host[:port]/path` 切分，无 query/fragment/percent-encoding/IPv6-literal/IDN 处理 | `src/http/types.mbt:36-51`、`utils.mbt:54-72` |

## 3. 实现方案（非侵入，新包 `easyhttp`）

### 3.1 分层与依赖方向

```
easyhttp（门面：拦截器链 + Dispatcher + Pool + Cookies + Auth + 超时）
   │ 仅依赖 ↓
easyhttp/core（HttpUrl、Request/Response/RequestBody/ResponseBody、HeadersV 有序头、Call）
   │ 仅依赖 ↓
moonbitlang/async（@http.Client / @socket / @tls / @io / timer / task_group / semaphore）
```

`easyhttp` 通过 moon.mod `import "moonbitlang/async"` 使用 registry 版本（建议钉 0.22.x 最新），与本地 async 仓库解耦；需要上游修复时用 `.mooncakes` 覆盖或等发版。

### 3.2 HttpUrl（L1 自建，OkHttp `HttpUrl.parse` 等价）

`resolve_url` 不足以支撑重定向/缓存/cookie（它们都要 path/query 级操作）。实现要点：

```moonbit
pub struct HttpUrl {
  scheme : Scheme              // http/https
  host : String                // 已解码、去 brackets 的 host（IPv6 保留原样字符串）
  port : Int                   // 显式或默认
  path_segments : Array[String] // 已 percent-decode；空首段 = 根路径
  query : String?              // 原样保留 encoded 串（OkHttp 同款决策）
  fragment : String?
}
```

- 解析/规范化规则对齐 OkHttp：`.`/`..` 段消解、空段压缩、path 必须以 `/` 开头、`resolve()`（相对引用解析，重定向必需）、`port() == defaultPort` 时 toString 省略端口。
- IPv6 literal：`[::1]:8080` 去方括号后传 socket（`resolve_host` 的 `re".*:port"` 正则对带括号形式会把 `.*` 吃到 `]`，端口解析仍成立，但 host 字符串含括号——**L1 必须先剥括号再传给 `Client::connect`**，这是纯上层修正，无需动 async）。
- IDN/punycode：M1 可只支持 ASCII host + 拒绝（raise `HttpUrlError::InvalidHost`），M3 补 punycode（纯 MoonBit 实现 ~200 行）。
- 测试直接移植 OkHttp 的 HttpUrl 测试用例（其测试矩阵覆盖畸形输入）。

### 3.3 Request / RequestBody（值对象 + Builder）

```moonbit
pub struct Request {
  url : HttpUrl
  meth : Method                 // 自定义 enum + Custom(String)
  headers : HeadersV            // 有序、允许重复名（见 3.4）
  body : RequestBody?
  tag : Unit?                   // 取消时按 tag 批量定位
}

pub struct RequestBody {
  content_type : String?
  content_length : Int64?       // None = 未知 → chunked
  // 三种形态，重放能力是重试/跟随的硬前提（见 02）
  data : BodySource
}
priv enum BodySource {
  Bytes(Bytes)                                  // 可重放，O(1)
  File(String, Int64)                           // 路径+长度，可重放（重开文件）
  Stream((&Reader) -> Unit)                     // 一次性写入回调，不可重放
}
```

- 定长帧规则（性能关键）：`Bytes/File` 一律带 `content_length`，发送时经 `client.request(meth, path, extra_headers~ + {"Content-Length": n})` 进入 `SendingFixed`，避免 chunked 编码开销（round3 已验证机制与收益路径）。
- 上传进度（OkHttp recipes 的 ForwardingSink 等价物）：`RequestBody::with_progress(body, on_bytes : Int64 -> Unit)`——Stream 形态包一层计数 Writer；Bytes 形态分块写。非侵入。

### 3.4 HeadersV（有序、多值）

- 存储 `Array[(CaseInsensitiveString, String)]`（复用 `@http.CaseInsensitiveString` 的免分配比较/哈希）。
- 查询 API：`get(name) -> String?`（首个）、`values(name) -> Iter[String]`、`set/add/remove`（OkHttp 语义：set 覆盖全部同名，add 追加）。
- **边界转换**：进入 `@http` 时折叠成 `Map[CaseInsensitiveString, String]`（同名逗号合并，与 `parser.mbt:283-286` 的响应侧语义对称；`Set-Cookie` 例外不在此路）。多值头里含逗号的 quoted-string（如 `WWW-Authenticate` 的 realm）不得折叠——认证路径保留原始 `HeadersV` 不经过 Map（见 `08-auth`）。
- 排序稳定性让"同 URL + 同头序"的缓存 Vary 键、重放请求的字节级一致成为可能。

### 3.5 Call：执行与取消

```moonbit
pub struct Call { request : Request, client : HttpClient, mut cancelled : Bool }
pub async fn Call::execute(self) -> Response raise        // 当前协程内执行
pub fn Call::enqueue(self, on_response : Response -> Unit, on_failure : Error -> Unit) -> Unit
pub fn Call::cancel(self) -> Unit
pub fn Call::is_cancelled(self) -> Bool
```

- **execute**：`HttpClient` 内部经拦截器链（见 04）拿到 pooled 连接执行。同步=直接在当前协程 await（事件循环单线程，等价 OkHttp execute）。
- **enqueue**：`@async.spawn` 进 `HttpClient` 的 TaskGroup；Dispatcher 闸门（semaphore）在链首。
- **cancel**：两层——
  1. `cancelled := true`，后续未发出的 follow-up/retry 直接以取消错误终止；
  2. 对在途协程：把该 call 的执行 spawn 在可独立取消的子 TaskGroup 中，`cancel()` 关闭该组 → runtime 水平触发取消生效（"后续异步操作立即失败"），正在 `read/write` 的协程收到取消错误；
  3. 连接毒化：被取消的连接不回池（半读半写状态不可复用），直接 `close()`。
- 取消错误建模：`pub suberror CallCancelled`，与网络错误区分，供拦截器/用户判断（对齐 OkHttp `IOException("canceled")` 的判别用法）。

### 3.6 ResponseBody

```moonbit
pub struct ResponseBody {
  content_type : String?
  content_length : Int64?       // gzip 已解压后的长度（parser 已剥头）
  // 二选一：已缓冲（缓存/小响应）或连接流（大响应直读，用完连接回池）
  buffered : Bytes?
  stream : StreamBody?          // 包装 &@http.Client：read/drop 完成后触发归池回调
}
pub fn ResponseBody::bytes(self) -> Bytes raise
pub fn ResponseBody::text(self) -> String raise          // 按 charset，默认 UTF-8
pub fn ResponseBody::json(self) -> @json.Json raise
pub fn ResponseBody::char_stream(...) // lazy，M2
```

- `StreamBody` 析构语义：完整消费或显式 `drop()` 后连接才能回池；未读完即丢弃时调 `client.skip_response_body()`（`client.mbt:296-298` 已提供）再回池，失败则毒化关闭。
- js target：Client 本身就是 fetch 语义（`client.js.mbt`），ResponseBody 直接适配 `@io.Reader` 的 fetch 流。

## 4. 侵入性清单

| 项 | 级别 | 说明 |
| --- | --- | --- |
| 全部 Calls 能力 | **非侵入** | 新包实现，仅用 `@http` 公开 API |
| （可选优化）`resolve_url` 增强 | 侵入 async/http（低价值） | L1 的 HttpUrl 完全覆盖，不需要 |
| （可选优化）`Map` 有序化 | 侵入 async/http（不建议） | HeadersV 在上层解决；动 Map 影响全 API |

## 5. Target 支持矩阵

| target | 支持 | 说明 |
| --- | :-: | --- |
| native | ✅ 完整 | `client.mbt` 全功能路径 |
| wasm | ✅ 完整 | 与 native 同源（`moon.pkg` targets）；socket 依赖宿主注入（见 `16-target-support`） |
| wasm-gc | ❌ | `@http` 本身未实现（`unimplemented.mbt:17`），runtime 级缺口，见 16 |
| js | ⚠️ 降级 | fetch 后端：无 proxy、`on_informational_response` 无效、`Response.cookies` 恒空（`client.js.mbt:112-115,186-192,214`）；Calls/取消（AbortController 已在 `end_request` 接入）可用 |

## 6. 性能影响

- Request 值对象让**头块预序列化**成为可能：拦截器链执行前把 Request 的头拼成 `Bytes` 缓存在 Call 上，重试/重定向重放时零重排成本（对比现状：每次 `send_headers` 重新迭代 Map、逐段 blit，`send.mbt:292-311`）。
- `SendingFixed` 定长帧 + 预序列化头 → 单请求发送路径分配：连接已建时 ≈ 2 个对象（头块引用 + body 引用）。
- HttpUrl 解析每请求一次 O(n)；重定向 resolve 复用已解析 base，O(增量)。

## 7. 工作量与依赖

- 依赖：无（这是所有其他特性的地基）。
- 估计：HttpUrl ~2 人日（含测试移植）；Request/Response/Body/Builder ~1.5；Call+取消 ~1（需 10 的 TaskGroup 骨架）；合计 **~4.5 人日**。
- 顺序：先于一切；02/04/05/08/10/11 都引用本篇的 Request/Call 定义。

## 8. 测试方案

- HttpUrl：移植 OkHttp 用例 + 自增 IPv6/畸形输入。
- 定长帧：本地 `@http.Server` 作夹具，断言线上字节 `Content-Length` 存在且无 `Transfer-Encoding`（round3 的 `verify_framing.sh` 思路，`mio/_connmeasure/`）。
- 取消三阶段（发前/发中/读体中）：用 `test_programs` 里可控服务端（仓库已有 cancellation 测试基建，`5c2d2ea refactor request cancellation test`）。
- js：浏览器/node 双跑 enqueue+cancel。
