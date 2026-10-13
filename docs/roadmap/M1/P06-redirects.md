# P06 自动重定向：follow-up 循环与 3xx 决策表

> 里程碑：M1 性能核心 ｜ 前置依赖：P05（P01/P02/P04 传递依赖）｜ 人力估计：~1.5 人日
> 来源：`proj-init-docs/okhttp-on-async-http/02-redirects-retries/README.md` §1/§3.1/§3.2/§3.4/§8
> 侵入性：非侵入 ｜ 建议特性 slug：`m1-p06-redirects`

## 功能描述（speckit 输入种子）

在 P05 的 execute 接缝上引入 **follow-up 循环**（OkHttp
`RetryAndFollowUpInterceptor` 的重定向部分）：解析 3xx 的 `Location` 头
（相对引用经 `HttpUrl::resolve`），按**决策表**生成 follow-up 请求并自动跟随
（上限 20 跳），构建 `Response.priorResponse` 链暴露历史；跨 host 跟随时剥离
`Authorization`/`Cookie` 头；中间响应体必须 `skip_response_body` 排干后连接才可
复用。M1 决策表为裁剪版（README 差异 D7：401/407/408 终态、304 透传）；
stale-retry 的失败恢复在同一循环，但独立成 P07。

## 范围

包含：

- follow-up 主循环：每轮前检查 `call.cancelled`；中间响应 body
  `skip_response_body()` 排干；follow-up 计数上限 20，超出 raise
  `TooManyFollowUps`（对齐 OkHttp「Too many follow-up requests」）。
- 决策表（M1 版）：
  - 301/302：POST→GET（浏览器历史兼容），body 丢弃（去 Content-Length/Type 头）；
    GET/HEAD 保持；
  - 303：非 GET/HEAD → GET，body 丢弃；
  - 307/308：保持方法与 body——body 可重放（`Bytes`）则重放，不可重放
    （`Stream`）则**不跟随、把 307/308 响应原样交给调用方**；
  - 300/304/305/306：不跟随，终态返回（304 在 M1 即终态——缓存层 M4 才存在，
    README 差异 D7）；
  - 401/407/408 及其余：终态返回（Authenticator 随 M2/08；408 可选重试不做）。
- Location 处理：缺失/非法（resolve raise）→ 返回原响应（OkHttp 行为）；
  相对/绝对/网络路径参考均经 `HttpUrl::resolve`。
- 跨 host（scheme/host/port 任一不同）：删 `Authorization`、删 `Cookie` 头。
- `Response.prior` 链填充（P02 预留字段）：priorResponse 深度与顺序可断言。
- 连接租约优化：Location 指向同 host 时在**同一次 execute 内保持租约**
  （不归还再重取，03 §6 性能注意）。

非目标（显式排除）：

- stale-retry/路由失败恢复（P07）；callTimeout 伞（P08 接线，本包循环天然被其
  包裹）；Authenticator follow-up（M2/08）；408 重试（不做，OkHttp 无此默认）；
- 缓存条件 GET 改写（M4/05）；js 上的自实现重定向循环（浏览器已自动跟随且不可关，
  L1 在 js 不实现循环、`priorResponse` 不可用——02 §5 原文）。

## 用户故事种子

### US-1 方法降级跟随（P1）

作为使用者，POST 收到 301/302/303 时自动降级为 GET 重放（body 丢弃），最终拿到
目标响应；prior 链记录中间响应。

**独立测试**：P03 重定向链夹具（任意状态码+Location 组合）。

**验收场景**：

1. Given `POST /a` → `301 Location: /b`，Then follow-up 为 `GET /b`、无 body 与
   Content-Length/Type 头、终态响应正确、prior 链长度 1。
2. Given `POST /a` → `303 Location: /b`，Then 同上。
3. Given `HEAD /a` → `301`，Then follow-up 保持 HEAD。
4. Given `PUT /a` → `302 Location: /b`，Then follow-up 保持 PUT（仅 POST 降级——
   对齐 OkHttp，clarify C2 复核）。

### US-2 方法保持与可重放判定（P1）

作为使用者，307/308 保持方法与 body 重放；body 不可重放时收到原始 307/308 响应。

**验收场景**：

1. Given `POST` + `Bytes` body → `307 Location: /b`，Then follow-up 为 `POST /b`
   且 body 逐字节重放（捕获对端两次字节一致）。
2. Given `POST` + `Stream` body → `307`，Then 不跟随，调用方收到该 307 响应本体。
3. Given `308`，Then 行为与 307 相同。

### US-3 Location 解析（P1）

作为使用者，相对/绝对/畸形 Location 均得到定义良好的处理。

**验收场景**：

1. Given 相对 `../b`、绝对 `/b`、网络路径 `//other.host/x`，Then 分别 resolve 到
   正确绝对 URL 后跟随。
2. Given 无 Location 头、或 Location 非法（resolve raise），Then 返回原 3xx 响应。

### US-4 跨 host 头剥离（P1）

作为使用者，重定向到不同 host/scheme/port 时，`Authorization` 与 `Cookie` 头
不出现在 follow-up。

**验收场景**：

1. Given 带 `Authorization: Bearer x` 与 `Cookie: a=1` 的请求 → `301` 跨 host，
   Then 捕获的 follow-up 字节不含这两个头。
2. Given 同 host 重定向，Then 头保留。

### US-5 跳数上限与不跟随集合（P2）

作为使用者，超过 20 跳得到 `TooManyFollowUps`；300/304/305/306 与无 Location 的
3xx 原样返回。

**验收场景**：

1. Given 21 跳链夹具，Then raise `TooManyFollowUps`。
2. Given `300`/`304`/`305`/`306` 响应，Then 不跟随、原样返回（M1 304 语义为
   终态透传，差异 D7）。

### US-6 中间响应排干与租约保持（P1）

作为使用者，同 host 多跳重定向复用同一连接，且中间响应 body 不污染后续请求。

**验收场景**：

1. Given 3 跳同 host 链（每跳带 1KB body），Then 夹具侧仅见 1 条连接、第 4 个请求
   （终态后新请求）读到干净流（中间 body 已排干）。
2. Given 跨 host 跳，Then 旧租约正确归还/关闭、新 host 建新连接。

## 边界用例

- Location 指回自身 host 但端口不同（视为跨 host）；重定向循环 A→B→A（受 20 跳
  上限保护）；303 后再 307（降级后的 GET 无 body，307 重放 trivially 成立）；
  HEAD/GET 带 body 的跟随语义；follow-up 轮间 cancel（每轮 guard 以 `CallCancelled`
  终止）；中间响应 `Connection: close`（该连接终态后关闭，follow-up 走新连接）。

## 需求种子

- **FR-001** 循环 MUST 每轮检查取消标记，取消以 `CallCancelled` 终止。
- **FR-002** 中间响应 body MUST `skip_response_body` 排干后连接才可复用。
- **FR-003** 决策表（M1 版，上文五行）MUST 逐行可测。
- **FR-004** 跨 host follow-up MUST 剥离 Authorization/Cookie。
- **FR-005** follow-up 上限 MUST 为 20，超出 raise `TooManyFollowUps`。
- **FR-006** prior 链 MUST 保序可遍历（`priorResponse` 等价访问器）。
- **FR-007** 同 host follow-up MUST 复用当前租约（无归还-重取往返）。

## 关键设计要点

- 循环骨架照 `02 §3.1` 伪代码：`chain.proceed` 在 M1 即 P05 的单轮 exchange；
  `release_body` = skip 排干；终态响应 body 惰性挂租约。
- follow-up 头改写在 `HeadersV` 层完成（保序），再经 P02 转换层重折叠——
  注意：改写后的 follow-up 视为新 Request，其折叠缓存独立于原 Request
  （L3 缓存键 = call 内的 request 代次，plan 时定细化）。
- 302 对 PUT/POST 之外方法的语义（OkHttp 仅 POST 降级）在 spec 对齐并记录。

## 侵入性与宪法合规

- 非侵入：纯上层循环（02 §4 表）。
- 宪法 III：与 OkHttp 语义差异（401/407/408/304 的 M1 处理、20 跳上限、跨 host
  剥离范围）在 spec 显式记录并给出理由。
- 宪法 II：重定向是正确性特性，性能上防退化（中间 body 排干 O(body)、同 host
  租约保持）——两条均有验收场景。

## target 矩阵

| target | 支持 | 说明 |
| --- | :-: | --- |
| native / wasm | ✅ | 同一路径 |
| js | ⚠️ | 浏览器自动跟随且不可关：L1 不实现循环、priorResponse 不可用（02 §5）；js 上 execute 直通返回浏览器跟随后的终态 |
| wasm-gc | ❌ | 上游 runtime 缺口 |

## 性能影响

防退化项：中间 body 排干为本地内存搬运 O(body)；同 host 租约保持消除归还-重取。
L3 在重放路径生效（follow-up 头改写后重折叠一次，属必要成本非退化）。

## 测试方案

- 决策表逐行：P03 重定向链夹具构造全部状态码 × Location 形态 × 方法组合；
  跨域头剥离用捕获对端字节断言；跳数上限/循环保护/取消交互逐项。
- prior 链深度与顺序断言（`assert_true(prior is Some(...))` 风格）。
- native + wasm 双绿；js `moon check`（循环代码在 js 后端不激活）。

## 澄清问题种子

- **C1** 用户手设的 `Cookie` 头跨 host 是否剥离（OkHttp 语义中 Cookie 头由 Jar
  注入、手设头的命运需对 5.5.0 源码核对——报告 02 §1 陈述为剥离，遵报告，spec 记录依据）。
- **C2** 301/302 对 PUT/DELETE 等非 POST 方法是否保持（OkHttp 仅 POST 降级；
  本文件 US-1 场景 4 按「仅 POST」写，spec 阶段对拍确认）。
- **C3** follow-up 计数上限是否可配置（OkHttp 固定 20 不暴露——默认不可配置，
  遵 OkHttp）。
- **C4** L3 缓存的代次粒度（原 Request 与每个 follow-up 各自缓存 or 仅原 Request）。

## 验收判据（包级 DoD）

1. US-1–US-6 验收场景测试全绿（native/wasm 双 target）；决策表每行至少一个用例。
2. `TooManyFollowUps`/`CallCancelled` 错误变体进 `.mbti` 并有判别测试。
3. `moon info && moon fmt` 干净；`.mbti` diff 审视（prior 访问器公开面）。
4. 与 OkHttp 的 M1 语义差异表（D7 相关行）写入 spec。

## 参考

- `02-redirects-retries/README.md` §1（OkHttp 规格）、§3.1（循环伪代码）、
  §3.2（决策表）、§3.4（与取消/超时交互）、§8（测试方案）。
- 下游引用方：P07（recover 插入同一循环）、P08（callTimeout 伞）、P10（重定向
  场景基准）。
