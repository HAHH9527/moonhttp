# Feature Specification: 请求/响应/体值模型与定长帧（M1-P02）

**Feature Branch**: `m1-p02-request-response`（建议名；本项目未启用分支 hook，实际分支由人工决定）

**Created**: 2026-10-15

**Status**: Draft

**Input**: User description: "docs/roadmap/M1/P02-request-response-bodies.md"（M1 工作包 P02 的 speckit 输入种子全文）

## User Scenarios & Testing *(mandatory)*

### User Story 1 - 构造请求（Priority: P1）

作为 moonhttp 库使用者，我用 Builder 组装 Request——URL（P01 HttpUrl）、
方法（P01 Method，默认 GET）、有序头（P01 HeadersV）、可选体（RequestBody）
与 tag——得到不可变的请求值对象，可安全地在重试/重定向路径中复用。

**Why this priority**: Request 是执行管线（P05）与重试/重定向（P06/P07）
的统一输入底座；没有它后续包无法开工。

**Independent Test**: 纯值对象构造与字段断言，无网络无 IO。

**Acceptance Scenarios**:

1. **Given** Builder 链式设置 url/method/headers/tag/body，**When** build，
   **Then** 字段逐项正确，headers 保序且允许重复名（沿 P01 HeadersV
   语义）。
2. **Given** 未设置方法与体，**When** build，**Then** 方法默认 GET、
   body 为 None。

---

### User Story 2 - 定长帧发送（Priority: P1，性能核心 L2）

作为使用者，我提交已知长度的 Bytes 体 POST；线上字节使用 `Content-Length`
定长帧而非 chunked——消除 chunked 每块 ≥5 字节的编码/解析开销（round3
已验证的机制；moonhttp 相对 @http 便捷 get/post 恒 chunked 路径的核心
性能价值之一，便捷路径弃用见宪法「技术约束」）。

**Why this priority**: 宪法 II 性能优先的 L2 杠杆本体；与 US-1 同为管线
（P05）消费的主路径。

**Independent Test**: P03 裸 TCP 对端捕获原始请求字节，直接以转换层输出
驱动 `@http.Client`（不经 P05），断言线上形态（js 上定长/chunked 由浏览器
fetch 管理，本故事在 js 仅 API 层验收）。

**Acceptance Scenarios**:

1. **Given** `RequestBody::bytes(data, content_length=Some(n), …)`，
   **When** 经转换层发送，**Then** 捕获字节含 `Content-Length: n` 且无
   `Transfer-Encoding` 头。
2. **Given** Stream 形态（content_length=None），**When** 发送，**Then**
   线上为 chunked（含 `Transfer-Encoding: chunked` 与块编码）。
3. **Given** 多次重放同一 Bytes 体，**Then** 内容逐字节一致（重放性——
   重试/重定向的硬前提）。

---

### User Story 3 - 读取响应体（Priority: P1）

作为使用者，我对终态 Response 的 body 调 `bytes()`/`text()` 得到缓冲
数据；charset 缺省按 UTF-8 解码，声明在受支持集内的 charset 按其解码。

**Why this priority**: 最常见的读取路径；缓冲态语义是重定向/缓存
（P06/M4）复用响应的前提。

**Independent Test**: 本地可控服务端（或桩响应）返回已知负载，断言读取
与解码结果，无外部网络依赖。

**Acceptance Scenarios**:

1. **Given** 小响应（缓冲态），**When** `bytes()`/`text()`，**Then**
   `bytes()` 返回完整负载、`text()` 按 UTF-8 正确解码。
2. **Given** `Content-Type` 带 `charset=gbk`（clarify 裁决后的受支持集
   内），**When** `text()`，**Then** 按其解码。

---

### User Story 4 - 流式响应体与析构回调（Priority: P2）

作为执行管线下游（P04/P05），我以流式形态持有大响应体：读到底、显式
drop、未读完即弃三类路径各自触发契约约定的回调事件，供连接归池与毒化
决策。本包只定义回调契约与默认行为，真实归池/毒化行为在 P04/P05 验收。

**Why this priority**: 服务连接池归还决策与毒化；依赖 P1 三个故事的
Response/ResponseBody 就位，但契约必须在本包先行定义（它是 P04/P05 的
接入面）。

**Independent Test**: 以桩连接器驱动三类路径，断言回调事件序列。

**Acceptance Scenarios**:

1. **Given** 流式 body 完整消费，**Then** 收到「可归池」语义事件。
2. **Given** 未读完即丢弃，**Then** 收到「需 skip/毒化」语义事件（本包
   以桩连接器断言事件序列；真实归池行为在 P04/P05 验收）。
3. **Given** 使用者显式释放（drop）流式 body，**Then** 触发契约中的
   「显式 drop」事件，与另两类事件可判别区分。

---

### User Story 5 - 上传进度回调（Priority: P3）

作为使用者，我用 `with_progress` 包装请求体，发送期间按块收到累计字节
数回调。

**Why this priority**: 使用体验增强，无管线依赖方；实现简单，随本包
交付。

**Independent Test**: 本地夹具发送已知长度体，断言回调序列。

**Acceptance Scenarios**:

1. **Given** 1MB Bytes 体 + 进度回调，**When** 发送，**Then** 回调累计值
   单调递增且终值等于 content_length。

### Edge Cases

- 空体 POST：content_length=0 走定长帧（`Content-Length: 0`），不落
  chunked。
- GET/HEAD 带 body：对齐 OkHttp——方法允许带体，不强制禁止；确切允许
  策略随 clarify C5 裁决（见 A5）。
- content_length 与实际字节数不一致：发送侧以先到者截断/报错，语义对齐
  @http SendingFixed 行为；确切口径（截断 or 报错）随 clarify C3 裁决
  （见 A3）。
- Stream 源中途抛错：发送中断，回调收到失败事件（失败事件的具体形态随
  clarify C1/C3 一并确认）。
- 响应体为空（0 字节）：`bytes()` 返回空数据，不报错。
- 超长/未识别 charset 参数：行为随 clarify C4 的受支持集口径显式定义
  （降级 UTF-8 or 可判别报错，二选一，不得静默错解）。
- Response.headers 由 @http 响应 Map 重建时含逗号合并值：须与 P01 折叠
  转换进出互逆（P01 SC-003 的对称性回读口径）；顺序为遍历序，不保证
  线上序。

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Request / RequestBody / Response / ResponseBody MUST 为
  不可变值对象语义（构造后字段不可变，值可安全跨重试/重定向复用）。
- **FR-002**: Request MUST 经配套 Builder 构造（url / method / headers /
  tag / body 五要素）；method 未设置时 MUST 默认 GET，body 默认 None；
  tag 在 M1 保持占位形态（假设 A2，clarify C2 裁决是否升级）。
- **FR-003**: RequestBody MUST 支持 Bytes / Stream 两形态：`Bytes(Bytes)`
  （O(1) 克隆语义、可无限次重放）与 `Stream((&Writer) -> Unit)`（一次性
  回调消费、不可重放）；RequestBody 另携带 `content_type` 与
  `content_length : Int64?`（None 表示未知长度）；**Bytes 形态 MUST
  携带确切的 content_length**（定长帧规则），Stream 形态可为 None。
- **FR-004**: 帧规则：未知长度体（content_length=None）MUST 走 chunked
  线上形态；已知长度体 MUST 走定长帧（`Content-Length` 头，经
  `extra_headers~{Content-Length}` 触发 @http `SendingFixed`）。
- **FR-005**: 转换层 MUST 为纯函数：`Request → (meth, path,
  folded_headers)`，同一 Request 重复转换 MUST 产出逐字节相同的折叠头
  结果（D4 的 L3「每 call 一次折叠、重放零折叠」缓存基础）；已知长度体
  的定长 `Content-Length` 头 MUST 在此注入。转换层是「Request → @http
  调用参数」的唯一产出面，供 P05 管线调用，也是本包独立验收的驱动面。
- **FR-006**: ResponseBody 流式形态 MUST 定义完整消费 / 显式 drop /
  未读完即弃三类析构事件契约，并提供默认行为；归池与毒化的真实接入归
  P04/P05。
- **FR-007**: `text()` MUST 默认按 UTF-8 解码；`Content-Type` 声明的
  charset 在受支持集内时 MUST 按其解码（受支持集口径见 A4，clarify C4
  裁决）。
- **FR-008**: Response MUST 携带 code / reason / headers / cookies /
  body / prior 六要素：headers 由 @http 响应 Map 重建为 HeadersV（顺序
  为遍历序，**不保证线上序**——与 OkHttp 的显式差异，验收 MUST NOT
  断言线上序）；cookies 为 @http 透传（M1 不建 CookieJar；js 上恒空）；
  prior 字段就位、由 P06 填充，本包不产生响应链。
- **FR-009**: `RequestBody::with_progress(body, on_bytes)` MUST 提供上传
  进度：Stream 形态包计数 Writer、Bytes 形态分块写，回调累计字节数
  MUST 单调递增且终值等于 content_length。
- **FR-010**: 本包 MUST NOT 含任何连接、执行、取消逻辑（归 P04/P05）；
  moonhttp MUST NOT 重复处理响应压缩——@http 已自动发送
  `Accept-Encoding: gzip,identity` 并透明解压（剥 Content-Encoding /
  Content-Length），响应体长度语义为「解压后长度」。
- **FR-011**: 接口面纪律（宪法 VI）：`BodySource::File`、`json()` /
  `char_stream`（D5/D6）、自动头补齐、Cookie 注入、缓存条件 GET 改写
  均 MUST NOT 在本包引入（非目标见 A7）。

### Key Entities

- **Request**: 不可变请求值对象；url（P01 HttpUrl）、method（P01
  Method，默认 GET）、headers（P01 HeadersV，保序可重复）、body
  （RequestBody?）、tag（占位）；经 RequestBuilder 构造，值可跨重试/
  重定向复用（FR-001）。
- **RequestBuilder**: Request 的可变配套构造器（链式设置五要素）。
- **RequestBody**: 请求体值；content_type、content_length（Int64?，
  None = 未知长度）、BodySource 两形态；`with_progress` 包装产出带
  进度的等价体。
- **BodySource**: 体源两变体——`Bytes`（内存字节，可重放）与 `Stream`
  （一次性写回调，不可重放）。
- **Response**: 不可变响应值；code、reason、headers（HeadersV，遍历序
  重建）、cookies（透传）、body（ResponseBody?）、prior（Response?，
  P06 填充）。
- **ResponseBody**: 响应体两态——buffered（缓冲，`bytes()`/`text()`
  直接可用）与 stream（流式）；流式形态挂三类析构回调契约（FR-006）。

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: US-1 至 US-5 的全部验收场景均有测试且 `moon test --target
  native` 与 `--target wasm` 双绿（验证面口径同 P01 SC-004：js 仅
  `moon check`、wasm-gc 暂不验证，宪法 v1.2.0 质量门）。
- **SC-002**: US-2 的线上字节断言在 P03 裸 TCP 对端夹具上稳定通过：
  Bytes 体请求含 `Content-Length: n` 且无 `Transfer-Encoding` 头；
  Stream 体请求为 chunked（js 不适用——fetch 语义由浏览器管理，仅
  API 层验收，见 A8）。
- **SC-003**: 转换层纯函数性与重放性回归零缺口（属性测试）：同一
  Request 多次转换输出逐字节相同；Bytes 体重放 N 次内容逐字节一致。
- **SC-004**: `moon info && moon fmt` 干净，`.mbti` 冻结 Request /
  RequestBody / Response / ResponseBody 公开面并经人工审视（宪法 VI）。
- **SC-005**: 与 OkHttp 的语义差异在 spec 与实现文档显式记录（宪法
  III）：响应头顺序不保真、File/json 裁剪、cookies 仅透传、GET/HEAD
  带体策略（以 clarify 裁决为准）。
- **SC-006**: L2 定长帧杠杆不回归：本包交付后请求体不再恒 chunked
  （线上形态以 SC-002 断言）；量化收益（线上字节/解析分支节省）在
  P10 基准的「POST 定长 vs chunked」场景可复现度量，本包不引入对既有
  已实测杠杆（连接池化、头块缓存、DNS 缓存）的回归（宪法 II）。

## Assumptions

- **A1（C1 默认，待 clarify 确认）**: Stream 形态的 Writer 采用 @http
  的公开写入口（发送路径实际使用的公开 API），具体接口在 plan 阶段对照
  registry 0.22.x 钉死；不经任何内部/私有通道（宪法 I 非侵入）。
- **A2（C2 默认，待 clarify 确认）**: tag 在 M1 保持占位形态（原文
  `Unit?`），字段就位、不做按 tag 定位/批量取消——M1 无调用方；泛型/
  任意值 tag 待需求出现再评估（宪法 VI YAGNI）。
- **A3（C3 默认，待 clarify 确认）**: content_length 与实际字节数不一致
  时，发送侧语义对齐 @http SendingFixed 现行为（以先到者截断/报错）；
  截断 or 报错的确切口径由 clarify 裁决后回写。
- **A4（C4 默认，待 clarify 确认）**: `text()` 受支持 charset 集合 M1
  以 UTF-8 为必须；gbk 等是否引入解码依赖由 clarify 裁决；未识别
  charset 的行为（降级 UTF-8 or 可判别报错）随裁决显式定义，不得静默
  错解。
- **A5（C5 默认，待 clarify 确认）**: GET/HEAD 带 body 对齐 OkHttp——
  方法允许带体、不强制禁止；确切允许策略由 clarify 裁决。
- **A6（行为基准与显式差异，宪法 III）**: 行为基准为 OkHttp 5.5.0；已知
  显式差异：① Response.headers 顺序不保真（上游 Map 无序，验收不得
  断言线上序）；② BodySource::File、json()/char_stream 裁剪（D5/D6，
  M2 回补）；③ cookies 仅透传、不建 Jar（M2/11）；④ Host/UA/
  Accept-Encoding 自动头不做（@http 连接层已写，Bridge 级自动头随
  M2/04）。
- **A7（非目标）**: 任何连接/执行/取消逻辑（P04/P05）、Cookie 注入
  （M2/11）、缓存条件 GET 改写（M4/05）、自动头补齐（M2/04）、
  File/json/char_stream（M2），均不在本包范围。
- **A8（target 矩阵，宪法 V）**: native/wasm 同路径全量验收；js 走
  fetch——定长/chunked 由浏览器管理，线上字节断言不可用（US-2 在 js
  仅 API 层验收），`Response.cookies` 恒空，记「未验证」；wasm-gc 被
  上游 runtime 缺口阻塞（README D9），暂不验证。网络行为测试基于可控
  本地服务端与桩连接器，不依赖外部网络（宪法 IV）。
- **A9（前置与测试纪律）**: 前置依赖 P01（HttpUrl/HeadersV/Method 及其
  折叠/重建对称性）与 P03（裸 TCP 对端夹具）；测试与快照中的敏感头
  样例值必须为明显合成的占位串（沿 P01 A8 纪律），禁止真实凭证入库。
