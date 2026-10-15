# Feature Specification: 请求/响应/体值模型与定长帧（M1-P02）

**Feature Branch**: `002-m1-p02-request-response`（实际已建立并在使用；specify 阶段的「建议名」口径已按实际分支回写）

**Created**: 2026-10-15

**Status**: Draft

**Input**: User description: "docs/roadmap/M1/P02-request-response-bodies.md"（M1 工作包 P02 的 speckit 输入种子全文）

## Clarifications

### Session 2026-10-15

- Q: `RequestBody` 的 `Stream((&Writer) -> Unit)` 形态中，回调收到的 Writer
  应当是哪种写入口类型？ → A: 复用底座公开抽象——`Stream((&@io.Writer) ->
  Unit)`，Writer 即 `@http.Client` 公开实现的 `@io.Writer`（`write` /
  `write_once` / `write_reader`，async 0.22.4 `pkg.generated.mbti:86`）；
  core 包不自立 Writer trait、也不暴露 `@http.Client` 具体类型（裁决 A；
  宪法 I 非侵入、VI 零新抽象）
- Q: 当请求体声明的 `content_length` 与实际写入的字节数不一致时，发送侧
  应当如何处理？ → A: 行为语义选 A——发送侧不截断，超写/欠写均报错（对齐
  @http `SendingFixed` 实证：多写 `send.mbt:124`、欠写 `end_body
  :253-254` 均 `raise IncorrectBodyLength`）；`Bytes` 形态构造期 O(1)
  校验 `content_length == data.len()`。错误模型：引入 moonhttp 自持错误
  类型统一包装上游错误（含 `IncorrectBodyLength` 语义变体，风格对齐
  P01：suberror、仅 `derive(Debug)`、错误消息只携带定位信息不回显原始
  输入）——构造期校验不通过 raise 该自持错误，发送期
  `@http.IncorrectBodyLength` 映射为同一变体且类别可判别。范围边界：
  P02 只交付错误类型 + 构造期 raise + 映射契约，发送期实际 catch/映射
  归 P05（FR-010 不含执行逻辑）；错误类型命名与 P01 冻结 `.mbti` 的
  一致性核对留待 plan 阶段
- Q: `RequestBuilder` 对「GET/HEAD 等方法携带请求体」应采取什么策略？ →
  A: 选 A 的双向构造期校验，矩阵按核实过的 OkHttp 5.x 源码修正——带体
  拒绝仅限 GET/HEAD（`permitsRequestBody = !(GET||HEAD)`）；缺体拒绝为
  POST/PUT/PATCH（`requiresRequestBody`）；DELETE/OPTIONS/TRACE/CONNECT
  体可选（不强制也不禁止）。校验在构造期、风格同 P01 HeadersVBuilder，
  错误并入 FR-012 自持类型（命名随 plan）。种子「GET/HEAD 不强制禁止」
  为事实错误，更正为对齐真实 OkHttp（宪法 III），双向矩阵在 A6 差异表
  显式记录；逐方法以 OkHttp 5.x `HttpMethod.kt` 为准，plan 阶段核对
  5.5.0 tag 一致性
- Q: `ResponseBody::text()` 在 M1 应当支持哪些 charset，声明了不受支持的
  charset 时如何表现？ → A: 选 A——M1 受支持集仅 {UTF-8}：缺省或声明
  UTF-8 按 UTF-8 解码；声明集外 charset（gbk 等）可判别报错（不静默
  降级、不乱码），报错并入 FR-012 自持错误类型语义变体；不引入任何
  非 UTF-8 解码依赖（宪法 VI YAGNI），集外支持需求驱动回补并挂欠账
  （F14）。对齐 OkHttp：其 `string()` 以 Content-Type charset 解码、
  缺省 UTF-8，`Charset.forName` 对未知字符集抛异常、从不猜
  （裁决 2026-10-15）
- Q: `Request` 上的 `tag` 字段在 M1 应当采用哪种类型形态？ → A: 选 A——
  M1 保持占位形态 `Unit?`：字段就位、语义零承诺，不做按 tag 定位/批量
  取消（该用途依赖 Dispatcher（P09）与 Call.cancel（P05），M1 无调用
  方）；不泛型化（避免类型参数传染 Request→P05 管线→重试/重定向整个
  公开面），也不引入 Any/trait 动态值。需求出现时再评估升级，届时破坏
  性变更走 spec 变更流程（0.x 实验期允许）并挂欠账跟踪（F15）
  （裁决 2026-10-15）

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
3. **Given** Builder 为 GET 设置 body（或 POST 缺 body），**When**
   build，**Then** raise 可判别的自持错误（方法/体矩阵，FR-002；
   2026-10-15 裁决 C5 新增）。

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
2. **Given** `Content-Type` 声明 `charset=UTF-8`，**When** `text()`，
   **Then** 按 UTF-8 解码；**Given** 声明集外 charset（如
   `charset=gbk`），**When** `text()`，**Then** raise 可判别错误
   （FR-007/FR-012，不静默降级；2026-10-15 裁决 C4 改写）。

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
- 方法/体矩阵（构造期校验，FR-002）：GET/HEAD 带 body 一律拒绝（OkHttp
  5.x 实证——种子「不强制禁止」说法已更正）；POST/PUT/PATCH 缺 body
  拒绝；DELETE/OPTIONS/TRACE/CONNECT 体可选。
- content_length 与实际字节数不一致：不截断——超写/欠写均报错（对齐
  @http `SendingFixed` 的 `IncorrectBodyLength` 语义）；`Bytes` 形态
  构造期 O(1) 校验即 raise 自持错误（FR-012），发送期映射为同一变体
  （实际 catch/映射执行归 P05）。
- Stream 源中途抛错：错误按 FR-012 自持错误类型可判别传播；进度回调的
  「失败事件」精确契约在 plan 阶段对照 `with_progress` 设计定（C3 已裁
  决错误模型，2026-10-15）。
- 响应体为空（0 字节）：`bytes()` 返回空数据，不报错。
- 超长/未识别/集外 charset 参数：一律可判别报错（FR-007，M1 受支持集
  仅 UTF-8），不静默降级、不乱码（2026-10-15 裁决 C4）。
- Response.headers 由 @http 响应 Map 重建时含逗号合并值：须与 P01 折叠
  转换进出互逆（P01 SC-003 的对称性回读口径）；顺序为遍历序，不保证
  线上序。

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Request / RequestBody / Response / ResponseBody MUST 为
  不可变值对象语义（构造后字段不可变，值可安全跨重试/重定向复用）。
- **FR-002**: Request MUST 经配套 Builder 构造（url / method / headers /
  tag / body 五要素）；method 未设置时 MUST 默认 GET，body 默认 None；
  tag 在 M1 保持占位形态 `Unit?`——字段就位、语义零承诺，MUST NOT
  提供按 tag 定位/批量取消（澄清 2026-10-15，裁决 C2；升级评估挂欠账
  F15）。Builder
  MUST 在构造期校验方法/体矩阵（澄清 2026-10-15，裁决 C5）：GET/HEAD
  带体拒绝、POST/PUT/PATCH 缺体拒绝、DELETE/OPTIONS/TRACE/CONNECT 体
  可选；违例 raise FR-012 自持错误类型（变体命名随 plan 定）。
- **FR-003**: RequestBody MUST 支持 Bytes / Stream 两形态：`Bytes(Bytes)`
  （O(1) 克隆语义、可无限次重放）与 `Stream((&@io.Writer) -> Unit)`（一次性
  回调消费、不可重放；Writer 为 `@http.Client` 公开实现的底座 `@io.Writer`，
  澄清 2026-10-15 裁决 A）；RequestBody 另携带 `content_type` 与
  `content_length : Int64?`（None 表示未知长度）；**Bytes 形态 MUST
  携带确切的 content_length**（定长帧规则）：构造期即 O(1) 校验
  `content_length == data.len()`，不符 raise 自持错误类型（FR-012，
  澄清 2026-10-15 裁决）；Stream 形态可为 None。
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
- **FR-007**: `text()` MUST 默认按 UTF-8 解码；受支持 charset 集 M1 仅
  {UTF-8}——缺省或声明 `charset=UTF-8` 按 UTF-8 解码；声明集外 charset
  （gbk 等）MUST 可判别报错（并入 FR-012 自持错误类型语义变体），
  MUST NOT 静默降级或错解（澄清 2026-10-15，裁决 C4；对齐 OkHttp
  `string()` 语义——以 Content-Type charset 解码、缺省 UTF-8、未知
  charset 抛错从不猜）。
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
- **FR-012**: 本包 MUST 引入 moonhttp 自持的请求/体错误类型（变体含：
  `IncorrectBodyLength` 语义——声明长度与实际字节超写/欠写不符；
  方法/体矩阵违例——GET/HEAD 带体或 POST/PUT/PATCH 缺体，FR-002；
  charset 违例——`text()` 声明集外 charset，FR-007），统一包装上游错误，
  风格对齐 P01：suberror 形态、仅 `derive(Debug)`
  可调试输出（不参与判等/哈希）、错误消息只携带定位片段、不回显原始
  输入。`Bytes` 构造期校验不通过 raise 该自持错误（FR-003）；发送期
  `@http.IncorrectBodyLength` MUST 映射为同一语义变体、保持类别可判别
  （映射契约）。发送期实际 catch/映射的执行逻辑归 P05——本包只交付
  错误类型 + 构造期 raise + 映射契约（FR-010 不含执行逻辑，澄清
  2026-10-15 裁决）。错误类型命名与 P01 冻结 `.mbti` 的一致性核对
  留待 plan 阶段。

### Key Entities

- **Request**: 不可变请求值对象；url（P01 HttpUrl）、method（P01
  Method，默认 GET）、headers（P01 HeadersV，保序可重复）、body
  （RequestBody?）、tag（`Unit?` 占位，C2 裁决）；经 RequestBuilder 构造，值可跨重试/
  重定向复用（FR-001）。
- **RequestBuilder**: Request 的可变配套构造器（链式设置五要素）。
- **RequestBody**: 请求体值；content_type、content_length（Int64?，
  None = 未知长度）、BodySource 两形态；`with_progress` 包装产出带
  进度的等价体。
- **BodySource**: 体源两变体——`Bytes`（内存字节，可重放）与 `Stream`
  （一次性写回调，参数为 `@http.Client` 公开实现的 `@io.Writer`，不可
  重放）。
- **Response**: 不可变响应值；code、reason、headers（HeadersV，遍历序
  重建）、cookies（透传）、body（ResponseBody?）、prior（Response?，
  P06 填充）。
- **ResponseBody**: 响应体两态——buffered（缓冲，`bytes()`/`text()`
  直接可用）与 stream（流式）；流式形态挂三类析构回调契约（FR-006）。
- **请求/体错误类型**（命名待 plan 与 P01 `.mbti` 风格核对后定）：
  moonhttp 自持可判别错误，变体含 `IncorrectBodyLength` 语义（长度
  超写/欠写不符）、方法/体矩阵违例（FR-002）与 charset 违例（FR-007）；
  构造期 raise 与发送期
  映射共用目标类型（FR-012）；仅要求可调试输出（`derive(Debug)`），
  不参与判等/哈希。

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
  III）：响应头顺序不保真、File/json 裁剪、cookies 仅透传、方法/体
  双向矩阵（2026-10-15 已裁决：对齐 OkHttp 5.x，种子说法已更正——
  见 A5/A6）。
- **SC-006**: L2 定长帧杠杆不回归：本包交付后请求体不再恒 chunked
  （线上形态以 SC-002 断言）；量化收益（线上字节/解析分支节省）在
  P10 基准的「POST 定长 vs chunked」场景可复现度量，本包不引入对既有
  已实测杠杆（连接池化、头块缓存、DNS 缓存）的回归（宪法 II）。

## Assumptions

- **A1（C1 已裁决，2026-10-15）**: Stream 形态的 Writer 确认为底座公开
  抽象 `@io.Writer`（`@http.Client` 公开 `impl`，async 0.22.4
  `pkg.generated.mbti:86`）；core 包的依赖面相应引入 `@io` 包，不经任何
  内部/私有通道（宪法 I 非侵入）。原「plan 阶段对照 registry 再钉死」
  的默认被本裁决取代。
- **A2（C2 已裁决，2026-10-15）**: tag 在 M1 保持占位形态 `Unit?`——
  字段就位、语义零承诺，不做按 tag 定位/批量取消（该用途依赖
  Dispatcher（P09）与 Call.cancel（P05），M1 无调用方）；不泛型化、
  不引入 Any/trait 动态值（宪法 VI YAGNI）。需求出现时再评估升级，
  届时破坏性变更走 spec 变更流程（0.x 实验期允许），欠账 F15。
- **A3（C3 已裁决，2026-10-15）**: 发送侧不截断，超写/欠写均报错——上游
  `SendingFixed` 实证（`send.mbt:124` 多写、`:253-254` 欠写均 `raise
  IncorrectBodyLength`），原「截断/报错误待裁决」默认被取代。错误经
  moonhttp 自持错误类型统一包装（FR-012）；错误类型命名与 P01 冻结
  `.mbti` 的一致性核对留待 plan 阶段。
- **A4（C4 已裁决，2026-10-15）**: `text()` 受支持 charset 集 M1 仅
  {UTF-8}；声明集外可判别报错、不静默降级（对齐 OkHttp
  `Charset.forName` 抛错从不猜的语义）；不引入任何非 UTF-8 解码依赖
  （宪法 VI YAGNI），集外（latin1/gbk 等）需求驱动回补并挂欠账（F14）；
  报错并入 FR-012 语义变体。原「受支持集待裁决」默认被取代。
- **A5（C5 已裁决，2026-10-15）**: RequestBuilder 构造期双向校验方法/体
  矩阵——带体拒绝仅 GET/HEAD（`permitsRequestBody = !(GET||HEAD)`），
  缺体拒绝 POST/PUT/PATCH（`requiresRequestBody`），DELETE/OPTIONS/
  TRACE/CONNECT 体可选；校验风格同 P01 HeadersVBuilder，错误并入
  FR-012 自持类型。**种子修正**：P02 种子「HEAD/GET 不强制禁止」为
  事实错误——OkHttp 5.5.0 实证拒绝 GET/HEAD 带体（宪法 III 显式记录，
  见 A6）；逐方法矩阵以 OkHttp 5.x `HttpMethod.kt` 为准，plan 阶段
  核对 5.5.0 tag 一致性。
- **A6（行为基准与显式差异，宪法 III）**: 行为基准为 OkHttp 5.5.0；已知
  显式差异：① Response.headers 顺序不保真（上游 Map 无序，验收不得
  断言线上序）；② BodySource::File、json()/char_stream 裁剪（D5/D6，
  M2 回补）；③ cookies 仅透传、不建 Jar（M2/11）；④ Host/UA/
  Accept-Encoding 自动头不做（@http 连接层已写，Bridge 级自动头随
  M2/04）；⑤ 方法/体双向矩阵（2026-10-15 裁决 C5）：对齐 OkHttp——
  GET/HEAD 拒体、POST/PUT/PATCH 必体、DELETE/OPTIONS/TRACE/CONNECT
  体可选，同时是对 P02 种子括号说法（「GET/HEAD 不强制禁止」）的
  显式更正。
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
