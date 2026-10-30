# Data Model: 连接失败重试 stale-retry（M1-P07）

> 2026-10-30。承接 spec FR-001～FR-011 与 research R1–R7 的机制形状。
> 本文只写新增实体与不变量；既有 Call/Lease/Pool 实体见 004/005/006
> data-model，不重复。

## 实体

### 1. SendStage（priv enum，新增）

阶段标记——L1 自有调用点边界（02 §4「写路径阶段化由 L1 自身控制」）。

| 变体 | 置位点（前置赋值） | 对应失败语义 |
| --- | --- | --- |
| `Connect` | `ensure_lease` 调用前（follow_up.mbt 捕获段） | 建连失败（无租约持有，池状态零变化） |
| `Send` | `request` / `write_once` / `filler` 调用前（exchange.mbt:122/127/129） | 发头/写体失败（含 flush 推迟形态进入本阶段之前的调用点） |
| `ReadHead` | `end_request` 调用前（exchange.mbt:135） | 读响应头失败（可能含前序缓冲数据的 flush 失败——按 R1 按 L1 调用点定义） |

### 2. ErrFamily（priv enum，新增）——族检测结果（段相关）

`error_family(stage, err)` 按**段归类**（qod-2 必修②：签名带 stage，
否则 OSError 双属矛盾无解）。match 顺序即优先级：`Protocol` 首判
（OkHttp :171-173 首行同构）→ 段相关 Stale/ConnectFailure →
`Other`。

| 变体 | 段 × 错误值 → 族 | 可重试性 |
| --- | --- | --- |
| `Protocol` | 任意段 × `@http.BadRequest`/`@http.HttpVersionNotSupported(_)`/`@http.IncorrectBodyLength` | ❌（毒化照常、零计数） |
| `ConnectFailure` | `stage == Connect` × `@os_error.OSError(_)`、`@socket.ResolveHostnameError(_)`、`@tls.TlsError(_)`/`@tls.ConnectionClosed`（握手族） | ✅（无毒化义务——无租约） |
| `Stale` | `stage ∈ {Send, ReadHead}` × `@io.ReaderClosed`、`@os_error.OSError(_)`（RST 族，Windows EOF 折算并入）、`@tls.ConnectionClosed`/`@tls.TlsError(_)`（传输段同族） | ✅（ReadHead 段＝stale 判定；Send 段再过体可重放门） |
| `Other` | 其余（未知错误、js 降级恒值） | ❌（透传；毒化照常经逸出 errdefer） |

### 3. RetryDecision + decide()（priv，纯函数）

六条件合取的机械形态（FR-001；**合取式判定为可交换的，重排无损**
——与 OkHttp isRecoverable 顺序不同仅落在双 Fail 格，观测面一致，
qod-2 点 2-6 注记）：

```text
replayable(body, entered):
  None | Bytes        → true          # 空体/静态体恒可重放（Bytes 部分写出后仍重放，C2）
  Stream              → !entered      # 保守封锁（R3：调用即置位）

decide(stage, family, body, stream_body_entered, attempts, enabled, cancelled):
  cancelled                              → Fail   # FR-006 取消优先（外层 guard 亦兜底）
  !enabled                               → Fail   # FR-010 开关
  attempts >= 2                          → Fail   # FR-005 预算（按请求代次）
  family == Protocol                     → Fail   # FR-002（毒化照常，经逸出/捕获路径）
  family == Other                        → Fail   # 未知错误透传
  !replayable(body, stream_body_entered) → Fail   # FR-003 体可重放门（qod-2 必修①：
                                                  #  ReadHead∧Stream∧entered 必经此格 Fail）
  stage == Connect ∧ family ∈ {Stale, ConnectFailure} → Retry   # FR-001 建连失败族
  stage == Send    ∧ family == Stale     → Retry  # 已过体可重放门
  stage == ReadHead ∧ family == Stale    → Retry  # stale 判定主路径
  否则                                    → Fail   # 收尾兜底行（qod-2 必修①，全域定义）
```

成功路径不进入本函数（无捕获即无判定）。

### 4. Call 新增 priv 字段（http_client.mbt；qod-2 必修④/建议修订）

| 字段 | 类型 | 语义 | 生命周期 |
| --- | --- | --- | --- |
| `last_stage` | `SendStage` | 当前 attempt 的阶段标记 | **子循环体首行复位为 `Connect`**（防跨 attempt 残留误计数）；各调用点前置赋值刷新 |
| `stream_body_entered` | `Bool` | filler 已被调用（保守封锁口径，R3） | **子循环体首行复位 false** |

（开关值不复制进 Call：`Call` 已持 `client` 同包 priv 可读，判定处
直读 `client.retry_on_connection_failure`——宪法 VI 冗余字段否决，
qod-2 点 4-5 采纳。`HttpClient` 增 priv 字段承载开关值，`new_call`
传入 Call 构造。）

### 5. ConnectionPool::note_stale_hit（priv 方法，client.mbt）

锁内 `inner.stale_evictions += 1`（与 evict_bucket_locked:360 同一字
段的第二个递增点；临界区无 IO 无 await，INV-4 满足）。调用判据统一
（qod-2 必修③，全文三处同步）：**`decide == Retry ∧ stage ==
ReadHead ∧ family == Stale`**——调用点仅一：exchange 段捕获分支
`poison_release()` 之后、`continue` 之前。建连段无租约不构成陈旧命
中；attempt≥2 恒 Fail ⇒ 每 execute 每代次至多计 1。

## 子循环状态迁移（轮内；qod-2 必修⑤：统一为 family → decide → 分支内 poison）

```text
        ┌────────────────────────────────────────────────┐
        │  attempt N（N=1,2）                             │
        │  体首行：last_stage=Connect; stream_body_entered=false; guard 取消 │
        └────────────────────────────────────────────────┘
   ensure_lease ──err──> family(Connect, err) → decide(Connect,…)
        │                  ├─Retry→（attempts<2 已在 decide）→ 下一 attempt（无毒化义务）
        │                  └─Fail→ raise（逸出；租约 None ⇒ errdefer no-op）
        ▼ 成功（持有租约）
   errdefer poison_release（单点登记，位于子循环之前——逸出路径毒化单点，006 语义）
   exchange_with_lease ──err──> family(last_stage, err) → decide(…)
        │                        ├─Retry→ poison_release()【进入重试分支前必完成】
        │                        │        (ReadHead∧Stale) → note_stale_hit()
        │                        │        → 下一 attempt（lease=None → 新建）
        │                        └─Fail→ raise err（原始值透传；逸出 errdefer 幂等兜底）
        ▼ 成功
   break（返回决策表；轮结构零变化）
```

## 不变量（INV-R1..R5）

- **INV-R1 毒化前置**：进入重试分支（continue 下一 attempt）前，旧
  租毒化必已完成（poison + close 不回池 + lease 置 None）；逸出路
  径毒化归属＝轮级 errdefer 单点（FR-007；006 D-2 加注承接）。
- **INV-R2 计数单点**：`stale_evictions` 每 stale 命中恰 +1，在进入
  重试分支时发生、与重试最终结果无关；Protocol/Other/预算耗尽路径
  零计数（FR-004）。
- **INV-R3 预算有界**：每请求代次 attempts ≤ 2；重试不触碰
  `follow_ups`/`gen`/决策表/prior 链（FR-005/FR-009；总线上请求数
  上界 ≤42，spec Assumptions C3 修正口径）。
- **INV-R4 请求不可变**：重试重放的请求对象、折叠头缓存、线上字节
  与原始 attempt 逐字节一致（FR-009；同代次零重折叠）。
- **INV-R5 公开面冻结**：client 公开面增量恰为 `HttpClient::new`
  可选参数；`note_stale_hit`/判定器/三枚举全 priv（FR-011）。

## 与既有不变量的交互

- 004 INV-5 守恒恒等式：毒化→closed、新租→新建（同锁段
  next_conn_id+1，client.mbt:244-252）自动平衡，无需补丁。
- 004 INV-4 临界区约束：`note_stale_hit` 锁内无 IO 无 await ✓。
- 005 FR-003 裸 `CallCancelled`：取消经外层 guard 与
  `handle_cancellation` 映射，判定器在取消后不被触达（decide 首
  条件兜底）。
- 006 INV（排干先于换代）：重试不换代，排干语义零接触。
