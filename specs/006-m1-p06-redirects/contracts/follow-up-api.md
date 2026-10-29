# Contract：P06 公开面（.mbti 事前契约）

> 本文是 plan 对 `.mbti` 的**事前契约**：implement 完成后 `moon info`
> 产出的 `src/client/pkg.generated.mbti` 以 §1 为对账面（SC-008/
> FR-012：计划外公开项为零），`src/core/pkg.generated.mbti` 以 §2
> 为对账面（零 diff）。字段级结构见 data-model.md 实体 6；机制证据
> 见 research.md R3/R9。

## 1. `hahh9527/moonhttp/client`（期望增量 = 且仅 = 错误变体两件套）

```text
// 保留项（P05 冻结面零变化）
pub fn placeholder() -> Bool

// Types（Address/ConnectionPool/Lease/HttpClient/Call 期望零 diff）
pub struct HttpClient { /* private fields */ }
pub struct Call { /* private fields */ }
pub fn HttpClient::new(ConnectionPool) -> Self
pub fn HttpClient::new_call(Self, @core.Request) -> Call
pub async fn Call::execute(Self) -> @core.Response        // 语义升级：follow-up 循环；签名不变
pub fn Call::cancel(Self) -> Unit
pub fn Call::is_cancelled(Self) -> Bool

// Errors——既有两变体原样
pub suberror CallCancelled derive(@debug.Debug)
pub suberror CallStateError derive(@debug.Debug)
// ——新增（FR-005/FR-012；R9 两件套先例 = CallCancelled）
pub suberror TooManyFollowUps derive(@debug.Debug)
pub fn TooManyFollowUps::to_repr(Self) -> @debug.Repr     // 经 pub extend 呈现
```

**明确不进公开面**：`exchange_loop`/`follow_up_request`/头改写与
prior 构建助手（包内私有）、`exchange_once`（包内私有接缝保留——
T004 起 spawn 换靶 `exchange_loop` 后 lib 构建零生产调用点，降为
白盒直调回归面；其 `#warnings("-unused_value")` 定点抑制的例外登记
见 plan「例外跟踪」，converge F3/T021）、`Call` 新增 3 个 priv 字段
（data-model 实体 6；租约地址经 `lease.addr` 同包直读、不设镜像——
round3 D-4 订正）、prior 链写入路径（读侧经 P02 既有 `Response::prior`）、
`followRedirects`/`followSslRedirects` 开关（P08 builder 配置位，
spec 非目标）。

**行为契约速查（execute 语义升级的 FR 对账）**：

| 方法 | 契约要点 |
| --- | --- |
| `Call::execute` | FR-001～FR-010：组内子任务改为 follow-up 循环（data-model 实体 1）；返回终态响应（挂 prior 链）；`TooManyFollowUps`/`CallCancelled`/网络错误三通道判别（`err is`）；P05 一次性/预取消/并发语义零变化 |
| `Call::cancel` | 逐轮生效：轮间由循环顶 guard 命中（零网络 `CallCancelled`）；轮内由 P05 既有 task.cancel/poison 通道命中 |
| `Response::prior`（P02 面读侧） | FR-006：终态响应挂链；条目 body=None、保序、链深=跳数（data-model 实体 4/INV-5） |

## 2. `hahh9527/moonhttp/core`（期望零 diff）

P06 对 core **零改动**：Location 解析（`HttpUrl::resolve`）、头改写
（`HeadersVBuilder::remove`）、请求重组（`RequestBuilder` 五件套）、
prior 装配位（`Response::from_http` 的 `prior?` 参）全部为 P01/P02
既有公开面（research R4/R5 逐条锚点）。若 implement 期发现 core
确需增量（预期为否），必须先回改本契约与 spec 并说明理由。

## 3. `hahh9527/moonhttp/internal/fixtures`（期望零 diff）

测试全部走既有夹具面（research R7：mount/mount_sequence/
conn_request_counts/accepted_total/Capture 等）。

**登记性例外（2026-10-28，T019/converge F1，owner 裁决①）**：ScriptedServer
增 `captured_request_heads()` 请求头观测面（一字段一捕获一访问器最小扩展）
——SC-004「同 host follow-up 捕获字节完整保留」缺黑盒字节级证据（原夹具无
请求头观测能力），按 tasks Path Conventions「先红后绿最小扩展并逐处归因」
落点；除此之外 §3 零 diff 口径不变。

**登记性例外（2026-10-28，review 修复批）**：`mount_truncated` 增
`derive_close~ : Bool = true` 参数——FR-002 排干失败毒化判别需剥离
close-token 混淆（原 Truncated 路径恒派生 `Connection: close`，US6
补②的「不回池」无法单点归因）；新用例 P06-US6 补③消费。除此之外
§3 零 diff 口径不变。
