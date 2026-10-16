# Data Model: 请求/响应/体值模型与定长帧（M1-P02）

> 本文件是 P02 值模型、错误变体与事件契约的**唯一规范源**；spec 与
> contracts/ 只按名引用、不重述清单。证据行号见 [research.md](research.md) R3。

## 实体总览

| 实体 | 形态 | 判等/哈希 | Debug | 一句话职责 |
| --- | --- | --- | --- | --- |
| Request | 不可变 struct | 无（含体源） | derive + to_repr | 请求五要素值（url/method/headers/tag/body） |
| RequestBuilder | 可变 struct | 无 | derive + to_repr | 构造期校验（方法/体矩阵）与组装 |
| RequestBody | 不可变 struct | 无 | **手写** | 体元信息 + Bytes/Stream 两形态 |
| BodySource | enum（两变体） | 无 | **手写** | Bytes（可重放）/ Stream（一次性回调） |
| Response | 不可变 struct | 无（含体） | derive + to_repr | 响应六要素值（code/reason/headers/cookies/body/prior） |
| ResponseBody | 不可变外观 + 内部状态 | 无 | **手写** | buffered/stream 两态 + 生命周期事件 |
| HttpMessageError | `pub(all) suberror` | 无（错误不判等） | derive + to_repr | 方法/体矩阵、体长度两类违例（2026-10-16 裁决 B：charset 维度不再入错误类型） |
| ResponseBodyEvent | enum（三变体） | 无 | derive + to_repr | 流式体生命周期事件（Consumed/Dropped/Abandoned） |

> 判等/哈希不承诺的原因与 Debug 手写范围见 research R10；P01 的
> Eq/Hash 口径（FR-006）是 P01 类型面的局部决策，不外溢到含函数/reader
> 字段的 P02 类型。`to_repr` 列口径：凡 `derive(Debug)` 的类型（本表 5 个）
> 均须紧随 `pub extend T with Debug::{to_repr}` 消 [0079]（N1-A/R1；
> P01 实证 `.mbti`:37/:52/:74/:93），冻结核对项见 tasks T017。

## 1. Request + RequestBuilder

**字段**（不可变值；Builder 可变，`build()` 产出值）：

| 字段 | 类型 | 约束 |
| --- | --- | --- |
| url | `HttpUrl`（P01） | 构造必填 |
| method | `Method`（P01） | 未设置默认 `Get` |
| headers | `HeadersV`（P01） | 保序可重复；Builder 侧沿用 P01 校验 |
| tag | `Unit?` | 占位，语义零承诺（C2 裁决，欠账 F15） |
| body | `RequestBody?` | 未设置 `None` |

**验证规则（构造期，`build()` 触发，违例 raise `HttpMessageError`）**：

- 方法/体矩阵（C5 裁决；佐证 research R2）：
  - `Get`/`Head` 带 body → `MethodBodyMismatch`；
  - `Post`/`Put`/`Patch` 缺 body → `MethodBodyMismatch`；
  - `Delete`/`Options`/`Trace`/`Connect` 体可选（不校验）。
- 头名/头值校验沿 P01 FR-012（`HeadersVBuilder::add/set` raise
  `HeadersError`，本包不重复实现、不放宽）。

**不变量**：构造成功后五字段不可变；同一 Request 重复参与重试/重定向内容
不变（FR-001）。

## 2. RequestBody + BodySource

**字段**：

| 字段 | 类型 | 约束 |
| --- | --- | --- |
| content_type | `String?` | 透传给转换层注入（research R5 注入规则） |
| content_length | `Int64?` | `None` = 未知 → chunked（FR-003/FR-004） |
| source | `BodySource` | 两形态，见下 |

**BodySource 两变体**：

- `Bytes(Bytes)`——可重放：`Bytes` 为不可变引用值，克隆 O(1)、重放 N 次内容
  逐字节一致（FR-003，SC-003）。**构造期 O(1) 校验**：`bytes(data,
  content_length, content_type?)` 要求 `content_length == data.len()`，
  不符 raise `IncorrectBodyLength`（C3 裁决；错误在构造点暴露，发送期不会
  再出现 Bytes 长度错）。
- `Stream((&@io.Writer) -> Unit)`——一次性回调消费、不可重放；Writer 为
  `@http.Client` 公开实现的底座 `@io.Writer`（C1 裁决）。`content_length`
  可为 `None`（chunked）或 `Some(n)`（定长帧；写超/欠写在发送期由上游
  `IncorrectBodyLength` 报错、P05 映射，research R3）。

**with_progress**：`with_progress(on_bytes : (Int64) -> Unit) -> RequestBody`
——**进度承诺仅 Stream 形态**（2026-10-16 owner 裁决 C）：Stream 包计数
`@io.Writer` 委托，成功完成时累计单调递增且终值 = content_length；Bytes
形态不承诺回调，仅保证 content_type/content_length 元信息与转换输出恒等。
失败路径不回调、以错误终止表达（research R4）。

## 3. Response

**字段**（不可变值；由 P05 经纯重建函数组装，FR-008）：

| 字段 | 类型 | 约束 |
| --- | --- | --- |
| code | `Int` | 上游原样 |
| reason | `String` | 上游原样 |
| headers | `HeadersV`（P01） | 由 @http 响应 Map 重建：逗号合并值拆回多条，条目序 = Map 遍历序，**不保证线上序**；拆分与 P01 折叠互逆（research R7） |
| cookies | `Array[@http.Cookie]` | 上游透传，M1 不建 Jar；js 恒空 |
| body | `ResponseBody?` | P05 组装传入（`@http.Response` 无 body 字段） |
| prior | `Response?` | 字段就位，P06 填充，本包不产链 |

## 4. ResponseBody（两态 + 生命周期）

**两态**：

- **buffered**：持有完整负载 `Bytes`（0 字节合法，`bytes()` 返回空不报错）；
  `bytes()` 直接返回、`text()` 解码后返回。
- **stream**：持有 `&@io.Reader`（P05 传入 `Client as @io.Reader`；测试用
  `@io.MemoryReader`/`pipe` 桩）+ 事件回调（默认 no-op）+ 只读状态
  （`consumed`/`dropped` 标志）。`read_some(max_len?)` 增量读（委托上游）；
  `bytes()` = 读到底 → 置 consumed → 触发 `Consumed`；`text()` = `bytes()`
  + charset 解码；显式 `drop()` 幂等释放 → 未 consumed 时置 dropped 并触发
  `Dropped`。

读取 API 统一 async 签名：`bytes()`/`text()`/`read_some` 均为
`pub async fn`——stream 态读 `&@io.Reader` 走上游 async 读取面，
buffered 态同签名对齐（plan review 修订；contracts/response.md 同步）。

**charset 语义（`text()`）**：解码集 = {UTF-8}（**2026-10-16 owner 裁决 B
覆写 C4**）；规则按 research R5（首个 `charset=` 参数、大小写不敏感、引号
值；缺省 UTF-8）；**集外 charset → 按 UTF-8 降级解码（`decode_lossy`）并
输出一条 stderr 告警（唯一出口包内私有 `warn_charset_fallback`，消息只带
charset 名定位片段），不 raise**——降级语义对齐 OkHttp 5.5.0（MediaType.kt
:44-51 + ResponseBody.string()）；告警为可观测面有意差异（宪法 III）；
解码用 `@utf8.decode_lossy`（畸形序列替换 U+FFFD，BOM 不嗅探差异记录 R6）。
长度语义 = 解压后长度（FR-010，research R3）。

**生命周期状态机**（流式态）：

```text
        ┌─────────┐ read 到 EOF(bytes()/read_some 耗尽)  ┌──────────┐
        │ Active  │ ───────────────────────────────────▶ │ Consumed │──▶ 触发 Consumed
        │         │                                      └──────────┘
        │         │ 显式 drop()（幂等）
        │         │ ───────────────────────────────────▶ ┌──────────┐
        └─────────┘                                      │ Dropped  │──▶ 触发 Dropped
   收尾查询：consumed()==false 且 dropped()==false
   ──▶ P04/P05 触发 Abandoned（毒化信号）
```

互斥/时序不变量：`Consumed` 与 `Dropped` 至多发生其一（先到者赢，后到
幂等无事件）；`Abandoned` 仅在二者皆未发生时由所有者触发，触达后状态终态。
三类事件可判别（FR-006）；本包默认回调 no-op，归池/毒化接归 P04/P05。

## 5. 错误模型 HttpMessageError（变体清单唯一规范源）

```moonbit
pub(all) suberror HttpMessageError {
  MethodBodyMismatch          // 方法/体矩阵违例（§1 构造期校验）
  IncorrectBodyLength         // 声明长度 ≠ 实际字节（Bytes 构造期；Stream 发送期经 P05 映射）
} derive(Debug)               // + 显式 pub extend Debug::{to_repr}
```

> **2026-10-16 owner 裁决 B**：删除 `UnsupportedCharset(String)` 变体
> （FR-007 改为集外 charset 按 UTF-8 降级解码 + stderr 告警，不再 raise；
> 保留永不触发的变体是错误面的虚假承诺，宪法 VI 最小接口；F14 回补时
> 新增变体走 spec 变更）。

**触发点与映射契约**：

| 变体 | 触发点 | 触发者 | 上游映射 |
| --- | --- | --- | --- |
| `MethodBodyMismatch` | `RequestBuilder::build()` | 本包 | 无 |
| `IncorrectBodyLength` | `RequestBody::bytes(...)` 构造期 | 本包 | 发送期 P05 将 `@http.IncorrectBodyLength`（pub suberror，0.22.4 mbti:37）映射为**同一变体**，类别可判别 |

风格条款：仅 `derive(Debug)` + `to_repr`，不判等不哈希不用 `Show`；错误
消息只携带定位片段（方法名、长度对），不回显头值/体内容
（宪法敏感信息口径；P01 同款条款继承）。

## 6. 事件模型 ResponseBodyEvent

```moonbit
pub(all) enum ResponseBodyEvent { Consumed; Dropped; Abandoned } derive(Debug)
pub extend ResponseBodyEvent with Debug::{to_repr}   // N1-A：消 [0079]（R1；quickstart 步骤 3 冻结项）
```

触发点契约与互斥/时序不变量见 §4 状态机；事件载荷为空（判别靠变体本身，
细节由状态查询承载）。

## 不变量与验证规则汇总（供 tasks 直接引用）

1. 方法/体矩阵双向校验（§1）——构造期、可判别错误。
2. Bytes 构造期长度恒等校验（§2）——O(1)，错误在构造点暴露。
3. 帧规则（FR-004）：`content_length=None → chunked`；`Some(n) → 定长帧`
   （机制锚点 research R3 send.mbt:333-348）。
4. 转换层纯函数：同 Request 多次转换输出逐字节相同（FR-005/SC-003）。
5. Response.headers 重建与 P01 折叠互逆；验收禁止断言线上序（FR-008）。
6. `text()`：集外 charset 按 UTF-8 降级解码（stderr 告警，不抛错——
   2026-10-16 裁决 B）；畸形 UTF-8 替换不抛（§4）。
7. 生命周期三事件互斥时序（§4 状态机）。
8. 全体值类型不可变（FR-001）；构造后无任何可变公开面。

## 数据量假设

- 请求头数量级 ≤ 数十条、体大小 0 B – 数 GB（Stream 形态为大体的常规
  路径；Bytes 形态受内存约束由调用方自理）。
- 生命周期事件每流式体至多 1 次（Consumed/Dropped 二选一）+ 至多 1 次
  Abandoned，无高频热点。
- charset 参数长度无上限假设：解析为线性扫描，超长参数不特殊处理
  （按 R5 规则确定性失败或成功，无回溯）。
