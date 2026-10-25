# Data Model: Call 执行骨架与取消（M1-P05）

**Date**: 2026-10-24 | 上游：P01 值对象 / P02 消息与回调契约 / P04 池与租约。
字段级 `.mbti` 事前契约见 contracts/call-api.md；本文记实体、不变量与状态迁移。

## 1. 实体

### 实体 1：HttpClient（门面）

| 字段 | 类型 | 可见性 | 说明 |
| --- | --- | --- | --- |
| pool | ConnectionPool | priv | P04 池实例（唯一必需状态） |
| （P08/P09 配置位） | — | — | 本包不建字段（YAGNI；P08 落位） |

- 构造 `HttpClient::new(pool)`：直连形态唯一入口（FR-008）；无 builder。
- `new_call(request)` 仅做参数装箱（Call::new），不做校验以外的工作。

### 实体 2：Call（一次待执行请求的句柄）

| 字段 | 类型 | 可见性 | 说明 |
| --- | --- | --- | --- |
| request | Request | priv(读) | 冻结面经访问器暴露（Key Entities） |
| client | HttpClient 引用 | priv | 租借来源 |
| state | mut CallState | priv | 一次性状态机（§3 图 1） |
| cancelled | mut Bool | priv | 标记通道（FR-002a）；`is_cancelled` 直读 |
| task | mut Task[Response]? | priv | 子任务句柄（FR-002b）；cancel 落点 |
| lease | mut Lease? | priv | 当前持有的租约引用；处置完成即置 None（FR-012 竞争安全的关键） |
| folded | mut Map[CIS, String]? | priv | L3 折叠缓存（FR-004，每 Call 恰一次） |
| fold_count | mut Int | priv | 白盒断言面（US-4 计数） |

- **不变量 I-1**（一次性）：state ∈ {Pending} 才可 execute；单线程模型下
  Pending→Executing 同步置位，无重入窗口。
- **不变量 I-2**（折叠一次）：folded 由 None→Some 恰一次；此后每次发送读
  同一实例（`fold_count` 与重放次数解耦）。
- **不变量 I-3**（租约唯一处置）：lease 非 None 期间，处置动作（release/
  poison+release）至多发生一次有效；处置后立刻置 None——迟到 cancel 只见
  None（FR-012 不 double-close 的机制保证）。

### 实体 3：exchange 接缝（内部函数，非公开面）

`Call::exchange_once(self) -> Response raise`：租借（`pool.acquire(Address)`)
→ 折叠（R5）→ 发送头（`Client::request(extra_headers=folded)`）→ 发送体
（Writer：Bytes 走 `write_once`、Stream 走 `write_reader`）→ 收头
（`end_request()`，不传 1xx 回调）→ 构建 Response（`Response::from_http` +
`ResponseBody::stream(bridge, on_event, on_dispose)`）→ 返回（归还逻辑不在
此步——归还由体处置驱动，FR-005）。

- Address 推导：`Request.url` → scheme/host/port（Protocol→串的匹配为包内
  私有helper，不用弃用 Show）。
- execute 包装：`with_task_group` → `spawn(exchange_once)` → 存句柄 →
  `task.wait()` → `handle_cancellation` 外皮把取消 `None` 映射为
  `CallCancelled`。

### 实体 4：BodyBridge（读适配器 + 租约处置状态机，包内私有）

包一层 `@io.Reader`（内持 @http Client），职责三行：

| 读路径事件 | 动作 | 通道 |
| --- | --- | --- |
| EOF（读到底） | ResponseBody 触发 `Consumed` → 处置器 `release` + lease 置 None | FR-005 回池 |
| 读中网络错误 | `poison + release` + lease 置 None；未取消 ⇒ 错误透传，`cancelled==true` ⇒ 映射裸 `CallCancelled`（spec FR-002a 第二轮裁决；第三轮定形态：不包装） | FR-011/FR-005 毒化 |
| 读边界发现 cancelled | raise `CallCancelled`（cancel 已完成 poison+release） | FR-002a/US-3-3 |

- `on_dispose`（dispose 注入）：`skip_response_body()` 成功 → `release` 回池；
  失败 → `poison + release` 后透传错误；`call.cancelled` 或 lease 已 None →
  no-op（与 cancel 竞争收敛）。
- 所有权（2026-10-25 analyze C1）：处置动作统一经 `Call.lease` 单点生效
  （BodyBridge 持 Call 引用触发处置，不自持租约副本）；「置 None」与
  处置完成在同一步，杜绝双写与时序错位。
- **不变量 I-4**（0 错路由）：回池当且仅当「发送完成 ∧ 体完整消费或 skip
  成功」（03 §3.2）；其余一切路径毒化。

### 实体 5：错误变体

| 变体 | 触发 | 判别 |
| --- | --- | --- |
| `CallCancelled`（suberror） | 预取消 / 在途取消（handle_cancellation→None）/ body 阶段边界发现 cancelled | `err is CallCancelled`（FR-003） |
| `CallStateError`（suberror） | 非 Pending 态二次 execute（完成/失败/取消后） | `err is CallStateError`（FR-001，plan 定名随本仓惯例） |

均 `derive(@debug.Debug)`；网络错误不包装、原样透传（FR-011）。

## 2. 不变量汇总

- I-1 一次性 / I-2 折叠一次 / I-3 租约唯一处置 / I-4 归池前提（上表）。
- I-5 取消幂等：`cancel()` 重入无错无副作用；`Task::cancel` 对已终止任务
  no-op（上游语义）。
- I-6 收尾仅同步：`CallCancelled` 映射后的清理只用同步操作
  （poison/release/close）——handle_cancellation 返回 None 后 async 操作
  仍会立即取消（R1 证据）。
- I-7 公开面零泄漏：上述全部私有字段不进 `.mbti`；白盒经同包 `_wbtest.mbt`
  直读（004 R7 先例）。

## 3. 状态迁移

**图 1：Call 一次性状态机（FR-001）**

```text
Pending ──execute──▶ Executing ──成功──▶ Done(响应已交付)
   │                    │─失败──▶ Done(错误已透传)
   │                    │─cancel──▶ Done(CallCancelled)
   └─cancel──▶ cancelled=true（execute 首检即 raise）
再次 execute（Executing|Done）──▶ raise CallStateError
```

**图 2：租约处置状态机（FR-005，0 错路由）**

```text
held ──体读完(Consumed)──────────▶ release（回池）──▶ None
held ──dispose→skip 成功─────────▶ release（回池）──▶ None
held ──dispose→skip 失败─────────▶ poison+release ──▶ None（错误透传）
held ──体读网络错误──────────────▶ poison+release ──▶ None（错误透传）
held ──exchange 内取消/异常──────▶ poison+release ──▶ None（CallCancelled/错误）
held ──body 阶段 cancel──────────▶ poison+release ──▶ None（cancel 内完成）
None（已处置）──迟到 cancel──────▶ 无操作（FR-012）
未处置且未 dispose 即弃─────────▶ 租约滞留（调用方责任；F9 欠账文档化）
```

## 4. P02 回调契约对接（契约面）

| ResponseBodyEvent | 本包处置器行为 |
| --- | --- |
| Consumed | release + lease→None（同步） |
| Dropped | 仅状态（真实处置在 dispose 的 on_dispose 异步步） |
| Abandoned | 由本包在毒化收尾按 `consumed()/dropped()` 查询触发（P02 契约授予 owner 的收尾权；默认路径是 dispose/drop 文档化后的用户责任） |
