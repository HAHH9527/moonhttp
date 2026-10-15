# P05 认证（Authenticator/challenges 解析/401 follow-up/407 代理认证）

> 里程碑：M2 完整门面 ｜ 前置依赖：M2-P03（RetryAndFollowUp 层回补 401 行）、
> M2-P02（407 的 CONNECT 隧道场景）｜ 人力估计：~3.5 人日
> 来源：`proj-init-docs/okhttp-on-async-http/08-auth/README.md` §1–§8；
> 回补 M1 欠账 **F6**（401/407 认证 follow-up）
> 侵入性：非侵入（407 走 ProxyError 捕获绕行；I4 优雅化 PR 默认不做）
> ｜ 建议特性 slug：`m2-p05-auth`

## 功能描述（speckit 输入种子）

为 moonhttp 交付 OkHttp 认证能力：`Authenticator`/`ProxyAuthenticator`
（函数字段：`authenticate : async (Response) -> Request?`）、
`Credentials::basic`（`Authorization: Basic base64(user:pass)`）、
**challenges 解析器**（RFC 7235：从底座折叠后的 `WWW-Authenticate`/
`Proxy-Authenticate` 逗号合并串解析 scheme/auth-param 列表，支持
quoted-string 转义与引号内逗号、token68、无 realm scheme）。401 流程回补进
RetryAndFollowUp 决策表（M1-D7 裁剪行的欠账回补）：401 ∧ authenticator 已
配置 ∧ 计数未超 → 构造 Response 视图 → 回调 → Some(新请求) follow-up /
None 终态透传；401 计数独立、总 follow-up 受 20 硬上限。407 走非侵入绕行：
捕获 CONNECT 隧道的 `ProxyError` → 经 M2-P02 静态凭据/回调机制重建隧道重试。

## 范围

包含：

- `Authenticator`/`ProxyAuthenticator` 类型与 `HttpClient` 挂接。
- `parse_challenges` 解析器：token、OWS、quoted-string（反斜杠转义、引号内
  逗号不分隔）、token68（scheme 后直达到逗号/行尾）、大小写不敏感 scheme。
- 401 决策表行回补（挂在 M2-P03 的 RetryAndFollowUp 层）：计数独立 +
  20 硬上限共享（防凭据死循环，okhttp 同款）。
- `Credentials::basic`：base64（来源见 C1）；结果缓存在不可变 Request 上，
  重放不重算。
- 407 绕行闭环：ProxyError 捕获 → authenticate 回调（Proxy-Authenticate
  挑战）→ 凭据经 M2-P02 的代理持久头预置 → 重建隧道重试；无 authenticator
  时 407 错误透传。
- Digest 扩展示例（~150 行，写进 README；**可裁剪项**——hash 依赖见 C2）。

非目标（显式排除）：

- I4（CONNECT 407 挑战回调，~15 行上游 PR）：现有绕行可用，默认不做；
  若后续评估需要，走 M2-P07 通道并人工批准；
- WWW-Authenticate 原始多行头保真（底座折叠语义可解析，侵入不建议——
  原报告明示）；
- http-over-proxy 的 407（absolute-form 不在 M2，见 F14；407 仅 CONNECT
  隧道场景）；
- Negotiate/NTLM 类绑定平台凭据的 scheme（仅解析不实现）。

## 用户故事种子

### US-1 challenges 解析器（P1）

作为实现正确性的核心证据，RFC 7235 挑战列表解析逐类落地。

**独立测试**：纯函数单测；不依赖网络与 P06/P07。

**验收场景**：

1. 单行多挑战（`Basic realm="a", Bearer, Digest realm=b, qop=auth`）→
   三挑战逐字段正确。
2. quoted realm 含逗号与转义引号（`realm="a,\"b"`）→ 值保留正确、不分隔。
3. token68（`Negotiate YIIg...`）→ scheme + blob 正确。
4. 畸形输入（裸引号未闭合/非法 token 字符）→ 可判别解析错误（对应 BadRequest
   分类），不 panic。
5. 大小写：scheme 大小写不敏感；参数名小写化、值保真。

### US-2 401 follow-up（P1）

**验收场景**：

1. Given 服务端先 401（`WWW-Authenticate: Basic realm=x`）后 200，When 配置
   Basic authenticator，Then 自动带凭据重发、最终拿到 200（夹具校验第二请求
   头正确）。
2. Given authenticator 返回 None，Then 401 终态透传给调用方。
3. Given 永远返回新请求的坏 authenticator，Then 受 20 次硬上限终止（可判别
   错误），无无限循环。
4. Given 401 与重定向混合脚本，Then 401 计数与重定向计数独立、总和受 20
   硬上限。
5. Given 未配置 authenticator 的 401，Then 行为与 M1 一致（终态返回，零回归）。

### US-3 407 代理认证（P2）

**验收场景**：

1. Given mini 代理夹具（CONNECT 先回 407 带 `Proxy-Authenticate: Basic`、
   凭据正确后放行 200），When 配置 ProxyAuthenticator，Then 隧道自动重建、
   请求成功（端到端 echo 正确）。
2. Given 未配置 ProxyAuthenticator 的 407，Then 可判别的代理错误透传。
3. Given 407 后凭据仍错（夹具二次 407），Then 受上限约束终止、错误分类清晰。

### US-4 Credentials::basic（P1）

**验收场景**：

1. `basic("user", "pass")` → `Basic dXNlcjpwYXNz`（RFC 4648 标准编码断言）。
2. 重定向/重试重放同一请求 → Authorization 头逐字节相同（不重算、Request
   不可变性保证）。

### US-5 Digest 扩展示例（P3，可裁剪）

**验收场景**：

1. Given Digest 挑战（MD5/SHA-256 qop=auth），Then 示例实现完成一次完整
   digest 握手（对拍 RFC 7616 示例向量或夹具双跑）。

## 边界用例

- 401 响应无 `WWW-Authenticate` 头（authenticator 仍被调，挑战列表为空——
  okhttp 同语义，clarify 确认）；
- `Authorization` 头已被用户显式设置时 authenticator 的行为（okhttp：仍覆盖
  ——按 okhttp 口径并记录）；
- 重定向后的 401（URL 已变，凭据作用域由使用者回调决定）；
- 407 与目标 401 在同一请求中都出现（先隧道后应用层，两层独立计数）；
- 敏感信息：错误消息/Debug 输出不得含 Authorization/Proxy-Authorization 值
  （宪法 v1.2.0；测试以合成值断言）。

## 需求种子

- **FR-001** challenges 解析器 MUST 支持 quoted-string（转义/引号内逗号）、
  token68、无参 scheme；畸形输入可判别报错。
- **FR-002** 401 流程 MUST 挂 RetryAndFollowUp 决策表；计数独立且总 follow-up
  受 20 硬上限。
- **FR-003** authenticator 返回 None MUST 终态透传原响应。
- **FR-004** 407 MUST 以 ProxyError 捕获 + 隧道重建绕行实现（零上游改动）；
  无配置时错误透传。
- **FR-005** Basic 凭据 MUST 在 Request 上缓存（重放不重算）。
- **FR-006** 认证相关头 MUST 不出现在错误消息与默认调试输出（敏感信息条款）。
- **FR-007** 认证路径构造的请求头 MUST 绕过底座 Map 折叠的逗号合并损失
  （HeadersV 例外条款，M1-P01 已留挂点）。

## 关键设计要点

- 折叠头解析：底座把多值 `WWW-Authenticate` 折叠为逗号合并单值
  （`parser.mbt:283-286`）；RFC 9110 §5.2 允许逗号列表形式，正确扫描器两种
  形态通吃——解析器输入即折叠串，无需侵入。
- 407 重建：捕获 `ProxyError`（`client.mbt:48-53` 路径）→ 凭据进代理 Client
  持久头（CONNECT 请求携带，M2-P02 机制）→ 重试整个 `Client::connect`；
  代价是多一次往返（HTTP 认证两步的正常成本，文档声明）。
- Response 视图暴露面：authenticate 回调看到完整 Response（含挑战头）；
  敏感头掩码与 F12/F13（M3）的关系在 spec 记录（M2 阶段明文，测试用合成值）。
- Digest 示例依赖 hash 能力（`moonbitlang/core` crypto 可用性待验证，C2）；
  不可得则裁剪该示例并记录（不挂欠账——原报告定位即扩展示例非判据）。

## 侵入性与宪法合规

- **非侵入**（08 §4 第一行）：401 上层 follow-up；407 绕行。
- 宪法 I：I4 默认不做（绕行可用）；若评估推进必须人工批准。
- 宪法 III：与 okhttp 的映射表在 spec 显式记录（Route 参数简化掉、407 两步
  往返成本、显式 Authorization 头覆盖语义）。
- 宪法（敏感信息）：FR-006 落实「默认不展示」；展示需求走人工确认例外程序。
- 宪法 IV：解析器矩阵先写测试（红-绿-重构）；407 基于本地 mini 代理夹具
  （M2-P02 交付物复用）。

## target 矩阵

| target | 支持 | 说明 |
| --- | :-: | --- |
| native / wasm | ✅ | 全功能（含 407 隧道场景） |
| js | ⭕ | 401 上层处理可行（Response 透传）；无 proxy → 无 407；浏览器可能弹原生认证框（fetch credentials 策略）——文档标注 |
| wasm-gc | ❌ | 上游 runtime 缺口（M5/16 收口） |

## 性能影响

- 401/407 follow-up 各多一次完整往返（协议固有，非实现开销）。
- Basic 凭据 O(len) 一次计算、重放缓存零重算。
- challenges 解析仅在有挑战头时触发（冷路径）。

## 测试方案

- US-1 纯函数矩阵（畸形输入全覆盖）；US-2/3 基于 P03 夹具 401 脚本 +
  M2-P02 mini 代理夹具（先 407 后 200 隧道）。
- 上限与计数：夹具计数器断言 follow-up 次数。
- 敏感信息断言：错误消息与 Debug 输出扫描无凭据（合成值）。
- native+wasm 双绿。

## 澄清问题种子（clarify 输入）

- **C1** base64 来源（`moonbitlang/core/encoding/base64` 可用性；否则自带
  ~40 行，M1 percent 实现先例）。
- **C2** Digest 示例的 hash 依赖（core crypto；不可得则裁剪，记录于 spec）。
- **C3** 407 重试计数：独立于 401 计数 vs 共享 20 上限的细则（okhttp 对齐
  口径核对）。
- **C4** authenticate 回调 Response 视图的暴露面（是否裁剪敏感头——与 F12/
  F13 的 M3 专版关系，M2 先明文的记录方式）。
- **C5** 无 `WWW-Authenticate` 头的 401 是否仍触发回调（okhttp 口径核对后
  定案）。

## 验收判据（包级 DoD）

1. US-1–US-4 验收场景测试全绿（native/wasm 双 target；US-5 视 C2 裁剪结论）。
2. 认证映射表（Route 简化、407 两步成本、计数语义）写入 spec（宪法 III）。
3. F6 回补完成可宣告（M1 明细状态更新就绪；M1-P06 决策表 401/407 行补齐）。
4. 敏感信息断言通过（错误消息/Debug 无凭据）。
5. `moon info && moon fmt` 干净；`.mbti` diff 已审视（Authenticator/
   Credentials/挑战解析公开面冻结）。

## 参考

- `08-auth/README.md` §3.1–§3.4（类型与流程/解析器/407 绕行/扩展示例）、
  §4（侵入性）、§5、§7、§8。
- 底座证据：`client.mbt:48-53`（CONNECT/ProxyError）、`parser.mbt:283-286`
  （折叠）、`utils.mbt:94-109`（quoted-string 形状参考）。
- M1 欠账 F6；M1 差异 D7；M1-P01（HeadersV 例外条款）。
- 下游引用方：M2-P06（recipes 收口）、M3/07（407 与 TLS 代理场景整合）。
