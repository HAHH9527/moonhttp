# Contract：P04 连接池公开面（src/client/pkg.generated.mbti 冻结面）

> 本文是 plan 对 `.mbti` 冻结面的**事前契约**：implement 完成后
> `moon info` 产出的 `src/client/pkg.generated.mbti` 以本清单为对账面
> （计划外公开项为零；SC-007）。命名全 snake_case（本仓 `.mbti` 零
> camelCase，FR-012/P6）。
> 字段级结构见 data-model.md；本文只记公开可见面与方法契约。

## 1. 冻结面清单（按包分组）

### `hahh9527/moonhttp/client`（门面包，池宿主）

```text
// placeholder 保留不删（裁决 P6；删除留给 implement 收口片）。
// 注：现签名 placeholder() -> Bool，保留原形态。
pub fn placeholder() -> Bool
// Types
pub struct Address          // 三元组；字段全 priv（data-model 实体 1）
pub struct ConnectionPool   // 字段全 priv（实体 2 外壳）
pub struct Lease            // 字段全 priv（实体 4）

// Address（FR-014；equal/hash 形态沿 P01 HttpUrl 先例，core mbti:76-79）
// Address::new 为 noraise：规范化在 new 内部单点收口
pub fn Address::new(scheme~ : String, host~ : String, port~ : Int) -> Address
pub fn Address::scheme(Self) -> String
pub fn Address::host(Self) -> String
pub fn Address::port(Self) -> Int
pub fn Address::equal(Self, Self) -> Bool
pub fn Address::hash(Self) -> Int

// ConnectionPool（C4 裁决：new 仅两参；注入时钟走私有构造，R2，不进本面）
// acquire：FR-001/004/008/015；evict 两入口：FR-005（R6 决策 -> Unit）
// 观测访问器：FR-007/FR-013（stale_evictions 仅超期剔除口径）
pub fn ConnectionPool::new(max_idle? : Int, keep_alive_ms? : Int) -> ConnectionPool
pub async fn ConnectionPool::acquire(Self, Address) -> Lease raise
pub fn ConnectionPool::evict_expired(Self) -> Unit
pub fn ConnectionPool::evict_all(Self) -> Unit
pub fn ConnectionPool::stale_evictions(Self) -> Int
pub fn ConnectionPool::per_host_total(Self, Address) -> Int

// Lease（FR-002/011/018；均为同步——关闭原语 Client::close 同步，http mbti:65）
pub fn Lease::release(Self) -> Unit
pub fn Lease::poison(Self) -> Unit
```

### `hahh9527/moonhttp/core`

期望 **零 diff**（P04 不改 core 任何文件；`HttpUrl`/`Headers` 等既有冻结面
原样）。

### `hahh9527/moonhttp/internal/fixtures`（增量，internal 非对外承诺）

`.mbti` 增面**逐处归因**（T025 先例，003 tasks）：

| 增面 | 归因 |
| --- | --- |
| `ScriptedServer::accepted_total(Self) -> Int` | FR-009 外部证据 / US-2 场景 2（R5 F-5） |
| `ScriptedServer::conn_request_counts(Self) -> Array[Int]` | 复用自证（长跑 keep-alive ≥2 请求）/ US-2 场景 2（R5 F-6） |
| 次序脚本类型（`RouteScript`/`Sequence`）与 `mount_sequence` 入口 | FR-010 集成桩 / US-4 场景 2（R5 F-7/R9） |

## 2. 方法契约（行为语义，正文为 spec FR 的 plan 级细化）

### `ConnectionPool::new(max_idle?, keep_alive_ms?)`

- 缺省 5 / 300_000ms；`max_idle` MUST > 0、`keep_alive_ms` MUST ≥ 0
  （违反为调用方契约错误，panic——构造期快速失败）。
- 时钟绑真实 `@async.now()`；白盒测试经私有构造入口换注入时钟（R2）。

### `ConnectionPool::acquire(addr)`（async，可 raise）

1. 上锁（异步路径 `acquire()/release()`，R3）后：先做**惰性剔除**——
   `idle[addr]` 中超期条目全部弹出并关闭（每条 `stale_evictions` +1）。
2. 栈非空 ⇒ LIFO `pop()`（FR-004），id 迁 idle→borrowed，返回 Lease
   （released=false，poisoned=false）。
3. 栈空 ⇒ 解锁后 `Client::Client(uri)` 新建（D13；uri=
   `\{scheme}://\{host}:\{port}`，C-1/C-10）——**解锁后建连**（临界区
   无 IO，FR-006）；成功则 `per_host_total[addr]` +1、id 入 borrowed。
4. 建连失败 ⇒ 错误原样透传，池状态零变化（FR-015：无半租约、计数
   不虚增——per_host_total 的 +1 只发生在建连成功后）。
5. 独占（FR-001）：borrowed 中的 id 不可能被二次弹出（不变量 1）。

### `Lease::release()`（同步）

- `released == true` ⇒ no-op（FR-018）。
- 首次调用：置 released；上锁（同步路径 `try_acquire`，失败即 abort，
  R3）后——
  1. 先做**惰性剔除**（与 `acquire` 第 1 步共用同一超期判定函数，R2
     时间语义单点/不变量 7）：`idle[addr]` 中超期条目自尾向头全部弹出
     并 `close`（不破坏 R4.1 的 LIFO 序），每条 `stale_evictions` +1
     （FR-007/T014 口径：release 时超期条目不入栈）。
  2. 评估归池谓词——
     - `poisoned == false` 且 `idle[addr].length() < max_idle` ⇒ 回栈
       （idle_since = now_ms()，FR-002 池侧谓词；body 已消费完是调用方
       契约，P5）；
     - 否则（毒化 ∨ 栈满）⇒ `conn.close()`（幂等，C-3），id → closed；
       **不加 stale_evictions**（FR-007 口径：该计数只属于上面第 1 步
       的超期剔除分支，毒化/栈满不计）。

### `Lease::poison()`（同步）

- 仅置 `poisoned = true`；已终结 no-op；不碰锁（Lease 自身标记，
  无共享状态）。毒化的关闭动作延后到 release（spec US-4 场景 1 口径：
  release 时关闭、idle 不增长）。

### `ConnectionPool::evict_expired()`（同步，FR-005）

- 上锁（try_acquire，失败即 abort，R3）后遍历**全桶**（遍历序无关，
  R4.2）：逐桶自尾向头剔除超期条目并关闭，每条 `stale_evictions` +1；
  无超期 ⇒ 零变化。幂等：连续调用第二次零剔除。
- 同步入口不 await（D15）；周期驱动在调用方 task group（P05/P09/P10）。

### `ConnectionPool::evict_all()`（同步，FR-005）

- 上锁后清空全部桶并逐一 `conn.close()`（幂等）；**不加
  stale_evictions**（Q3 口径）；borrowed 不受影响（只清空闲，在租连接
  由其 Lease 生命周期管理）。幂等：第二次调用零效果、零错误。

### 观测访问器

- `stale_evictions()`：只增不减，语义见 data-model 实体 2 注记（含
  03 §3.4 偏移登记指引）。
- `per_host_total(addr)`：按键查询；未见过 key 返回 0；单调不减
  （FR-013：观测非硬上限——同 addr 并发租借数不受其约束）。

## 3. 明确不进公开面的项（防泄漏）

- 时钟：`now_ms` 字段与私有构造入口（R2）。
- `PoolInner`/`IdleLease` 全部内部结构、`conn_id`、三态集合（白盒测试
  经同包 `_wbtest.mbt` 直读，R7）。
- `placeholder` 原样保留（P6）——删除动作留给 implement 收口片。
- js 路径：不写任何 `#cfg(js)` 空实现/直通分支（D14/D9：js 未验证，
  归 P05/P09 的 js 路径处理）。
