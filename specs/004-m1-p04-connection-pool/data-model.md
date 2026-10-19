# Data Model：P04 连接池（src/client）

> 契约面见 contracts/pool-api.md；本文记录实体、字段、不变量与状态迁移。
> 决策依据见 research.md（时钟 R2、锁策略 R3、选型 R4、夹具扩展 R5）。
> 全部类型仅依赖 `@http`/`@async` 公开 API 与本模块 core 包（宪法 I）。

## 常量

| 常量 | 值 | 语义 |
| --- | --- | --- |
| `DEFAULT_MAX_IDLE` | 5 | 每地址空闲栈容量缺省（种子口径；C4 裁决为构造参数） |
| `DEFAULT_KEEP_ALIVE_MS` | 300_000 | 空闲超期缺省 5min（毫秒，与 `@async.now()` 同单位） |

## 实体 1：Address（池键，FR-014）

```text
pub struct Address {
  priv scheme : String   // 小写化（"http"/"https"）
  priv host   : String   // 小写化；IPv6 字面量剥 [] 方括号
  priv port   : Int      // 端口是键的一部分（严禁跨端口复用连接，R4.3）
}

pub fn Address::new(scheme~ : String, host~ : String, port~ : Int) -> Address
  // 规范化在 new 内部单点收口（noraise）；语义与 P01 HttpUrl 冻结面对齐
  // （FR-014；P01 已交付，HttpUrl::equal/hash 先例见 core mbti:76-79）
pub fn Address::scheme(self) -> String
pub fn Address::host(self) -> String
pub fn Address::port(self) -> Int
pub fn Address::equal(self, other : Address) -> Bool
pub fn Address::hash(self) -> Int
```

不变量：
- 两个 Address 相等 ⇔ 规范化后三元组全等；同 host 不同端口/scheme 必为
  不同键（互不租借，FR-014）。
- 键构造 noraise：不解析 URL，不做网络语义校验（窄语义，R4.3）。

## 实体 2：PoolInner（互斥保护的可变状态，不进公开面）

```text
priv struct PoolInner {
  idle : Map[Address, Array[IdleLease]]  // LIFO 栈桶（R4.1/R4.2）
  borrowed : Map[Int, Unit]               // conn_id 在租（独占中）
  closed : Map[Int, Unit]                 // conn_id 已关（终态）
  per_host_total : Map[Address, Int]      // 观测：按键累计新建（FR-007/013）
  stale_evictions : Int                   // 观测：超期剔除计数（口径见下）
  next_conn_id : Int                      // 单调发号器，1 起
}

priv struct ConnectionPool {
  priv max_idle : Int                     // > 0
  priv keep_alive_ms : Int                // >= 0
  priv inner : Mutex[PoolInner]           // C3 裁决：保留互斥锁（R3 分流用法）
  priv mut now_ms : () -> Int64           // 注入式时钟（R2），缺省 @async.now
}
```

`stale_evictions` 计数口径（2026-10-19 裁决，Clarifications Q3）：
**只计超期剔除**——`evict_expired()` 的剔除与 acquire/release 惰性剔除
每条 +1；`evict_all()` 的关闭、毒化关闭、栈满关闭一律 **不计**（毒化/
栈满路径以 idle 不增长断言观测，spec US-4）。

**与 03 §3.4 的有意语义偏移（本节为两处登记之一，另一处在
research.md「R4.4 补记」）**：03 §3.4 毒化表原文的
`pool.stale_evictions += 1`（`03-connection-pool/README.md:102`）只出现在
「stale-retry 命中（02）」行——原义仅指 P07 的 stale-retry 命中。本口径
把「stale」有意扩展为「陈旧连接家族 ＝ 超期剔除 ＋ P07 stale-retry
命中」：因 stale-retry 归 P07 承载（集成归属见 spec DoD-2 映射口径），
M1 的 P04 内该家族当前只有超期剔除；P07 落地时其命中行照 03 §3.4 对
**同一计数器** +1，同名同族、无计数器二义。此为与上游文档的有意偏移，
非遗漏，analyze 对账时以本注记为准。

## 实体 3：IdleLease（空闲栈条目，不进公开面）

```text
priv struct IdleLease {
  conn : @http.Client      // 保温的底层连接
  conn_id : Int            // 池内单调 id（守恒断言的主键）
  idle_since : Int64       // 入栈瞬间的 now_ms() 快照；超期判定只读它
}
```

不变量：
- `idle_since` 入栈后不可变；超期 ⇔ `now_ms() - idle_since >
  keep_alive_ms`（纯函数，D15；时钟语义见 R2）。
- 栈内顺序即闲置顺序（尾=最热）；`Array` 长度 ≤ max_idle（入栈前判定）。

## 实体 4：Lease（独占租约，公开面 FR-001/FR-002/FR-011/FR-018）

```text
pub struct Lease {
  priv conn : @http.Client
  priv conn_id : Int
  priv addr : Address
  priv pool : ConnectionPool
  priv mut poisoned : Bool   // FR-011：毒化标记（池只认它，P4）
  priv mut released : Bool   // FR-018 终结标记（幂等锚；形态归 plan）
}

pub fn Lease::poison(self) -> Unit   // 仅置标记；已终结则为 no-op
pub fn Lease::release(self) -> Unit
  // 首次按 FR-002 判定归池或关闭；已终结 no-op
```

### 状态迁移（连接生命周期，conn_id 视角）

```text
            acquire(命中)                 acquire(未命中)
  ┌─────────────────────┐      ┌──────────────────────────────┐
  │ Idle ──pop──▶ Borrowed ◀──── │ 新建（Client::Client，per_host_total+1）
  │  ▲                │          └──────────────────────────────┘
  │  │ release(未毒化∧idle未满)   │
  │  │                ├─ release(毒化 ∨ idle满) ──▶ Closed（close 幂等）
  │  └─ evict_expired/惰性剔除 ──▶ Closed（stale_evictions +1）
  └─ evict_all ──▶ Closed（不计 stale_evictions）
  Borrowed ──(无此路径：毒化只置标记，关闭动作延后到 release)──▶ Closed
```

### 两条 W06 契约在模型上的落点

1. **终结幂等（FR-018）**：`released=true` 后，`release`/`poison` 一律
   no-op——不重复入栈、不二次关闭、不改任何计数。守恒恒等式在任意调用
   序列下保持（见不变量 5）。内部标记的物理形态（bool 字段/状态枚举）
   归 plan 实现期定，不进公开面（spec Clarifications Q5）。
2. **stale_evictions 口径**：仅「Idle ──超期──▶ Closed」迁移 +1；
   「Borrowed/Idle ──毒化/栈满──▶ Closed」与 evict_all 批量关闭均不加
   （口径与偏移登记见实体 2 注记，research R4.2 补记为第二处）。

## 不变量（全部可白盒断言）

1. **独占**：任一时刻一个 conn_id 至多属于 {borrowed, idle, closed} 之一，
   且 borrowed 中的 id 必有唯一存活 Lease 指向（FR-001）。
2. **容量**：`idle[addr].length() <= max_idle` 恒成立（FR-002/FR-003 栈满
   分支的镜像）。
3. **LIFO**：同桶内，`idle_since` 自尾向头单调不增（FR-004；超期剔除
   splice 不破坏该序）。
4. **临界区**：对 `inner` 的每次持锁段内无 IO、无 await（FR-006；
   锁用法分流见 R3——同步路径 try_acquire 失败即 abort）。
5. **守恒恒等式**：`borrowed.count + Σ idle.count + closed.count ==
   next_conn_id - 1`，对任意调用序列（含重复 release/poison、并发
   acquire、任意驱逐交错）恒成立（FR-009 内部证据；FR-018）。
6. **观测一致性**：`per_host_total` 单调不减；新建必然 +1，关闭与驱逐
   不回退（FR-007/FR-013：观测计数不是硬上限，P10 的 K=64 形态依赖）。
7. **时间单点**：全部超期判定只经 `now_ms()`，全池无第二个时间源
   （R2；`idle_since` 不可变）。

## 实体关系

- `ConnectionPool` 1 ─▶ N `IdleLease`（按 Address 分桶）
- `ConnectionPool` 1 ─▶ N `Lease`（在租；Lease 持 pool 引用用于 release 回流）
- `IdleLease` 1 ─▶ 1 `@http.Client`（构造期固化 Host，R4.3——键隔离的
  物理依据）
- `Address` ──键──▶ 桶与 `per_host_total`（equal/hash 即键语义）
