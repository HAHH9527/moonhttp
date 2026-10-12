# 12 WebSocket

> 结论：**底座已实现**（`@websocket` 双侧、wss、代理隧道）——本篇工作是把 WebSocket 纳入 easyhttp 门面（拦截器/事件/超时统一），并补 OkHttp 风格的 listener API。全部非侵入（js 桥接除外）。

## 1. OkHttp 行为规格

- `client.newWebSocket(request, listener)`：走**与 HTTP 完全相同的客户端栈**（拦截器、代理、TLS、连接池语义对 WebSocket 升级请求生效）。
- Listener：`onOpen / onMessage(text|bytes) / onClosing / onClosed / onFailure`。
- 发送侧队列化（内部有发送缓冲，close 后拒绝）；`send(text|bytes) : Bool`；`close(code, reason)`；ping/pong 由库自动应答，`pingInterval` 可配。

## 2. async/http + @websocket 现状（证据）

- `@websocket` 已有**客户端+服务端**（探索代理核实，`websocket/pkg.generated.mbti`）：

```
pub async fn Conn::connect(url, headers?, proxy? : @http.Client) -> Conn   // L42-47 一带
pub async fn Conn::from_http_client(@http.Client, ...)                      // 从升级后的 Client 建立
pub async fn Conn::from_http_server(...)
Message 实现 @io.Reader；Conn 实现 @io.Writer（流式大消息）
ping / send_close
```

- wss ✅；CONNECT 代理 ✅（proxy 参数即 03 的隧道形状）。
- target：**仅 native/wasm**（`websocket/unimplemented.mbt:17` 排除 js/wasm-gc）。
- 缺口（相对 okhttp）：
  - 不在 easyhttp 门面内——升级请求不经过我们的拦截器链/事件/超时；
  - 无 listener 形状（当前是 Reader/Writer 流式原语）；
  - 无 pingInterval 自动心跳、无发送队列语义（背压需用户自理）。

## 3. 实现方案

### 3.1 门面化（HTTP 栈复用，okhttp 语义）

```moonbit
pub struct WebSocket {
  conn : @websocket.Conn
  sender : Mutex[State]            // Open/Closing/Closed；close 后 send 返回 false
  pong_timeout : Int               // 心跳失联判定
}
pub fn HttpClient::new_websocket(self, request : Request, listener : WebSocketListener) -> WebSocket
pub struct WebSocketListener {
  on_open     : () -> Unit
  on_message  : (WsMessage) -> Unit          // Text(String) | Binary(Bytes)
  on_closing  : (Int, String) -> Unit        // 对端发起 close
  on_closed   : (Int, String) -> Unit
  on_failure  : (Error) -> Unit
}
pub fn WebSocket::send(self, String | Bytes) -> Bool
pub fn WebSocket::close(self, code : Int, reason : String) -> Unit
```

- 实现路径：`new_websocket` 在 L1 内部**走一遍拦截器链**（04：应用拦截器可见升级请求；Cache/Connect 层跳过——GET+Upgrade 不缓存、租约即本连接）→ 终端不是 CallServer 而是"发升级请求 → 101 → `Conn::from_http_client(client)`"。`@http.Client` 的 101 语义已就绪：`end_request` 返回 101 响应、`enter_passthrough_mode`（`client.mbt:227-231,351-355`）——`from_http_client` 正是吃这个形状。
- 接收循环：`spawn` 读协程（Message 作 Reader 分帧读出 Text/Binary → 回调 listener）；协程挂 HttpClient 的 TaskGroup，失败 → on_failure + 清理。
- 发送队列：`send` 经 `aqueue` 串行化（避免用户并发交错帧）；close 后立即 false（okhttp 同）。

### 3.2 心跳（pingInterval）

- `Timer` 周期发 ping（`@websocket` 已有 ping API）；`pong_timeout` 内未收 pong → 判定失联走 on_failure + close。可配 interval=0 关闭（okhttp 默认 0）。

### 3.3 js 桥接（补 target 缺口，独立适配层）

- `websocket/unimplemented.mbt` 排除 js → L1 在 js 上走**浏览器原生 WebSocket**：`extern "js"` 绑定（`new WebSocket(url)`、`onmessage/onopen/onclose/onerror`、`binaryType="arraybuffer"`），适配到 3.1 的同一 `WebSocket` 门面类型。
- 限制：浏览器 ws 无自定义 headers（协议限制，非我们缺口）、无代理、wss 策略同浏览器。
- 工作量 ~1.5 人日；**非侵入**（桥在 L1 包内，`#cfg(target="js")`）。

## 4. 侵入性清单

| 项 | 级别 | 说明 |
| --- | --- | --- |
| 门面/listener/心跳/js 桥 | **非侵入** | — |
| 升级请求经过拦截器链 | 非侵入 | L1 终端替换 CallServer 即可（101 + from_http_client） |
| 大消息流式语义与 listener 回调共存 | 非侵入 | listener 收聚合消息（小）；大消息暴露 `conn` 原始 Reader 逃生口 |

## 5. Target 支持矩阵

| target | 支持 | 说明 |
| --- | :-: | --- |
| native / wasm | ✅ | `@websocket` 原生路径 |
| js | ✅（经 3.3 桥） | 浏览器 WebSocket；headers 受限 |
| wasm-gc | ❌ | runtime 级缺口（16） |

## 6. 性能影响

- 复用 HTTP 栈意味着代理/池化/TLS 配置一次到位；无额外拷贝（Message 本身是 Reader）。
- 发送队列的间接层：每消息一次 aqueue 入队，ns 级。

## 7. 工作量与依赖

- 依赖：01/04（链与门面骨架）、10（ping Timer）。
- 估计：门面+listener ~1.5 人日；心跳 ~0.5；js 桥 ~1.5；测试 ~1。**~4.5 人日**。

## 8. 测试方案

- 对 `examples/websocket_echo_server`（仓库已有）做 echo 全链路：文本/二进制/大消息（分片）、并发 send 串行化、close 码传播、ping/pong 超时。
- 升级请求经过应用拦截器断言（记录器）。
- js：浏览器手测脚本 + node ws 服务器。
