---
description: "M1-P02 请求/响应/体值模型与定长帧任务清单"
---

# Tasks: 请求/响应/体值模型与定长帧（M1-P02）

**Input**: Design documents from `/specs/002-m1-p02-request-response/`

**Prerequisites**: plan.md（布局/依赖边/宪法门）、spec.md（US-1–US-5 与
FR-001–FR-012、SC-001–SC-006，Clarifications 2026-10-15 已裁决 C1–C5）、
research.md（R1–R10，上游行号证据）、data-model.md（错误/事件清单唯一
规范源）、contracts/（三份契约含验收锚点表）、quickstart.md（5 步验证）。
**外部依赖**：T009 线上字节断言前置 **P03 裸 TCP 对端夹具**（当前仓库
未有 P03 产物，任务内标注处理方式）；P01 已落地（`src/core` 既有
HttpUrl/HeadersV/Method 冻结面直接复用）。

**Tests**: 本特性**显式要求测试任务**（宪法 IV「验收场景与测试先行」
不可妥协：先写失败测试，再实现，红-绿-重构）。测试锚点直接引用
[contracts/request.md](contracts/request.md)、
[contracts/response.md](contracts/response.md)、
[contracts/conversion-errors.md](contracts/conversion-errors.md) 的
「验收锚点」表与 spec Edge Cases。

**Organization**: 按用户故事分组（US1 🎯 MVP → US2 → US3 → US4 → US5）。
US1/US2/US3 依优先序交付但相互独立可测；US4 依赖 US3（同一文件
response_body.mbt 的流式态增量）；US5 依赖 US2（组合不变式断言复用
转换层）。

**决策口径**（spec.md `## Clarifications` Session 2026-10-15，全部已裁决）：
C1=A（Writer = 底座 `@io.Writer`，不自立 trait）、C2=A（tag 占位 `Unit?`，
欠账 F15）、C3=自定义（不截断双向报错 + Bytes 构造期 O(1) 校验 + 自持错误
类型，发送期映射归 P05）、C4=A（charset 解码集仅 UTF-8；集外语义已由
2026-10-16 owner 裁决 B 覆写为「按 UTF-8 降级解码 + stderr 告警」，
不再 raise、错误类型删 charset 变体；F14 仍挂）、C5=A 修正矩阵（拒体仅
GET/HEAD、必体 POST/PUT/PATCH、DELETE/OPTIONS/TRACE/CONNECT 体可选）。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 可并行（不同文件、无未完成依赖）
- **[Story]**: 归属用户故事（US1–US5）
- 所有路径相对仓库根

## Path Conventions

单包增量：`src/core/`（P01 既有文件不动，本包只新增）。MoonBit 惯例：
黑盒测试 `*_test.mbt`、白盒测试 `*_wbtest.mbt`、每包 `moon.pkg`、生成
接口 `.mbti`。

**类型面口径（贯穿全部实现任务）**：

- **判等/哈希**：P02 值类型（Request/RequestBody/Response/ResponseBody）
  **一律不 derive Eq/Hash**（research R10：函数/trait-object 字段判等无
  语义；池键由 P01 HttpUrl+HeadersV 承担）——这是与 P01 FR-006 的有意
  差异，`.mbti` 冻结审视时按此核对。
- **Debug 三分法**（research R10）：`Request`/`Response`/
  `HttpMessageError`/`ResponseBodyEvent` **derive(Debug)**；`BodySource`/
  `RequestBody`/`ResponseBody` **手写 `impl @debug.Debug`**（Bytes 印
  元信息、Stream 印 `<stream fn>`、ResponseBody 印状态——**一律不印体
  字节**，属输出实用性：避免调试打印转储大块字节，非脱敏/掩码措施
  ——owner 2026-10-15 裁定，掩码与可配置开关归 M3 F13/F12）。
- **[0079] 配套（N1-A）**：凡 `derive(Debug)` 类型紧随
  `pub extend T with Debug::{to_repr}`（P01 实证：0.1.20261012 下一经
  使用含同包测试 `debug_inspect` 即触发 [0079]）——涉及
  `HttpMessageError` 与 `ResponseBodyEvent`（R1）。
- **不使用 `derive(Show)`**（[0027] 弃用警告）；错误消息中文优先、只携带
  定位片段（方法名/长度对/charset 名），不回显头值/体字节/URL 全文；
  测试与 `.snap` 敏感头样例值用合成占位串（如 `Bearer test-token-123`）。
- **禁项**：不自立 Writer trait（C1）、不暴露 `@http.Client` 具体类型、
  不做按 tag 定位/取消（C2）、不含连接/执行/取消逻辑（FR-010）、L3 缓存
  不进 core（research R7）。

---

## Phase 1: Setup（共享基础设施）

**Purpose**: core 包依赖边扩展

- [X] T001 在 `src/core/moon.pkg` 的 import 块新增
  `moonbitlang/async/io`（`@io.Writer`/`@io.Reader` trait 与
  `MemoryReader`/`pipe` 桩原语，C1 裁决落点）与
  `moonbitlang/core/encoding/utf8`（`text()` 解码，research R6/R8），
  保留既有 `"moonbitlang/async/http"`；`moon check` 确认解析成功
  （research R8：import 键写包路径，`@` 只在代码引用处）

---

## Phase 2: Foundational（阻塞性前置）

**Purpose**: 全部故事共享的错误类型与体值模型；不依赖任何故事实现

**⚠️ CRITICAL**: US1–US5 均依赖本阶段完成

- [X] T002 [P] 在 `src/core/request_test.mbt` 写失败测试（与 T003/T004
  可并行编辑；红-绿验证以 T003/T004 合入为前提——测试引用其类型与
  构造器。I7 处置口径修正 2026-10-15，原「先于 T003/T004 实现」措辞
  更正）：① `RequestBody::bytes(data, content_length, content_type?)`
  构造期校验两态——`content_length != data.len()` raise
  `HttpMessageError::IncorrectBodyLength`、相等时构造成功；②
  `HttpMessageError` 二变体可判别断言（`assert_true(e is
  HttpMessageError::MethodBodyMismatch)` 风格，错误不判等；**封闭
  二变体——2026-10-16 owner 裁决 B 删除 `UnsupportedCharset`**）；③
  `to_repr` 输出形态断言——**只携带定位片段**（方法名/长度对），
  以含敏感样式的触发输入构造后断言输出不含整体回显；④ 顺带确认本文件
  `moon check` 无 [0079]/[0027] 警告
- [X] T003 [P] 在 `src/core/message_error.mbt` 定义
  `pub(all) suberror HttpMessageError { MethodBodyMismatch;
  IncorrectBodyLength }` **仅
  `derive(Debug)`** + 紧随 `pub extend HttpMessageError with
  Debug::{to_repr}`（N1-A，R1）；变体触发点与映射契约以
  [data-model.md §5](data-model.md) 为**唯一规范源**（本文件与 contracts
  只引用不重述）；~~`UnsupportedCharset` 载荷仅 charset 名定位片段~~
  （2026-10-16 owner 裁决 B：该变体删除——FR-007 改集外 charset 按
  UTF-8 降级解码 + stderr 告警，不再 raise）
- [X] T004 [P] 在 `src/core/request_body.mbt` 定义 `RequestBody` 结构
  （`content_type : String?`、`content_length : Int64?`、
  `source : BodySource`）与 `pub(all) enum BodySource { Bytes(Bytes);
  Stream((&@io.Writer) -> Unit) }`（C1 裁决：Writer 即底座
  `@io.Writer`）；实现 `RequestBody::bytes(data, content_length : Int64,
  content_type?)`——**构造期 O(1) 校验 `content_length == data.len()`，
  不符 raise `IncorrectBodyLength`**（C3 裁决）——与
  `RequestBody::stream(f, content_length? : Int64?, content_type?)`
  （content_length 缺省 None）；`BodySource`/`RequestBody` **手写
  `impl @debug.Debug`**（不印体字节，R10）；本任务**不含**
  `with_progress`（归 US5/T016）

**Checkpoint**: 错误类型与体值模型就绪，US1/US2/US3 可依序开工
（US1 与 US3 测试可并行编写）

---

## Phase 3: User Story 1 - 构造请求（Priority: P1）🎯 MVP

**Goal**: 用 Builder 组装不可变 Request（五要素，默认 GET/无体），
方法/体矩阵双向构造期校验（spec US-1、FR-001/002、C2/C5 裁决）

**Independent Test**: 纯值对象 `moon test --target native` 断言字段与
校验；无网络

### Tests for User Story 1（先写、先失败）

- [X] T005 [P] [US1] 在 `src/core/request_test.mbt` 增写失败测试（锚点：
  [contracts/request.md](contracts/request.md) 验收锚点表）：① spec US-1
  场景 1–3（链式设置五要素逐项正确、headers 保序可重复；未设 method/body
  → `Get` + `None`；GET/HEAD 带 body 与 POST/PUT/PATCH 缺 body →
  raise `MethodBodyMismatch`）；② 矩阵可选组（DELETE/OPTIONS/TRACE/
  CONNECT ± body 构造成功）；③ `header(...)` 非法名/值 raise
  `HeadersError`（P01 HeadersV 校验错误，委托继承——非本包 FR-012；
  I12 处置消歧 2026-10-15）且 Builder 状态不变；④ `tag`
  存取往返（`Unit?` 占位，无任何定位语义）；⑤ 校验失败后修正再次
  `build()` 成功（可重入）

### Implementation for User Story 1

- [X] T006 [US1] 在 `src/core/request.mbt` 实现 `pub struct Request`
  （url/method/headers/tag/body 五字段，`derive(Debug)`，**无 Eq/Hash**，
  R10）与 `pub struct RequestBuilder`：`new(url)`、`method`、`headers`
  （整体替换，收已固化 HeadersV）、`header`（委托 `HeadersVBuilder`
  校验，raise `HeadersError`）、`tag`、`body`、`build() -> Request
  raise HttpMessageError`——build 内执行方法/体矩阵双向校验（拒体：
  Get/Head；必体：Post/Put/Patch；可选：Delete/Options/Trace/Connect，
  C5 裁决矩阵）；校验失败 Builder 状态不变；method 缺省 `Get`、body
  缺省 `None`（依赖 T002/T003/T004/T005）

**Checkpoint**: US1 独立可用——`moon test --target native` 全绿，
不可变值语义与矩阵校验成立

---

## Phase 4: User Story 2 - 定长帧发送（Priority: P1，性能核心 L2）

**Goal**: 「Request → @http 调用参数」纯转换层：origin-form 请求目标 +
折叠头 + Content-Length/Content-Type 注入；定长帧机制就位（spec US-2、
FR-004/005、SC-003）

**Independent Test**: 转换纯函数属性测试（同 Request N 次转换逐字节
相同）零网络可验；线上字节断言前置 P03 夹具（T009）

### Tests for User Story 2（先写、先失败）

- [X] T007 [P] [US2] 在 `src/core/conversion_test.mbt` 写失败测试（锚点：
  [contracts/conversion-errors.md](contracts/conversion-errors.md) 验收
  锚点表）：① **纯函数性属性**——同一 Request 重复 `to_http_request`
  N 次输出逐字节相同（SC-003）；② path 重组：`HttpUrl` 的
  path_segments 重组为 `/a/c` 形态、有 query 时追加 `?query`、fragment
  不出现在输出；③ Bytes 体（n=len）→ headers 含 `Content-Length: n`；
  Stream 体（None）→ 无 Content-Length；④ Content-Type/Content-Length
  **覆盖**（~~注入与用户头优先、headers 已含时不覆盖、body.content_type
  静默忽略~~——**2026-10-16 裁决 A 撤销**；现行 = body 元信息 `Some(v)`
  覆盖同名 Content-Type、`Some(n)` 覆盖 Content-Length、`None` 删除该键、
  body=None 不动）；⑤ Bytes
  体重放 N 次内容逐字节一致（SC-003 重放性）；⑥ 空体 Bytes（n=0）→
  headers 含 `Content-Length: 0`（spec 边界用例「空体 POST 不落
  chunked」，U1 补锚 2026-10-15；线上形态断言随 T009/P03）
- [X] T008 [US2] 在 `src/core/conversion.mbt` 实现
  `pub fn Request::to_http_request(Self) -> @http.Request`（复用上游
  `pub(all) struct @http.Request`，零新类型）：meth 经 P01
  `Method::to_request_method` 封闭映射；path 由 `HttpUrl` 的
  path_segments 以 `/` 重组 + `?query`（无 query 不追加、fragment 剥除）；
  headers = `HeadersV::to_http_map()` 基底 + Content-Length 覆盖
  （`body.content_length is Some(n)` 时写 n、`None` 时删除该键；
  ~~大小写不敏感查重、已含不覆盖~~——**2026-10-16 裁决 A 撤销**）
  + Content-Type 覆盖（`body.content_type is Some(v)` 时大小写不敏感
  单键替换；~~折叠结果不含才注入~~；research R5）；**MUST NOT 注入
  Transfer-Encoding**（上游 forbidden_headers 自管帧头，spec FR-005/
  contracts 条款 4）；**无状态、无 memoization**（L3 缓存归 P05/P07，
  research R7）（依赖 T004/T007）
- [ ] T009 [US2] 线上字节断言接线（**⚠️ 前置 P03 裸 TCP 对端夹具**，spec
  A8/quickstart 步骤 2）：以 `to_http_request` 输出直接驱动
  `@http.Client`（不经 P05），经 P03 对端捕获原始字节断言——Bytes 体
  （Some(n)）含 `Content-Length: n` 且无 `Transfer-Encoding`；Stream 体
  （None）含 `Transfer-Encoding: chunked` 与块编码；**Bytes +
  with_progress 组合**线上仍 `Content-Length: n` 无 `Transfer-Encoding`
  （conversion-errors.md 条款 7）。**依赖补记（I4 处置，2026-10-15）**：
  组合断言（Bytes + with_progress）另前置 T016——随 P03 + US5 就位后
  执行相应断言。**若 P03 未落地：保持本任务未勾**，
  在任务备注登记依赖，不阻塞 T010+（SC-002 的达成随 P03 排期闭环）
  > **欠账登记（implement 执行口径 #2，2026-10-15）**：P03 裸 TCP 对端
  > 夹具在仓库中尚无产物（`src/` 仅 client 占位与 core 包），本任务
  > 保持未勾；SC-002 线上形态断言（Bytes 定长 / Stream chunked / 空体
  > POST 不落 chunked / Bytes+with_progress 组合不降级 chunked）随 P03
  > 排期闭环。T007/T008 已覆盖转换层可离线验收的全部锚点（注入规则、
  > 纯函数性、path 重组、空体 Content-Length: 0 元信息面）；不伪造
  > 任何线上断言。本欠账不阻塞 T010+。
  >
  > **注记①（target 口径，converge 2026-10-16，以 spec SC-002/A8 原文为准）**：
  > 线上原始字节捕获仅在 native 执行；wasm 以转换层输出断言代验（机制
  > 等价）；js 不适用（fetch 语义由浏览器管理，仅 API 层验收，A8）。故
  > P03 夹具就位后的本任务验收面 = native 线上字节 + wasm 转换层代验，
  > 不要求 wasm 捕获裸字节。
  >
  > **注记②（人类处置口径，owner 2026-10-16 授权）**：converge 命令契约
  > 无 `already_tracked` 出路——§4:143-144 不看勾选态纳入盘点、:59-60 与
  > §7:207-208 剩余工作只能以新 `T{M+1}` 追加、§7:221-222 禁止触碰既有
  > Convergence phase、§7:224-228 的 `converged` 分支要求无 actionable
  > finding——故后续每次 converge pass 必然把本条重复登记为新编号。届时
  > 处置：删除新编号 + 留墓碑（同 Phase 9 墓碑）；**T009 恒为 SC-002 唯一
  > 跟踪点**。

**Checkpoint**: US2 纯函数面独立可用（T007/T008 绿）；线上形态断言随
P03 就位闭环（SC-002），L2 杠杆机制就位

---

## Phase 5: User Story 3 - 读取响应体（Priority: P1）

**Goal**: 终态 Response 值组装（六要素、重建与 P01 折叠互逆）与
buffered 态 `bytes()`/`text()`（charset 三态、替换式解码）（spec US-3、
FR-007/008/010）

**Independent Test**: 本地桩数据 `moon test --target native` 断言重建
与解码；无网络

### Tests for User Story 3（先写、先失败）

- [X] T010 [P] [US3] 在 `src/core/response_test.mbt` 写失败测试（锚点：
  [contracts/response.md](contracts/response.md) 验收锚点表）：①
  `from_http` 重建：同名逗号合并值拆回多条（`"a,b"` → `["a","b"]`）且
  与 P01 折叠互逆（P01 SC-003 不变量②回读）、条目序 = Map 遍历序、
  **不断言线上序**；② buffered 态 `bytes()` 返回完整负载（0 字节 → 空
  不报错）；③ `text()` charset 三态：`charset=UTF-8`（任意大小写/带
  引号）按 UTF-8 解码、`charset=gbk` **按 UTF-8 降级解码（返回
  `decode_lossy` 结果、不抛错；2026-10-16 owner 裁决 B，stderr 告警为
  人工可见诊断、测试不断言告警文本）**、无 Content-Type 缺省
  UTF-8；④ 畸形 UTF-8 字节 → U+FFFD 替换不抛（`decode_lossy`）；⑤
  六要素访问器与 `prior` 字段就位（`None`，不产链）；⑥ Debug 抽查：
  ResponseBody/RequestBody 的 Debug 输出不含体字节内容（R10）

### Implementation for User Story 3

- [X] T011 [P] [US3] 在 `src/core/response_body.mbt` 实现 ResponseBody
  **buffered 态**：`ResponseBody::buffered(data : Bytes)`；`pub async fn
  bytes()`（buffered 直取）与 `pub async fn text()`（= bytes() + charset
  解码）；charset 解析按 research R5——取 Content-Type 合并值中**首个**
  `charset=` 参数（名值大小写不敏感、值可带引号）、缺省/utf-8 → UTF-8、
  ~~集外 raise `UnsupportedCharset(该值原文)`~~（**2026-10-16 owner
  裁决 B 覆写**：集外按 UTF-8 降级解码，经包内私有
  `warn_charset_fallback` 输出 stderr 告警——唯一出口、消息只带
  charset 名定位片段、每次调用都告警不去重）；解码用
  `@utf8.decode_lossy`（**不做 BOM 嗅探**，差异记录 R6）；手写
  `impl @debug.Debug`（印状态与元信息，不印体字节）（依赖 T003/T010）
- [X] T012 [P] [US3] 在 `src/core/response.mbt` 实现 `pub struct
  Response`（code/reason/headers/cookies/body/prior 六字段，
  `derive(Debug)`，无 Eq/Hash）与 `pub fn Response::from_http(code,
  reason, headers : @http.Headers, cookies : Array[@http.Cookie],
  body? : ResponseBody?, prior? : Response?)` 纯重建——逐键把逗号合并
  值以无空格 `,` 拆回多条、条目序 = Map 遍历序、**无 IO 无状态**；六
  要素访问器（依赖 T010/T011——struct 字段引用 ResponseBody 类型）

**Checkpoint**: US3 独立可用——重建互逆与 charset 三态全绿

---

## Phase 6: User Story 4 - 流式响应体与生命周期事件（Priority: P2）

**Goal**: 流式态 + 三类生命周期事件契约（Consumed/Dropped/Abandoned），
默认行为 no-op，归池/毒化接归 P04/P05（spec US-4、FR-006）

**Independent Test**: `@io.MemoryReader`/`pipe` 桩驱动三路径断言事件
序列；无网络

### Tests for User Story 4（先写、先失败）

- [X] T013 [P] [US4] 在 `src/core/response_body_lifecycle_test.mbt` 写
  失败测试（锚点：[contracts/response.md](contracts/response.md) 生命
  周期锚点表 + [data-model.md §4 状态机](../data-model.md)）：① 以
  `@io.MemoryReader`（或 `@io.pipe`）为源，流式体读到底（`bytes()` 或
  多次 `read_some` 耗尽）→ 回调恰收到一次 `Consumed`、`consumed()` 为
  true；② 未读完 `drop()` → 恰收到一次 `Dropped`、`dropped()` 为 true、
  重复 `drop()` 幂等无二次事件；③ `Consumed` 后再 `drop()` 静默无事件
  （互斥时序：Consumed/Dropped 至多其一）；④ `consumed()`/`dropped()`
  均为 false 的中间态可查（**Abandoned 触发权在 P04/P05 所有者**，本包
  只断言状态查询契约，不模拟其触发）；⑤ 默认构造（无 on_event）三路径
  不 panic（默认 no-op 行为）

### Implementation for User Story 4

- [X] T014 [US4] 在 `src/core/response_body.mbt` **增量**实现流式态：
  `ResponseBody::stream(reader : &@io.Reader, on_event? :
  (ResponseBodyEvent) -> Unit)`（回调缺省 no-op）+ 内部
  consumed/dropped 标志；`pub async fn read_some(max_len?)` 增量读
  （委托上游，`None` = EOF 且置 consumed/触发 `Consumed`）；stream 态
  `bytes()` = 读到底 → 置 consumed → 触发 `Consumed`；`pub fn drop()`
  幂等释放（未 consumed 时置 dropped/触发 `Dropped`）；事件互斥时序
  严格按 [data-model.md §4](../data-model.md) 状态机；`ResponseBody`
  手写 Debug 增补流式态分支（印状态，不印 reader 内部）（依赖
  T011/T013）

**Checkpoint**: US4 独立可用——三路径事件序列与互斥时序全绿；
真实归池/毒化行为归 P04/P05（不在本包验收）

---

## Phase 7: User Story 5 - 上传进度回调（Priority: P3）

**Goal**: `with_progress` 包装——Bytes 分块回调、Stream 包计数 Writer；
成功完成时累计单调递增且终值 = content_length（spec US-5、FR-009、
conversion-errors.md 条款 7）

**Independent Test**: 本地夹具断言回调序列与组合不变式；无网络

### Tests for User Story 5（先写、先失败）

- [X] T015 [P] [US5] 在 `src/core/request_test.mbt` 增写失败测试（锚点：
  [contracts/request.md](contracts/request.md) with_progress 锚点）：
  ① 1MB 分块 Stream 体 + 进度回调：累计值单调递增、终值 = content_length
  （FR-009 仅 Stream 形态承诺——2026-10-16 裁决 C；Bytes 形态不承诺
  回调，由③/补用例锁定恒等语义）；② Stream 体（管道驱动写侧）包
  计数 Writer 后写入：回调累计与实际写量一致；③ **组合不变式**
  （conversion-errors.md 条款 7）：`with_progress` 包装前后
  `to_http_request` 输出逐字节相同（content_length 元信息不被包装改变
  ——进度分块不降级 chunked）；④ 失败路径：Stream 回调中途抛错时错误
  可判别传播且 `on_bytes` 不再回调（research R4）
  > **裁决 C 同步（2026-10-16）**：FR-009 已裁剪为仅对 Stream 形态承诺
  > 进度——①改经 **Stream 形态全量验证**（1MB/64KB 分块，T015①），
  > **Bytes 形态不承诺回调（非欠账，不新增台账条目）**；③/补用例锁定
  > Bytes 包装的元信息与转换输出恒等语义。其余锚点 ②③④ 全绿（④的错误
  > 源以测试包 Writer 桩驱动——管道关闭在本工具链为致命 abort 而非可捕
  > 错误，探针实证）。

### Implementation for User Story 5

- [X] T016 [US5] 在 `src/core/request_body.mbt` **增量**实现
  `pub fn RequestBody::with_progress(Self, on_bytes : (Int64) -> Unit)
  -> RequestBody`：**进度仅 Stream 形态承诺（2026-10-16 裁决 C）**；Stream 形态以计数
  `@io.Writer` 包装后传给用户回调（实现 `@io.Writer` 委托 + 累计）；
  失败路径不回调 `on_bytes`（错误沿 async 写调用传播，research R4）；
  包装不得改变 content_type/content_length 元信息（条款 7）（依赖
  T004/T008/T015）
  > **裁决 C 同步（2026-10-16）**：Stream 形态全量落地（CountingWriter
  > 委托 write_once + 累计回调；失败路径不回调；元信息保持）；**Bytes
  > 形态不承诺回调（spec FR-009 裁剪，非欠账）**——按条款 7 返回元信息
  > 恒等的等价体（T015③/补用例锁定恒等语义），不新增台账条目。技术
  > 背景留痕：Bytes 体无可装配写回调位（E4149/E4118 实证：sync 不能调
  > async、async 闭包不能赋 sync 签名）。

**Checkpoint**: US5 独立可用——进度契约与组合不变式全绿；US1–US5 全部
交付

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: 跨故事收口与质量门（宪法 VI/III/敏感信息条款）

- [X] T017 执行 `moon info && moon fmt`，核对 `src/core/pkg.generated.mbti`
  增量 = quickstart 步骤 3 冻结清单：Request/RequestBuilder/RequestBody/
  BodySource/Response/ResponseBody/HttpMessageError/
  ResponseBodyEvent + `to_http_request`/`from_http`/
  `with_progress`/`bytes`/`text`/`read_some`/`drop`/`consumed`/`dropped`/
  `buffered`/`stream`；**to_repr 冻结项按 R1 全量核对（I9 处置补全，
  2026-10-15）**——全部 5 个 derive(Debug) 类型（Request/RequestBuilder/
  Response/HttpMessageError/ResponseBodyEvent）各配 `to_repr` extend
  （N1-A 配套适用本包全部 derive(Debug) 类型；P01 实证 `.mbti`
  :37/:52/:74/:93 值类型均带 extend）——**不得**出现自立 Writer
  trait（C1）、泛型/任意值
  tag（C2）、Logger/Show/序列化输出类签名、按 tag 定位 API 或 Eq/Hash
  意外泄漏（SC-004，宪法 VI；P02 值类型无 Eq/Hash 为有意口径，R10）
- [X] T018 [P] 在各测试文件头注释列明 OkHttp 移植对拍清单（SC-005，
  宪法 III/IV）：移植组（Request.Builder 方法/体矩阵、MediaType charset
  参数解析、`string()` 替换式解码语义）与显式差异组（BOM 不嗅探、响应
  头序不保真、File/json 裁剪、cookies 不建 Jar、tag 占位），来源注明
  `OkHttp 5.5.0 (Apache-2.0)`
- [X] T019 OkHttp 5.5.0 tag 行号复核（**条件任务：网络可达时执行**）：
  对照 `okhttp/src/.../internal/http/HttpMethod.kt` 的
  `permitsRequestBody`/`requiresRequestBody` 与 C5 矩阵逐方法核对
  （research R2 佐证链待收口项）；**网络不可达时（I10 处置补，
  2026-10-15）**：按 T022 对 P03 的同款口径登记欠账（任务备注 +
  欠账跟踪清单）并在 Clarifications 留痕，禁止静默丢失；若与裁决矩阵
  不一致，回改 spec
  （Clarifications 追加）并向下同步 contracts/实现——不得手改实现迁就
  > **复核完成（2026-10-15，owner 补充口径：本机仓库直读 tag
  > parent-5.5.0，`git show` 只读、未执行任何 git 写操作）**：
  > `okhttp/src/commonJvmAndroid/kotlin/okhttp3/internal/http/HttpMethod.kt`
  > :33-41 `requiresRequestBody` = POST/PUT/PATCH/PROPPATCH/QUERY/REPORT、
  > :45 `permitsRequestBody = !(GET||HEAD)`——与 owner 预锚点一致。
  > C5 九方法矩阵逐条核对**一致，无 spec 回改诉求**；显式差异（宪法 III）：
  > requiresRequestBody 的 PROPPATCH/QUERY/REPORT 不在 moonhttp 九方法
  > 封闭枚举（P01 FR-007），枚举扩展时须同步对齐——已记入 research R2。
  > 附带取证（research R5）：BridgeInterceptor.kt:42-54 + Request.kt:247-256
  > 证实 OkHttp 注入为 body 覆盖语义。
  > ~~「用户头优先/已含不覆盖」按宪法 III 更正定性为显式差异（规则与
  > 实现不变；spec FR-005 侧的「对齐」措辞修正留待 owner，本轮禁改
  > spec.md；spec Clarifications 中先前「网络受限未闭环」的留痕一并
  > 交 owner 处置）。~~——**2026-10-16 裁决 A 撤销**：spec FR-005 已回写
  > 为 body 覆盖语义（用户头不优先、body 值覆盖同名头），并存两套说法
  > 已消除；本条「规则与实现不变」「措辞修正留待 owner」「网络受限未
  > 闭环」三处过期表述一并作废。
- [X] T020 质量门：`moon check`（native/wasm 双 target）零错误零警告
  （含 [0079]/[0027]）；`moon test --target native` 与
  `moon test --target wasm` 双双全绿（SC-001；宪法合入门 :130-133）
- [X] T021 [P] 敏感信息输出面抽查（quickstart 步骤 4，分层口径——①③
  宪法敏感信息条款 / ② 输出实用性，owner 2026-10-15 裁定）：① 错误
  消息只带定位片段；② `RequestBody`/`ResponseBody` 的 Debug 输出不含
  体字节（输出实用性检查——避免调试打印转储大块字节，非脱敏/掩码
  验收项，掩码与开关归 M3 F13/F12）；③ `git grep` 抽查测试与 `.snap`
  无真实形态凭证串（样例值全为合成占位，
  A9 纪律；宪法敏感信息条款 + P01 展示例外（M3 F13/F12 收口））
- [X] T022 跑 [quickstart.md](quickstart.md) 全流程：步骤 1（双 target
  测试）/3（零警告与冻结）/4（输出面）/5（移植清单）必须全过；步骤 2
  （线上断言）视 P03 就位状态——未就位时在任务备注登记欠账并保持
  SC-002 开放（不伪装通过）
  > **执行结果（2026-10-15）**：步骤 1 ✓（native/wasm 各 113/113 全绿）；
  > 步骤 3 ✓（双 target check 零错误零警告，`[0035]` 按有理由例外包级
  > 关闭、`[0079]` 经 N1-A to_repr extend 消除、无 [0027]；moon info &&
  > moon fmt 干净；.mbti 增量 = 冻结清单，见 T017）；步骤 4 ✓（T021）；
  > 步骤 5 ✓（T018）；**步骤 2 ✗ 登记欠账**——P03 裸 TCP 对端夹具未
  > 落地（T009 备注），SC-002 保持开放，不伪装通过。

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup（Phase 1）**: 无依赖，立即可做
- **Foundational（Phase 2）**: 依赖 T001；**阻塞全部用户故事**
- **US1（Phase 3）**: 依赖 Phase 2；US2 的转换层依赖 Request（T006）
  与 RequestBody（T004），故 US2 实现任务排在 US1 后
- **US2（Phase 4）**: 依赖 Phase 3（T006）；T009 额外前置 P03 夹具，
  其组合断言另前置 T016（I4 处置补记 2026-10-15——随 P03+US5 就位执行）
- **US3（Phase 5）**: 依赖 Phase 2（T002–T004）；与 US1/US2 无实现耦合
  （可与 US2 并行编写测试）
- **US4（Phase 6）**: 依赖 US3（T011——同一文件 response_body.mbt 增量）
- **US5（Phase 7）**: 依赖 US2（T008——组合不变式断言复用转换层）
- **Polish（Phase 8）**: 依赖全部故事完成（T019 可独立后置）

### User Story Dependencies

- **US1（P1）**: Foundational 后即可开工——无跨故事依赖
- **US2（P1）**: 依赖 US1 产物（Request 类型）；线上断言另依赖 P03
- **US3（P1）**: Foundational 后即可开工（与 US1/US2 并行安全，不同文件）
- **US4（P2）**: 依赖 US3（同文件增量：buffered → stream）
- **US5（P3）**: 依赖 US2（组合不变式）与 T004（with_progress 载体）

### Within Each User Story

- 测试任务（标注「先写、先失败」）必须先于实现任务完成并确认失败
- 契约锚点表 = 测试用例来源；锚点全绿即故事完成
- 同包编译（MoonBit 块序无关），但 US4/US5 为同文件增量任务，严格串行

### Parallel Opportunities

- Phase 2：T002/T003/T004 三任务可并行编辑（不同文件）；T002 的红-绿
  验证以 T003/T004 合入为前提（I7 处置口径，2026-10-15）
- US1 测试（T005）与 US3 测试（T010）、US2 测试（T007）可并行编写
  （不同文件）
- US3 的 T011/T012 不同文件可并行（T012 引用 ResponseBody 类型名，
  联调以 T011 先合入为宜）
- Polish：T018/T021 可并行；T019 独立后置（网络条件）

---

## Parallel Example: User Story 3

```text
# 先行（同文件组）：
Task: T010 失败测试 response_test.mbt（重建互逆/charset 三态/0 字节/Debug 抽查）
# 随后（不同文件，可并行）：
Task: T011 response_body.mbt buffered 态 + text()/charset
Task: T012 response.mbt Response + from_http（依赖 T011 的类型定义合入）
```

---

## Implementation Strategy

### MVP First（US1 only）

1. Phase 1 → Phase 2（Foundational 阻塞全部故事）
2. Phase 3 US1 → `moon test --target native` 独立验证
3. **STOP & VALIDATE**：矩阵校验与不可变值语义成立即可演示

### Incremental Delivery

1. Setup + Foundational → 基础就绪
2. US1 → 验证（MVP）
3. US2 → 转换纯函数绿；线上断言随 P03 闭环（SC-002）
4. US3 → 重建与 charset 绿
5. US4 → 生命周期三路径绿
6. US5 → 进度契约绿 → US1–US5 全交付
7. Polish → 质量门 + 冻结审视（SC-004/SC-005/SC-006 前置面）

### Notes

- [P] = 不同文件、无未完成依赖；同文件增量任务（T014/T016）严格串行
- 每故事停在设计文档标注的 Checkpoint 验证后再前进
- SC-006（L2 杠杆量化）归 P10 基准——本包只保 SC-002 形态断言不回归
- Avoid: 跨故事同文件并行、先实现后补测试、把 P05/P04 职责
  （发送期映射执行、归池/毒化触发）写进本包

---

## Phase 9: Convergence

> `/speckit.converge`（2026-10-16）对照 spec/plan/tasks 与当前 `src/core`
> 实现后追加：只登记尚未满足的剩余工作，不改动既有任务与 spec/plan。
> 现状核对：`moon test --target native` 与 `--target wasm` 各 115/115 全绿、
> 双 target `moon check` 零错误零警告、`moon info && moon fmt` 干净——
> SC-001/SC-004/SC-005 达成、SC-003 由 T007①⑤ 属性断言覆盖、SC-002 随
> P03 排期、SC-006 归 P10 基准；US-1/US-3/US-4/US-5 全验收场景与转换层
> 离线锚点均有测试覆盖并已通过。

- [X] T024 [Polish] 将 tasks.md 内 T007④/T008/T019 备注的注入规则措辞同步为
  2026-10-16 裁决 A 的覆盖语义 per FR-005 (contradicts)
  - 核对时现状：T007④ 仍写「headers 已含时不覆盖、body.content_type 静默
    忽略」、T008 仍写「大小写不敏感查重、已含不覆盖」、T019 备注仍写
    「用户头优先/已含不覆盖（规则与实现不变）」——三处均被 2026-10-16
    裁决 A 撤销。
  - 冲突源：spec FR-005（body 值覆盖用户同名 Content-Type/Content-Length，
    `None` 删键）与 Clarifications I2「不留相互矛盾的两套说法」；当前
    实现/contracts/测试已按裁决 A，故**无需改码**，只差 tasks 措辞同步
    （否则 tasks 与 spec 脱节，未来 pass 可能据旧措辞回退实现）。
  - 处置（**owner 2026-10-16 授权的人类编辑**，超出 converge append-only
    自主写权限）：按既有「划线旧措辞 + 裁决注记」模式改写 T007④/T008/
    T019 三处（旧「headers 已含时不覆盖 / body.content_type 静默忽略 /
    大小写不敏感查重已含不覆盖 / 用户头优先（规则与实现不变）」全部作废，
    现行 = 裁决 A body 覆盖语义），作废 T019 备注「规则与实现不变」「措辞
    修正留待 owner」「网络受限未闭环」三处过期表述，并补「MUST NOT 注入
    Transfer-Encoding」。纯文档同步，无码改动、不影响收口门。

> **去重墓碑（T023，owner 2026-10-16 授权的人类编辑）**：本次 converge
> 另产出 `T023 [US2] 接线 US-2 线上字节断言 per SC-002 (missing)`。经逐项
> 核对，T023 与既有开放任务 T009 纯冗余：四态断言清单在 T009 正文与
> 欠账备注（Phase 4 T009 条目）全有、前置同为 P03 裸 TCP 夹具、驱动面
> （`to_http_request` 直接驱动 `@http.Client`、不经 P05）逐字同义，且 T009
> 还多记一条 T023 漏掉的组合断言依赖（T016）。据 owner 授权删除 T023、
> 编号作废不复用（合 §7:221-222），不留「在清单中但不执行」的僵尸 `[ ]`
> 项（违 §7:207-208 的 actionable 语义）；T023 唯一净增量（SC-002 target
> 口径）归位到 T009 备注注记①。

> **Convergence 结论（2026-10-16）**：无宪法 MUST 违背、无 CRITICAL 缺口。
> 剩余工作仅 SC-002/T009 线上字节断言一项未勾（T009 保持未勾，待 P03 裸
> TCP 对端夹具就位后闭环）。**后续 pass 预期（契约缺口，非执行疏忽）**：
> 只要 T009 保持未勾，`/speckit.converge` 下次仍会另发一个新编号重复登记
> SC-002——§4:143-144 要求不看勾选态把每条既有任务纳入盘点，:59-60 与
> §7:207-208 要求把剩余工作以新 `T{M+1}` 追加，§7:221-222 禁止触碰既有
> Convergence phase，§7:224-228 的 `converged` 分支又要求「无 actionable
> finding」方可不动 tasks.md（而 SC-002 未满足即构成 actionable finding）。
> 故 T009 恒为 SC-002 的唯一跟踪点：届时删除新编号 + 留墓碑（同本处处置）。
> 根治需在 `.opencode/commands/speckit.converge.md` 增加 `already_tracked`
> 类出路，属命令契约修订、不在本特性范围。
