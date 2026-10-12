# 08 认证（Authenticator / 401/407 挑战）

> 结论：**非侵入可实现**。依赖 02 的 follow-up 循环与 01 的 Request builder。

## 1. OkHttp 行为规格

- `Authenticator::authenticate(Route?, Response) -> Request?`：401 时被调；返回带凭据的新 Request 继续 follow-up，返回 null 放弃（把 401 响应交给调用方）。
- `Response.challenges()`：解析 `WWW-Authenticate`（或代理的 `Proxy-Authenticate`）为 `(scheme, realm)` 列表。
- `Credentials.basic(user, pass)`：`Authorization: Basic base64(user:pass)`。
- 代理认证：`proxyAuthenticator`，407 触发，头为 `Proxy-Authorization`，作用于 CONNECT 隧道建立请求。
- follow-up 次数与重定向共享 20 次上限（防凭据死循环）。

## 2. async/http 现状（证据)

- 无认证支持（grep 零命中）。
- 相关底座行为：
  - 代理是 `proxy? : Client`（CONNECT 隧道，`client.mbt:48-53`），**"用另一个 HTTP client 作代理"**的形状天然支持"代理认证"：隧道建立前向代理 Client 发的 CONNECT 若得 407，上层可对代理 Client 重发带 `Proxy-Authorization` 的 CONNECT——但 CONNECT 请求是 `Client::connect` 内部发出的，**L1 够不着**（见 §4 侵入项）。
  - `WWW-Authenticate` 多值头被 @http 折叠为逗号合并的单值（`parser.mbt:283-286`）——挑战列表需从合并串解析（RFC 7235 本就允许逗号列表形式，可行；引号内逗号需正确处理）。

## 3. 实现方案

### 3.1 类型与流程

```moonbit
pub struct Authenticator {
  authenticate : async (Response) -> Request?     // 401；简化掉 okhttp 的 Route 参数（03 §3.1 无 Route 层）
}
pub struct ProxyAuthenticator {
  authenticate : async (Response) -> Request?
}
pub fn Credentials::basic(user : String, password : String) -> String
  // "Basic " + base64(user:pass)；base64 用 moonbitlang/core/encoding/base64（若无则自带 ~40 行实现）
```

- 401 流程（挂 02 的 follow-up 决策表）：响应 401 ∧ `authenticator` 已配置 ∧ 该 call 的 401 follow-up 计数 < 上限 → 构造带 challenges 的 Response 视图 → `authenticate(response)` → Some(new_request)（通常 `request.new_builder().header("Authorization", creds)`）→ follow-up；None → 终态返回 401。
- 计数按"每 call 的 401 follow-up"独立于重定向计数，总 follow-up 仍受 20 硬上限（02 §3.1）。

### 3.2 challenges 解析（RFC 7235）

```
parse_challenges(s) : 切分 scheme [auth-param]* 列表
  - 逐字符扫描：token 后跳 OWS；'=' 后取 token 或 quoted-string（反斜杠转义、引号内逗号不分隔）
  - 产出 Array[Challenge{ scheme : String, params : Map[String,String] }]，realm 常用键
```

- 输入来自折叠后的 `headers["WWW-Authenticate"]`（逗号合并串）；此形式与多行头语义等价（RFC 9110 §5.2），正确实现的扫描器两者通吃。
- 引用材料：@http 自己的 `validate_quoted_string`（`utils.mbt:94-109`）语法判断可抄形状，但挑战解析要**保留**值，需自写完整解析器（~80 行 + 用例）。
- 注：`Bearer` 等 scheme 无 realm 也合法；`token68`（如 Negotiate base64 blob）无参数——扫描器需支持 scheme 后直接到逗号/行尾。

### 3.3 代理认证（407）

- **https over proxy（CONNECT 隧道场景）**：CONNECT 由 `Client::connect` 内部发出（`client.mbt:50-52`），407 时它直接 `raise ProxyError(response)`。非侵入路径：L1 捕获 `ProxyError`，**重建代理 Client**，在代理 Client 的持久 headers 里预置 `Proxy-Authorization`（`Client::connect` 的 headers 参数会进 CONNECT 请求——`proxy..request(Connect, ...)` 用的是 proxy Client 的持久头，`client.mbt:50`），重试整个 `Client::connect`。可用但浪费一次往返（先 407 再带凭据重试是 HTTP 认证的正常两步，浪费有限）。
- **http over proxy**：M1 不支持 absolute-form（03 §3.6），代理认证仅在 CONNECT 场景提供。
- 407 的 `Proxy-Authenticate` 解析复用 3.2。

### 3.4 扩展示例（写进 README）

- Digest（okhttp-digest 等价）：`authenticate` 内按 challenges 选 MD5/SHA-256 算 nonce 响应——纯上层，~150 行（MD5/SHA 需 core 支持，`moonbitlang/core/crypto`? 若无带 hash 实现）。
- AWS SigV4 / HMAC 签名：同形扩展，签名拦截器 + authenticate 组合。

## 4. 侵入性清单

| 项 | 级别 | 说明 |
| --- | --- | --- |
| 401 Authenticator / challenges / Basic | **非侵入** | 上层 follow-up |
| 407 代理认证 | 非侵入（绕行） | 经 `ProxyError` 捕获 + 预置头重建隧道（§3.3）；**【侵入 async/http，~15 行】**的优雅做法：`Client::connect` 增加 `on_proxy_challenge? : async (Response) -> Headers` 回调，在 CONNECT 407 时询问上层——建议 M2 提上游 PR，L1 先用绕行 |
| WWW-Authenticate 原始多行头 | 侵入 async/http（不建议） | 折叠语义可解析，无需侵入 |

## 5. Target 支持矩阵

| target | 支持 | 说明 |
| --- | :-: | --- |
| native / wasm | ✅ | 全功能（含 407） |
| js | ⭕ | fetch 的 401 处理由上层同样可行（Response 透传）；无 proxy → 无 407；注意浏览器可能弹原生认证框（fetch 默认 credentials 同源策略）——文档标注 |
| wasm-gc | ❌ | runtime 级缺口（16） |

## 6. 性能影响

- 401 follow-up 多一次完整往返（协议固有）；Basic 凭据计算 O(len) 一次。
- 缓存 `Credentials::basic` 结果在 Request builder 上（重试/重定向重放时不重算——Request 不可变自带此性质✅）。

## 7. 工作量与依赖

- 依赖：01、02（follow-up 表）、03（407 场景连接重建）。
- 估计：challenges 解析器 ~1 人日（含 quoted-string 用例）；401 流程 ~0.5；407 绕行 ~0.5；Basic/Digest 示例 ~0.5；测试 ~1。**~3.5 人日**。

## 8. 测试方案

- 挑战解析器：单行多挑战、quoted realm 含逗号/转义、token68、大小写 scheme、畸形输入（对应 BadRequest 行为）。
- 401：Basic 成功 follow-up、authenticator 返回 null 终止、20 次上限（坏 authenticator 永远重发）。
- 407：本地代理夹具（Python/`@http.Server` 检 CONNECT）先 407 后 200 隧道。
