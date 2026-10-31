# hahh9527/moonhttp

基于 `moonbitlang/async` 公开 API 构建的 OkHttp 对齐 HTTP 客户端。

## 超时配置（M1-P08）

四类超时独立可配（`Timeouts`：connect/write/read 缺省 10s、call 缺省
0=不限；0＝不限且不建窗，负值构建期快速失败）。定制经 builder 派生：

```moonbit
// 从连接池根构造（全缺省）
let client = HttpClient::new_builder(pool).build()
// 自既有 client 派生（共享连接池，仅覆盖标量——OkHttp newBuilder 同形）
let slow = client.builder()
  .timeouts({ connect_ms: 10_000, write_ms: 10_000, read_ms: 10_000, call_ms: 300 })
  .build()
```

- 超时以 `HttpTimeout::{Connect/Write/Read/Call}` 显式变体暴露（`err is`
  判别）；读/写按操作计时（每操作一窗，非整段限时）；call 伞覆盖
  execute 全程（含重定向与重试轮）。
- 超时连接一律毒化不回池；`Connect` 变体在重试预算内自动换新连接重试，
  其余变体不重试（对齐 OkHttp）。
- 跟随开关：`follow_redirects` / `follow_ssl_redirects`（缺省 true＝
  恒跟随）；关闭后 3xx 终态透传（prior 链不累积）。
- **js target**（未验证面）：调用方仍按窗拿到超时变体，但底层 fetch
  不保证取消（浏览器自管连接）；随 M5 收口。

