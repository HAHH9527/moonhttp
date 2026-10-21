///|
pub fn placeholder() -> Bool {
  // 能力入口占位：客户端功能由 spec 驱动的垂直切片逐步替换
  true
}

///|
// 直连三元组池键（P04 data-model 实体 1，FR-014）：(scheme, host, port)
// 缺一不可；端口是键的一部分——上游 @http.Client 在构造期把 Host 头写进
// 持久头（R4.3），跨 host:port 复用同一连接会把请求发到错误源站。
// 键构造 noraise：不解析 URL、不做网络语义校验（窄语义，R4.3）。
// 字段恒为规范化形态（规范化在 new 内部单点收口），derive(Eq, Hash)
// 即键语义；equal/hash 显式方法面沿 P01 HttpUrl 先例（core mbti:76-79）。
pub struct Address {
  priv scheme : String // 小写化（"http"/"https"）
  priv host : String // 小写化；IPv6 字面量剥 [] 方括号
  priv port : Int32
} derive(Eq, Hash)

///|
// 消除 implicit_impl_as_method 警告 [0079] 的配套写法（决策 N1-A，
// core/http_url.mbt:29-32 先例）。
pub extend Address with Eq::{equal, not_equal}

///|
pub extend Address with Hash::{hash, hash_combine}

///|
// 键规范化单点收口（FR-014）：scheme/host 小写化、IPv6 字面量剥方括号。
pub fn Address::new(scheme~ : String, host~ : String, port~ : Int32) -> Address {
  {
    scheme: scheme.to_lower(),
    host: strip_ipv6_brackets(host.to_lower()),
    port,
  }
}

///|
// IPv6 字面量剥方括号："[" 前缀 + "]" 后缀形态剥离，其余原样（P01 HttpUrl
// 「剥方括号逐字存储」同款语义；host 已先小写化，IPv6 十六进制位一并归一）。
fn strip_ipv6_brackets(host : String) -> String {
  let len = host.length()
  if len >= 2 && host[0] == '[' && host[len - 1] == ']' {
    host[1:len - 1].to_owned()
  } else {
    host
  }
}

///|
pub fn Address::scheme(self : Address) -> String {
  self.scheme
}

///|
pub fn Address::host(self : Address) -> String {
  self.host
}

///|
pub fn Address::port(self : Address) -> Int32 {
  self.port
}

///|
// 构造校验错误（priv 不进公开面；P04-FR② 判据通道，形态裁决见
// pool_wbtest.mbt 文件头注）。
priv suberror PoolConfigError {
  PoolConfigError(String)
}

///|
// 池配置纯校验（可 raise ⇒ 双 target 均可断言；D15 纯函数口径）。
fn validate_pool_config(
  max_idle~ : Int32,
  keep_alive_ms~ : Int32,
) -> Unit raise PoolConfigError {
  if max_idle <= 0 {
    raise PoolConfigError("max_idle must be > 0, got \{max_idle}")
  }
  if keep_alive_ms < 0 {
    raise PoolConfigError("keep_alive_ms must be >= 0, got \{keep_alive_ms}")
  }
}

///|
// 缺省配置（data-model 常量表）：每地址空闲栈容量 5；空闲超期 5min（毫秒）。
const DEFAULT_MAX_IDLE : Int32 = 5

///|
const DEFAULT_KEEP_ALIVE_MS : Int32 = 300_000

///|
// 空闲栈条目（data-model 实体 3，不进公开面）：保温的底层连接 + 池内单调
// id + 入栈时刻快照。idle_since 入栈后不可变；超期判定只读它（不变量 7）。
priv struct IdleLease {
  conn : @http.Client
  conn_id : Int32
  idle_since : Int64
}

///|
// 互斥保护的可变状态（data-model 实体 2，不进公开面）。
// 三集合（idle/borrowed/closed）承载守恒恒等式（不变量 5）；per_host_total
// 与 stale_evictions 为公开观测计数（FR-007/013，Q3 口径见 data-model）。
priv struct PoolInner {
  idle : Map[Address, Array[IdleLease]] // LIFO 栈桶（R4.1/R4.2）
  borrowed : Map[Int32, Unit] // conn_id 在租（独占中）
  closed : Map[Int32, Unit] // conn_id 已关（终态）
  per_host_total : Map[Address, Int32] // 观测：按键累计新建
  mut stale_evictions : Int32 // 观测：仅超期剔除计数（Q3 口径）
  mut next_conn_id : Int32 // 单调发号器，1 起
}

///|
// 连接池公开外壳（data-model 实体 2 / contracts §1）：字段全 priv。
// inner 为共享可变状态，恒经 lock 保护（C3 裁决保留互斥锁；锁用法分流
// R3：异步路径 acquire/release，同步路径 try_acquire 失败即 abort——
// 临界区无 IO 无 await，FR-006/不变量 4）。
pub struct ConnectionPool {
  priv max_idle : Int32 // > 0
  priv keep_alive_ms : Int32 // >= 0
  priv lock : @async.Mutex
  priv inner : PoolInner
  priv now_ms : () -> Int64 // 注入式时钟（R2），缺省绑 @async.now；构造期注入后不重赋值
}

///|
// 独占租约（data-model 实体 4，公开面 FR-001/002/011/018）：acquire 的
// 返回值；release 按归池谓词回流或关闭；poison 仅置标记（池只认它，P4）；
// released 为终结幂等锚（FR-018，no-op 短路）。
// 注：poisoned 的 mut 自 T009（poison 写入）在场；released 的 mut 自
// T012（终结幂等写入门）引入——先以不可变形态在场（避免 unused_mut 假红）。
pub struct Lease {
  priv conn : @http.Client
  priv conn_id : Int32
  priv addr : Address
  priv pool : ConnectionPool
  priv mut poisoned : Bool
  priv mut released : Bool
}

///|
// 公开构造（C4 裁决：仅两参；缺省 5 / 300_000）。max_idle MUST > 0、
// keep_alive_ms MUST ≥ 0——违反为调用方契约错误，构造期快速失败（abort，
// contracts §2）。校验逻辑经 validate_pool_config 承载（可 raise ⇒ 双
// target 可断言，P04-FR②；panic 在 native 不可断言，裁决见 wbtest 头注）。
// 时钟绑真实 @async.now；白盒注入走私有构造 with_clock（R2，不进公开面）。
pub fn ConnectionPool::new(
  max_idle~ : Int32 = DEFAULT_MAX_IDLE,
  keep_alive_ms~ : Int32 = DEFAULT_KEEP_ALIVE_MS,
) -> ConnectionPool {
  validate_pool_config(max_idle~, keep_alive_ms~) catch {
    PoolConfigError(msg) => abort(msg)
  }
  ConnectionPool::with_clock(max_idle~, keep_alive_ms~, now_fn=fn() {
    @async.now()
  })
}

///|
// 私有构造（R2）：白盒测试注入受控时钟的唯一入口；非 pub 方法即包私有，
// 不进公开 .mbti。
fn ConnectionPool::with_clock(
  max_idle~ : Int32,
  keep_alive_ms~ : Int32,
  now_fn~ : () -> Int64,
) -> ConnectionPool {
  {
    max_idle,
    keep_alive_ms,
    lock: @async.Mutex(),
    inner: {
      idle: Map([], capacity=8),
      borrowed: Map([], capacity=8),
      closed: Map([], capacity=8),
      per_host_total: Map([], capacity=8),
      stale_evictions: 0,
      next_conn_id: 1,
    },
    now_ms: now_fn,
  }
}

///|
// 同步路径锁纪律（R3）：try_acquire 失败即 abort（fail fast）——失败只可能
// 意味「有人跨 await 持锁」，即 FR-006 临界区不变量已被破坏，属实现级缺陷，
// 立即爆红而非静默跳过（静默跳过会让 SC-004 确定性断言变 flaky）。
fn sync_lock_or_abort(lock : @async.Mutex, site : String) -> Unit {
  if !lock.try_acquire() {
    abort(
      "\{site}：同步路径锁竞争——FR-006 临界区不变量已被破坏（R3 fail fast）",
    )
  }
}

///|
// 独占租借（contracts §2，FR-001/004/008/015）。T005 交付建连路径：
// 锁内查桶（pop 命中路径 T006 接入）→ 解锁后建连（FR-006 临界区无 IO）→
// 成功才记账——conn_id 分配与入 borrowed 同锁段，守恒恒等式无隙（不变量
// 5）；per_host_total 新建必然 +1（不变量 6）。建连失败错误原样透传、
// 池状态零变化（FR-015：无半租约、计数不虚增）。uri 形态
// \{scheme}://\{host}:\{port} 仅经 Client::Client(uri) 单点收口（D13）。
pub async fn ConnectionPool::acquire(
  self : ConnectionPool,
  addr : Address,
) -> Lease {
  // 锁内查桶：命中 LIFO pop（FR-004，尾=最热）；id 迁 idle→borrowed 同
  // 锁段（不变量 5 无隙）。此段即 FR-006 临界区形态：无 IO、无 await。
  // 先做惰性剔除（FR-005 下半/contracts §2 步骤 1：超期条目弹出关闭、
  // 每条 stale_evictions +1，与 evict_expired 共享判定单点），再评估命中。
  self.lock.acquire()
  let mut hit : IdleLease? = None
  match self.inner.idle.get(addr) {
    Some(bucket) => {
      self.evict_bucket_locked(bucket)
      match bucket.pop() {
        Some(idle) => {
          self.inner.borrowed[idle.conn_id] = ()
          hit = Some(idle)
        }
        None => ()
      }
    }
    None => ()
  }
  self.lock.release()
  match hit {
    Some(idle) =>
      return {
        conn: idle.conn,
        conn_id: idle.conn_id,
        addr,
        pool: self,
        poisoned: false,
        released: false,
      }
    None => ()
  }
  // 解锁后建连（FR-006）
  let uri = "\{addr.scheme()}://\{addr.host()}:\{addr.port()}"
  let client = @http.Client::Client(uri)
  // 建连成功才记账（不变量 5/6）
  self.lock.acquire()
  let conn_id = self.inner.next_conn_id
  self.inner.next_conn_id = conn_id + 1
  self.inner.per_host_total[addr] = self.inner.per_host_total
    .get(addr)
    .unwrap_or(0) +
    1
  self.inner.borrowed[conn_id] = ()
  self.lock.release()
  { conn: client, conn_id, addr, pool: self, poisoned: false, released: false, }
}

///|
// 归池判定（FR-002，contracts §2）：已终结（released）⇒ no-op（FR-018
// 终结幂等：不重复入栈、不二次关闭、不改任何计数）；首次调用置标记后——
// 同步锁（R3 fail fast）后评估归池谓词：未毒化 ∧ idle 未满 ⇒ push 尾部
// （idle_since = now_ms()，LIFO 尾=最热）；否则 close（幂等，C-3）且不计
// stale_evictions（FR-007 口径）。borrowed 移除两分支恒做（状态迁移
// Borrowed→Idle / Borrowed→Closed，不变量 5 守恒）。
pub fn Lease::release(self : Lease) -> Unit {
  if self.released {
    return
  }
  self.released = true
  let pool = self.pool
  sync_lock_or_abort(pool.lock, "Lease::release")
  let bucket = match pool.inner.idle.get(self.addr) {
    Some(b) => b
    None => {
      let fresh : Array[IdleLease] = []
      pool.inner.idle[self.addr] = fresh
      fresh
    }
  }
  // 惰性剔除（FR-005 下半/contracts §2 release 步骤 1，与 T013 共享判定
  // 单点）：超期条目自栈弹出关闭（每条 +1）——超期条目不入栈
  pool.evict_bucket_locked(bucket)
  let full = bucket.length() >= pool.max_idle
  if !self.poisoned && !full {
    // 回池：尾部 push（LIFO），入栈瞬间快照时钟（不变量 7：idle_since 不可变）
    bucket.push({
      conn: self.conn,
      conn_id: self.conn_id,
      idle_since: (pool.now_ms)(),
    })
    pool.inner.borrowed.remove(self.conn_id)
  } else {
    // 毒化 ∨ 栈满：close（幂等，C-3），不加 stale_evictions（Q3 口径）
    self.conn.close()
    pool.inner.borrowed.remove(self.conn_id)
    pool.inner.closed[self.conn_id] = ()
  }
  pool.lock.release()
}

///|
/// 毒化标记（FR-011，P4 裁决：池只认 poison 标记）：仅置 poisoned，不碰
/// 锁（Lease 自身标记，无共享状态）；关闭动作延后到 release（毒化分支 →
/// close，不计 stale_evictions）。已终结（released）⇒ no-op（FR-018）。
pub fn Lease::poison(self : Lease) -> Unit {
  if self.released {
    return
  }
  self.poisoned = true
}

///|
// 按键查询累计新建连接数（FR-007/FR-013）：未见过 key 返回 0；单调不减
// （观测非硬上限——同 addr 并发租借数不受其约束）。
pub fn ConnectionPool::per_host_total(
  self : ConnectionPool,
  addr : Address,
) -> Int32 {
  sync_lock_or_abort(self.lock, "per_host_total")
  let total = self.inner.per_host_total.get(addr).unwrap_or(0)
  self.lock.release()
  total
}

///|
// 超期剔除计数（FR-007，Q3 口径）：只计超期剔除（evict_expired 与
// acquire/release 惰性剔除每条 +1）；evict_all 关闭、毒化关闭、栈满关闭
// 一律不计（data-model 实体 2 注记与 03 §3.4 偏移登记）。
pub fn ConnectionPool::stale_evictions(self : ConnectionPool) -> Int32 {
  sync_lock_or_abort(self.lock, "stale_evictions")
  let count = self.inner.stale_evictions
  self.lock.release()
  count
}

///|
// 单桶超期剔除（持锁段内调用；T013/T014 共享的超期判定单点，R2 时间语义
// 单点/不变量 7）：自尾向头 splice（R4.1——不破坏 LIFO 序；R4.2——结果
// 不依赖 Map 迭代序）；每条关闭（幂等 C-3）、迁 Closed、stale_evictions +1。
fn ConnectionPool::evict_bucket_locked(
  self : ConnectionPool,
  bucket : Array[IdleLease],
) -> Unit {
  let mut i = bucket.length() - 1
  while i >= 0 {
    let entry = bucket[i]
    if (self.now_ms)() - entry.idle_since > self.keep_alive_ms.to_int64() {
      // remove(i)（splice 语义）：自尾向头遍历下，移除 i 不影响 < i 的下标
      let _ = bucket.remove(i)
      entry.conn.close()
      self.inner.closed[entry.conn_id] = ()
      self.inner.stale_evictions = self.inner.stale_evictions + 1
    }
    i = i - 1
  }
}

///|
// 全桶扫描的超期剔除（FR-005 显式入口，D15 同步无 await；R6：-> Unit，
// 观测走 stale_evictions()）：同步路径锁 fail fast（R3）；幂等——第二次
// 调用零剔除。周期驱动归调用方 task group（P05/P09/P10）。
pub fn ConnectionPool::evict_expired(self : ConnectionPool) -> Unit {
  sync_lock_or_abort(self.lock, "evict_expired")
  for _key, bucket in self.inner.idle {
    self.evict_bucket_locked(bucket)
  }
  self.lock.release()
}

///|
// 清空全部空闲桶（FR-005 显式入口，contracts §2）：同步锁 fail fast（R3）
// 后逐桶逐一 close（幂等 C-3）、迁 Closed；不加 stale_evictions（Q3 口径
// ——evict_all 可关未超期连接，非「陈旧」语义）；borrowed 不受影响（只清
// 空闲，在租连接由其 Lease 生命周期管理）。幂等：第二次调用零效果、零错误。
pub fn ConnectionPool::evict_all(self : ConnectionPool) -> Unit {
  sync_lock_or_abort(self.lock, "evict_all")
  for _key, bucket in self.inner.idle {
    for entry in bucket {
      entry.conn.close()
      self.inner.closed[entry.conn_id] = ()
    }
    let _ = bucket.clear()
  }
  self.lock.release()
}
