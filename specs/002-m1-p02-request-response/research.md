# Research: 请求/响应/体值模型与定长帧（M1-P02）

> Phase 0 产物。每项给出 Decision / Rationale / Alternatives。
> 证据基准：本仓库已钉 `moonbitlang/async@0.22.4`（moon.mod），本地解包
> `%TEMP%\opencode\async-0.22.4`；P01 已落地（`src/core/pkg.generated.mbti`
> 为公开面实测）。

## R1 P01 错误类型风格核对与 P02 错误类型命名

- **Decision**：P02 引入单一自持错误类型 **`HttpMessageError`**，形态完全对齐
  P01 实测风格：`pub(all) suberror HttpMessageError { ... } derive(@debug.Debug)`
  + 显式 `pub extend Debug::{to_repr}`（`.mbti` 产物为 `pub fn ...::to_repr`），
  **不参与判等/哈希、不使用 `derive(Show)`**。变体清单（唯一规范源见
  [data-model.md §5](data-model.md)）：
  `MethodBodyMismatch`（方法/体矩阵违例，FR-002）、
  `IncorrectBodyLength`（声明长度与实际字节超写/欠写，语义对齐上游同名错误）。
  **（2026-10-16 owner 裁决 B）**：原第三变体 `UnsupportedCharset(String)`
  **删除**——FR-007 改为集外 charset 按 UTF-8 降级解码（不 raise），
  该变体失去唯一触发点；封闭二变体（宪法 VI 最小接口），F14 回补时
  新增变体走 spec 变更。
  **配套写法适用本包全部 `derive(Debug)` 类型**：
  P01 `error.mbt` 决策 N1-A 留痕——工具链 0.1.20261012 下 `derive(Debug)`
  一经使用（含同包测试 `debug_inspect`）即触发 `implicit_impl_as_method`
  [0079]，须显式 `pub extend ... with Debug::{to_repr}` 消除；
  `HttpMessageError` 之外，`ResponseBodyEvent` 同样适用（登记于
  data-model §6，并列入 quickstart 步骤 3 冻结清单）。
- **Rationale**：P01 `.mbti` 实测（`src/core/pkg.generated.mbti:12-24`）：
  错误类型为 `pub(all) suberror`、仅 `derive(@debug.Debug)`、每类型一个
  `to_repr`——`HttpMessageError` 照搬该形态即满足 spec FR-012「风格对齐 P01」
  与「命名与 P01 冻结 `.mbti` 一致性核对」的裁决要求。命名取 `HttpMessage`
  前缀而非 `Request`：C4 裁决把响应侧 charset 违例也并入本类型，`RequestError`
  以偏概全；上游已有 `HttpProtocolError`（协议层），值模型层用 `HttpMessageError`
  不冲突。
- **Alternatives**：`RequestError`（响应侧 charset 违例语义错位，弃）；
  `BodyError`（不含方法/体矩阵违例，弃）；拆 Request/Response 两个错误类型
  （违背 spec C3/C4「并入同一自持类型」裁决，弃）；~~`UnsupportedCharset`
  不带载荷~~（**2026-10-16 裁决 B**：整个变体已删除——FR-007 改降级语义，
  charset 维度不再产生错误）。

## R2 OkHttp 方法/体矩阵核实（C5 裁决的佐证链）

- **Decision**：构造期矩阵按 C5 裁决实现——**拒体仅 GET/HEAD；必体为
  POST/PUT/PATCH；DELETE/OPTIONS/TRACE/CONNECT 体可选**。✅ **已按 OkHttp
  5.5.0 逐方法核对通过（取自本机 tag parent-5.5.0，复核日期 2026-10-15）**：
  `okhttp/src/commonJvmAndroid/kotlin/okhttp3/internal/http/HttpMethod.kt`
  - :33-41 `requiresRequestBody(method)` = POST / PUT / PATCH /
    PROPPATCH / QUERY / REPORT（:38 PROPPATCH、:39 QUERY、:41 REPORT，
    后三者为 WebDAV / OkHttp 5.x query 方法）；
  - :45 `permitsRequestBody(method) = !(method == "GET" || method == "HEAD")`。
  逐方法对照 C5 矩阵：拒体组 GET/HEAD ↔ :45（拒体集恰为其补集语义）；
  必体组 POST/PUT/PATCH ↔ :33-41 的 moonhttp 九方法内子集；可选组
  DELETE/OPTIONS/TRACE/CONNECT ↔ permit=true（OPTIONS 允许带体）且
  require=false。**无矩阵不一致，无 spec 回改诉求。**
  **显式差异（宪法 III）**：OkHttp `requiresRequestBody` 另含
  PROPPATCH/QUERY/REPORT 三方法——不在 moonhttp M1 九方法封闭枚举内
  （P01 FR-007 裁剪 `Custom` 的既定口径）；Method 枚举未来若扩展，须
  同步对齐该清单（本包不涉及）。
- **Rationale**：三角证据（按证据强度排序）：
  1. **tag 快照直读（本机 `parent-5.5.0`，2026-10-15）**：上方行号级
     核对，为最终依据。
  2. OkHttp 官方 issue
     [#6674](https://github.com/square/okhttp/issues/6674)（2021-05）原文引用
     源码：`permitsRequestBody(String method) { return !(method.equals("GET")
     || method.equals("HEAD")); }`，且 issue 标题实证 `OPTIONS` 返回 true
     （允许带体）——与 ：45 一致，排除「CONNECT/OPTIONS/TRACE/DELETE
     入拒体集」的旧版记忆。
  3. 上游 `@http` 便捷 `get` 自带守卫标签
     `` `GET` request should not contain a body ``（0.22.4
     `pkg.generated.mbti:12,15,70`）——上游对 GET 拒体同立场。
  4. `Request.Builder` 对 GET 带体抛 `IllegalArgumentException: method GET
     must not have a request body` 的行为自 2014 引入、master 仍存（检索实证）。
- **Alternatives**：按种子原文「HEAD/GET 不强制禁止」实现——已被证伪（宪法
  III 要求对齐真实基准并显式记录，spec A5/A6⑤ 已更正），弃。

## R3 @http 0.22.4 集成面（行号证据）

- **Decision**：转换层产物、定长帧触发、长度错误映射、Writer 落点全部锚定
  以下上游公开面（本地解包实测）：
  - 请求行组合：`Client::request(RequestMethod, StringView, extra_headers?)`
    （`client.mbt:283-291`）→ `send_request` 逐段写
    `METHOD <path> HTTP/1.1`（`send.mbt:322-335`）——**path 即请求目标
    原样写入**，故转换层产出 origin-form 请求目标 `path?query`
    （fragment 剥除、不参与线上）。
  - 定长帧触发：`send_headers` 从 `extra_headers` 提取 `Content-Length` →
    `mode = SendingFixed(remaining=len)`；否则 `WaitingRequestBody`（写时
    chunked）（`send.mbt:333-348`）——FR-004 机制闭环。
  - 长度不符：多写 `guard len <= remaining else { raise IncorrectBodyLength }`
    （`send.mbt:124`）；欠写 `end_body` `raise IncorrectBodyLength`
    （`:253-254`）——**双向报错、无截断**；`IncorrectBodyLength` 为
    `pub suberror`（`pkg.generated.mbti:37`），可被 P05 catch 并映射。
  - Writer 落点：`pub impl @io.Writer for Client`（`pkg.generated.mbti:86`）
    及 `write`/`write_once`/`write_reader`（`:82-84`）——C1 裁决的类型落点。
  - Response 形态：`@http.Response` 为 `code/reason/headers(Map，值已逗号
    合并)/cookies(Array[Cookie])` 四字段、**无 body 字段**
    （`:132-137`）——moonhttp `Response.body` 由 P05 在管线中围绕
    `Client as @io.Reader` 组装后传入，P02 提供纯重建函数（R7）。
  - 透明 gzip：发送侧自动 `Accept-Encoding: gzip,identity`（`send.mbt:338-342`），
    解压由上游 parser 侧完成（roadmap 引 `parser.mbt:331-335` 剥
    Content-Encoding/Content-Length）——FR-010「长度语义=解压后」成立，
    moonhttp 不重复处理。
  - 桩夹具原语：`@io.MemoryReader::MemoryReader(async (&Writer) -> Unit)`、
    `pipe()`（`io/pkg.generated.mbti`）——US-4 桩连接器直接用上游公开原语
    构造，无需自写 socket 桩。
- **Rationale**：宪法 I 要求只经公开 API 耦合；以上全部为 `pub` 面，行号
  可复核。
- **Alternatives**：经 `Sender`/内部状态机（非 pub，违宪，弃）；自建 socket
  桩（`@io.MemoryReader` 已足，D8 夹具自建指 P03 的裸 TCP 对端，US-4 不需要，
  弃）。

## R4 Writer 落点与上传进度的失败语义

- **Decision**：`BodySource::Stream((&@io.Writer) -> Unit)`（C1 裁决）；
  `with_progress(body, on_bytes : (Int64) -> Unit)` 的失败语义 = **不新增
  独立失败回调**——Stream 源中途抛错时，错误沿 async 写调用向上传播（上游
  Writer 方法为 async raise 面），发送调用以错误终止即为失败信号；进度包装
  在错误路径**不回调** `on_bytes`，保证「累计单调递增、终值=content_length」
  仅在成功完成时成立（spec FR-009/SC 前提不被污染）。
- **Rationale**：spec 边界用例把「失败事件精确契约」留给 plan；种子措辞
  「回调收到失败事件」若落成独立失败回调，则 `on_bytes` 签名要膨胀为
  Result 风格或双回调，公开面变大且 M1 无消费方（P05 只需发送终止即知败）。
  异常即信号的口径与 FR-012「错误经自持类型可判别传播」一致。
- **Alternatives**：`on_bytes : (Int64) -> Unit` + `on_error : (...) -> Unit`
  双回调（M1 无调用方，YAGNI，弃）；`on_bytes` 返回 Bool 中断协议（把控制流
  塞进回调，语义不清，弃）。

## R5 Content-Type 注入与 charset 参数解析规则

- **Decision**：
  1. 转换层注入/覆盖规则（**2026-10-16 owner 裁决 A 定稿：对齐 OkHttp
     body 覆盖语义**；5.5.0 取证见下）：`folded_headers` 基底 =
     `HeadersV::to_http_map()`；body != None 且 `body.content_type =
     Some(v)` → **覆盖**用户同名 Content-Type（大小写不敏感单键替换）；
     `body.content_length = Some(n)` → **覆盖** Content-Length 为 n；
     `body.content_length = None` → **删除** Content-Length 键（等价
     OkHttp `removeHeader`）；body = None → 不注入也不删除。用户头优先
     的 2026-10-15 I2 口径**作废**（不留两套说法）。`Content-Length`
     注入规则不变之表述同步作废。
     ✅ **OkHttp 取证（本机 tag parent-5.5.0，复核日期 2026-10-15/16）**：
     - `okhttp/src/commonJvmAndroid/kotlin/okhttp3/internal/http/BridgeInterceptor.kt`
       :40-45：body 非空且 `body.contentType()` 非空即
       `requestBuilder.header("Content-Type", contentType.toString())`；
       :47-54：`contentLength != -1` 即 `header("Content-Length", …)` 并
       `removeHeader("Transfer-Encoding")`，否则 `header("Transfer-Encoding",
       "chunked")` 并移除 Content-Length（定长/chunked 互斥）；
       :57-68：Host/Connection/Accept-Encoding 才是「缺了才补」。
     - `okhttp/src/commonJvmAndroid/kotlin/okhttp3/Request.kt`
       :248-256：`Builder.header(name, value)` 为**替换语义**（同名头全部
       替换）；:262-263 文档自认 Content-Length/Content-Encoding 可由
       body 派生值替换。
     - **机制差异（上游实现差异，非行为偏离）**：帧头由上游自管——上游
       `forbidden_headers` 丢弃调用方 Transfer-Encoding，chunked 由上游
       在无 Content-Length 时自行写出（send.mbt:37-39/:296-306/:103），
       转换层 MUST NOT 注入 TE。
  2. 响应 charset 解析规则（`text()` 用；**2026-10-16 owner 裁决 B 覆写**）：
     取响应头 `Content-Type` 合并值中**首个** `charset=` 参数（名值大小写
     不敏感、值可带双引号）；缺省/`utf-8`（忽略大小写）→ UTF-8；
     **其余任何 charset 值 → 按 UTF-8 降级解码（`@utf8.decode_lossy`）并
     输出一条 stderr 告警，不 raise**。病态场景（多 Content-Type 被上游
     逗号合并）按「首个参数」确定性取值。
     ✅ **OkHttp 取证（同上 tag）**：`okhttp/src/commonJvmAndroid/kotlin/
     okhttp3/MediaType.kt` :44-51 `charset(defaultValue)`——`parameter(
     "charset")`（:57-59 大小写不敏感）取值，解析失败 `Charset.forName`
     回退 `defaultValue`；`ResponseBody.string()` 按 UTF_8 + U+FFFD 替换。
     **可观测面有意差异（宪法 III 显式记录）**：OkHttp 静默回退；moonhttp
     额外输出 stderr 告警（本地化增强，不改变返回值），唯一出口
     `warn_charset_fallback`（包内私有，每次调用都告警、不去重）。
- **Rationale**：@http 头 Map 值已合并（R3），响应侧重建与解析只能基于合并
  值；「首个 charset 参数」是确定性规则，避免合并序歧义。OkHttp
  `MediaType.charset(...)` 参数词法口径（大小写不敏感、引号值）与 R5 一致。
- **Alternatives**：charset 解析放 P05（撕裂 `text()` 自足性，弃）；多值
  Content-Type 报错（病态输入引入新错误类，YAGNI，弃）；body.content_type
  与用户头冲突时报错（偏离 OkHttp 覆盖语义，弃——2026-10-16 裁决 A 改
  覆盖后此分叉消失）；~~用户头优先、body 静默忽略~~（2026-10-15 I2 口径，
  **2026-10-16 裁决 A 撤销**——改为对齐 OkHttp 覆盖语义）；~~集外 charset
  raise `UnsupportedCharset`~~（2026-10-15 C4 口径，**2026-10-16 裁决 B
  撤销**——改为降级 UTF-8 + stderr 告警）。

## R6 UTF-8 解码机制

- **Decision**：`text()` 的 UTF-8 解码用 `@utf8.decode_lossy(BytesView)`
  （`moonbitlang/core/encoding/utf8`，工具链 `.mbti` 实测：
  `decode(BytesView, ignore_bom?) -> String raise Malformed` /
  `decode_lossy(BytesView, ignore_bom?) -> String`）。**M1 不做 BOM 嗅探**
  ——即便字节带 BOM 也按 Content-Type/缺省 UTF-8 解、BOM 原样保留在结果中；
  与 OkHttp `string()` 的「BOM 嗅探并覆盖 charset、剥 BOM」差异在实现文档
  显式记录（宪法 III；SC-005）。
- **Rationale**：OkHttp `string()` 底层是 Java `String(bytes, charset)`——
  畸形序列替换为 U+FFFD、从不抛错；`decode_lossy` 逐字对齐。BOM 嗅探是
  加在 charset 语义上的第二层决策，M1 charset 集仅 UTF-8，BOM 只可能指向
  UTF-8/UTF-16，收益近零（YAGNI），差异记录即可。
- **Alternatives**：`decode`（对畸形字节 raise——与 OkHttp 替换语义相悖，
  弃）；BOM 嗅探全量实现（M1 无 UTF-16 受支持集，无处消费，弃；随 F14
  charset 集扩展时一并评估）。

## R7 Response 重建与 L3 缓存口径

- **Decision**：
  1. P02 提供纯重建函数 `Response::from_http(...)`：headers Map → HeadersV
     重建 = 逐键把逗号合并值拆回多条（`,` 无空格拆分），条目序 = Map 遍历序
     （不保证线上序，spec FR-008）；该拆分与 P01 折叠互逆（P01 SC-003 不变量
     ②），quoted-string 逗号不做边界感知（与 P01 折叠同一已记录限制，认证
     路径 M2 绕过）。
  2. 转换层保持**无状态纯函数**；「折叠结果按 call 缓存一次、重放复用」的
     L3 口径（roadmap D4）由 P05/P07 的 call 对象承载，core 不引入任何可变
     缓存（保 FR-001 不可变值语义与 FR-005 纯函数承诺）。
- **Rationale**：@http Response 无 body 字段、头值已合并（R3），重建是 P02
  值模型的必然组成（spec 边界用例「折叠对称性回读」）；缓存放 core 会引入
  内部可变状态，破坏纯函数验收（SC-003）。
- **Alternatives**：重建不拆分、保留合并单值（`values` 语义残废，且与 P01
  互逆承诺相悖，弃）；core 内 memoize 转换结果（可变状态入值模型，弃）。

## R8 包布局与依赖边

- **Decision**：P02 增量进入既有 `src/core` 包（M1 README L115-116「core 值
  对象（P01/P02）入 core 包」+ P01 plan Structure Decision 同口径）；
  `moon.pkg` 在既有 `moonbitlang/async/http` 之上新增两条 import：
  `moonbitlang/async/io`（`@io.Writer`/`@io.Reader` trait、`MemoryReader`/
  `pipe` 桩原语）与 `moonbitlang/core/encoding/utf8`（`text()` 解码）。
  依赖方向不变：`client → core → moonbitlang/async(+core)`。
- **Rationale**：C1 裁决让类型面直接引用 `@io` trait，必须显式 import；
  `@utf8` 是 core/encoding 家族公开包（async 自身同样引用，R6）。二者均非
  新上游、不扩宪法 I 风险面。
- **Alternatives**：P02 单立 `src/body` 包（值模型被 P01/P05 双向引用，切包
  只增 import 环风险，弃）；把 @io 依赖隔离在 P05（类型面无法表达 C1 裁决，
  弃）。

## R9 ResponseBody 生命周期事件契约

- **Decision**：事件枚举 `ResponseBodyEvent { Consumed; Dropped; Abandoned }`
  （命名见 data-model §6），流式 ResponseBody 持有事件回调（默认 no-op）与
  只读状态。触发点契约：
  | 事件 | 触发点 | 触发者 |
  | --- | --- | --- |
  | `Consumed` | 读到 EOF（`bytes()` 读到底 / 流式读取耗尽） | 本包 |
  | `Dropped` | 使用者显式调用释放方法（幂等；已 Consumed 则不再触发） | 本包 |
  | `Abandoned` | 调用收尾发现既未 Consumed 也未 Dropped（毒化信号） | P04/P05 所有者（本包提供状态查询） |
  本包只定义契约、默认行为（no-op 回调）与状态查询；真实归池/毒化接归
  P04/P05（spec FR-006）。US-4 以 `@io.MemoryReader`/`pipe` 桩驱动三类路径
  断言事件序列。
- **Rationale**：MoonBit 无 GC 析构钩子，「未读完即弃」只能由持有连接的
  所有者在调用收尾检测——契约把触发权显式划分给 P04/P05，本包保证状态可查、
  事件可判别（三类互斥、时序单调：Consumed/Dropped 至多其一先行，Abandoned
  仅在二者皆未发生时由所有者触发）。
- **Alternatives**：三类事件合并为「关闭原因」参数（判别度不足，spec FR-006
  要求三类可判别，弃）；Abandoned 由本包在 read 中途探测（无法观测「弃读」
  这一不作为，语义不成立，弃）。

## R10 判等/哈希与 Debug 形态（函数字段的类型面约束）

- **Decision**：P02 值类型 **不承诺 Eq/Hash**（与 P01 不同）：`BodySource::Stream`
  持函数、`ResponseBody::stream` 持 `&@io.Reader` trait 对象，判等/哈希无
  语义（P04 池键由 HttpUrl+HeadersV 判等承担，不涉体）。Debug 形态：
  `BodySource`/`RequestBody`/`ResponseBody` **手写 `impl @debug.Debug`**——
  Stream 印 `<stream fn>`、Bytes 印元信息（content_type/content_length）
  **不整打字节内容**（输出实用性：避免调试打印转储大块字节，非脱敏/
  掩码措施——owner 2026-10-15 裁定；敏感头掩码与可配置开关归 M3
  F13/F12）、
  ResponseBody 印状态与长度元信息（不印 reader 内部与 body 字节）；
  `Request`/`Response` 字段由此全部可 Debug，仍可 derive。
- **Rationale**：derive 对函数/trait 对象字段不可行（编译事实，非风格选择）；
  P01「全部 derive 默认实现」的口径受其类型面限制（无可执行字段），P02 的
  手写仅限必要范围且输出更收敛（body 字节不打）。明文 Debug（headers 等）
  沿 P01 已确认的展示例外口径（R3-M1 留痕；F13 明文覆盖后续
  Request/Response 值类型）。
- **Alternatives**：给 Request/RequestBody 强造 Eq/Hash（函数字段参与判等
  无定义，弃）；Debug 印全量 body 字节（调试输出转储大块字节、实用性差，
  弃——非违宪判定；脱敏/掩码归 M3 F13/F12，owner 2026-10-15 裁定）。
