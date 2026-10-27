# src/core/

## Responsibility

核心 HTTP 模型层（P01/P02 值类型）：URL 解析/规范化/相对引用解析（`HttpUrl`）、
百分号编解码、有序多头容器（`HeadersV`）、九标准方法（`Method`）、不可变请求值
（`Request`/`RequestBody`）、响应值与流式体生命周期（`Response`/`ResponseBody`）、
错误模型（`HttpUrlError`/`HeadersError`/`HttpMessageError`），以及出站纯转换
`Request::to_http_request`。本包无网络 IO：发送/连接归 src/client。

## Design

- 不可变值 + 可变 Builder：`HeadersVBuilder`/`RequestBuilder` 的 `build()`
  产出冻结值；`build()`/`builder()` 均防御性复制，值与 Builder 互不串改。
  `HttpUrl` derive Eq/Hash（可作池键）；`Request`/`Response` 有意不实现
  Eq/Hash（body/prior 含函数与引用字段，判等无语义）。
- 头折叠与重建互逆：`HeadersV::to_http_map` 按插入序把同名值以无空格 ","
  合并（与 @http 响应侧 parser 逐字节对称）；`Response::from_http` 逐键拆回。
  同名值保序遍历用 `HeadersV::values`（不折叠）。
- 构造期校验收口：`HeadersVBuilder::add/set` 做 RFC 9110 token 名 + 禁 CR/LF
  值校验（防头注入，违例 `HeadersError`，失败时容器不变）；
  `RequestBuilder::build` 执行方法/体矩阵（Get/Head 拒体、Post/Put/Patch 必体，
  违例 `HttpMessageError::MethodBodyMismatch`）；
  `RequestBody::bytes` 构造期 O(1) 校验长度（`IncorrectBodyLength`）。
- 封闭映射复用上游类型：scheme 复用 `@http.Protocol`（不自立枚举、不重复
  默认端口）；`Method::to_request_method`/`from_request_method` 与
  `@http.RequestMethod` 双向封闭映射（无失败分支）。
- 标签联合错误：三个 `pub(all) suberror`，仅 derive(Debug)，不参与判等/哈希；
  错误输出只带变体名定位片段，不回显头值/体内容/URL 全文。
- 体两形态 `BodySource`：`Bytes`（可重放）| `Stream(async (&@io.Writer) -> Unit)`
  （一次性回调）；`content_length: None` → chunked。`with_progress` 仅对
  Stream 注入计数 Writer（`CountingWriter`，在 `write_once` 唯一落盘点收口）。
- `ResponseBody` 两态：buffered（持 `Bytes`）/ stream（持 `&@io.Reader`），
  生命周期事件 `Consumed`/`Dropped` 互斥（先到者赢、后到幂等），`Abandoned`
  触发权在 src/client；`dispose()` 提供 `on_dispose` 异步收尾钩子。charset
  仅支持 UTF-8：集外经 `warn_charset_fallback` 告警并降级 `@utf8.decode_lossy`。
- Debug 纪律：体类型手写 Debug，只印长度/状态元信息，不印体字节。
- `moon.pkg` 包级关闭 `-reserved_keyword`（五要素字段名 `method` 为保留字，
  显式有理由例外）。

## Flow

- URL 入口：`HttpUrl::parse(input)` / `HttpUrl::resolve(base, location)` →
  统一核心 `parse_with_base`（裁剪空白 → scheme 判定 → authority 切分
  `split_authority`/`parse_port` → 路径 `resolve_path` 消解点段 → query/
  fragment 经 `canonicalize_query`/`canonicalize_fragment`）。畸形输入
  raise `HttpUrlError`，绝不 panic。
- 序列化出口：`HttpUrl::to_string` 以 `percent_encode_path_segment` 重编码
  解码态 path_segments，满足 `parse(to_string(u)) == u` 往返幂等；IPv6 重包
  方括号、默认端口省略。
- 请求组装：`RequestBuilder::new(url)` → 链式 `method`/`header(s)`/`tag`/
  `body` → `build()`（矩阵校验）→ 不可变 `Request`。
- 出站转换：`Request::to_http_request` 产出上游 `@http.Request` 三元组
  （meth 封闭映射；origin-form path 剥 fragment；headers = `to_http_map`
  折叠基底 + Content-Type 覆盖 / Content-Length 覆盖或删除；不注
  Transfer-Encoding）。纯函数，重复转换输出逐字节相同。
- 响应组装：`Response::from_http`（code/reason/@http.Headers/cookies，
  body~/prior~ 可选装配位）拆分合并头、并把 Content-Type 合并值注入 body
  作 charset 上下文。
- 体消费：`ResponseBody::bytes`/`read_some`/`text`（统一 async 签名；EOF 置
  consumed 并触发 `Consumed`）→ `drop()`/`dispose()` 触发 `Dropped`。

## Integration

- 消费方：src/client（唯一下游，import `hahh9527/moonhttp/core`）——Call 持
  `Request`/`Response`，body_bridge 以 `ResponseBody::stream` 包装 Client as
  `@io.Reader`，按 `consumed()`/`dropped()` 查询触发 `Abandoned`，并把上游
  发送期错误映射为 `HttpMessageError::IncorrectBodyLength`。
- 运行时依赖（moon.pkg）：`moonbitlang/async/http`（`@http.Protocol`/
  `RequestMethod`/`CaseInsensitiveString`/`Headers`/`Cookie`/`Request`）、
  `moonbitlang/async/io`（`@io.Writer`/`@io.Reader`）、
  `moonbitlang/core/encoding/utf8`（`@utf8.decode_lossy`）。
- 仅测试依赖：`moonbitlang/async`、`hahh9527/moonhttp/internal/fixtures`
  （wire_form_test 的裸 TCP 对端夹具，不进入运行时依赖）。
- 只经公开 API 使用 moonbitlang/async；对上游的行为对齐基准为 OkHttp 5.5.0
  （已记录差异：userinfo 拒绝、IPv6 不压缩规范化等）。
