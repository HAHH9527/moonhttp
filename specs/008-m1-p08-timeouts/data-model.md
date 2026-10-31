# Data Model: M1-P08 四类超时与 per-call 配置

**Branch**: `008-m1-p08-timeouts` | **Date**: 2026-10-30
**Spec**: [spec.md](spec.md) | **Research**: [research.md](research.md)
（R1–R12 决策与证据在彼处，本文只承载模型）

## 实体 1：Timeouts（配置标量）

```
pub struct Timeouts {
  connect_ms : Int = 10_000   // 连接伞（建连段，含 DNS——FR-007）
  write_ms   : Int = 10_000   // 写窗（每次写调用——R3）
  read_ms    : Int = 10_000   // 读窗（收头调用/每次体读——R4）
  call_ms    : Int = 0        // call 伞（execute 全程；0=不建窗）
}
```

- 构建期不可变；HttpClient 持有；Call 经 `self.client.timeouts` 同包
  直读（P07 开关同形态）。校验：负值 ⇒ build() 单点 abort（C5）；
  0 ⇒ 该级伞/窗不建立（FR-001，非「立即到期」）。

## 实体 2：HttpTimeout（超时错误）

```
pub suberror HttpTimeout { Connect / Write / Read / Call }
```

- 注入通道：`with_timeout(..., error=)`（连接伞/写窗/读窗）与标记位
  选定（call 伞，R1）。判别面 `err is`；透传无包装（FR-005）。
- 与 P07 判定器的接点＝error_family 三行（R5）：`Connect`（stage=
  Connect）→ ConnectFailure；`Write/Read/Call` → Other。decide 零改动。

## 实体 3：HttpClient / Call 字段增量（全 priv）

```
pub struct HttpClient {
  priv pool : ConnectionPool            // 既有
  priv retry_on_connection_failure : Bool  // 既有（P07）
  priv timeouts : Timeouts              // 新
  priv follow_redirects : Bool          // 新（缺省 true）
  priv follow_ssl_redirects : Bool      // 新（缺省 true）
}
pub struct Call {
  // 既有字段不动；新增：
  priv mut call_timeout_fired : Bool    // 看门者标记（实体 4）
}
```

- `HttpClient::new` 签名不变（FR-012），字面量补缺省。Call 一次性状
  态机 ⇒ 标记无复位需求（单 execute 生命周期，I-1）。

## 实体 4：看门者（call 伞逸出通道，R1/Shape C）

```
execute():
  state=Executing; errdefer{ state=Done; task=None }
  with_task_group() <| group:
    task   = group.spawn(exchange_loop)      // 既有
    self.task = Some(task)                    // 既有
    if call_ms > 0:
      group.spawn(() => {                     // 新（有界例外①）
        sleep(call_ms)
        self.call_timeout_fired = true        //   同步置位先于取消
        task.cancel()                         //   任务级取消直达在途 await
      })
    try { handle_cancellation(task.wait()) }  // 既有
  match outcome:
    Delivered(resp) => ...                    // 既有
    Cancelled =>                              // 改：变体选择（有界例外①）
      self.poison_release()
      if self.call_timeout_fired { raise HttpTimeout::Call }
      else { raise CallCancelled }            // 用户取消路径逐位不变
```

状态迁移图（叠加在 P05 图 1 上，新增边以「超时」标注）：

```
Executing ──交付──▶ Done（成功）
Executing ──用户 cancel──▶ Done + 裸 CallCancelled     （既有边，不变）
Executing ──看门者到期──▶ Done + HttpTimeout::Call     （新边，标记位选定）
Executing ──失败逸出──▶ Done + 原始错误（errdefer 兜底）  （既有边；超时类
                          错误 Write/Read 亦走此边）
```

竞争窗口裁定：标记置位与取消同为看门者协程内的顺序同步/异步段——
标记先置、取消后发 ⇒ 收尾分支目睹标记时取消必已发生；用户 cancel 与
看门者 cancel 竞争时，收尾分支读到的标记值即裁决（二择一终态，US-5-2
不赌赢家；cancel 明确先到 ⇒ 标记假 ⇒ 裸 CallCancelled，反向隔离）。

## 实体 5：四级伞接线点位图（叠加在 P05/P06/P07 管线上）

```
execute()                                      ④ call 伞（实体 4，全程）
  exchange_loop()（P06，循环/prior/预算零改动）
    轮级 errdefer（P07 既有，毒化单点）
    轮内尝试子循环（P07 既有，≤2 attempts）
      ensure_lease(addr)
      连接伞＝看门者同型（R2 订正）：子任务 acquire + 定时器 cancel
      + wait 交付（① 每 attempt 新伞）
      exchange_with_lease(request, lease)
        last_stage = Send
        with_timeout(write_ms, conn.request)     ② 写窗：header 写
        Bytes → with_timeout(write_ms, write_once) ② 写窗：整写
        Stream → filler(Writer 门面)             ② 写窗：每次用户写调用（R3）
        last_stage = ReadHead
        with_timeout(read_ms, end_request)       ③ 读窗：收头（含 1xx，C4）
    follow_up_request(+两开关门，R7)
  体消费期（交付后，call 伞外——FR-004）
    BodyBridge.read_checked → with_timeout(read_ms, 内层读)  ③ 读窗：体读
                               （读错误 ⇒ 既有 poison+release，S5）
```

拓扑纪律：循环/捕获/毒化/预算/决策表机器零改动；改动点＝①②③的
包裹插入 + 实体 4 的两处有界例外 + follow_up_request 两门（FR-002）。

## 实体 6：HttpClientBuilder（派生面，双入口）

```
HttpClient::new_builder(pool) -> HttpClientBuilder    // pool 根，全缺省
HttpClient::builder()          -> HttpClientBuilder   // 自既有 client 派生
  //（pool 引用共享、标量缺省=被派生方当前值——OkHttp newBuilder 同形）
  .timeouts(Timeouts) .follow_redirects(Bool) .follow_ssl_redirects(Bool)
  .retry_on_connection_failure(Bool)                  // 链式，P01 家法
  .build() -> HttpClient                              // 负值校验单点（C5）
```

- 共享 pool 引用语义（US-4-1 连接记账同池）；标量覆盖仅影响派生方；
  派生链（A→B→C）经 `builder()` 逐级缺省继承。
- Request::new_builder（core）：五要素保三换（url/method/body 换、
  headers/tag 保留，R6）——与既有 RequestBuilder 复用（同一构建器，
  新增派生构造入口）。

## 实体 7：跟随开关两门（follow_up_request 决策表扩展）

```
3xx 码集命中 ──▶ !follow_redirects ? Terminal
             ──▶ Location 门（既有）
             ──▶ resolve 成功 ──▶ 跨 scheme && !follow_ssl_redirects ? Terminal
             ──▶ 既有方法分叉（保持/降级/重放）
```

- 门序＝5.5.0 buildRedirectRequest 严格对拍（R7）；Terminal 短路 ⇒
  prior 链不累积、follow_ups 零推进（INV-4 计数点在决策表后，天然满
  足）；判据载体 `Response::prior() is None`（S7）。

## 不变量（INV-T1..T5）

- **INV-T1（0=无窗）**：任一阈值 0 ⇒ 该级伞/窗不建立、无 Timer 构造；
  call_ms=0 ⇒ 看门者不派生（FR-001）。
- **INV-T2（变体恰达）**：call 伞到期终态恰为 `HttpTimeout::Call`；
  用户取消终态恰为裸 `CallCancelled`（标记位裁决，R1）；写/读窗终态
  恰为对应变体且无包装（FR-005）。
- **INV-T3（池守恒全交叠）**：连接伞到期与建连完成的任何交叠下，
  004 INV-5 恒等式成立——伞截断在途建连 ⇒ 记账零发生（零状态）；
  记账已完成 ⇒ 租约经 wait 必达（R2 订正形态；US-3-3 收敛断言）。
- **INV-T4（毒化全段覆盖）**：写/收头超时逸出 ⇒ 轮级 errdefer 毒化；
  体读超时 ⇒ read_checked 既有毒化点；call 伞到期 ⇒ cancel 链
  poison_release（取消不可捕获、defer 照常触发，R4）——四伞任一触
  发后 idle 不含该连接（FR-006/US-3）。
- **INV-T5（缺省零扰动）**：缺省 Timeouts（10s/10s/10s/0）与两开关
  true 下，P05/P06/P07 全部既有行为面逐位不变（决策表门序、重试机
  器、取消语义零变化；US-6-3/DoD 4 回归面）。

## 与 007 data-model 的接缝

- P07 `last_stage`（Connect/Send/ReadHead）即伞的阶段归属锚（实体 5
  点位与插桩点一一对应）；P07 尝试子循环的 catch 分支新增族来源仅
  error_family（R5），decide/子循环骨架零改动。
- P07 `stream_body_entered`（filler 调用即置位）语义不变——门面不改
  变 filler 被调用的事实（R3）。
