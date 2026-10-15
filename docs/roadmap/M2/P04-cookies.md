# P04 CookieJar（Cookie 存储/匹配/回发/Expires 解析/持久化）

> 里程碑：M2 完整门面 ｜ 前置依赖：M2-P03（Bridge 接线挂点）、M1-P01（HttpUrl）
> ｜ 人力估计：~3.5 人日
> 来源：`proj-init-docs/okhttp-on-async-http/11-cookies/README.md` §1–§8
> 侵入性：非侵入（I7 expires 预解析 PR 不做，自带解析器）
> ｜ 建议特性 slug：`m2-p04-cookies`

## 功能描述（speckit 输入种子）

为 moonhttp 交付 OkHttp `CookieJar` 能力面：`CookieJar` 接口（函数字段，
`save_from_response`/`load_for_request`）挂 `HttpClient`；库内置
`InMemoryCookieJar`（域规范化、host-only vs 域 cookie、RFC 6265 path 前缀
匹配、secure 限制、Max-Age 优先于 Expires 的过期判定、同 (name,domain,path)
覆盖、总量上限 LRU）；**Expires 三格式宽容解析器**（RFC 1123 / RFC 850 /
asctime，~120 行——底座 `expires_raw` 只存原串）；客户端 `Cookie` 头序列化
（path 长度降序、同长按创建时间升序，RFC 6265 §5.4）；Bridge 层接线
（请求前注入、响应与重定向中间响应回存）；可选 `FileCookieJar` 持久化
（JSON Lines、启动全量载入、变更防抖落盘）。

## 范围

包含：

- `CookieJar` 接口与 `HttpClient` 挂接（底座 `Cookie::parse`/`Response.cookies`
  已有，零侵入复用）。
- `InMemoryCookieJar`：存储 `Map[domain key, Array[CookieEntry]]`；最小公共
  后缀黑名单（~30 项：com/org/net/edu/gov/io/co/...，okhttp 无 PSL 的黑名单
  近制同款）。
- Expires 三格式解析器（失败 → 会话 cookie，不持久化）。
- 客户端 Cookie 头序列化（RFC 6265 §5.4 顺序；值不编码）。
- M2-P03 Bridge 层接线：`load_for_request` 非空且请求未显式设置 Cookie 头时
  注入；响应（含重定向中间响应）`save_from_response`。
- `FileCookieJar(path)`（可选组件）：JSONL 序列化（补 `host_only`/`expires_at`
  计算值字段）、防抖 1s 异步落盘、启动全量载入。

非目标（显式排除）：

- I7 expires 预解析上游 PR 的提交（材料可随 M2-P07 评估，默认不做——L1 自带
  解析器已闭环）；
- PSL（公共后缀表）完整实现（黑名单近似为终态口径，差异显式记录）；
- 持久化的加密/并发多进程协调（对齐生态实现水准即可）；
- js 后端 Jar 的 save 侧能力（浏览器禁读 `Response.cookies`，恒空）。

## 用户故事种子

### US-1 Jar 接口与内存 Jar 基本流（P1）

作为使用者，我配置 `InMemoryCookieJar` 后，Set-Cookie 自动存储、后续请求
自动携带。

**独立测试**：P03 夹具 Set-Cookie 脚本路由；不依赖 P05/P06/P07。

**验收场景**：

1. Given 服务端 `Set-Cookie: a=1; Path=/`，When 首次请求，Then 无 Cookie 头；
   响应后再次请求，Then 自动携带 `Cookie: a=1`。
2. Given 同 (name,domain,path) 新 Set-Cookie，When 再次请求，Then 旧值被覆盖。
3. Given 无 Jar 配置，When 请求带 Set-Cookie 响应，Then 行为与 M1 完全一致
   （不存储、不注入）。

### US-2 匹配矩阵（P1）

作为实现正确性的核心证据，RFC 6265 匹配规则逐条落地（移植 okhttp
CookieTest 代表用例）。

**验收场景**：

1. host-only vs 域 cookie：`Set-Cookie` 无 Domain 属性 → 仅原 host 回发；
   带 `Domain=example.com` → 子域 `api.example.com` 也回发。
2. 前导点与全域后缀误匹配拒绝：`.com` 黑名单拒绝存储。
3. path 目录规则（RFC 6265 §5.1.4）：`Path=/foo` 匹配 `/foo`、`/foo/bar`，
   不匹配 `/foobar`；默认 path = 设置路径的目录。
4. secure：仅 https 请求回发 secure cookie。
5. 同名不同 path/domain 共存（各自独立条目、序列化去重正确）。

### US-3 过期与日期解析（P1）

**验收场景**：

1. Max-Age 与 Expires 同时存在 → Max-Age 优先（okhttp 同款）。
2. 负 Max-Age → 立即失效（不回发、条目清除）。
3. 三格式日期（RFC 1123/RFC 850/asctime）逐一解析正确；垃圾日期 → 会话
   cookie（内存可存、不落盘）。
4. 会话 cookie（无过期属性）进程内有效、FileCookieJar 不持久化。

### US-4 Cookie 头序列化与 Bridge 注入策略（P1）

**验收场景**：

1. Given 多条匹配 cookie（不同 path 长度、不同创建时间），When 请求，Then
   Cookie 头顺序为 path 长度降序、同长创建时间升序（RFC 6265 §5.4）。
2. Given 请求已显式设置 Cookie 头 + Jar 有匹配项，Then 仅发显式头（**有意
   差异**：okhttp 会发两行共存，我们选 Jar 注入仅当未显式设置——spec 与
   文档显式记录，宪法 III）。
3. Given 3 跳重定向跨 host，Then 每跳 Cookie 头按新 URL 重新计算（中间响应
   的 Set-Cookie 已逐跳回存）。

### US-5 持久化 FileCookieJar（P2）

**验收场景**：

1. Given 存量 JSONL 文件，When 新建 Client 启动载入，Then 匹配规则立即生效。
2. Given 运行期变更，Then 防抖 1s 后落盘（文件内容含 `host_only`/`expires_at`）。
3. Given 落盘失败（目录不可写），Then 运行不受阻（内存 Jar 继续，错误可观测
   ——clarify C3 定暴露形态）。

## 边界用例

- 大小写与规范化：Domain 去前导 `.`、host 小写化后再比对；
- httpOnly 标记：保留字段但无区分使用场景（我们无该 API 分层，文档声明）；
- 超上限（默认 500）淘汰：LRU/最旧过期优先（clarify 定策略细节）；
- 空 Jar/全过期：不产生 Cookie 头（零字节头省略，不发空头）；
- 值含分号/逗号的 cookie（底座 parse 行为透传，序列化原样——RFC 容差记录）。

## 需求种子

- **FR-001** Jar 接口 MUST 为函数字段结构，挂 `HttpClient` 可选配置。
- **FR-002** 匹配 MUST 覆盖：域后缀（含黑名单拒绝）、path 前缀目录规则、
  secure、过期（Max-Age 优先）。
- **FR-003** Expires 三格式解析失败 MUST 降级为会话 cookie，不得报错中断。
- **FR-004** 序列化顺序 MUST 符合 RFC 6265 §5.4（path 长度降序、创建时间升序）。
- **FR-005** 注入策略 MUST 为「Jar 仅当请求未显式设置 Cookie 头时注入」，
  与 okhttp 的差异 MUST 在 spec 显式记录。
- **FR-006** 中间响应（重定向）MUST 逐跳回存。
- **FR-007** FileCookieJar MUST 防抖落盘且失败不阻塞请求路径。

## 关键设计要点

- 底座复用面：`Cookie::parse` 字段面与 okhttp 基本一致（`cookie.mbt:43-105`）、
  `Response.cookies` 收集齐备——本包全部工作在存储/匹配/回发三层（纯上层）。
- 匹配引擎纯函数化（输入 url + 条目 → bool），便于矩阵化对拍测试。
- 客户端方向序列化（`name=value; ...` 平铺）与底座 `Cookie::write_to`（服务端
  Set-Cookie 方向）是两个方向，不复用。
- 接线位置在 M2-P03 Bridge 层（链序内建层），本包提供挂点回调。

## 侵入性与宪法合规

- **非侵入**（11 §4）；I7 不做，自带解析器即终态。
- 宪法 III：注入共存策略（FR-005）与 PSL 黑名单近似（vs okhttp 无 PSL 的同款
  近制）两条有意差异在 spec 显式记录。
- 宪法 IV：okhttp CookieTest 代表用例移植对拍（关键子系统对拍要求）。
- 宪法（敏感信息）：Cookie/Set-Cookie 值默认不得出现在错误消息与调试输出
  （v1.2.0 展示条款；测试用合成值断言无泄漏）。

## target 矩阵

| target | 支持 | 说明 |
| --- | :-: | --- |
| native / wasm | ✅ | 全功能（含文件持久化） |
| js | ⭕ | fetch 下 `Response.cookies` 恒空（浏览器禁读）→ save 侧无数据；Jar 仅可用于主动 set（load 注入，浏览器可能剥离 Cookie 头）；**js 推荐关闭 Jar 交给浏览器**——文档明示 |
| wasm-gc | ❌ | 上游 runtime 缺口（M5/16 收口） |

## 性能影响

- load/save 每 URL 一次 Map 查找 + 小数组扫描（cookie 数典型 <50）：µs 级以下。
- Cookie 头拼装仅在有 cookie 时一次小 Bytes 分配。
- 无 cookie 配置时零开销（不进 Bridge 注入分支）。

## 测试方案

- 匹配矩阵（US-2）移植 okhttp CookieTest 代表用例（宪法 IV 对拍）；日期
  三格式矩阵；序列化顺序断言（捕获对端）。
- Bridge 注入共存策略与跨跳重算（M2-P03 链上集成测试）。
- FileCookieJar：JSONL roundtrip、防抖落盘时机、启动载入。
- 敏感信息：错误消息/Debug 输出不含 cookie 值的断言（合成值）。
- native+wasm 双绿；js 侧行为差异文档核对。

## 澄清问题种子（clarify 输入）

- **C1** 最小公共后缀黑名单清单来源与规模（~30 项的取表依据；遗漏域的处理）。
- **C2** 超上限淘汰策略（LRU vs 最旧过期优先；okhttp 无上限，我们是差异项，
  需确认默认值 500 与可配置面）。
- **C3** FileCookieJar 落盘失败的暴露形态（静默+计数器 vs 可观测错误回调）。
- **C4** httpOnly 的文档口径（保留不用的声明方式）。
- **C5** I7 是否随 M2-P07 附带评估（默认不做；若上游评估有价值再走人工批准）。

## 验收判据（包级 DoD）

1. US-1–US-5 验收场景测试全绿（native/wasm 双 target）。
2. okhttp CookieTest 代表用例移植清单与对拍结果写入 spec。
3. 两条有意差异（注入共存策略、PSL 黑名单近似）在 spec 显式记录。
4. `moon info && moon fmt` 干净；`.mbti` diff 已审视（CookieJar/InMemory
   CookieJar/FileCookieJar 公开面冻结）。

## 参考

- `11-cookies/README.md` §3.1–§3.4（接口/内存 Jar/持久化/序列化）、§4、
  §5（js ⭕）、§7、§8。
- 底座证据：`cookie.mbt:43-105`（parse）、`parser.mbt:280-281`（cookies 收集）。
- 上游引用方：M2-P03（Bridge 接线）、M2-P06（recipes 收口）。
