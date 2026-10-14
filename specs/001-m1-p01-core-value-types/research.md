# Research: core 值对象——HttpUrl 与 HeadersV（M1-P01）

**日期**：2026-10-13 ｜ **状态**：全部 NEEDS CLARIFICATION 已解决
**核实基线**：本地 `E:\Project\async`（moon.mod 版本 0.22.4）源码 + 本机
mooncakes registry 索引 + 工具链 core 源码（`moon 0.1.20260920` 自带）。

## R1 依赖钉版：`moonbitlang/async@0.22.4`

- **Decision**：`moon.mod` 新增 `import "moonbitlang/async@0.22.4"`（本包
  首个实现任务；M1 README §5 前置事项）。
- **Rationale**：registry 索引显示 0.22.x 已发布序列为 0.22.0–0.22.4，最新
  0.22.4 发布于 2026-09-24，与本地核实副本（moon.mod `version = "0.22.4"`）
  同版——可行性报告与本文全部接口核实结论对 0.22.4 直接成立。宪法要求钉
  0.22.x，取该线最新版。
- **Alternatives considered**：`0.22.1`（本机缓存已有 zip，但旧两个版本，
  无理由降级）；不钉版本（违反宪法「钉 0.22.x」）；`.mooncakes` 覆盖（宪法
  已明文弃用）。

## R2 `CaseInsensitiveString` 复用（spec C1，关闭 A1 的「待核对」）

- **Decision**：直接复用 `@http.CaseInsensitiveString`，不自建。
- **Rationale**：源码核实（`src/http/case_insensitive_string.mbt:18-52`）：
  `pub(all) struct CaseInsensitiveString(String)`，且 `Eq`/`Compare`/`Debug`/
  `Show`/`Hash` 均为 `pub impl`（Hash 按 ASCII 小写逐 code unit 组合，零分配）。
  HeadersV 的判等/哈希（FR-006）与折叠键（FR-005）可全部复用。
- **Alternatives considered**：自建等价类型（P01 种子 C1 的备选）——仅当
  非 pub 时需要；已排除。注意：自建也不能解除 wasm-gc 阻塞（见 R7）。

## R3 `Method` 与 `@http.RequestMethod` 的关系（spec 裁决 Q2-B）

- **Decision**：moonhttp `Method` 为九值枚举，与 `@http.RequestMethod`
  （`types.mbt:16-26`，Get/Head/Post/Put/Delete/Connect/Options/Trace/Patch）
  一一对应，提供映射函数；不引入 `Custom(String)`。
- **Rationale**：`@http.Client::request(meth : RequestMethod, ...)` 为封闭
  枚举签名（`client.mbt:283-291`），非侵入边界内无法发送任意 method token；
  用户裁决裁剪 `Custom`（OkHttp 接受任意 token 的差异已在 spec A6 记录）。
- **Alternatives considered**：`Custom` 仅建模不可发送（用户已否决）；
  经上游改动开放枚举（违宪 I，须人工批准，不做）。

## R4 derive 组合与零警告配套写法（FR-006/SC-004 前置，决策 M5-A + N1-A）

- **Decision**：值类型（`HttpUrl`/`HeadersV`/`HeadersVBuilder`/`Method`）
  `derive(Eq, Hash, Debug)`，并在其后**紧随显式 `pub extend`** 暴露方法：
  `T with Eq::{not_equal, equal}`、`T with Hash::{hash, hash_combine}`、
  `T with Debug::{to_repr}`；错误类型（`HttpUrlError`/`HeadersError`）
  **仅 `derive(Debug)`**，不 derive `Eq`/`Hash`（判别用 `is` 与模式匹配）；
  **全包不使用 `derive(Show)`**。`HeadersV` 的 Debug 属例外——必须手写
  `impl Debug` 以做脱敏（见 R13）。
- **Rationale**：工具链（`moon 0.1.20260920`）实测三条：① `derive(Eq, Hash,
  Debug)` 生成的是 **impl 而非方法**，按契约写法调用 `a.equal(b)` 或
  `debug_inspect(x)` 会触发 `implicit_impl_as_method` **警告 [0079]**，补上
  `pub extend` 后消除；② `derive(Show)` 直接报 deprecated_syntax **警告
  [0027]**，与 SC-004「零错误零警告」互斥，故弃用（`Show` 是可 readback 的
  源码形态，序列化另有 `ToJson`，本包都不需要）；③ 错误对象不参与池键哈希，
  且 `HttpUrlError::UnsupportedScheme` 若携带 payload，`Eq`/`Hash` 需递归
  derive，属无收益的公开面。`Array` 的 Eq/Hash 实现已核实存在
  （`builtin/array.mbt:293`、`:305`），元组有内建实现，`CaseInsensitiveString`
  见 R2。
- **Alternatives considered**：只 derive、把 SC-004 放宽为「允许 [0079]/[0027]」
  （用户否决——警告与真实问题混流，[0027] 是弃用信号，后续包无法把警告当门禁）；
  全部手写 `impl Eq/Hash/Debug`（零警告且脱敏完全自控，但 HttpUrl 六字段与
  HeadersV 的哈希手写会明显抬高实现量与出错面）。
- **代价与跟踪**：`pub extend` 会把方法名带进 `.mbti`，须并入公开面冻结清单
  逐条核对（宪法 VI「接口变化必须是有意识的决定」）。

## R5 HeadersV 可变性设计（clarify 2026-10-13 Q1）

- **Decision**：不可变 `HeadersV` + 可变 `HeadersVBuilder`（`add`/`set`/
  `remove` 在 Builder，`build()` 产出值；值上 `get`/`values`）。
- **Rationale**：对齐 OkHttp `Headers`/`Headers.Builder` 二分（宪法 III）；
  入池键后哈希恒稳（P04 Address 前提）；MoonBit 中含 `Array` 字段的 struct
  复制会共享底层引用，不可变值语义恰好规避「共享后被改」的哈希失稳风险。
- **Alternatives considered**：单一可变容器（靠约定，风险）；函数式更新
  每次返回新值（无 Builder，热路径分配放大）。

## R6 错误类型、变体规范源与折叠分隔符（specify 裁决 Q1-A/Q3-A + clarify Q2 + 决策 H2-A/L4-A）

- **Decision**：两个错误枚举——`HttpUrlError` 四变体 `InvalidHost`/
  `InvalidPort`/`MalformedUrl`/`UnsupportedScheme`；**新增** `HeadersError`
  两变体 `InvalidName`/`InvalidValue`（承载 FR-012 的头名/头值校验，防头注入）。
  **变体清单的唯一规范源是 `data-model.md` 的错误模型节**，spec/contracts/
  quickstart 只按名引用、不重述分类细节。折叠同名值以无空格 `","` 合并；
  userinfo 显式拒绝（归 `MalformedUrl`）。端口合法区间 `1..=65535`。
- **Rationale**：`@http` 响应侧合并实证为 `"\{v0},\{v}"`（`parser.mbt:285`），
  无空格逗号保证进出对称不变形；四变体让 P06/P07 可按类别判别降级。头校验
  独立成 `HeadersError` 而非并入 `HttpUrlError::MalformedUrl`——后者是 URL
  错误类型，承载头错误语义错位，且下游无法只继承「校验」这一半义务。端口
  区间与上游 priv 守卫 `port is (1..<65536)`（`request.mbt:55-72`）实证一致。
- **Alternatives considered**：`", "`（OkHttp toString 习惯，破坏对称）；
  三/二变体粒度（用户已否决）；userinfo 静默丢弃（破坏 FR-001 往返幂等）；
  头校验并入 `HttpUrlError`（H2-B，语义错位）；不新增类型、只记为范围外
  （H2-C，P02 会把它当已验收能力继承）。

## R7 target 矩阵与 wasm-gc（宪法 V）

- **Decision**：native/wasm 双 target 测试双绿；js `moon check` 通过即可；
  wasm-gc 显式不支持。
- **Rationale**：wasm-gc 阻塞源是 `@http` 包本身未实现（可行性报告 01 §5），
  与本包是否复用 `CaseInsensitiveString` 无关（R2 备选亦不解除）；M1 不建
  stub（M1 README D9）。
- **Alternatives considered**：全 target 纯净（不可达，依赖 @http 即入编译图）。

## R8 query/path 规范化策略（spec A2 落地口径）

- **Decision**：对齐 OkHttp：path 段 percent-decode 后存储、to_string 时按
  path 编码集重编码；query 保留 encoded 形式，既有合法 `%XX` 不二次编码、
  裸非法字符按 query 编码集补编码；fragment 同 query 口径。
- **Rationale**：OkHttp 5.5.0 行为（canonicalize + 不重复编码）；「原样保留」
  种子表述收窄为「不二次编码」已在 spec A2 记录；编码集常量集中放
  `percent.mbt`，与 OkHttp encode set 对拍。公开面命名统一 MoonBit
  snake_case（`to_string`/`default_port`），spec 内的 OkHttp camelCase
  旧称已按决策 L1-A 全量归一。
- **Alternatives considered**：严格原样透传（非法裸字符不编码，偏离 OkHttp
  且与 to_string 重序列化矛盾）。

## R9 OkHttp 测试移植来源与范围（宪法 III/IV）

- **Decision**：移植 OkHttp 5.5.0 `HttpUrlTest`（Apache-2.0）五个用例组：
  畸形输入拒绝、规范化（parsing/lowering/dot-segment）、resolve 相对引用、
  IPv6 literal、percent-encoding；略去组及理由在测试文档列明（预期略去：
  IDN/punycode 组——M1 显式拒绝非 ASCII host；userinfo 组——M1 显式拒绝）。
- **Rationale**：宪法 IV「关键子系统必须移植 OkHttp 对应测试场景对拍」；
  宪法 III 场景复用需注明来源。
- **Alternatives considered**：全量移植（含 M3 范围组，超范围）；仅自增用例
  （不满足宪法 IV 对拍要求）。

## R10 包布局与 `moon.pkg` import 写法（spec A4 落地，决策 L3-A）

- **Decision**：新建 `src/core`，`moon.pkg` 写
  `"import": { "moonbitlang/async/http": { "link": ... } }` 的**目录路径形式**
  ——即 import 项统一为 `moonbitlang/async/http`；描述代码引用时才使用
  `@` 命名空间形式（如 `@http.CaseInsensitiveString`、`@http.Protocol`）。
  `src/client` 门面骨架本包不动。
- **Rationale**：`moon.pkg` 的 import 键是包路径，`@` 前缀只在引用处作命名空间；
  混用会写出非法路径 `"moonbitlang/async/@http"` 而直接报错。宪法分层（门面 →
  core → async）与 M1 README §5 映射不变；P02 的 Request/Response 值对象后续
  并入 `src/core`。
- **Alternatives considered**：并入 `src/client`（违背分层方向）；
  顶层多包拆分（HttpUrl 与 HeadersV 分包——包内聚度高，无必要）；
  统一改成 `@http` 形式（T002 直接执行失败）。

## R11 上游有无可复用的 URL 解析公开面（决策 N2-A 的前提核实）

- **Decision**：**没有**。HttpUrl 的解析、规范化、percent 编解码与 RFC 3986
  resolve 全部由本包自建；上游源码只可「读以参考做法」，MUST NOT 复制
  （宪法 I 禁止 fork/复制/vendor）。
- **Rationale**：核实本地 `E:\Project\async`（与 0.22.4 同源）：`resolve_url`
  （`src/http/request.mbt:36-51`）与 `resolve_host`（`:55-72`）都是 **priv，
  不在 `pkg.generated.mbti`**；能力也远浅于 P01 需求——只按 `://` 与首个 `/`
  切出 `(protocol, host, path)`，不拆 query/fragment、不 percent-decode、
  不消解 `.`/`..`、不剥 IPv6 方括号、不规范化大小写、无 resolve；端口守卫
  `port is (1..<65536)` 同样在 priv 函数里且带 `#cfg(native|wasm)`。公开消费
  边界只有 `Client::Client(uri)`（要求 path 必须为 `/`，只管连接 authority）
  与 `Client::request(meth, path : StringView)`（收已切好的 path）。
- **Alternatives considered**：复用上游私有解析（不可能，非公开面）；
  复制上游实现（违宪 I）；提上游 PR 开放解析能力（属上游改动，须人工批准，
  且 M1 范围不需要）。

## R12 scheme 的类型选型（决策 N2-A，取代 H3 原勾选）

- **Decision**：`HttpUrl::scheme()` 返回上游 `@http.Protocol`（`pub(all) enum
  { Http; Https }`，已 derive `Debug, Eq, Compare, Hash, ToJson`），默认端口
  直接用 `Protocol::default_port`（http=80 / https=443）；本包 **MUST NOT**
  自立 `Scheme` 枚举、**MUST NOT** 重复提供 `default_port(Scheme)` 静态签名。
  若需要便捷入口，至多保留 `HttpUrl::default_port(self) -> Int` 的实例转发。
- **Rationale**：`@http.Client::request` 的签名本就吃 `Protocol`，P02/P04
  必然要映射一次；自立枚举等于 +1 公开类型、+2 映射函数，并让 `default_port`
  出现本包与上游两份真相。封闭枚举的收益（可穷举匹配、无 `String` 弱类型）
  复用上游即可全部拿到，公开面 0 增项。耦合 `@http` 是本包既有事实（宪法 I
  把 async 定为唯一底座），属有意接受而非新增风险。
- **Alternatives considered**：自立 `Scheme { Http; Https }`（N2-B，两份真相）；
  自立 `Scheme { HTTP; HTTPS }`（H3 原勾选，除上述代价外变体名还与上游与
  MoonBit 惯例不一致，文档需额外解释）；`scheme() -> String`（N2-D，弱类型、
  丢失穷举性）。

## R13 脱敏 Debug 的实现路径（决策 C1-A + N4-A）

- **Decision**：`HeadersV` 不用 `derive(Debug)`，改**手写 `impl Debug`**，
  对 `Authorization`/`Proxy-Authorization`/`Cookie`/`Set-Cookie` 四个头名
  （大小写不敏感）的值输出脱敏占位；另提供一个必须主动调用的逃生口方法
  （contracts 建议名 `debug_unredacted`，最终命名实现期定案）输出未脱敏形态，
  仅供特殊排查。脱敏只作用于输出层，判等与哈希仍看原值。
- **Rationale**：宪法「技术约束与合规」的掩码 MUST 明确覆盖**调试输出**，而
  derive 出来的 Debug 会逐条原样打印名/值对，任何一次 `debug_inspect` 或测试
  失败回显都可能把明文写进日志与提交的 `.snap`。`@debug`
  （`moonbitlang/core/debug`）**实测无法作为用户工程依赖 import**（解析失败），
  所以「借用上游脱敏工具」这条路不存在，只能本包手写；`Debug` 在 core 是
  `pub(open) trait Debug { fn to_repr(Self) -> Repr }`
  （`~/.moon/lib/core/debug/debug.mbt:17-20`），open trait 使手写实现合法。
  URL 用户信息一侧由 FR-008 拒绝 userinfo 达成，无明文可泄漏。
- **Alternatives considered**：`redacted_debug()` 之类只读包装而保留 derive 的
  Debug（明文仍在公开面上）；声明本包不适用并把脱敏推给门面层（C1-B，
  `.snap` 仍会落盘明文，宪法在本包实际未满足）；禁止本包用 Debug 快照而
  不改实现（C1-C，规避而非实现）。

## R14 掩码开关的归属（决策 N4-A，欠账 F12）

- **Decision**：本包**不提供**包级可变的脱敏开关。运行期可配置掩码（全局或
  作用域级）连同宪法中留待补充的「不安全配置 opt-in」条款一起归 **M3**
  （可观测与安全：Logger/EventListener 落地时设计），登记为欠账
  **F12**（`docs/roadmap/deferred-items.md` 与其 M1 明细）。
- **Rationale**：包级可变全局状态会跨测试用例泄漏（A 用例关掉掩码会改变 B
  用例的快照）、在 native/wasm/wasm-gc/js 四目标语义不一致，且与宪法 VII
  的接口纪律相冲；而「开发期默认不脱敏」恰恰是 C1 的泄漏面——P01 阶段 Debug
  的主要消费者就是本包自己的测试。真正的需求是「排查那一次要明文」，显式
  逃生口方法已覆盖，无需一个随时可关的总闸。
- **Alternatives considered**：本包提供全局 flag（N4-B，+1 可变公开面）；
  开发期不脱敏、发布前再开（N4-C，等于 C1 重开）；连逃生口也不给（过严，
  特殊排查无路，且宪法并未禁止显式取明文）。
