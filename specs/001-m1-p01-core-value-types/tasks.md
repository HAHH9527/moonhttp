---
description: "M1-P01 core 值对象（HttpUrl 与 HeadersV）任务清单"
---

# Tasks: core 值对象——HttpUrl 与 HeadersV（M1-P01）

**Input**: Design documents from `/specs/001-m1-p01-core-value-types/`

**Prerequisites**: plan.md（布局/钉版/占位定案）、spec.md（US-1–US-4 与
FR-001–FR-013、SC-001–SC-005）、research.md（R1–R14）、data-model.md
（错误变体唯一规范源）、contracts/、quickstart.md（5 步验证）

**Tests**: 本特性**显式要求测试任务**（宪法 IV「验收场景与测试先行」不可妥协：
先写失败测试，再实现，红-绿-重构）。测试锚点直接引用
[contracts/http-url.md](contracts/http-url.md)、[contracts/headers.md](contracts/headers.md)
的「验收锚点」表与 spec Edge Cases（15 条）。

**Organization**: 按用户故事分组（US1 🎯 MVP → US2 → US3 → US4），
US1 与 US3 可并行；US2 依赖 US1，US4 依赖 US3。

**决策口径**（全部取 analysis-report.md 决策登记表 A 项）：C1-A / H1-A / H2-A /
H3→N2-A / M1-A / M2-A / M3-A / M4（plan V 行不动）/ M5→N1-A / M6-A / L1-A /
L2-A / L3-A / L4-A / L5-A / L6-A / N3-A / N4-A。

## Format: `[ID] [P?] [Story] Description`

- **[P]**: 可并行（不同文件、无未完成依赖）
- **[Story]**: 归属用户故事（US1–US4）
- 所有路径相对仓库根

## Path Conventions

单项目：`src/core/`（本包新建）、`src/client/`（既有门面骨架，本包不动）。
MoonBit 惯例：黑盒测试 `*_test.mbt`、白盒测试 `*_wbtest.mbt`、每包
`moon.pkg`、生成接口 `.mbti`。

**derive 配套写法（贯穿全部实现任务，决策 N1-A + M5-A）**：值类型
`derive(Eq, Hash, Debug)` 后**紧随**三行 `pub extend T with
Eq::{not_equal, equal}` / `Hash::{hash, hash_combine}` / `Debug::{to_repr}`，
以消除 `implicit_impl_as_method` 警告 [0079]；错误类型**仅** `derive(Debug)`，
不 derive `Eq`/`Hash`；全包**不使用** `derive(Show)`（工具链报 deprecated_syntax
[0027]）。唯一例外：`HeadersV` 的 `Debug` 手写 `impl Debug` 以做脱敏（决策 C1-A）。

---

## Phase 1: Setup（共享基础设施）

**Purpose**: 依赖钉版与 core 包落地

- [ ] T001 在 `moon.mod` 声明依赖 `"moonbitlang/async@0.22.4"`（执行
  `moon add moonbitlang/async@0.22.4`，或手动填充 import 块后 `moon update`
  拉取），`moon check` 确认依赖解析成功（research R1；M1 README §5 前置）
- [ ] T002 [P] 新建 `src/core/moon.pkg`：`import { "moonbitlang/async/http" }`
  + `pkgtype(kind: "library")`（research R10 + 决策 L3-A：**import 键写包路径
  `moonbitlang/async/http`，`@` 只出现在代码引用处**，如
  `@http.CaseInsensitiveString`；写成 `"moonbitlang/async/@http"` 是非法路径）。
  按决策 L5-A **不预先放置空的 `error.mbt` 占位**——空包不触发 `moon check`
  报错，`error.mbt` 由 T003 直接创建（plan.md「初始化与占位」定案）

---

## Phase 2: Foundational（阻塞性前置）

**Purpose**: 全部故事共享的错误/方法类型；不依赖任何故事实现

**⚠️ CRITICAL**: US1–US4 均依赖本阶段完成

- [ ] T003 [P] 在 `src/core/error.mbt` 定义 `pub enum HttpUrlError {
  InvalidHost; InvalidPort; MalformedUrl; UnsupportedScheme }`
  **仅 `derive(Debug)`**（不 derive `Eq`/`Hash`，不用 `Show`——决策 M5-A/N1-A）；
  变体触发条件以 [data-model.md §4.1](data-model.md) 为**唯一规范源**
  （决策 L4-A，本文件与 contracts 只引用不重述），当前口径：`InvalidHost`＝
  host 非法/非 ASCII/IPv6 括号畸形；`InvalidPort`＝端口不在 `1..=65535`
  （**含 `http://h:0/` 与 `http://h:65536/`**，决策 M1-A）或非数字；
  `MalformedUrl`＝空串/缺 scheme/缺 host/含 userinfo（显式拒绝）；
  `UnsupportedScheme`＝非 http/https。错误消息中文优先（宪法 VII），只携带
  定位片段、不整体回显原始输入。同文件定义
  `pub enum HeadersError { InvalidName; InvalidValue }` **仅 `derive(Debug)`**
  （决策 H2-A：独立小枚举，method-error.md 的 a/b 二选一就此关闭）
- [ ] T004 [P] 在 `src/core/method.mbt` 定义 `Method` 九值枚举（Get/Post/
  Put/Delete/Head/Options/Trace/Patch/Connect）`derive(Eq, Hash, Debug)` +
  **紧随三行 `pub extend`**（决策 N1-A，不用 `Show`）；实现
  `to_request_method` / `from_request_method` 与 `@http.RequestMethod`
  一一对应的双向封闭映射（无失败分支，FR-007）
- [ ] T005 [P] 在 `src/core/method_error_test.mbt` 写失败测试：九值映射往返
  断言（`from(to(m)) == m` 对九值穷举）；`HttpUrlError`/`HeadersError` 变体
  可判别断言（`assert_true(e is HttpUrlError::InvalidHost)` 风格，错误不判等）；
  两错误枚举的 `debug_inspect` 输出形态断言；顺带确认本文件 `moon check`
  无 [0079]/[0027] 警告

**Checkpoint**: 基础类型就绪，US1/US3 可并行开工

---

## Phase 3: User Story 1 - HttpUrl 解析与规范化（Priority: P1）🎯 MVP

**Goal**: 传入 URL 字符串得到规范化可比较的 HttpUrl；畸形输入得到可判别
HttpUrlError 而非 panic（spec US-1、FR-001/002/003/009/010）

**Independent Test**: 纯函数 `moon test --target native` 断言解析与
`to_string`；无需网络

### Tests for User Story 1（先写、先失败）

- [ ] T006 [P] [US1] 在 `src/core/http_url_parse_test.mbt` 写失败测试：
  ① spec US-1 场景 1–5（`http://Example.COM:80/a/./b/../c?x=1#frag` →
  `http://example.com/a/c?x=1#frag`；`http://[::1]:8080/x` host=`::1`
  port=8080；`http://bad host/`、`http://host:notaport/` raise 可判别；
  非 ASCII host → `InvalidHost`；往返幂等 `parse(to_string(parse(s))) ==
  parse(s)`）；② spec Edge Cases 全部 **15 条**（含决策 M1-A 的
  `http://h:0/` 与 `http://h:65536/` → `InvalidPort`；空串/仅 scheme/仅 host →
  `MalformedUrl`；path 空规范化为 `/`；query 保留字符与 `%XX` 不二次编码；
  fragment `None` 与空串可区分；IPv6 畸形括号报错、zone-id 保留；host 末尾点
  `a.com.` 保留；重复 query 键保留；`ftp://` → `UnsupportedScheme`；
  userinfo → `MalformedUrl`；其余头相关两条与脱敏一条归 T013）；
  ③ OkHttp `HttpUrlTest` 畸形输入组与规范化组移植（来源注释见 T017）。
  断言优先 `assert_eq`
- [ ] T007 [P] [US1] 在 `src/core/percent_wbtest.mbt` 写失败白盒测试：
  percent-decode/encode 的 path 段、query、fragment 三口径（合法 `%XX`
  保留不二次编码、裸非法字符按对应编码集补编码，research R8）。该文件名
  与 plan.md 源码清单一致（决策 M3-A）

### Implementation for User Story 1

- [ ] T008 [US1] 在 `src/core/percent.mbt` 实现编码集常量与
  percent-decode/percent-encode（priv；对齐 OkHttp encode set，R8）
- [ ] T009 [US1] 在 `src/core/http_url.mbt` 实现 `HttpUrl`：六字段（scheme
  **类型为 `@http.Protocol`**，本包**不自立 `Scheme` 枚举**、**不提供
  `default_port(scheme)` 静态函数**——默认端口真相用上游
  `@http.Protocol::default_port`（http=80/https=443），如需便捷入口只在
  `.mbti` 冻结时决定是否加实例转发（决策 N2-A + H3，FR-002）；host 已 decode、
  ASCII、小写、IPv6 剥方括号存储含 `:` 与可选 zone-id、末尾点保留；port
  `1..=65535` 缺省填 scheme 默认值；path_segments 已 decode、无 `.`/`..`/空段、
  空序列=根路径；query/fragment 保留 encoded 形式且 `None`/空串可区分——
  data-model §1 不变量逐条落实）+ `derive(Eq, Hash, Debug)` + 紧随三行
  `pub extend`；`parse` 单遍 O(n) 落实六条验证规则（全部 raise 拒收、绝不 panic）；
  `to_string`（snake_case，决策 L1-A；默认端口省略、path 重建以 `/` 起始、
  `None` 不输出 `?`/`#`）；访问器 scheme/host/port/path_segments/query/fragment
- [ ] T010 [US1] 运行 `moon test --target native`：US-1 全部断言由红转绿；
  `moon fmt` 格式化本阶段改动

**Checkpoint**: US1 独立可用（MVP 达成：parse/to_string/访问器/错误判别）

---

## Phase 4: User Story 2 - 相对引用解析 resolve（Priority: P1）

**Goal**: `HttpUrl::resolve(base, location)` 把 Location 值解析为绝对 URL
（spec US-2、FR-002）

**Independent Test**: 纯函数断言（OkHttp resolve 组移植），无需网络

### Tests for User Story 2（先写、先失败）

- [ ] T011 [P] [US2] 在 `src/core/http_url_resolve_test.mbt` 写失败测试：
  base `http://a.com/dir/page` + `"../up"` → `http://a.com/up`；+ `"/root"`
  → `http://a.com/root`；+ `"//b.com/x"` → `http://b.com/x`（scheme 继承）；
  绝对 location 直接 parse；空 location → base 去 fragment（对齐 OkHttp）；
  非法 location raise `HttpUrlError`；**并补决策 L6-A 的三条分支锚点**：
  query-only 参考 `"?x=1"` → `http://a.com/dir/page?x=1`（fragment 丢弃）、
  仅 fragment 参考 `"#f"` → `http://a.com/dir/page#f`（path/query 保持）、
  base 无 path（`http://a.com` + `"../up"`）→ `http://a.com/up`；
  OkHttp resolve 测试组移植

### Implementation for User Story 2

- [ ] T012 [US2] 在 `src/core/resolve.mbt` 实现 RFC 3986 §5 相对引用合并：
  复用已解析 base、O(增量)；覆盖 T011 的全部分支（含 query-only、仅 fragment、
  base 无 path）；空串返回 base 去 fragment（contracts/http-url.md）

**Checkpoint**: US1+US2 均独立可用（重定向地基就绪）

---

## Phase 5: User Story 3 - HeadersV 操作语义（Priority: P1）

**Goal**: 不可变有序多头容器 + 可变 Builder（含头名校验）+ 默认脱敏的调试
输出（spec US-3、FR-004/006/012/013）

**Independent Test**: 纯容器语义单测，无 IO

### Tests for User Story 3（先写、先失败）

- [ ] T013 [P] [US3] 在 `src/core/headers_test.mbt` 写失败测试：Builder
  `add("Accept","a")`+`add("Accept","b")` 后 build，值上
  `values("accept")` **先收集为数组**再断言 `["a","b"]`（决策 M2-A：
  `values` 返回保序 `Iter[String]`、不折叠，迭代器本身不作断言对象）、
  `get("ACCEPT")`=`"a"`（大小写不敏感、保插入序）；`set("Accept","c")` 后
  同名仅剩一条；`remove` 删全部同名；两次相同顺序构造相同列表 → 相等且
  哈希一致（供 P04 池键）；**头校验（FR-012，决策 H2-A）**：`add("Bad Name","v")`
  （含空格）/ 空名 / 含 `:` 等非 RFC 9110 token 字符 → raise
  `HeadersError::InvalidName`；`add("X","a\r\nY: 1")`（值含 CR/LF）→ raise
  `HeadersError::InvalidValue`；两者违例后**容器不变**；`remove("Bad Name")`
  对非法名**静默无操作、不 raise**；值为空串的头合法保留；
  **脱敏（FR-013/SC-005，决策 C1-A）**：`add("Authorization","Bearer secret")`
  → build → 调试输出含头名与脱敏占位、**不含** `Bearer secret`，
  同一容器判等/哈希不受脱敏影响；对 `Proxy-Authorization`/`Cookie`/
  `Set-Cookie` 各写一条同类断言。本文件 **MUST NOT 调用脱敏逃生口**（N4-A）

### Implementation for User Story 3

- [ ] T014 [US3] 在 `src/core/headers.mbt` 实现 `HeadersV`（不可变，底层
  `Array[(CaseInsensitiveString, String)]`，复用 `@http.CaseInsensitiveString`
  ——research R2）：`derive(Eq, Hash)` + 紧随 `pub extend` 配套，但 **`Debug`
  走手写 `impl Debug for HeadersV with to_repr(self, h)`**（不 derive，否则
  逐条原样打印名/值对——research R13；`@debug` 实测不可作用户工程依赖）；
  手写实现对 `Authorization`/`Proxy-Authorization`/`Cookie`/`Set-Cookie`
  （名字大小写不敏感匹配）输出脱敏占位，其余头名/值原样输出，脱敏只在输出层
  （判等/哈希看原值）；同时提供**显式逃生口方法**（建议名
  `debug_unredacted(self) -> String`，最终命名在 `.mbti` 冻结时定案），
  **MUST NOT 引入包级可变掩码开关**（决策 N4-A，可配置开关归 M3 欠账 F12）；
  `HeadersVBuilder`（`add`/`set` 带 FR-012 校验并 raise、`remove` 静默、
  `build`；`derive(Eq, Hash, Debug)` + `pub extend`）；值上 `get`（首个）/
  `values`（保序 `Iter[String]`，不折叠）

**Checkpoint**: US1/US2/US3 均独立可用

---

## Phase 6: User Story 4 - 边界折叠转换（Priority: P2）

**Goal**: HeadersV → `@http.Headers` 折叠（同名无空格逗号合并）
（spec US-4、FR-005）

**Independent Test**: 纯函数断言折叠结果

### Tests for User Story 4（先写、先失败）

- [ ] T015 [P] [US4] 在 `src/core/headers_fold_test.mbt` 写失败测试，按
  SC-003 的**两个可满足不变量**组织（决策 H1-A，原「折叠后 `get` 首个语义不变」
  已弃用）：① **无重复名**——生成名字唯一的头列表（`@property` 不可用时以
  种子随机+循环），折叠后每个名字的 `get` 值与折叠前逐字节相等（恒等映射）；
  ② **有重复名**——`X-Multi: a` + `X-Multi: b` 折叠为单值 `"a,b"`（无空格，
  与 @http 响应侧 `parser.mbt` 的 `"\{v0},\{v}"` 逐字节对称），并断言该串经
  响应侧拆分可**还原**原名值序列（进出互逆）；另断言空容器折叠为空 Map、
  值为空串的头折叠后值为空串。文件头注释显式声明「折叠不保证 quoted-string
  边界（如 `WWW-Authenticate: Basic realm="a, b"`），认证路径 M2 绕过」——
  US-4 场景 2 的文档承诺落在代码注释。本文件 **MUST NOT 使用脱敏逃生口**

### Implementation for User Story 4

- [ ] T016 [US4] 在 `src/core/headers.mbt` 增 `to_http_map() ->
  @http.Headers`：遍历序列、同名值以 `","` 无空格合并（FR-005，specify
  裁决 Q1-A），满足 T015 的两个不变量

**Checkpoint**: 全部用户故事独立可用

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: 对拍清单、质量门、零明文泄漏验收与提交（宪法「合入前质量门」）

- [ ] T017 [P] 在 `src/core/http_url_parse_test.mbt` 头部注释固化 OkHttp
  移植对拍清单（SC-002，research R9）：移植组=畸形输入/规范化/resolve/
  IPv6/percent-encoding；略去组=IDN（M1 显式拒绝非 ASCII host）、
  userinfo（M1 显式拒绝）；resolve 组须列明 T011 的三条补充锚点
  （query-only / 仅 fragment / base 无 path，决策 L6-A）；来源注明
  `OkHttp 5.5.0 HttpUrlTest (Apache-2.0)`（宪法 III 署名合规）
- [ ] T018 质量门收口（quickstart.md 5 步全跑）：`moon check` 四目标
  **零错误零警告**（SC-004：verify `pub extend` 已消除 [0079]、全包无
  `derive(Show)` 残留 [0027]）；`moon info && moon fmt` 干净；逐条审视
  `src/core/pkg.generated.mbti` 公开面＝HttpUrl/HeadersV/HeadersVBuilder/
  Method + HttpUrlError/HeadersError + parse/resolve/to_string/访问器/
  get/values/set/add/remove/build/to_http_map + **derive 配套的 `pub extend`
  方法与脱敏逃生口**（新入清单须逐条确认），并确认**不含**自立 `Scheme`
  枚举与包级掩码开关（决策 N2-A/N4-A，SC-004/宪法 VI）；
  `moon test --target native` 与 `moon test --target wasm` 双绿；
  `moon check --target js` 通过（SC-001）
- [ ] T019 [P] SC-005 脱敏零明文泄漏验收：`git grep` 扫描 `src/core/**` 的
  `.snap` 快照与测试源码，确认 `Authorization`/`Proxy-Authorization`/
  `Cookie`/`Set-Cookie` 的示例明文值（如测试里的 `Bearer secret`）**未**出现在
  任何 `.snap` 中；确认测试与快照均未调用逃生口方法；发现泄漏即修断言/改手写
  `impl Debug`，不得以「删除该测试」了事
- [ ] T020 宪法合规自查（非侵入/测试先行/target 矩阵/中文文档/敏感信息掩码
  逐项核对 plan.md Constitution Check 表，含「技术约束与合规」行）后以
  Conventional Commits（中文描述）提交本包全部改动，汇报中列明 commit 范围

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup（Phase 1）**: 无依赖，立即开始
- **Foundational（Phase 2）**: 依赖 Phase 1；阻塞全部故事
  （T003 阻塞 US1/US2，`HeadersError` 部分阻塞 US3）
- **User Stories（Phase 3–6）**: 依赖 Phase 2
- **Polish（Phase 7）**: 依赖全部故事完成

### User Story Dependencies

- **US1（P1）**: 依赖 T003/T008——无跨故事依赖（MVP）
- **US2（P1）**: 依赖 US1（resolve 复用 parse 产物与 HttpUrl 构造）
- **US3（P1）**: 仅依赖 T003（HeadersError）——与 US1 完全并行
- **US4（P2）**: 依赖 US3（折叠作用于 HeadersV）

### Within Each User Story

- 测试任务先写并确认失败（红），再实现（绿），后 `moon fmt`（重构）
- percent.mbt（T008）先于 http_url.mbt（T009）；error.mbt（T003）先于两者
- T013 的脱敏断言与 T014 的手写 `impl Debug` 构成红-绿对
- T016 与 T014 同文件（`headers.mbt`），**不可并行**，顺序在 T014 之后

### Parallel Opportunities

- Phase 1：T001 与 T002 可并行（不同文件）
- Phase 2：T003 ∥ T004（T005 随后，三个文件互相独立）
- Phase 2 完成后：**US1 全线 ∥ US3 全线**（不同文件集，见下例）
- US1 内：T006 ∥ T007（不同测试文件）
- US2 与 US3/US4 在 US1 完成后可与 US3 并行
- Phase 7：T017、T019 可与 T018 的跑测部分并行（不同文件）

---

## Parallel Example: US1 ∥ US3

```text
开发者/会话 A（US1）:                开发者/会话 B（US3）:
T006 http_url_parse_test.mbt         T013 headers_test.mbt
T007 percent_wbtest.mbt              （红）
（红）                                T014 headers.mbt
T008 percent.mbt                     （绿：含手写 impl Debug 脱敏）
T009 http_url.mbt
（绿）                                T015 headers_fold_test.mbt（红）
T010 moon test 验证                   T016 to_http_map（绿）→ 转 US2
```

---

## Implementation Strategy

### MVP First（User Story 1 Only）

1. Phase 1（依赖钉版 + moon.pkg，import 键 `moonbitlang/async/http`）
   → Phase 2（error/method 基础类型，错误仅 Debug）
2. Phase 3（US1：parse/to_string/访问器/错误判别，scheme 用 `@http.Protocol`）
3. **STOP and VALIDATE**：`moon test --target native` US-1 断言全绿
   ——此刻已可向 P02/P04 消费方演示 HttpUrl 地基

### Incremental Delivery

1. Setup + Foundational → 基础就绪
2. +US1 → 独立验证（MVP！）
3. +US2（依赖 US1）与 +US3（并行，含 FR-012 校验与 FR-013 脱敏）→ 各自独立验证
4. +US4（依赖 US3）→ 独立验证（SC-003 两不变量）
5. Polish：对拍清单、质量门、零明文泄漏验收、提交

### Parallel Team Strategy

- A：US1 → US2；B：US3 → US4；Phase 7 由最后完成者收口

---

## Notes

- [P] = 不同文件且无未完成依赖
- [Story] 标签对应 spec.md 用户故事，便于追溯
- 每个故事先写失败测试再实现（宪法 IV）；断言优先 `assert_eq`
- 术语统一 snake_case（`to_string`/`default_port`，决策 L1-A）；OkHttp 的
  Java 方法名只出现在对拍清单注释里
- 每个任务或逻辑组完成后 `moon fmt`；Checkpoint 处验证独立可测性
- 禁止触碰 `src/client/`（本包范围外）；禁止改动上游 async 任何内容（宪法 I）
- 完成判据以 quickstart.md「通过判据」为准（SC-001–SC-005）
- **留待下一轮 analyze 复核的一处口径**：`HeadersVBuilder` 按 FR-006 参与
  `derive(Debug)`，而 FR-013 的脱敏承诺只绑定 `HeadersV`——Builder 的调试输出
  是否构成脱敏旁路，spec/契约未表态；本清单按现有产物照写，不擅自扩大或收窄
  FR-013 范围（改口径须回 spec 走命令链）
