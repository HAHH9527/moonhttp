# 契约：Request / RequestBuilder / RequestBody（M1-P02 core 包公开 API）

**包**：`hahh9527/moonhttp/core`（P02 增量，落 `src/core`）。类型与变体
清单的**唯一规范源**是 [data-model.md](../data-model.md)；本文件给签名形态、
调用约定与验收锚点。

## Request（不可变值）

```moonbit
pub struct Request {
  url     : HttpUrl        // P01
  method  : Method         // P01，构造默认 Get
  headers : HeadersV       // P01，保序可重复
  tag     : Unit?          // C2 裁决：占位，语义零承诺（欠账 F15）
  body    : RequestBody?
} derive(Debug)
```

**契约条款**：

1. 字段不可变（FR-001）；跨重试/重定向复用内容恒定。**不实现 Eq/Hash**
   （body 含函数/引用字段，判等无语义；池键由 HttpUrl+HeadersV 承担，
   research R10）。
2. 构造只经 `RequestBuilder`；`build()` 成功即冻结（FR-002）。
3. `Debug` 为 derive 默认实现（headers 明文输出沿 P01 展示例外口径，
   F13/M3 收口；测试样例值用合成占位串，A9 纪律）。

## RequestBuilder（可变构造器 + 构造期校验）

```moonbit
pub struct RequestBuilder { /* 可变字段 */ } derive(Debug)

pub fn RequestBuilder::new(url : HttpUrl) -> Self
pub fn RequestBuilder::method(Self, Method) -> Self
pub fn RequestBuilder::headers(Self, HeadersV) -> Self      // 整体替换（P01 已固化值）
pub fn RequestBuilder::header(Self, String, String) -> Unit raise HeadersError
pub fn RequestBuilder::tag(Self, Unit?) -> Self
pub fn RequestBuilder::body(Self, RequestBody) -> Self
pub fn RequestBuilder::build(Self) -> Request raise HttpMessageError
```

**契约条款**：

1. `build()` 执行方法/体矩阵双向校验（C5 裁决，矩阵以 OkHttp 5.x
   `HttpMethod.kt` 为准，research R2）：
   - 拒体：`Get`/`Head` + `body != None` → raise `MethodBodyMismatch`；
   - 必体：`Post`/`Put`/`Patch` + `body == None` → raise
     `MethodBodyMismatch`；
   - 体可选：`Delete`/`Options`/`Trace`/`Connect` 不校验。
2. 头操作 `header` 委托 P01 `HeadersVBuilder` 校验（raise `HeadersError`，
   不在本包重复/放宽）；`headers` 整体替换入口接收已固化 HeadersV
   （P01 校验已发生）。
3. 校验失败即 raise 且 Builder 状态不变（沿用 P01「容器不变」纪律）。
4. `tag` 只存取、无任何按 tag 定位/取消语义（C2 裁决）。

**验收锚点**（对应 spec US-1、Edge Cases、SC-001）：

| Given | When | Then |
| --- | --- | --- |
| 链式设置五要素 | build | 字段逐项正确；headers 保序可重复 |
| 未设 method/body | build | `Get` + `None` |
| GET/HEAD + body | build | raise `MethodBodyMismatch` |
| POST/PUT/PATCH 无 body | build | raise `MethodBodyMismatch` |
| DELETE/OPTIONS/TRACE/CONNECT ± body | build | 成功，不校验 |
| 非法头名/头值 | header(...) | raise `HeadersError`（P01 继承） |

## RequestBody（体值）

```moonbit
pub struct RequestBody {
  content_type    : String?
  content_length  : Int64?
  source          : BodySource
}
// Debug = 手写 impl @debug.Debug（research R10）：
// Bytes 印元信息（content_type/content_length）、Stream 印 <stream fn>，不印体字节

pub fn RequestBody::bytes(data : Bytes, content_length : Int64,
                          content_type? : String?) -> RequestBody raise HttpMessageError
pub fn RequestBody::stream(f : (&@io.Writer) -> Unit, content_length? : Int64?,
                           content_type? : String?) -> RequestBody
pub fn RequestBody::with_progress(Self, on_bytes : (Int64) -> Unit) -> RequestBody
```

**BodySource 两变体**（Debug 同为手写 impl，口径与 RequestBody 一致，research R10）：

```moonbit
pub(all) enum BodySource {
  Bytes(Bytes)
  Stream((&@io.Writer) -> Unit)
}
```

**契约条款**：

1. **Bytes 构造期 O(1) 校验**：`content_length == data.len()`，不符 raise
   `IncorrectBodyLength`（C3 裁决；Bytes 长度错在构造点暴露，发送期不再
   出现）。Bytes 可重放：克隆 O(1)，重放 N 次逐字节一致（SC-003）。
2. Stream 形态：回调一次性消费、不可重放；`content_length` 缺省 `None`
   （→ chunked），显式 `Some(n)` 走定长帧、写超/欠写由发送期上游
   `IncorrectBodyLength` 报错（P05 映射，research R3）。Writer 参数类型为
   底座 `@io.Writer`（`@http.Client` 公开 impl；C1 裁决——本包不自立
   Writer trait、不暴露 `@http.Client` 具体类型）。
3. `with_progress`：成功完成时 `on_bytes` 累计值**单调递增且终值 =
   content_length**（FR-009）；Bytes 按分块回调、Stream 包计数 Writer 委托。
   失败路径不回调 `on_bytes`、以错误终止表达（research R4）。
4. 帧规则不进本文件实现——转换层按 `content_length` 注入（见
   [conversion-errors.md](conversion-errors.md)）；本文件只约束元信息。
5. Debug 不整打体字节（payload 可能含凭证；research R10）。

**验收锚点**（spec US-2、US-5、Edge Cases）：

| Given | When | Then |
| --- | --- | --- |
| bytes(data, Some(n)≠len) | 构造 | raise `IncorrectBodyLength` |
| bytes(data, n=len) | 构造 | 成功；重放 N 次逐字节一致 |
| stream + content_length=None | 转换/发送 | 线上 chunked（P03 夹具断言） |
| 1MB Bytes + with_progress | 发送 | 累计单调递增、终值 = content_length |
| Stream 源中途抛错 | 发送 | 错误可判别传播；on_bytes 不再回调 |
