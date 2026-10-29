# src/client/

## Responsibility

面向用户的 HTTP 客户端层（对齐 OkHttp 语义），构建在 moonbitlang/async 公开 API 之上：
- `http_client.mbt`：`HttpClient` 门面（唯一状态＝`ConnectionPool` 引用）、一次性请求句柄
  `Call`（Pending→Executing→Done 状态机）、取消通道与错误变体 `CallCancelled`/`CallStateError`。
- `client.mbt`：连接池 `ConnectionPool`、直连三元组池键 `Address`（scheme/host/port，构造期
  小写化 + IPv6 剥方括号）、独占租约 `Lease`（poison/release）。
- `exchange.mbt`：单轮收发管线与 `Address` 推导——`exchange_with_lease`
  （持租约段：折叠→发送→收头→close 检查→构建响应，循环每轮复用；返回
  响应与原始 `@http.Headers` 供 Location 保真读取）+ `exchange_once`
  （spec 钦定白盒直调接缝，单轮语义不变）。
- `follow_up.mbt`：P06 follow-up 层——`follow_up_request` 决策表
  （300–308 × Location × 方法 × 可重放，5.5.0 对拍）+ `exchange_loop`
  轮循环（循环顶取消 guard、中间体排干、同 host 租约保持/跨 host 换租、
  prior 链、20 跳上限 `TooManyFollowUps`）+ 头改写（跨 host 剥
  `Authorization`/`Cookie`）。
- `body_bridge.mbt`：`BodyBridge` 响应体读适配器（实现 `@io.Reader`）与租约处置状态机
  （Consumed/Dropped/Abandoned 事件驱动）。

## Design

- 门面模式：`HttpClient::new(pool)` 仅持池引用，`new_call(request)` 装箱 Pending 态 `Call`，
  不做校验以外的工作、无 builder。
- 池化 + LIFO 策略：`ConnectionPool` 以 `Address`（derive Eq/Hash 即键语义）分桶，
  `Map[Address, Array[IdleLease]]` 空闲栈（尾=最热），`max_idle` 缺省 5、`keep_alive_ms`
  缺省 300_000；超期惰性剔除（acquire/release 时 `evict_bucket_locked`）+ 显式入口
  `evict_expired`/`evict_all`；时钟注入（`now_ms`，缺省绑 `@async.now`）；观测计数
  `per_host_total`/`stale_evictions`。
- 资源生命周期管理：三集合 idle/borrowed/closed 承载守恒不变量；`@async.Mutex` 保护，
  临界区无 IO 无 await（异步路径 acquire/release 持锁，同步路径 `try_acquire` 失败即
  abort fail fast）；建连失败零状态变化；`Lease::poison` 仅置标记，`Lease::release`
  按「未毒化 ∧ 未栈满」谓词回池或关闭，终结幂等。
- 分发/交换抽象：`Call::execute` 在 `@async.with_task_group` 内 spawn
  follow-up 循环 `exchange_loop`（P06 T004 换靶）：每轮循环顶取消 guard →
  `ensure_lease`（同 host 复用/跨 host 换租）→ `exchange_with_lease` 单轮
  收发 → 决策表判定 → Terminal 挂 prior 链返回 / Next 排干中间体后换代；
  超 20 跳 raise `TooManyFollowUps`。`exchange_once` 降为白盒直调接缝
  （`#warnings` 定点抑制，plan 例外跟踪）。`@async.handle_cancellation`
  把取消映射为 `CallCancelled`；`errdefer` 兜底置终态；并发上限闸门不在
  本包（调用方自控）。
- Location 保真：follow-up 的 `Location` 读取走 `exchange_with_lease`
  返回的原始 `@http.Headers` 直读——P02 `from_http` 的逗号拆分会把含
  `,` 的头值截断为多条（query 中 `,` 合法）， WB⑧ 钉死。
- 体桥接策略：请求体 `BodySource::Bytes`→`write_once`、`Stream`→填充回调；响应体经
  `BodyBridge`（`read_checked` 单点收口取消检查与错误映射 `map_read_error`）挂入
  `@core.ResponseBody::stream`，`Connection: close` 按 token 解析命中即毒化不回池。

## Flow

用户调用链：`HttpClient::new(pool)` → `new_call(@core.Request)` → `Call::execute()`：
1. 状态机检查（非 Pending ⇒ `CallStateError`；已取消 ⇒ 零网络抛 `CallCancelled`）；
2. 组内 spawn `exchange_loop`（follow-up 循环）：每轮先查取消（裸
   `CallCancelled`）；`ensure_lease` 同 host 复用租约、跨 host 先归还旧租
   再取新租；
3. `folded_headers()` 恰一次经 `@core.Request::to_http_request()` 折叠并
   缓存头 Map（按请求代次 `gen` 键化，换代后重折叠恰一次）；
4. `lease.conn.request(meth, origin_form(url), extra_headers=folded)` 发头，
   按 `BodySource` 发体，`end_request()` 收头（不传 1xx 回调）；
5. 收头后查 `Connection: close` 决定毒化，经 `make_response_body` 组装
   `@core.ResponseBody::stream(bridge, on_event, on_dispose)`，
   `@core.Response::from_http` 得本轮响应；`follow_up_request` 决策表判定：
   Terminal ⇒ 挂 prior 链返回终态；Next ⇒ 排干中间响应体、（中间 close 或
   跨 host 时）归还旧租、换代进入下一轮；超 20 跳 raise `TooManyFollowUps`。
响应体读取：`BodyBridge` 委托 `@http.Client::read_some`；读到底触发 Consumed →
`release_lease` 回池；`dispose` 的 skip 收尾成功回池、失败毒化；读错误经
`poison_release`（poison+release+lease 置 None 单点）后按取消态映射透传。

## Integration

- 依赖 `src/core`（`hahh9527/moonhttp/core`）：`Request`/`RequestBody`/`BodySource`、
  `Method::to_request_method`、`HttpUrl`（scheme/host/port/path_segments/query）、
  `Request::to_http_request`、`Response::from_http`、`ResponseBody::stream` 与
  `ResponseBodyEvent`（Consumed/Dropped/Abandoned）。
- 仅经 moonbitlang/async 公开 API：`@async.Mutex`/`now`/`with_task_group`/
  `handle_cancellation`/`Task::cancel`；`@http.Client`（构造/`request`/`write_once`/
  `end_request`/`read_some`/`skip_response_body`/`close`、`CaseInsensitiveString`、
  `Protocol`、`RequestMethod`）；`@io.Reader` trait。Location 解析经
  `@core.HttpUrl::resolve`（相对/绝对/网络路径三形态）。
- `moon.pkg` 另引入 `core/debug`（错误 derive Debug）与测试专用 `internal/fixtures`、
  `core/test`（运行时零引用，抑制 unused_package 警告）。
- 消费方：外部库用户（公开面见 `pkg.generated.mbti`：HttpClient/Call/ConnectionPool/
  Address/Lease 与两错误变体）；基准/测试工具经同一公开面驱动。
