# Implementation Plan: core 值对象——HttpUrl 与 HeadersV（M1-P01）

**Branch**: `001-m1-p01-core-value-types` | **Date**: 2026-10-13 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/001-m1-p01-core-value-types/spec.md`

## Summary

在 `moonbitlang/async@0.22.4` 之上新建 moonhttp 的 core 值对象包 `src/core`，
交付两块纯数据能力：(1) **HttpUrl**——对齐 OkHttp `HttpUrl.parse` 语义的 URL
解析、规范化、相对引用解析（`resolve`）与序列化（`to_string`）；(2) **HeadersV**
——不可变有序多头容器（变更经可变 Builder，Builder 侧做头名/头值校验防头注入）
、向 `@http` 头 Map 的边界折叠转换，以及**默认脱敏的调试输出**（宪法「技术约束
与合规·敏感信息自动掩码」在本包的落地点）。另含 `Method`（九个标准方法，与
`@http.RequestMethod` 一一对应）与错误类型 `HttpUrlError`（四变体）/
`HeadersError`（两变体）。scheme 复用上游 `@http.Protocol`，本包不自立枚举。
不含任何 IO 与执行逻辑。关键裁决（spec Clarifications 2026-10-13 两轮 +
specify 裁决）：折叠分隔符无空格 `","`（与 @http 响应侧逐字节对称）、
`Custom` method 裁剪出 M1、userinfo 显式拒绝、HeadersV 不可变 + Builder、
URL 错误四变体、头校验 raise `HeadersError`（FR-012）、调试输出默认脱敏 +
显式逃生口（FR-013/N4-A）、scheme 复用 `@http.Protocol`（N2-A）、derive 配
显式 `pub extend` 保持 `moon check` 零警告（N1-A）。

## Technical Context

**Language/Version**: MoonBit（工具链 `moon 0.1.20260920`；按 AGENTS.md 工程约定使用 `moon fmt`/`moon info`/`moon test`）

**Primary Dependencies**: `moonbitlang/async@0.22.4`（registry 钉版，见 [research.md](research.md) R1；`moon.mod` 尚未声明，属本包首个实现任务）；复用上游公开面 `@http.Protocol`（`pub(all) enum { Http; Https }`，带 `Protocol::default_port`）、`CaseInsensitiveString`、`Headers`、`RequestMethod`；工具链自带 core/builtin（`Array` 的 `Eq`/`Hash` 实现已核实存在，支撑 FR-006 derive）

**Storage**: N/A（纯值对象，无持久化）

**Testing**: `moon test --target native` 与 `--target wasm` 双绿、`moon check --target js` 通过；`moon check` 四目标**零错误零警告**（SC-004：derive 的值类型紧随显式 `pub extend`，全包不用 `derive(Show)`）；断言优先 `assert_eq`；OkHttp `HttpUrlTest` 场景矩阵移植（Apache-2.0 来源注明）；测试与 `.snap` 快照禁用脱敏逃生口（FR-013）

**Target Platform**: native（首选）与 wasm 全支持；js 仅编译检查；wasm-gc 不支持（`@http` 进入编译图，M1 不建 stub，见 M1 README D9）

**Project Type**: library（moonhttp 的 core 包；分层：门面 `src/client` → core `src/core` → `moonbitlang/async`）

**Performance Goals**: 解析每 URL 一次 O(n)；`resolve` 复用已解析 base、O(增量)；名字比较/哈希零分配（复用 `@http.CaseInsensitiveString` 的免分配实现）；本包无独立基准门禁（宪法 II 的性能数据要求由 P10 汇总覆盖）。**A3「path 段是否惰性化」评估结论（决策 M6-A）**：本包**不惰性化**，path 段以 `Array[String]` 立即解码——理由是 ① P01 无基准数据可依据，过早引入惰性结构违背宪法 VI 的 YAGNI；② 解码本身与 parse 同遍完成，惰性化只是把分配推迟到访问点，而下游 P04 池键与 P06 重定向几乎必然访问 path 段，推迟等于白付复杂度；③ 值类型需满足 Eq/Hash，惰性结构会让判等/哈希需要 memoization，公开面复杂化。**再评估触发条件**：P10 基准若显示「每请求 URL 解析分配」成为热点、或出现「只取 host/port 不取 path」的高频消费方（如连接池键瘦身），届时在 M2/M3 的门面层重评，不在本包返工。

**Constraints**: 非侵入（宪法 I）——仅经 `@http` 公开 API 耦合，禁止 fork/vendor；纯值对象无 IO（FR-011）；0.22.x 钉版、上游改动须人工批准；行为基准 OkHttp 5.5.0 + RFC 9110/3986，差异显式记录（宪法 III）；**敏感信息自动掩码（宪法「技术约束与合规」MUST）**——调试/展示输出对 `Authorization`/`Proxy-Authorization`/`Cookie`/`Set-Cookie` 与 URL 用户信息脱敏，本包经 FR-013（手写 `impl Debug` + 显式逃生口，无包级开关）与 FR-008（拒绝 userinfo）达成

**Scale/Scope**: 4 个值类型 + 1 个 Builder + 2 个错误枚举（`HttpUrlError`/`HeadersError`）；人力 ~3 人日（含 OkHttp 测试矩阵移植与脱敏 Debug 的额外 ~0.25 人日）

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| 原则 | 判定 | 依据 |
| --- | --- | --- |
| I 非侵入底座 | ✅ 通过 | 仅使用 `@http` 公开 API：`CaseInsensitiveString`（pub(all)，已核实）、`Headers = Map[CaseInsensitiveString, String]`、`RequestMethod`、`Protocol` + `Protocol::default_port`（`request.mbt:17-25`，pub(all)，N2-A 复用）；无 fork/复制/vendor；上游 `resolve_url`/`resolve_host` 是 priv 且能力不足（见 research R11），HttpUrl 解析全量自建，不存在复制上游源码 |
| II 性能优先 | ✅ 通过（附注） | 设计避免热路径分配放大（query 保留 encoded 原串、path 段非惰性但每请求一次解析、比较/哈希零分配）；本包无基准要求，P10 汇总覆盖——spec A3/「性能影响」已声明；A3 惰性化评估结论见上文 Performance Goals |
| III OkHttp 语义对齐 | ✅ 通过 | 解析/规范化/resolve 规格与测试矩阵对齐 OkHttp 5.5.0；三处差异（userinfo 拒绝、method 封闭九值、折叠分隔符 `","`）在 spec A6 显式记录并给出理由；移植来源注明 Apache-2.0 |
| IV 验收场景与测试先行 | ✅ 通过 | spec 已固化 US-1–US-4 验收场景与 15 条边界用例；实现顺序必须先写测试（红-绿-重构）；纯函数测试无网络依赖 |
| V Target 策略 | ✅ 通过 | 矩阵显式：native/wasm ✅（双 target 测试双绿）、js ⚠️（仅 check）、wasm-gc ❌（@http 编译图阻塞，D9） |
| VI 简洁与接口纪律 | ✅ 通过 | YAGNI 三处落地：裁剪 `Method::Custom`、path 段不惰性化、错误变体不过度细分；`moon info && moon fmt` + `.mbti` 审视列入 DoD（SC-004）；derive + 显式 `pub extend` 的配套写法（N1-A）新增的方法名并入 `.mbti` 冻结清单逐条核对，属**有意识的接口决定** |
| VII 中文表达 | ✅ 通过 | 本 plan 及全部设计产物、代码注释中文优先 |
| 技术约束与合规·敏感信息自动掩码 | ✅ 通过 | 宪法的掩码 MUST（constitution「技术约束与合规」）在 P01 的落地面有二：① **调试/展示输出**——HeadersV **不用 `derive(Debug)`**，改手写 `impl Debug`，对 `Authorization`/`Proxy-Authorization`/`Cookie`/`Set-Cookie` 的头值脱敏（FR-013 / SC-005），明文只可经显式逃生口方法取得，且测试与 `.snap` 快照禁用逃生口；② **URL 用户信息**——M1 显式拒绝 userinfo（FR-008），不存在携带明文凭证的 URL 值。脱敏不影响判等/哈希（只在输出层）。**运行期可配置掩码开关不在本包**：不引入包级可变状态（N4-A），该能力连同宪法留待补充的「不安全配置 opt-in」条款归 M3，已登记欠账 **F12**（`docs/roadmap/deferred-items.md`） |

**门评估：无违宪项。** Phase 1 设计后复检见文末「Post-Design Constitution Re-check」。

## Project Structure

### Documentation (this feature)

```text
specs/001-m1-p01-core-value-types/
├── spec.md              # 特性规格（/speckit.specify + /speckit.clarify 产物）
├── plan.md              # 本文件（/speckit.plan 产物）
├── research.md          # Phase 0 研究结论（依赖钉版、API 核实、derive 可行性）
├── data-model.md        # Phase 1 数据模型（实体、不变量、验证规则）
├── quickstart.md        # Phase 1 验证指南（运行什么、看什么结果）
├── contracts/           # Phase 1 公开接口契约
│   ├── http-url.md
│   ├── headers.md
│   └── method-error.md
├── analysis-report.md   # /speckit-analyze 结论与决策登记表（C1–M6、L1–L6、N1–N4）
├── checklists/
│   └── requirements.md  # 规格质量清单（16/16 通过）
└── tasks.md             # /speckit.tasks 产物（本命令不创建）
```

### Source Code (repository root)

```text
src/
├── client/                  # 既有门面包骨架（本包不动，占位保留）
│   ├── moon.pkg
│   ├── client.mbt
│   └── client_test.mbt
└── core/                    # P01 新建：core 值对象包（moon.pkg import moonbitlang/async/http，引用形 @http）
    ├── moon.pkg
    ├── error.mbt            # HttpUrlError 四变体 + HeadersError 两变体（仅 derive Debug）
    ├── method.mbt           # Method 九值枚举 + 与 @http.RequestMethod 的映射
    ├── percent.mbt          # percent-encode/decode 与 path/query/fragment 编码集
    ├── percent_wbtest.mbt   # 白盒测试：编码集边界（保留字符/既有 %XX/非法裸字符）
    ├── http_url.mbt         # HttpUrl 值、parse、to_string、访问器（scheme 用 @http.Protocol）
    ├── resolve.mbt          # resolve(base, location) 相对引用解析
    ├── headers.mbt          # HeadersV（不可变）+ HeadersVBuilder（校验）+ to_http_map 折叠
    │                        #   + 手写 impl Debug 脱敏 + 显式逃生口 + pub extend 配套
    ├── headers_fold_test.mbt # 折叠边界：无重复名恒等 / 重复名 "," 拼接与响应侧互逆还原
    └── *_test.mbt           # 黑盒测试：http_url_parse_test / http_url_resolve_test /
                             #   headers_test / method_error_test（OkHttp 矩阵移植分文件）
```

**初始化与占位（决策 L5-A 定案）**: `src/core` 从零起步时，`moon check` 对「无任何
实现的包」不报错，因此**不预先放置空的 `error.mbt` 占位**——`error.mbt` 由首个
真实任务（定义 `HttpUrlError`/`HeadersError`）直接创建；若后续工具链版本变化导致
空包检查报错，才按占位处理并在 tasks 中记为前置动作。包清单 `moon.pkg` 的 import
写法统一为 research R10 口径（`moonbitlang/async/http` 以 `@http` 引入）。

**Structure Decision**: 采纳宪法「技术约束」的分层方向与 M1 README §5 的映射：
core 值对象（P01 本包、P02 后续）入 `src/core`，执行管线类（P04–P09）入门面
`src/client`（既有骨架保留为门面包起点）。依赖方向严格单向：
`client → core → moonbitlang/async`。本包只创建 `src/core`，不触碰 `src/client`。

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

无违宪项，无需记录。

## Post-Design Constitution Re-check

Phase 1 设计产物（data-model.md / contracts / quickstart.md）落地后复检：

- **I 非侵入**：contracts 全部基于 `@http` 公开面（`CaseInsensitiveString`/
  `Headers`/`RequestMethod`/`Protocol` + `Protocol::default_port`），设计未引入
  任何上游改动诉求——✅ 维持通过。scheme 复用上游 `Protocol`（N2-A）是有意的
  耦合选择，不新增依赖边（本包本就依赖 `@http`）。
- **IV 测试先行**：quickstart.md 的验证场景与 contracts 契约一一对应，可先行
  编写失败测试；SC-003 的两个不变量（无重复名恒等映射 / 重复名 `,` 拼接且与
  响应侧 parser 互逆还原）替换了原不可满足命题——✅ 维持通过。
- **VI 接口纪律**：公开面为 4 值类型 + 1 Builder + 2 错误枚举 + parse/resolve/
  to_string + 折叠与访问器 + 脱敏 Debug 的显式逃生口，无多余抽象（无 trait、
  无泛型参数外泄）、**无自立 scheme 枚举**（N2-A）、**无包级可变掩码开关**
  （N4-A）——✅ 维持通过；derive 配套的 `pub extend` 方法与逃生口均计入 `.mbti`
  冻结清单，`.mbti` 检查移交 tasks/implement 执行。
- **技术约束与合规·敏感信息自动掩码**：data-model 与 contracts/headers.md 把
  「默认脱敏 + 显式逃生口 + 测试/快照禁用逃生口」写成可测条款，SC-005 给出
  零明文泄漏判据；可配置开关以欠账 F12 归 M3 跟踪——✅ 通过（首轮 analyze 的
  C1 CRITICAL 已在 spec/plan/design 三层闭环）。
- 其余原则（II/III/V/VII）无设计期新风险——✅ 全部维持通过。
