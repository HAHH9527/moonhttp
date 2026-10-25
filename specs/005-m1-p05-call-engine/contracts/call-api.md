# Contract：P05 Call 公开面（.mbti 冻结面事前契约）

> 本文是 plan 对 `.mbti` 的**事前契约**：implement 完成后 `moon info` 产出的
> `src/client/pkg.generated.mbti` 以 §1 为对账面，`src/core/pkg.generated.mbti`
> 以 §2 为对账面（计划外公开项为零；SC-007/FR-014）。命名全 snake_case。
> 字段级结构见 data-model.md；机制证据见 research.md。

## 1. `hahh9527/moonhttp/client`（FR-014 冻结面）

```text
// 保留项
pub fn placeholder() -> Bool                    // 原样保留（P6，004 口径）

// Types（Address/ConnectionPool/Lease 为 P04 既有面，期望零 diff）
pub struct HttpClient { /* private fields */ }
pub struct Call { /* private fields */ }

// HttpClient（FR-008：直连形态构造；无 builder；P08 配置位不建）
pub fn HttpClient::new(pool : ConnectionPool) -> Self
pub fn HttpClient::new_call(Self, Request) -> Call

// Call（FR-014：execute/cancel/is_cancelled）
pub async fn Call::execute(Self) -> Response raise
pub fn Call::cancel(Self) -> Unit
pub fn Call::is_cancelled(Self) -> Bool

// Errors
pub suberror CallCancelled derive(@debug.Debug)      // FR-003
pub suberror CallStateError derive(@debug.Debug)     // FR-001（plan 定名）
```

- `Call::request/client` 访问器：Key Entities 列出 request/client 引用为
  实体内容；公开只读访问器**本包不建**（无消费方，YAGNI；若 tasks 期证实
  测试需要，走白盒同包直读，不进公开面）。
- 明确不进公开面：enqueue（D2）、拦截器 API（D1）、builder（P08）、
  `exchange_once` 与 BodyBridge（包内私有）、1xx 回调参数（C3 裁决）。

## 2. `hahh9527/moonhttp/core`（期望增量 = 且仅 = FR-015 裁决面）

P05 对 core 的唯一改动是 FR-015 预留支点的裁决落地（research R3）；
P01/P02 既有面零 diff：

```text
// ResponseBody::stream 增可选参（既有参数位置不变）
pub fn ResponseBody::stream(
  &@io.Reader,
  on_event? : (ResponseBodyEvent) -> Unit,
  on_dispose? : async () -> Unit raise,      // 新增：dispose 收尾钩子
) -> Self

// 新增显式异步收尾 API（OkHttp body.close() 的异步对应物）
pub async fn ResponseBody::dispose(Self) -> Unit raise
```

`dispose` 方法契约：

1. `consumed() == true` ⇒ no-op（处置已由 Consumed 通道完成）。
2. 否则：未 dropped 则置 dropped 并触发 `Dropped` 事件（与 `drop()` 同一
   互斥时序，先到者赢），随后 `await on_dispose()`。
3. `on_dispose` 缺省（未注入）⇒ 等价当前 `drop()`（纯状态标记，无收尾）——
   core 独立可用性不被 P05 绑架。
4. `on_dispose` raise ⇒ 错误透传（毒化由注入方在 raise 前完成）。
5. `drop()` 语义零变化（纯状态标记；文档注明「仅 drop 不 dispose ⇒ 租约
   滞留，调用方责任」）。
6. `dispose` 幂等与收尾唯一性（2026-10-24 第二轮 clarify 裁决）：收尾
   动作（Dropped 触发 + `await on_dispose()`）整体至多发生一次有效，
   「已收尾」后再 dispose ⇒ no-op（内部「已收尾」标记）；先 `drop()` 再
   `dispose()`：Dropped 事件不重发（先到者赢），`on_dispose()` 仍补执行
   一次——`drop()` 不阻断收尾；disposed 后 drop 亦 no-op。

## 3. 行为契约（FR → 方法语义速查）

| 方法 | 契约要点（正文为 spec FR 的 plan 级细化） |
| --- | --- |
| `HttpClient::new` | 持池引用；零网络动作 |
| `HttpClient::new_call` | 装箱 Call（Pending 态）；不校验 URL 可达性 |
| `Call::execute` | FR-001/002/006/009：Pending 首检（cancelled→CallCancelled 零网络）→ 组内 spawn 单轮 exchange → wait；非 Pending → CallStateError；返回挂租约的完整 Response |
| `Call::cancel` | FR-002/012：置标记 → `Task::cancel`（在途）→ 若 lease 仍持有：poison+release（同步关连、清引用）；重入幂等 |
| `Call::is_cancelled` | 直读标记（FR-012） |
| `ResponseBody::dispose` | §2；US-5 场景 2 的验收动作 |

## 4. 明确不进公开面的项（防泄漏）

- `Call` 全部内部字段（state/task/lease/folded/fold_count）与
  `exchange_once`、`BodyBridge`、Address 推导 helper——白盒同包直读。
- 时钟/锁/池内部（P04 已冻结口径继续有效）。
- js 分支：零 `#cfg(js)`（D14；research R7）。
- 1xx 回调（C3）：`end_request` 调用不传 `on_informational_response`。
