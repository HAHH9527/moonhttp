# Feature Specification: core 值对象——HttpUrl 与 HeadersV（M1-P01）

**Feature Branch**: `m1-p01-core-value-types`（建议名；本项目未启用分支 hook，实际分支由人工决定）

**Created**: 2026-10-13

**Status**: Draft

**Input**: User description: "docs/roadmap/M1/P01-core-value-types.md"（M1 工作包 P01 的 speckit 输入种子全文）

## Clarifications

### Session 2026-10-13

- Q: 请求头容器 HeadersV 应采用哪种可变性设计？ → A: 不可变 HeadersV + 可变 Builder（`add`/`set`/`remove` 在 Builder 上，`build()` 产出不可变值；对齐 OkHttp Headers/Headers.Builder 二分，入键后哈希恒稳）
- Q: HttpUrlError 应细分到什么变体粒度？ → A: 四变体 `InvalidHost` / `InvalidPort` / `MalformedUrl` / `UnsupportedScheme`（下游 P06/P07 可按类别精确判别降级）
- Q: HeadersV Builder 的头名/头值校验（防头注入）是否属本包承诺的行为？ → A: 属 MUST；非法头名（空名、非 RFC 9110 token）与含 CR/LF 的头值一律拒绝并 raise 新增公开类型 `HeadersError`（`InvalidName`/`InvalidValue`）（analyze C1/H2/N3，2026-10-13 决策 → FR-012）
- Q: 宪法「敏感信息自动掩码」MUST 覆盖调试输出，本包 HeadersV 的 Debug 如何满足？ → A: 调试/展示输出 MUST 默认对 `Authorization`/`Proxy-Authorization`/`Cookie`/`Set-Cookie` 与 URL 用户信息脱敏，需手写 `impl Debug`（`derive(Debug)` 无法脱敏）（决策 C1 → FR-013）
- Q: 脱敏关掉的路径用什么形态（包级 flag 还是显式方法）？ → A: 只用「必须主动调用的显式逃生口方法」，不引入包级可变开关；测试与 `.snap` 快照 MUST NOT 使用逃生口；可配置掩码 flag 与宪法「不安全配置 opt-in」条款归 M3（决策 N4-A，见 A8）
- Q: scheme 用本包自立枚举还是复用上游 `@http.Protocol`？ → A: 复用上游 `@http.Protocol`（`Http`/`Https`）与 `Protocol::default_port`，本包 MUST NOT 自立 scheme 枚举、MUST NOT 重复提供 `default_port`（决策 H3→N2-A → FR-002）
- Q: FR-006「全部公开类型可判等、可哈希」是否含错误类型？ → A: 不含。值类型 MUST Eq/Hash/Debug，错误类型仅 MUST 可调试输出（判别用 `is`/模式匹配足够）；本包一律不使用 `derive(Show)`（本工具链报弃用警告 [0027]）（决策 M5-A + N1-A → FR-006）
- Q: 「`moon check` 零警告」口径如何与 derive 并存？ → A: derive 的值类型紧随显式 `pub extend`（`Eq::{equal, not_equal}`/`Hash::{hash, hash_combine}`/`Debug::{to_repr}`）消除 `implicit_impl_as_method` [0079]，SC-004 保持「零错误零警告」，新增方法并入 `.mbti` 冻结清单逐条审视（决策 N1-A → SC-004）
- Q: 端口合法区间与 `http://h:0/` 的口径？ → A: 统一为 `1..=65535`（与上游 priv 守卫 `1..<65536` 实证一致），`http://h:0/` MUST 报 `InvalidPort`（决策 M1-A → Edge Cases）
- Q: SC-003 的折叠属性测试命题（重复名折叠后 `get` 首个语义不变）不可满足，如何改写？ → A: 改为两个可满足不变量：无重复名时折叠对单值名是恒等映射；有重复名时折叠值 = 插入序 `,` 无空格拼接，且该串经 @http 响应侧 parser 可还原原名值序列（决策 H1-A → SC-003）
- Q: `values` 返回类型与折叠的关系？ → A: `values` 返回保序迭代器，MUST NOT 折叠同名值；折叠只发生在 FR-005 的边界转换（决策 M2-A → FR-004）
- Q: spec 内的 OkHttp camelCase 术语（`defaultPort`/`toString`）与下游 snake_case 漂移？ → A: 全 spec 统一为 MoonBit snake_case（`default_port`/`to_string`）（决策 L1-A）
- Q: `HttpUrlError` 变体清单在 spec 内 4 处重述，规范源是谁？ → A: 以 `data-model.md` 为唯一规范源，spec 只引用不重述（决策 L4-A → FR-009）
- Q: RFC 3986 的 query-only（`?x=1`）、仅 fragment（`#f`）、base 无 path 三个 resolve 分支是否需要验收锚点？ → A: 需要，落在 `contracts/http-url.md` 锚点表与 T011/T017（决策 L6-A，属契约层，不改 spec 边界用例计数）

## User Scenarios & Testing *(mandatory)*

### User Story 1 - HttpUrl 解析与规范化（Priority: P1）

作为 moonhttp 库使用者，我传入 URL 字符串，得到一个规范化、可比较的 `HttpUrl`
值；畸形输入得到类型可判别的明确错误（`HttpUrlError`），而非 panic 或静默容忍。
重定向、缓存与 cookie 等后续特性都以该值作为 path/query 级操作的统一底座
（async/http 现有 `resolve_url` 仅做 `protocol://host[:port]/path` 顶层切分，
无 query/fragment/percent-encoding/IPv6-literal 处理能力）。

**Why this priority**: 下游全部工作包（P02 请求建模、P04 连接池键、P06 重定向
Location 解析）都以 HttpUrl 为地基；没有它后续包无法开工。

**Independent Test**: 纯函数、无网络无 IO；`moon test` 直接断言解析结果与
to_string 输出。

**Acceptance Scenarios**:

1. **Given** `"http://Example.COM:80/a/./b/../c?x=1#frag"`，**When** parse 后
   to_string，**Then** 得到 `"http://example.com/a/c?x=1#frag"`（scheme/host
   小写规范化、点段消解、默认端口省略、空段压缩）。
2. **Given** `"http://[::1]:8080/x"`，**When** parse，**Then** host 为剥去方括号
   的 `"::1"`、port 为 8080（使用侧后续传给连接层时无需再处理括号）。
3. **Given** `"http://bad host/"` 或 `"http://host:notaport/"`，**When** parse，
   **Then** raise 类型可判别的 `HttpUrlError`。
4. **Given** 含非 ASCII host 的 URL，**When** parse，**Then** raise
   `HttpUrlError::InvalidHost`（IDN/punycode 支持随 M3 回补）。
5. **Given** 任意 parse 成功的 URL，**When** 对 parse 结果 to_string 再 parse，
   **Then** 与第一次 parse 结果相等（往返幂等）。

---

### User Story 2 - 相对引用解析 resolve（Priority: P1）

作为重定向/缓存特性的下游使用者，我用 `HttpUrl::resolve(base, location)` 把
`Location` 头的值解析为绝对 URL；相对引用、绝对 URL、网络路径参考均可用，
解析过程复用已解析的 base。

**Why this priority**: P06 自动重定向与 M4 缓存键计算直接依赖；与 US-1 同为
P02/P04 的前置。

**Independent Test**: 纯函数断言（移植 OkHttp `HttpUrl.resolve` 测试组），
无需网络。

**Acceptance Scenarios**:

1. **Given** base `http://a.com/dir/page` 与 location `"../up"`，**Then** 解析
   结果为 `http://a.com/up`。
2. **Given** 同一 base 与 `"/root"`，**Then** `http://a.com/root`；与
   `"//b.com/x"`，**Then** `http://b.com/x`（scheme 自 base 继承）。
3. **Given** 非法 location，**Then** raise `HttpUrlError`（外层如何降级为
   「返回原响应」由 P06 决定，不在本包范围）。

---

### User Story 3 - HeadersV 操作语义（Priority: P1）

作为 moonhttp 库使用者，我以 OkHttp 语义操作有序、允许重复名的请求头容器：
变更操作（`set` 覆盖全部同名、`add` 追加、`remove` 删全部同名）发生在可变
Builder 上，`build()` 产出不可变的 HeadersV 值，值上提供 `get`（取首个）与
`values`（保序遍历）；名字比较大小写不敏感。

**Why this priority**: P02 Request 建模与 P04「同 URL + 同头序」池键的前提；
排序稳定性是缓存 Vary 键与重放字节级一致的基础。

**Independent Test**: 纯容器语义单测，无 IO。

**Acceptance Scenarios**:

1. **Given** Builder 依次 `add("Accept","a")`、`add("Accept","b")` 后
   `build()`，**Then** 值上 `values("accept")` 得到 `["a","b"]`（大小写
   不敏感、保插入序），`get` 返回 `"a"`。
2. **When** Builder `set("Accept","c")` 后 `build()`，**Then** 同名头仅剩
   一条 `"c"`。
3. **Given** 两次以相同顺序构造相同的头列表，**Then** 两容器相等且哈希一致
   （供 P04 Address 键使用）。
4. **Given** Builder `add("Bad Name","v")`（含空格、非 token 字符）或
   `add("X","a\r\nInjected: 1")`（值含 CR/LF），**Then** raise 可判别的
   `HeadersError::InvalidName` / `InvalidValue`，容器不变（FR-012，防头注入）。
5. **Given** Builder 已 `add("Authorization","Bearer secret")` 后 `build()`，
   **When** 对该值做调试输出，**Then** 输出含头名与脱敏占位、**不含**
   `Bearer secret`；同一容器判等/哈希不受脱敏影响（FR-013/SC-005）。

---

### User Story 4 - 边界折叠转换（Priority: P2）

作为执行管线的下游使用者（P02/P05），我把 `HeadersV` 折叠为
`@http` 请求侧所需的头 Map（同名值合并为单值）。

**Why this priority**: 仅为边界集成服务；P1 三个故事成立后本故事才被下游
消费，但实现简单且与 US-3 同包交付。

**Independent Test**: 纯函数断言折叠结果。

**Acceptance Scenarios**:

1. **Given** 两条 `X-Multi: a` / `X-Multi: b`，**Then** Map 中同名键单值
   `"a,b"`（无空格逗号，与 @http 响应侧合并逐字节对称，见 FR-005）。
2. **Given** 值内含 quoted-string 逗号（如 `WWW-Authenticate: Basic
   realm="a, b"`），**Then** 折叠结果的字符串语义在文档中显式声明为
   「不保证 quoted-string 边界」；认证路径未来绕过此转换（M2，08-auth）。

### Edge Cases

- URL 为空串、仅 scheme、仅 host：parse MUST 明确报错（`MalformedUrl` 类），
  不得 panic。
- port 合法区间为 `1..=65535`：越界（`http://h:0/`、`http://h:65536/`）或非数字
  （`http://h:notaport/`）一律报 `InvalidPort` 类错误，不得 panic。
- path 为空：规范化为 `/`。
- query 含保留字符与既有百分号序列：不二次编码（见假设 A2 的规范化策略）。
- fragment 为 `None` 与空串两种状态 MUST 可区分（to_string 时 `#` 的有无）。
- IPv6 带畸形括号（未闭合、多重括号）：报错；带 zone-id 的形式对齐 OkHttp
  保留原样。
- host 末尾点（`a.com.`）：对齐 OkHttp 保留原样、不剥离。
- 含 userinfo（`user:pass@host`）的 URL：parse 显式报错（见 FR-008）。
- 非 http/https scheme（如 `ftp://`）：报 `UnsupportedScheme`。
- 重复 query 键：原样保留，不合并。
- HeadersV 空容器折叠为空 Map。
- 值为空串的头：合法，保留；折叠后值为空串。
- 头名为空串或含非 RFC 9110 token 字符（空格、`:`、CR/LF 等）：Builder 操作
  MUST raise `HeadersError::InvalidName`（见 FR-012）。
- 头值含 CR 或 LF（含 CRLF 折叠注入序列）：Builder 操作 MUST raise
  `HeadersError::InvalidValue`（见 FR-012，防头注入）。
- HeadersV 含 `Authorization`/`Cookie` 等敏感头：调试/展示输出 MUST 只呈现脱敏
  值，明文 MUST NOT 进入日志或 `.snap` 快照（见 FR-013）。

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: HttpUrl MUST 实现解析与 to_string 双向，且对 parse 成功的任意
  输入满足往返幂等：parse(to_string(parse(s))) 与 parse(s) 相等。
- **FR-002**: HttpUrl MUST 提供 `resolve(base, location)` 相对引用解析与
  scheme/host/port/path/query/fragment 访问器；scheme MUST 复用上游
  `@http.Protocol`（`Http`/`Https`），默认端口 MUST 直接使用
  `@http.Protocol::default_port`（http=80 / https=443），本包 MUST NOT 自立
  scheme 枚举、MUST NOT 重复定义默认端口真相（澄清 2026-10-13，决策 N2-A）。
- **FR-003**: 非 ASCII host MUST raise `HttpUrlError::InvalidHost`（M1 范围，
  IDN 随 M3 回补）。
- **FR-004**: HeadersV MUST 为不可变值（判等/哈希在其上恒稳，供 P04 池键
  安全使用），保插入序、名字大小写不敏感比较、支持重复名；`get`（首个）与
  `values`（保序遍历，**不折叠同名值**）在值上提供，`set`（覆盖全部同名）/
  `add` / `remove`（删全部同名）在配套可变 Builder 上提供（澄清 2026-10-13；
  同名值合并只发生在 FR-005 的边界折叠）。
- **FR-005**: HeadersV 向 `@http` 头 Map 的边界折叠 MUST 与 @http 响应侧同名
  合并语义逐字节对称：同名值以无空格逗号 `","` 合并（用户裁决 Q1-A；RFC 9110
  允许无空格逗号，且保证响应侧已合并的头再进请求侧折叠不变形）。
- **FR-006**: 值类型（HttpUrl / HeadersV / HeadersVBuilder / Method）MUST
  可判等、可哈希、可调试输出（Eq/Hash/Debug）；错误类型（HttpUrlError /
  HeadersError）MUST 可调试输出（Debug），**不参与判等与哈希**——错误判别以
  `is` 与模式匹配为准（澄清 2026-10-13，决策 M5-A）。本包 MUST NOT 使用
  `derive(Show)`（本工具链报弃用警告 [0027]）；HeadersV 的 Debug 输出受 FR-013
  脱敏约束，MUST 手写实现而非 derive。
- **FR-007**: `Method` MUST 仅以九个标准方法（Get/Post/Put/Delete/Head/
  Options/Trace/Patch/Connect）建模，与 `@http.RequestMethod` 一一对应；
  自定义方法 token 不在 M1 类型面内（用户裁决 Q2-B：裁剪 `Custom` 出范围，
  需求出现时再评估回补——上游枚举开放属侵入项，须人工批准，宪法 I）。
- **FR-008**: 含 userinfo（`user:pass@host`）的 URL 在 M1 MUST 显式拒绝
  （raise `HttpUrlError`，按 A5 默认归入 `MalformedUrl` 变体），不得静默
  丢弃，以保住 FR-001 对全部被接受输入的往返幂等承诺（用户裁决 Q3-A）。
- **FR-009**: 本包 MUST 提供可判别的错误类型 `HttpUrlError`，变体清单以
  `data-model.md` 的错误模型为**唯一规范源**（当前裁决为 `InvalidHost` /
  `InvalidPort` / `MalformedUrl` / `UnsupportedScheme` 四变体，见 A5），本文件
  其余处只按名引用、不重述分类细节（澄清 2026-10-13，决策 L4-A）。
- **FR-010**: IPv6 literal（`[::1]:8080` 形式）MUST 可解析，host 存储为剥去
  方括号的字符串。
- **FR-011**: 本包 MUST 不含任何网络 IO 与请求执行逻辑（纯值对象层）。
- **FR-012**: HeadersVBuilder MUST 在进入存储前校验头名与头值，违例 raise 可
  判别的 `HeadersError`：头名 MUST 为非空 RFC 9110 token 字符序列（违例
  `InvalidName`）；头值 MUST NOT 含 CR 或 LF（违例 `InvalidValue`，防头注入）。
  `add`/`set` 受此约束，`remove` 对非法名静默无操作（澄清 2026-10-13，
  决策 H2-A；本条为安全类 MUST，P02/P05 按此继承）。
- **FR-013**: HeadersV 的调试与展示输出 MUST **默认脱敏** `Authorization`、
  `Proxy-Authorization`、`Cookie`、`Set-Cookie` 的头值（宪法「技术约束与合规·
  敏感信息自动掩码」MUST 在本包的落地；URL 用户信息的脱敏由 FR-008 拒绝
  userinfo 达成）。脱敏 MUST NOT 影响判等与哈希（脱敏只发生在输出层）。
  如需明文排查，MUST 通过**显式调用的逃生口方法**获取，本包 MUST NOT 提供
  包级可变掩码开关；测试与 `.snap` 快照 MUST NOT 使用逃生口（澄清 2026-10-13，
  决策 C1-A + N4-A）。可配置掩码开关与宪法「不安全配置 opt-in」条款归 M3，
  登记在 `docs/roadmap/deferred-items.md`（见 A8）。

### Key Entities

- **HttpUrl**：规范化后的 HTTP URL 值。属性：scheme（复用上游 `@http.Protocol`，
  本包不自立枚举）、host（已解码、IPv6 剥括号）、port（显式或默认，
  `1..=65535`）、path 段序列（已 percent-decode、以 `/` 起始）、query
  （保留 encoded 形式）、fragment。支持解析、to_string、相对引用解析与
  判等/哈希。
- **HeadersV**：有序、允许重复名的**不可变**请求头容器（变更经配套可变
  Builder 完成后由 `build()` 产出）；名字大小写不敏感；支持向 `@http`
  头 Map 的折叠转换；调试/展示输出默认脱敏敏感头值（FR-013）。
- **HeadersVBuilder**：HeadersV 的可变配套容器，`add`/`set`/`remove` 与头名
  头值校验（FR-012）在此发生。
- **Method**：请求方法值；仅九个标准方法，与底层 HTTP 库的方法枚举一一对应
  （自定义方法 token 不在 M1 类型面内）。
- **HttpUrlError**：URL 解析失败的可判别错误，变体清单见 FR-009 指向的
  `data-model.md` 规范源；仅要求可调试输出（不参与判等/哈希）。
- **HeadersError**：头名校验与头值校验失败的可判别错误（`InvalidName` /
  `InvalidValue`），由 FR-012 引入；仅要求可调试输出。

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: US-1 至 US-4 的全部验收场景均有测试且 `moon test --target
  native` 与 `--target wasm` 双绿；js 至少 `moon check --target js` 通过。
- **SC-002**: OkHttp `HttpUrlTest` 场景矩阵的移植清单在测试文档中列明
  （移植了哪些组：畸形输入/规范化/resolve/IPv6/percent-encoding；略去了
  哪些及理由），移植来源注明 Apache-2.0（宪法 III）。
- **SC-003**: 语义级回归零缺口，折叠由两个可满足不变量共同保证（属性测试）：
  ① **无重复名**的任意头列表，折叠后每个名字的 `get` 值与折叠前逐字节相等
  （折叠对单值名是恒等映射）；② **有重复名**时，折叠值 = 按插入序以无空格
  `","` 拼接，且该串经 @http 响应侧 parser 拆分可还原原名值序列（进出互逆）
  （澄清 2026-10-13，决策 H1-A：原「折叠后 get 首个语义与折叠前一致」在存在
  重复名时必然为假，故弃用）。
- **SC-004**: `moon info && moon fmt` 干净，`.mbti` 冻结 core 值对象公开面
  并经人工审视（宪法 VI）；四个目标 `moon check` **零错误零警告**——derive
  的值类型紧随显式 `pub extend`（`Eq::{equal, not_equal}`、
  `Hash::{hash, hash_combine}`、`Debug::{to_repr}`）以消除
  `implicit_impl_as_method` [0079]，且不使用 `derive(Show)`（决策 N1-A；
  由此新增的方法名一并进入 `.mbti` 冻结清单逐条审视）。
- **SC-005**: 敏感头零明文泄漏：含 `Authorization`/`Proxy-Authorization`/
  `Cookie`/`Set-Cookie` 的 HeadersV 实例，其调试/展示输出不含对应明文头值，
  且本包提交的 `.snap` 快照与测试输出中不含这些值（FR-013 的验收判据；
  决策 C1-A）。

## Assumptions

- **A1（C1 已核实）**：`@http.CaseInsensitiveString` 在 async 0.22.4 源码中为
  `pub(all)` 且 Eq/Compare/Hash/Show/Debug 均为公开实现，可复用；wasm-gc
  target 维持不支持（`@http` 包进入编译图；M1 亦不建 stub，见 M1 README D9）。
  实施前需在 registry 版 0.22.x 上再核对一次接口（本仓库 `moon.mod` 尚未添加
  `moonbitlang/async` 依赖，属 M1 README §5 前置事项，由本包 plan/implement
  承接）。
- **A2（query 规范化策略）**：种子的「query 原样保留 encoded 串」理解为对齐
  OkHttp 的规范化决策——既有合法 `%XX` 序列保留不二次编码、裸非法字符按
  query 编码集补编码；与 OkHttp 的任何残余差异在实现文档显式记录（宪法 III）。
- **A3（C4 默认）**：path 段采用非惰性表示（YAGNI）；若 plan 阶段评估发现
  每请求解析分配成为热点，再引入惰性化，不在本包 spec 承诺。
- **A4（C5 默认）**：包布局按 M1 README §5 方向——core 值对象入 core 包
  （`src/core` 起步），现有 `src/client` 骨架作门面包起点；确切划分在本包
  plan 阶段定。
- **A5（C3 已澄清）**：错误变体确认为四变体 `InvalidHost` / `InvalidPort` /
  `MalformedUrl` / `UnsupportedScheme`（2026-10-13 用户裁决），原「三变体可增
  scheme」默认被取代。
- **A6**：行为基准为 OkHttp 5.5.0 语义 + RFC 9110/3986；host 末尾点保留、
  IPv6 zone-id 保留均对齐 OkHttp。与 OkHttp 的已裁决差异（宪法 III 显式
  记录）：① userinfo 显式拒绝（OkHttp 支持并保留，M3 回补建模）；② method
  仅九个标准值（OkHttp 接受任意 method token，受 @http 封闭枚举限制）；
  ③ 折叠分隔符取无空格 `","`（对齐 @http 响应侧；OkHttp 发送侧本身不折叠，
  其 `Headers.toString` 展示习惯为 `", "`）。
- **A7（非目标，按种子与用户裁决）**：punycode/IDN（M3）、userinfo 建模
  （Q3-A：M1 拒绝，建模随 M3 回补）、`Method::Custom`（Q2-B：裁剪出 M1，
  需求驱动回补）、`Set-Cookie` 解析与 Cookie 回发（M2）、认证路径多值
  quoted-string 保留（M2，08-auth）、任何网络执行逻辑，均不在本包范围。
- **A8（掩码开关的归属，决策 N4-A）**：本包 MUST NOT 提供包级可变的脱敏开关
  ——可变全局状态会跨测试用例泄漏、在 native/wasm/wasm-gc/js 四目标语义不一致，
  且与宪法 VII 的接口纪律相冲。明文排查只经 FR-013 的显式逃生口方法，且测试
  与 `.snap` 快照不得使用它。「运行期可配置掩码 flag」连同宪法中留待补充的
  「不安全配置 opt-in」条款一起归 **M3**（可观测与安全），登记在
  `docs/roadmap/deferred-items.md`。
