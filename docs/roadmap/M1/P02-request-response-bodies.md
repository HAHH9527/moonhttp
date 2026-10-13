# P02 请求/响应/体值模型与定长帧（L2）

> 里程碑：M1 性能核心 ｜ 前置依赖：P01、P03 ｜ 人力估计：~1.5 人日
> 来源：`proj-init-docs/okhttp-on-async-http/01-calls/README.md` §2/§3.3/§3.6/§6/§8、
> `14-performance/README.md` §2 L2
> 侵入性：非侵入 ｜ 建议特性 slug：`m1-p02-request-response`

## 功能描述（speckit 输入种子）

交付 moonhttp 的请求/响应/体值模型：`Request`（+Builder、tag）与三种语义要素
`Method`/`HeadersV`/`HttpUrl`（P01）组装；`RequestBody` 的 **Bytes/Stream 两形态**
（可重放性是重试/重定向的硬前提）；`Response`/`ResponseBody`（缓冲与流式两态、
`bytes()`/`text()` 便捷读取）；以及**定长帧规则（性能杠杆 L2）**——已知长度的
body 经 `extra_headers~{Content-Length}` 进入 `@http` 的 `SendingFixed` 定长发送，
消除 chunked 每块编码/解析开销（round3 已验证机制）。
本包交付「Request → @http 调用参数」的纯转换层与体模型；执行管线归 P05。

## 范围

包含：

- `Request` 值对象 + Builder（url/method/headers/tag/body）；默认方法 GET。
- `RequestBody`：`content_type`、`content_length : Int64?`（None = 未知 → chunked）、
  `BodySource` 两形态：`Bytes(Bytes)`（可重放 O(1)）与
  `Stream((&Writer) -> Unit)`（一次性回调，不可重放）。
  定长帧规则：`Bytes` 一律携带 `content_length`。
- `RequestBody::with_progress(body, on_bytes : Int64 -> Unit)`（Stream 包计数
  Writer；Bytes 分块写）。
- **转换层纯函数**：`Request` → `(meth, path, folded_headers)`，其中定长
  `Content-Length` 头在此注入（供 P05 管线调用；也是本包独立验收的驱动面）。
- `Response`：code/reason/`headers : HeadersV`（由 @http 响应 Map 重建，顺序为遍历序，
  不保证线上序——README 口径说明）、`cookies`（@http 透传，M1 不建 Jar）、
  `body : ResponseBody?`、`prior : Response?`（字段就位，由 P06 填充）。
- `ResponseBody`：`buffered/stream` 两态；`bytes()`/`text()`（charset 默认 UTF-8）；
  流式形态的**析构回调协议**（完整消费/显式 drop/未读完丢弃三类事件，
  由 P04/P05 接入归池与毒化，本包只定义回调契约与默认行为）。
- 透明 gzip 语义说明：@http 已自动 `Accept-Encoding: gzip,identity` 并透明解压
  （剥 Content-Encoding/Content-Length，`send.mbt:338-342`、`parser.mbt:331-335`），
  moonhttp 不重复处理，Response 的 content_length 语义为「解压后长度」。

非目标（显式排除）：

- `BodySource::File`（D5，随 M2/09）；`json()`/`char_stream`（D6，M2）；
- 自动头补齐（Host/UA/Accept-Encoding 由 @http 连接层已写；Bridge 级自动头随
  M2 04 的 Bridge 拦截器）；Cookie 注入（M2/11）；缓存条件 GET 改写（M4/05）；
- 任何连接/执行/取消逻辑（P04/P05）。

## 用户故事种子

### US-1 构造请求（P1）

作为使用者，我用 Builder 组装 Request（URL、方法、有序头、可选体与 tag），
得到不可变值对象。

**验收场景**：

1. Given Builder 链式设置，Then 字段逐项正确、headers 保序可重复。
2. Given 未设方法，Then 默认 GET、body 为 None。

### US-2 定长帧发送（P1，性能核心 L2）

作为使用者，我提交 `Bytes` 体（已知长度）的 POST；线上字节使用
`Content-Length` 定长帧而非 chunked。

**独立测试**：P03 裸 TCP 对端捕获原始请求字节，直接以转换层输出驱动
`@http.Client`（不经 P05），断言线上形态。

**验收场景**：

1. Given `RequestBody::bytes(data, content_length=Some(n), …)`，When 经转换层发送，
   Then 捕获字节含 `Content-Length: n` 且无 `Transfer-Encoding` 头。
2. Given `Stream` 形态（content_length=None），Then 线上为 chunked
   （含 `Transfer-Encoding: chunked` 与块编码）。
3. Given 多次重放 `Bytes` 体，Then 内容逐字节一致（重放性）。

### US-3 读取响应体（P1）

作为使用者，我对终态 Response 调 `body.bytes()`/`body.text()` 得到缓冲数据，
charset 缺省按 UTF-8 解码。

**验收场景**：

1. Given 小响应（缓冲态），Then `bytes()` 返回完整负载、`text()` 正确解码。
2. Given `Content-Type` 带 `charset=gbk`（clarify 后的受支持集内），Then 按其解码。

### US-4 流式响应体与析构回调（P2）

作为执行管线下游（P05），我以流式形态持有大响应体：读到底、显式 drop、
未读完即弃三类路径各自触发契约中约定的回调事件。

**验收场景**：

1. Given 流式 body 完整消费，Then 收到「可归池」语义事件。
2. Given 未读完即丢弃，Then 收到「需 skip/毒化」语义事件（本包以桩连接器断言
   事件序列；真实归池行为在 P04/P05 验收）。

### US-5 上传进度回调（P3）

作为使用者，我包一层 `with_progress`，发送期间按块收到累计字节数回调。

**验收场景**：

1. Given 1MB Bytes 体 + 进度回调，Then 回调累计单调递增且终值等于 content_length。

## 边界用例

- 空体 POST（content_length=0 的定长帧）与无体方法（GET 带 body 的语义处理——
  对齐 OkHttp：方法允许带体，HEAD/GET 不强制禁止）；
- content_length 与实际字节数不一致（发送侧：以先到者截断/报错，语义对齐 @http
  SendingFixed 行为，clarify C3）；Stream 中途抛错（回调收到失败事件）；
- 响应体为空（0 字节）、超长 charset 参数、headers Map 重建时含逗号合并值
  （折叠对称性回读）。

## 需求种子

- **FR-001** Request/RequestBody/Response/ResponseBody MUST 为不可变值对象语义。
- **FR-002** `Bytes` 形态 MUST 携带确切 content_length 且可无限次重放。
- **FR-003** 转换层 MUST 为纯函数：同 Request 产出逐字节相同的折叠头结果（D4 的
  L3 缓存基础）。
- **FR-004** 未知长度体 MUST 走 chunked；已知长度 MUST 走定长帧（L2）。
- **FR-005** ResponseBody 流式形态 MUST 定义完整消费/显式 drop/未读完即弃三类
  析构事件契约。
- **FR-006** `text()` MUST 默认 UTF-8，声明的 charset 在受支持集内生效。

## 关键设计要点

- 定长帧机制证据：`send.mbt:292-350` 状态机；便捷 `get/post` 路径恒 chunked 故弃用
  （宪法「技术约束」）。
- 转换层缓存：折叠结果（Map 实例）按 call 缓存一次、重放复用（L3 收敛口径，
  roadmap README D4）；@http 内部逐段 blit 不可避免。
- Response.headers 顺序不保真（上游 Map 无序），验收不得断言线上序。
- 每请求发送路径分配目标：连接已建时 ≈ 2 个对象（头块引用 + body 引用，01 §6）。

## 侵入性与宪法合规

- 非侵入：全部经 `Client::request/write/end_request` 公开 API 语义建模。
- 宪法 VI：接口面最小化（json/char_stream/File 裁剪见 D5/D6）。
- 宪法 II：L2 属性能杠杆，收益量化（线上字节/解析分支节省）在 P10 基准的
  「POST 定长 vs chunked」场景中体现。

## target 矩阵

| target | 支持 | 说明 |
| --- | :-: | --- |
| native / wasm | ✅ | 同一路径（@http native/wasm 同源） |
| js | ⚠️ | fetch 语义：定长/chunked 由浏览器管理，线上字节断言不可用（US-2 在 js 仅 API 层验收）；`Response.cookies` 恒空 |
| wasm-gc | ❌ | 上游 runtime 缺口（README D9） |

## 性能影响

- L2：消除 chunked 每块 ≥5 字节编码/解析与服务端分支；小请求体节省数百字节/请求。
- L3 基础：转换层纯函数化使「每 call 一次折叠、重放零折叠」成为可能（01 §6）。

## 测试方案

- US-2 用 P03 裸 TCP 对端做线上字节断言（round3 `verify_framing` 思路自建）。
- 重放性/回调契约/进度累计用本地夹具 + 桩连接器。
- native + wasm 双绿；js `moon check`。

## 澄清问题种子

- **C1** `Stream((&Writer) -> Unit)` 的 Writer 具体接口（@http 的哪个公开写入口）。
- **C2** `tag` 的类型：原文 `Unit?` 占位——是否 M1 即引入泛型/任意值 tag，
  还是保持占位（取消按 tag 批量定位在 M1 无调用方）。
- **C3** content_length 与实际字节不符时发送侧语义（截断 or 错误）。
- **C4** `text()` 受支持 charset 集（UTF-8 必须；gbk 等是否 M1 引入解码依赖）。
- **C5** GET/HEAD 带 body 的允许策略（对齐 OkHttp 程度）。

## 验收判据（包级 DoD）

1. US-1–US-5 验收场景测试全绿（native/wasm 双 target）。
2. 线上字节断言（US-2 场景 1/2）在 P03 夹具上稳定通过。
3. `moon info && moon fmt` 干净；`.mbti` 冻结 Request/Body/Response 公开面。
4. 与 OkHttp 语义差异（响应头顺序、File/json 裁剪）在 spec 显式记录。

## 参考

- `01-calls/README.md` §3.3（Body 三形态与定长帧规则）、§3.6（ResponseBody）、
  §6（性能）、§8（测试）；`14-performance/README.md` §2 L2、§3.3（请求头序列化现状）。
- 下游引用方：P05（管线消费转换层与回调契约）、P06（prior 链）、P07（重放判定）。
