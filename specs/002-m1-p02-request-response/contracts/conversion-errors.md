# 契约：转换层纯函数与 HttpMessageError（M1-P02 core 包公开 API）

**包**：`hahh9527/moonhttp/core`（P02 增量）。本文件是「Request → @http
调用参数」唯一产出面（spec FR-005）与错误映射契约的签名形态；机制证据
（行号）见 [research.md](research.md) R3。

## 转换层：Request::to_http_request（纯函数）

```moonbit
pub fn Request::to_http_request(Self) -> @http.Request
// @http.Request = { meth : @http.RequestMethod, path : String,
//                   headers : Map[CaseInsensitiveString, String] }
```

**契约条款**：

1. **产出形态**：复用上游 `pub(all) struct @http.Request`——字段与 spec
   FR-005 的 `(meth, path, folded_headers)` 一一对应，零新类型（research
   R3；P05 直接以 `meth`/`path`/`headers` 喂 `Client::request(...) +
   Client::write(...)`）。
2. **meth**：经 P01 `Method::to_request_method` 封闭映射（无失败分支）。
3. **path**：origin-form 请求目标——`/` 起始的 path 段重组 + `?query`
   （有 query 时）；**fragment 剥除**（不参与线上）。上游把该串原样写入
   请求行（send.mbt:334）。
4. **headers（folded）注入/覆盖规则**（**2026-10-16 owner 裁决 A：对齐
   OkHttp body 覆盖语义**，5.5.0 取证 = BridgeInterceptor.kt:42-54 +
   Request.kt:247-256 `header()` 同名全部替换）：
   - 基底 = `HeadersV::to_http_map()`（P01 折叠，同名无空格 `,` 合并）；
   - **Content-Type 覆盖**：body != None 且 `body.content_type = Some(v)`
     → 覆盖用户同名 Content-Type（大小写不敏感单键替换）；body = None
     或 content_type = None → 用户 Content-Type 保持不动；
   - **Content-Length 覆盖**：body != None 且 `content_length = Some(n)`
     → 覆盖 Content-Length 为 n（用户设错值也被覆盖）；
   - **Content-Length 删除**：body != None 且 `content_length = None`
     → 从输出 Map **删除** Content-Length 键（等价 OkHttp
     `removeHeader`）；chunked 由上游在无 Content-Length 时自行写出；
   - **body = None** → 不注入也不删除 Content-Length（用户显式声明
     透传，帧长由上游按其值处理）；
   - **MUST NOT 注入 Transfer-Encoding**（机制差异，上游实现自管：上游
     `forbidden_headers` 丢弃调用方 TE，chunked 由上游自行写出——
     send.mbt:37-39/:296-306/:103）。
5. **纯函数性（SC-003）**：同一 Request 重复调用产出逐字节相同的三元组；
   实现无状态、无 memoization（L3「每 call 一次折叠、重放零折叠」缓存归
   P05/P07 call 对象，research R7）。
6. 本函数不触网络、不写发送状态机；定长帧由上游在 `Client::request` 时从
   headers 提取 Content-Length 触发 `SendingFixed`（send.mbt:343-345）。
7. **with_progress 组合不变式**：进度包装只改变写粒度（分块回调），不得
   改变 content_length 元信息与注入结果——进度承诺仅 Stream 形态
   （FR-009，2026-10-16 裁决 C）；Bytes + with_progress 的
   `to_http_request` 输出与未包装逐字节相同（元信息恒等）。

**验收锚点**（spec US-2、Edge Cases、SC-003）：

| Given | When | Then |
| --- | --- | --- |
| Bytes 体（n=len） | to_http_request | headers 含 `Content-Length: n` |
| Stream 体（None） | to_http_request | 输出无 Content-Length 键（用户声明的也被删除）→ 线上 chunked |
| 带 query 的 url | to_http_request | path = `/...?query`；fragment 不出现 |
| 用户已设 Content-Type + body 带 type | to_http_request | 输出为 body 值（覆盖，2026-10-16 裁决 A） |
| 用户设错 Content-Length + body Some(n) | to_http_request | 输出为 n（覆盖） |
| Stream(None) + 用户声明 Content-Length | to_http_request | 该键被删除、线上 chunked（2026-10-16 裁决 A） |
| body = None + 用户声明 Content-Length/Content-Type | to_http_request | 两键原样透传（不注入不删除） |
| 同一 Request 转换 N 次 | 属性测试 | 输出逐字节相同 |
| 空体 Bytes（n=0） | to_http_request → 发送（P03 夹具） | 含 `Content-Length: 0`、不落 chunked（spec 边界用例「空体 POST」；U1 补锚 2026-10-15；覆盖语义下不变） |
| Bytes 体 + with_progress 包装 | to_http_request | 输出与未包装逐字节相同（裁决 C：Bytes 不承诺回调，元信息恒等） |

## HttpMessageError（错误类型 + 映射契约）

```moonbit
pub(all) suberror HttpMessageError {
  MethodBodyMismatch
  IncorrectBodyLength
} derive(@debug.Debug)
pub extend HttpMessageError with Debug::{to_repr}   // .mbti 产物 to_repr，P01 同款
```

> **2026-10-16 owner 裁决 B**：删除 `UnsupportedCharset(String)` 变体——
> FR-007 改为集外 charset 按 UTF-8 降级解码（不 raise），该变体失去唯一
> 触发点；保留永不触发的变体是错误面的虚假承诺（宪法 VI 最小接口），
> F14 回补时新增变体走 spec 变更。

**契约条款**：

1. 变体清单唯一规范源 = [data-model.md §5](../data-model.md)；触发点矩阵
   见该节表格。本类型是 spec FR-012 的「moonhttp 自持错误类型」。
2. **映射契约（发送期，执行归 P05）**：P05 捕获上游
   `@http.IncorrectBodyLength`（0.22.4 mbti:37，pub suberror）后 MUST
   映射为本类型 `IncorrectBodyLength` 变体，保持类别可判别；映射本身不得
   吞错、不得降级为字符串消息。P02 交付该契约（本条），catch/映射执行在
   P05（FR-010 不含执行逻辑，C3 裁决）。
3. 风格：仅 `derive(Debug)` + `to_repr`；不判等、不哈希、不用 `derive(Show)`
   （[0027] 弃用警告与 SC 零警告互斥；P01 决策 M5-A/N1-A 继承）。
4. 错误消息（`to_repr`/构造期消息）只携带定位片段：方法名、长度对
   （声明值/实际值）、charset 名；**不回显**头值、体字节、URL 全文
   （宪法敏感信息口径；P01 SC-005 ② 同款继承）。

## 与 P01 冻结 `.mbti` 的一致性核对结论（plan 期裁决，spec 留痕事项）

- P01 实测公开面（`src/core/pkg.generated.mbti:12-24`）：错误类型 =
  `pub(all) suberror` + `derive(@debug.Debug)` + 独立 `to_repr`；
  `HttpMessageError` 完全同构——**命名与风格一致性核对通过**（research
  R1）。
- P01 值类型均带 Eq/Hash；P02 值类型**有意不带**（函数/trait-object 字段，
  research R10）——该差异属类型面事实约束而非风格漂移，已登记
  data-model「实体总览」，tasks 阶段 `.mbti` 冻结审视时按此口径核对。
- 复用清单：`HttpUrl`、`HeadersV`（`to_http_map`）、`Method`
  （`to_request_method`）、`HeadersError`（Builder 头校验错误透传，
  不并入 HttpMessageError——域不同，P01 已冻结）。
