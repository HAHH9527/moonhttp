# P01 core 值对象：HttpUrl 与 HeadersV

> 里程碑：M1 性能核心 ｜ 前置依赖：无 ｜ 人力估计：~2.75 人日
> 来源：`proj-init-docs/okhttp-on-async-http/01-calls/README.md` §2/§3.2/§3.4/§8
> 侵入性：非侵入（目标：仅 `@http` 公开 API；见澄清种子 C1） ｜ 建议特性 slug：`m1-p01-core-value-types`

## 功能描述（speckit 输入种子）

在 moonbitlang/async 之上新建 moonhttp 的 core 值对象层，交付两块纯数据能力：
（1）**HttpUrl**——对齐 OkHttp `HttpUrl.parse` 语义的 URL 解析、规范化、相对引用解析
（`resolve`）与序列化，支撑后续重定向、缓存与 cookie 的 path/query 级操作
（async/http 现有 `resolve_url` 只做 `protocol://host[:port]/path` 顶层切分，无
query/fragment/percent-encoding/IPv6-literal 处理，证据 `01 §2` 表）；
（2）**HeadersV**——有序、允许重复名的请求头容器，及向 `@http`
`Map[CaseInsensitiveString, String]` 的边界折叠转换。本包不含任何 IO 与执行逻辑。

## 范围

包含：

- `HttpUrl`：scheme/host/port/path_segments/query/fragment 模型；解析与规范化规则对齐
  OkHttp（`.`/`..` 段消解、空段压缩、path 以 `/` 开头、scheme/host 小写规范化、
  `port == defaultPort` 时 toString 省略端口）；`resolve(base, ref)` 相对引用解析；
  percent-encode/decode（query 原样保留 encoded 串，OkHttp 同款决策）；
  IPv6 literal `[::1]:8080` 解析（使用侧需先剥括号再传 `Client::connect`）；
  非 ASCII host（IDN）M1 拒绝并 raise `HttpUrlError::InvalidHost`（punycode 随 M3 补）。
- `HeadersV`：`Array[(CaseInsensitiveString, String)]` 存储；`get`（首个）/
  `values`/`set`（覆盖全部同名）/`add`/`remove`；`to_http_map` 边界折叠
  （同名逗号合并，与 `@http` 响应侧 `parser.mbt:283-286` 语义对称）。
- `Method` enum（Get/Post/… + `Custom(String)`，大小写语义对齐 OkHttp）。
- 错误类型：`HttpUrlError`（`InvalidHost`/`InvalidPort`/`MalformedUrl` 等，clarify 定）。

非目标（显式排除）：

- punycode/IDN 支持（M3）；userinfo（用户名/密码）建模——见澄清种子 C2；
- `Set-Cookie` 解析与 Cookie 头自动回发（M2，11-cookies）；
- 认证路径的多值 quoted-string 保留（M2，08-auth；本包仅在文档注明折叠例外条款）；
- 任何网络执行、连接、发送逻辑。

## 用户故事种子

### US-1 HttpUrl 解析与规范化（P1）

作为库使用者，我传入 URL 字符串，得到规范化、可比较的 `HttpUrl` 值，
畸形输入得到明确的 `HttpUrlError` 而非 panic 或静默容忍。

**独立测试**：纯函数，`moon test` 直接断言，无需网络。

**验收场景**：

1. Given `"http://Example.COM:80/a/./b/../c?x=1#frag"`，When parse+toString，
   Then 得到 `"http://example.com/a/c?x=1#frag"`（小写、点段消解、默认端口省略）。
2. Given `"http://[::1]:8080/x"`，When parse，Then host 为剥括号的 `"::1"`、port 为 8080。
3. Given `"http://bad host/"`、`"http://host:notaport/"`，When parse，
   Then raise `HttpUrlError`（类型可判别）。
4. Given 含非 ASCII host 的 URL，When parse，Then raise `HttpUrlError::InvalidHost`。

### US-2 相对引用解析 resolve（P1）

作为重定向/缓存特性的下游使用者，我用 `HttpUrl::resolve(base, location)`
把 `Location` 值解析为绝对 URL（相对/绝对/网络路径参考均可）。

**独立测试**：纯函数断言（OkHttp HttpUrl.resolve 测试组移植）。

**验收场景**：

1. Given base `http://a.com/dir/page` 与 `"../up"`，Then 结果 `http://a.com/up`。
2. Given base 与 `"/root"`，Then `http://a.com/root`；与 `"//b.com/x"`，
   Then `http://b.com/x`（scheme 继承）。
3. Given 非法 location，Then raise（由 P06 决定外层降级为「返回原响应」）。

### US-3 HeadersV 操作语义（P1）

作为库使用者，我以 OkHttp 语义操作有序头：`set` 覆盖全部同名、`add` 追加、
`get` 取首个、`values` 保序遍历、`remove` 删全部同名。

**验收场景**：

1. Given `add("Accept","a")` + `add("Accept","b")`，Then `values("accept")` 为
   `[a, b]`（大小写不敏感、保插入序）、`get` 返回 `"a"`。
2. When `set("Accept","c")`，Then 同名仅剩一条 `"c"`。
3. 两次构造相同头列表，Then 相等且 Hash 一致（供 P04 Address 键使用）。

### US-4 边界折叠转换（P2）

作为执行管线的下游使用者（P02/P05），我把 `HeadersV` 折叠为
`Map[CaseInsensitiveString, String]`（同名逗号合并）传入 `@http`。

**验收场景**：

1. Given 两条 `X-Multi: a` / `X-Multi: b`，Then Map 中单值 `"a, b"`。
2. Given 值内含 quoted-string 逗号（如 `WWW-Authenticate: Basic realm="a, b"`），
   Then 折叠产生的字符串语义在文档中显式声明为「不保证 quoted-string 边界」，
   认证路径未来绕过此转换（M2，08）。

## 边界用例

- 空串/仅 scheme/仅 host 的 URL；port 越界（<0 或 >65535）；path 为空（规范化为 `/`）；
- query 含保留字符与百分号序列（原样保留，不二次编码）；fragment 为 None/空串区分；
- IPv6 带_zone_ 或畸形括号；host 末尾点（`a.com.`）；重复 query 键（原样保留）；
- HeadersV 空容器折叠为空 Map；值为空串的头。

## 需求种子

- **FR-001** HttpUrl MUST 实现解析/toString 双向，往返幂等（parse∘toString 不变形）。
- **FR-002** HttpUrl MUST 提供 `resolve`、`defaultPort`（http=80/https=443）、
  scheme/host/port/path/query/fragment 访问器。
- **FR-003** 非 ASCII host MUST raise `HttpUrlError::InvalidHost`（M1 范围）。
- **FR-004** HeadersV MUST 保插入序、大小写不敏感比较、支持重复名。
- **FR-005** HeadersV→Map 折叠 MUST 与 @http 响应侧合并语义对称（逗号合并）。
- **FR-006** 全部类型 MUST 可 derive(Eq/Hash/Debug 相应组合) 供 P04 池键使用。

## 关键设计要点

- 结构照 `01 §3.2/§3.4`：`HttpUrl` 六字段（query 保留 encoded 原串）；
  `HeadersV` 底层 `Array[(CaseInsensitiveString, String)]`。
- 解析每请求一次 O(n)；`resolve` 复用已解析 base，O(增量)。
- 排序稳定性是后续「同 URL + 同头序」的缓存 Vary 键与重放字节级一致的前提（01 §3.4）。

## 侵入性与宪法合规

- 无侵入。C1（见下）若判定 `@http.CaseInsensitiveString` 非 pub，则自建等价类型
  （零分配比较/哈希，`case_insensitive_string.mbt:21-52` 手法），仍非侵入。
- 宪法 III：与 OkHttp 的差异（IDN 拒绝、userinfo 处理）在 spec 显式记录。
- OkHttp HttpUrl 测试矩阵移植属 Apache-2.0 场景复用，spec 中注明来源（宪法 III）。
- 宪法 v1.2.0「敏感信息默认不展示」（:112-117）在本包的落地面（2026-10-14 第三轮
  裁决 R3-H1-A/R3-M1）：P01 **不含脱敏**——全部公开类型 `derive(Debug)` 默认实现
  （明文输出，走宪法展示例外程序，人工确认留痕＝分析报告 R3-M1 与 plan「例外
  跟踪」节），测试与 `.snap` 样例值须为合成占位串；SC-005 判据为输出面三项核对。
  **URL userinfo** 仍结构性拒绝（FR-008，不因脱敏延后撤销）。脱敏专版登记为
  **F13**、可配置开关登记为 **F12**，均归 M3（`docs/roadmap/deferred-items.md`）。

## target 矩阵

| target | 支持 | 说明 |
| --- | :-: | --- |
| native / wasm | ✅ | 纯值对象，无 IO；宪法 v1.2.0 验证面（check 零错误零警告 + 双 target test 全绿） |
| js | ⏸ 暂不验证 | 宪法 v1.2.0 原则 V（:67-77）：M5 前不在验证面，显式标注 + 欠账跟踪（F9） |
| wasm-gc | ❌ | 复用 `@http.CaseInsensitiveString`（C1 已定）带入编译图；M5 前不建 stub（宪法 :75-76） |

## 性能影响

比较/哈希零分配（CaseInsensitiveString 手法）；解析 O(n)；无热路径分配放大风险。
本包无基准要求（宪法 II 的性能数据要求由 P10 汇总覆盖）。

## 测试方案

- HttpUrl：移植 OkHttp `HttpUrlTest` 场景矩阵（畸形输入、规范化、resolve、IPv6、
  percent-encoding），`assert_eq` 风格；自增中文/边界用例。
- HeadersV：语义单测 + 折叠属性测试（两个可满足不变量：无重复名折叠为恒等映射；
  有重复名按插入序 `,` 无空格拼接且进出互逆——决策 H1-A）。
- native + wasm 双 target `moon test` 全绿。

## 澄清问题种子（clarify 输入）

- **C1** `@http.CaseInsensitiveString` 是否 pub 可复用？（01 §3.4 称复用；
  需在 spec 阶段对 0.22.x 实际接口核实；非 pub 则自建。）
- **C2** URL userinfo（`user:pass@host`）：丢弃、拒绝、还是建模？
  （01 §3.2 结构未含；涉及宪法「敏感信息掩码」条款的 URL 用户信息项。）
- **C3** `HttpUrlError` 的变体粒度（仅 InvalidHost 还是细分 InvalidPort/Malformed）。
- **C4** `path_segments` 是否需要惰性化以避免热路径分配（每请求一次解析的分配量级）。
- **C5** 包布局：core 包路径（`src/core`）与门面包的划分起点。

## 验收判据（包级 DoD）

1. 上述 US-1–US-4 验收场景全部有测试且 `moon test --target native` 与
   `--target wasm` 双绿；js/wasm-gc 依宪法 v1.2.0「暂不验证」（挂欠账 F9，
   M5 收口），不作本包门禁。
2. OkHttp HttpUrl 测试矩阵移植清单在 spec 中列明（移植了哪些组、略了哪些及理由）。
3. `moon info && moon fmt` 干净，`.mbti` 冻结 core 值对象公开面并经审视。

## 参考

- `proj-init-docs/okhttp-on-async-http/01-calls/README.md` §2（现状证据表）、
  §3.2（HttpUrl）、§3.4（HeadersV）、§8（测试方案）。
- 下游引用方：P02（Request/Response）、P04（Address 键）、P06（Location resolve）。
