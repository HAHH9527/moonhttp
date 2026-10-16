# Implementation Plan: 请求/响应/体值模型与定长帧（M1-P02）

**Branch**: `002-m1-p02-request-response` | **Date**: 2026-10-15 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/002-m1-p02-request-response/spec.md`

## Summary

在既有 `src/core` 包（P01 已落地）上增量交付 moonhttp 的请求/响应/体值
模型与「Request → @http 调用参数」纯转换层：`Request`（Builder + 方法/体
矩阵双向构造期校验，C5 裁决）/`RequestBody`（Bytes/Stream 两形态，Bytes
构造期 O(1) 长度校验，C3 裁决）/`Response`/`ResponseBody`（缓冲与流式
两态、`bytes()`/`text()`、UTF-8 唯一受支持集 C4 裁决、三类生命周期事件
契约）；定长帧规则（性能杠杆 L2）由转换层注入 `Content-Length` 触发上游
`SendingFixed`（send.mbt:343-345 实证）。Writer 落点为底座 `@io.Writer`
（C1 裁决，`Client` 公开 impl）；tag 保持 `Unit?` 占位（C2 裁决）；单一
自持错误类型 `HttpMessageError`（封闭二变体——2026-10-16 owner 裁决 B
删除 `UnsupportedCharset` 变体；P01 `.mbti` 同构风格，R1 核对
通过）。不含连接/执行/取消逻辑（FR-010）；发送期映射执行归 P05、归池/
毒化接归 P04/P05。关键裁决全部收口于 spec Clarifications（2026-10-15，
C1–C5 五题）。

## Technical Context

**Language/Version**: MoonBit（工具链下限 ≥ `0.1.20260920`，本仓库实测 `0.1.20261012`——P01 `error.mbt` 决策 N1-A 留痕；`moon fmt`/`moon info`/`moon test` 按 AGENTS.md 工程约定）

**Primary Dependencies**: `moonbitlang/async@0.22.4`（已钉 moon.mod）；复用 P01 冻结公开面（`HttpUrl`/`HeadersV`/`HeadersVBuilder`/`Method`/`to_http_map`/`to_request_method`，`src/core/pkg.generated.mbti` 实测）；复用上游公开面 `@http.RequestMethod`/`@http.Headers`/`@http.Cookie`/`@http.Response`（重建输入）/`@http.IncorrectBodyLength`（映射目标，pub suberror）/`@io.Writer`/`@io.Reader`（C1 落点）/`@io.MemoryReader`+`pipe`（测试桩）。**新增 import 两条**（research R8）：`moonbitlang/async/io`、`moonbitlang/core/encoding/utf8`（`decode_lossy`，research R6）——均属既有依赖家族公开包，不扩宪法 I 风险面

**Storage**: N/A（纯值模型；流式态持有的 reader 引用由 P05 注入）

**Testing**: `moon test --target native` 与 `--target wasm` 双绿；`moon check` 双 target 零错误零警告；断言优先 `assert_eq`；US-2 线上字节断言（场景 1/2）**前置 P03 裸 TCP 夹具**（当前仓库未有 P03 产物，排期前置，quickstart 步骤 2）；生命周期/重放/进度用 `@io.MemoryReader`/`pipe` 桩与本地夹具，零外部网络（宪法 IV）；OkHttp 场景移植注明 Apache-2.0；敏感头样例值合成占位串（A9 纪律）

**Target Platform**: 验证面 native（首选）与 wasm（能力等价，P01 已验证同路径）；js 仅 API 层验收（US-2 线上断言不适用、`Response.cookies` 恒空，spec A8）；wasm-gc「暂不验证」挂欠账 F9（宪法 V）

**Project Type**: library（`src/core` 增量；分层不变：`client → core → moonbitlang/async`）

**Performance Goals**: 转换层 O(头数) 纯函数、零多余折叠（直接复用 P01 `to_http_map`）；Bytes 重放 O(1)（不可变引用语义）；每请求发送路径分配目标（连接已建 ≈2 对象）由 P05 承接，core 侧约束 = 转换输出零二次加工可直喂 `Client::request`。**L2 杠杆不回归由 SC-002（线上形态）+ SC-006 把守，量化归 P10「POST 定长 vs chunked」基准（宪法 II）**

**Constraints**: 非侵入（宪法 I，全部经上游 pub 面耦合）；无连接/执行/取消逻辑（FR-010）；0.22.x 钉版、上游改动须人工批准；行为基准 OkHttp 5.5.0，差异显式记录（C5 矩阵更正、BOM 不嗅探、响应头序不保真、File/json 裁剪，SC-005）；错误消息只带定位片段、Debug 体字节打印口径见「例外跟踪」（owner 2026-10-15 追认留痕）；**US-4 的 Abandoned 触发权在 P04/P05**（本包只交付契约与默认行为）

**Scale/Scope**: 5 值类型（Request/RequestBuilder/RequestBody/Response/ResponseBody）+ 2 枚举（BodySource/ResponseBodyEvent）+ 1 错误类型（3 变体）+ 转换层 1 纯函数 + 纯重建函数 1 个；人力 ~1.5 人日（M1 README P02 估时；US-2 线上断言随 P03 就位）

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| 原则 | 判定 | 依据 |
| --- | --- | --- |
| I 非侵入底座 | ✅ 通过 | 类型面只依赖上游 pub 面：`@http.RequestMethod`/`Headers`/`Cookie`/`Response`/`IncorrectBodyLength`（mbti:37，pub）、`@io.Writer`/`Reader` trait（C1 裁决拒绝自立 trait）+ `@utf8` 公开包；定长帧经 `extra_headers` 公开参数触发（send.mbt:343-345），无 fork/复制/vendor；新增 import 两条均属既有依赖家族（R8） |
| II 性能优先 | ✅ 通过（附注） | L2 定长帧杠杆本包交付并经 SC-002 线上形态断言；转换纯函数是 D4/L3 缓存前提（FR-005）；无对既有已实测杠杆的回归路径（本包不触碰连接/发送缓冲）；量化收益归 P10 基准（SC-006） |
| III OkHttp 语义对齐 | ✅ 通过 | C5 矩阵按真实 OkHttp 5.x 校正（种子「GET/HEAD 不强制禁止」已证伪更正，A5/A6⑤；佐证链 research R2）；差异显式：响应头序不保真、BOM 不嗅探、File/json 裁剪、cookies 不建 Jar、tag 占位（SC-005/A6）；`string()` 替换式解码语义经 `decode_lossy` 对齐（R6）；移植来源注明 Apache-2.0 |
| IV 验收场景与测试先行 | ✅ 通过 | US-1–US-5 + 边界用例在 spec 固化，契约锚点表一一对应（contracts/*），实现红-绿-重构；US-4 以 `@io.MemoryReader`/`pipe` 桩零网络验收；US-2 线上断言明示 P03 前置（不构成门禁缺口，属排期依赖） |
| V Target 策略 | ✅ 通过 | 验证面 native/wasm 双绿双零警告（P01 已证 wasm 同路径可行）；js API 层验收、wasm-gc 暂不验证均显式标注并挂 F9（宪法 v1.2.0 :67-77 合规态） |
| VI 简洁与接口纪律 | ✅ 通过 | YAGNI 三处落地：不自立 Writer trait（C1）、tag 占位（C2）、单错误类型承载三语义（拒绝拆分）；转换输出复用 `@http.Request` 零新类型（R3/R7）；`moon info && moon fmt` + `.mbti` 冻结审视列入 DoD；手写 Debug 仅限函数/trait-object 字段所迫的三个类型（R10） |
| VII 中文表达 | ✅ 通过 | 本 plan 及全部设计产物中文；代码注释中文优先 |
| 技术约束与合规·敏感信息默认不展示 | ⚠️ 例外跟踪 | Request/Response 携带头值，`derive(Debug)` 默认明文——沿 P01 已确认口径（所有者 2026-10-14 确认，留痕 R3-M1；欠账 F13 明文覆盖「后续 Request/Response 等值类型」）。本包追加收敛：RequestBody/ResponseBody Debug 手写不整打体字节（owner 2026-10-15 裁定属输出实用性、非脱敏需求，见「例外跟踪」），错误消息只带定位片段（方法名/长度对） |
| 零警告门依赖包级警告抑制 | ⚠️ 例外跟踪 | `src/core/moon.pkg` 的 `options(warnings: "-reserved_keyword")` 为**有理由包级抑制**（host 侧独立验证：撤掉后 [0035] 在冻结契约名 `method` 上触发 6 处，且 [0035] 为解析期警告、声明级 `#warnings` 压不住；spec FR-002 五要素字段名不可改名）——零警告门（T020）依赖该条，owner 2026-10-16 确认保留 |

**门评估：无违宪项**（敏感信息条目为 ⚠️ 例外跟踪态——继承 P01 已走完的
宪法 v1.2.0 :112-117 展示例外程序，且 F13 已把 Request/Response 纳入 M3
脱敏专版范围；所有者已于 2026-10-15 对本包范围予以追认留痕，见文末
「例外跟踪」）。
Phase 1 设计后复检见文末「Post-Design Constitution Re-check」。

## 例外跟踪

- **Request/Response 值类型的 Debug 明文输出（headers 字段）**：
  - **依据**：宪法 v1.2.0 :112-117 展示例外程序；P01 所有者确认（2026-10-14，
    留痕 = 分析报告 R3-M1）已声明形态覆盖「后续 Request/Response 等值
    类型」（欠账 F13 原文）。
  - **形态**：`Request`/`Response` derive(Debug)（headers 全量明文）；
    `BodySource`/`RequestBody`/`ResponseBody` 手写 Debug（手写范围由函数/
    trait-object 字段不可 derive 的编译事实所迫，R10，非风格选择）；其
    Bytes 变体打印元信息不整打体字节——依 owner 裁决（2026-10-15）属
    **输出实用性**（避免调试打印转储大块字节），不作为脱敏/掩码需求。
  - **纪律**：测试与 `.snap` 敏感头样例值 = 合成占位串（沿 P01 A8/A9）。
  - **回补**：敏感头掩码与可配置开关统一归 M3（F13 脱敏专版 / F12），
    P02 不做任何形态的脱敏工作。
  - **追认留痕（2026-10-15，analyze C1 处置）**：owner 追认本例外适用于
    P02 全范围，并裁定「P02 不做脱敏需求、不新增掩码式手写 Debug」——
    plan 汇报项就此闭环；下游产物（R10/quickstart 步骤 4/T021 等）措辞
    按本口径同步。

## Project Structure

### Documentation (this feature)

```text
specs/002-m1-p02-request-response/
├── spec.md              # 特性规格（/speckit.specify + /speckit.clarify 产物，C1–C5 已裁决）
├── plan.md              # 本文件（/speckit.plan 产物）
├── research.md          # Phase 0 研究结论（R1–R10：错误命名核对、OkHttp 矩阵佐证链、上游行号证据）
├── data-model.md        # Phase 1 数据模型（实体、状态机、错误/事件清单唯一规范源）
├── quickstart.md        # Phase 1 验证指南（5 步；US-2 线上断言前置 P03）
├── contracts/           # Phase 1 公开接口契约
│   ├── request.md           # Request/RequestBuilder/RequestBody/BodySource + 方法体矩阵
│   ├── response.md          # Response/ResponseBody + charset + 生命周期事件
│   └── conversion-errors.md # to_http_request 纯函数 + 注入规则 + HttpMessageError 映射契约
├── checklists/
│   └── requirements.md  # 规格质量清单（16/16 通过，含 clarify 轨迹）
└── tasks.md             # /speckit.tasks 产物（本命令不创建）
```

### Source Code (repository root)

```text
src/core/                     # P02 增量（P01 既有文件保留：http_url/headers/method/percent/resolve）
├── moon.pkg                  # import 增加 moonbitlang/async/io、moonbitlang/core/encoding/utf8（R8）
├── request.mbt               # Request + RequestBuilder（方法/体矩阵构造期校验）
├── request_body.mbt          # RequestBody + BodySource（Bytes 构造期校验/Stream/with_progress）+ 手写 Debug
├── response.mbt              # Response + from_http 纯重建（逗号合并值拆分）
├── response_body.mbt         # ResponseBody 两态 + 生命周期状态机/事件 + text() charset + 手写 Debug
├── conversion.mbt            # Request::to_http_request 纯转换（path 重组 + Content-Length/Content-Type 注入）
├── message_error.mbt         # HttpMessageError 封闭二变体 + to_repr（P01 error.mbt 风格同构；裁决 B 删 charset 变体）
├── request_test.mbt          # 黑盒：Builder/矩阵校验/RequestBody 构造校验/with_progress
├── conversion_test.mbt       # 黑盒：纯函数性属性测试/注入规则/请求目标形态
├── response_test.mbt         # 黑盒：from_http 重建互逆/charset 三态/0 字节
├── response_body_lifecycle_test.mbt  # 黑盒：Consumed/Dropped/Abandoned 三路径（MemoryReader/pipe 桩）
└── *_wbtest.mbt             # 白盒：状态机标志位边界（按需）
```

**Structure Decision**: 沿 M1 README L115-116 与 P01 plan Structure
Decision——core 值对象（P01、P02）入 `src/core`，不触碰 `src/client`；
依赖方向严格单向 `client → core → moonbitlang/async(+core)`。P02 全部
为 `src/core` 包内增量文件，不改 P01 冻结面（`.mbti` diff 仅新增）。
P03 裸 TCP 夹具是 US-2 线上断言的运行前置（tasks 排期处理）。

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

无违宪项，无需记录。

## Post-Design Constitution Re-check

Phase 1 设计产物（research/data-model/contracts/quickstart）落地后复检：

- **I 非侵入**：contracts 全部签名锚定上游 pub 面（`@http.Request` 复用、
  `@io.Writer/Reader` trait、`IncorrectBodyLength` pub suberror、`@utf8`
  公开包）；定长帧经 `extra_headers` 公开参数；无任何上游改动诉求——
  ✅ 维持通过。
- **II 性能优先**：转换层零状态零多余折叠；SC-002 线上形态断言守住 L2
  不回归；量化归 P10——✅ 维持通过。
- **III OkHttp 对齐**：C5 矩阵更正与佐证链落 research R2；`decode_lossy`
  对齐替换式解码；BOM/头序/File/json/cookies 差异全部显式登记——✅ 维持
  通过（5.5.0 tag 行号复核为 tasks 核对项，网络受限未阻塞设计）。
- **IV 测试先行**：三份契约的锚点表与 quickstart 步骤一一对应，可先行
  写失败测试；US-4 桩方案（`@io.MemoryReader`/`pipe`）上游原语可零网络
  驱动三路径——✅ 维持通过。
- **VI 接口纪律**：公开面 = 5 值类型 + 2 枚举 + 1 错误类型 + 转换/重建/
  进度/生命周期 API，全部有 spec FR 对应；无自立 Writer trait（C1）、无
  泛型 tag（C2）、无输出类 API；`.mbti` 增量清单已列 quickstart 步骤 3，
  冻结审视移交 tasks/implement——✅ 维持通过。
- **V/ VII**：设计期无新风险（验证面口径与 P01 一致；产物全中文）——✅。
- **敏感信息（例外跟踪态，合法）**：Debug 明文沿 P01 已确认口径；体字节
  不整打属输出实用性（函数/trait-object 字段所迫手写，非脱敏需求）。
  所有者已于 2026-10-15 追认本例外覆盖 P02 全范围并裁定「P02 不做脱敏
  需求、不新增掩码式手写 Debug」，掩码统一归 M3（F13/F12）——**⚠️ 例外
  跟踪（非违宪，已追认留痕，见「例外跟踪」）**。
