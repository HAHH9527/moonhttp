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
4. **headers（folded）**：
   - 基底 = `HeadersV::to_http_map()`（P01 折叠，同名无空格 `,` 合并）；
   - 注入 `Content-Length: <n>`：`body.content_length is Some(n)` 时
     （大小写不敏感查重，头已含时不覆盖——调用方显式声明优先）；
   - 注入 `Content-Type`：仅当折叠结果**不含** Content-Type 且
     `body.content_type is Some(v)`（research R5，对齐 OkHttp Bridge
     「头缺失才从 body 补」；用户头优先，body 元信息静默忽略）。
5. **纯函数性（SC-003）**：同一 Request 重复调用产出逐字节相同的三元组；
   实现无状态、无 memoization（L3「每 call 一次折叠、重放零折叠」缓存归
   P05/P07 call 对象，research R7）。
6. 本函数不触网络、不写发送状态机；定长帧由上游在 `Client::request` 时从
   headers 提取 Content-Length 触发 `SendingFixed`（send.mbt:343-345）。
7. **with_progress 组合不变式**：进度包装只改变写粒度（分块回调），不得
   改变 content_length 元信息与注入结果——Bytes + with_progress 的线上
   形态仍为 `Content-Length: n`、无 `Transfer-Encoding`（进度分块不得
   降级 chunked；SC-002 锚点见下表末行）。

**验收锚点**（spec US-2、Edge Cases、SC-003）：

| Given | When | Then |
| --- | --- | --- |
| Bytes 体（n=len） | to_http_request | headers 含 `Content-Length: n` |
| Stream 体（None） | to_http_request | headers 无 Content-Length → 线上 chunked |
| 带 query 的 url | to_http_request | path = `/...?query`；fragment 不出现 |
| headers 已含 Content-Type | to_http_request | 不覆盖；body.content_type 忽略 |
| 同一 Request 转换 N 次 | 属性测试 | 输出逐字节相同 |
| Bytes 体 + with_progress 包装 | to_http_request → 发送（P03 夹具） | 线上仍 `Content-Length: n`、无 `Transfer-Encoding`（分块回调不降级 chunked，SC-002） |

## HttpMessageError（错误类型 + 映射契约）

```moonbit
pub(all) suberror HttpMessageError {
  MethodBodyMismatch
  IncorrectBodyLength
  UnsupportedCharset(String)
} derive(@debug.Debug)
pub extend HttpMessageError with Debug::{to_repr}   // .mbti 产物 to_repr，P01 同款
```

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
