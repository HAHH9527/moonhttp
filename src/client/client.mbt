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
