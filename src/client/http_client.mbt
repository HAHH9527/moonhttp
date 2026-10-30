///|
// http_client：P05 门面——HttpClient/Call/错误变体（contracts §1 冻结面，
// FR-008/FR-014；data-model 实体 1/2/5）。执行管线与取消接线随任务增量
// （T006/T007/T008）在同一包内展开（exchange.mbt/body_bridge.mbt）。
//
// 宪法 I：全部经 @async/@http 公开 API（research R1/R2 锚点表）；
// 宪法 VII：注释中文；`.mbti` 对账面 = contracts/call-api.md §1。

///|
// FR-003：取消错误（预取消 / 在途取消 / body 阶段边界发现 cancelled）。
pub suberror CallCancelled derive(@debug.Debug)

///|
// FR-001：一次性语义状态错误（非 Pending 态二次 execute）。
pub suberror CallStateError derive(@debug.Debug)

///|
// FR-005（P06）：follow-up 跳数超限——收到第 21 个仍需跟随的响应即抛
// （至多实际发出 20 个 follow-up、总请求数 21；对齐 5.5.0
// MAX_FOLLOW_UPS=20 的 ProtocolException，显式变体替代消息判别——R9）。
pub suberror TooManyFollowUps derive(@debug.Debug)

///|
// P08 FR-005：超时错误四变体（contracts/timeout-api.md §1 冻结面①）。
// 变体对应四级伞——Connect=连接伞（建连段，FR-007 含 DNS）/
// Write=写窗（每次写调用）/Read=读窗（收头调用+每次体读）/
// Call=call 伞（execute 全程）。判别面＝`err is`；透传无包装
// （FR-005）。call 伞变体经看门者标记位选定（research R1——上游
// with_timeout 包 execute 的形态会确定性吞变体，故不走该形态）。
pub suberror HttpTimeout {
  Connect
  Write
  Read
  Call
} derive(@debug.Debug)

///|
// 消除 implicit_impl_as_method [0079] 的配套写法（007 现行三变体
// 同款先例，http_client.mbt:37）。
pub extend HttpTimeout with @debug.Debug::{to_repr}

///|
// P08 FR-001：四类超时配置标量（contracts/timeout-api.md §1 冻结面②；
// data-model 实体 1）。缺省 connect/write/read = 10s、call = 0（不限，
// OkHttp 对齐）；值 0 ＝不限时且 MUST NOT 建立该级计时窗（非「立即
// 到期」）；负值在 build() 单点构建期快速失败（C5/004 abort 先例）。
// 字段类型钉 Int（对齐 with_timeout(time : Int, ...) 形参——qod-2 S11）。
// 纯值对象无方法（契约）。字段 pub(all)＝调用方可字面量构造
// （builder .timeouts(Timeouts) 派生面的构造原料）；「四字段带缺省」
// 由 HttpClient::new / new_builder / builder() 构造点以全缺省字面量
// 落地（Timeouts::DEFAULT 形态）——本工具链不支持 struct 字段缺省值
// 语法（moon 0.1.20261023 实测），缺省单点收口于此（与 004
// DEFAULT_MAX_IDLE 常量先例同形）。构建期不可变，HttpClient 持有、
// Call 经 `self.client.timeouts` 同包直读（P07 开关同形态）。
pub(all) struct Timeouts {
  connect_ms : Int // 连接伞（建连段，含 DNS——FR-007）；缺省 10_000
  write_ms : Int // 写窗（每次写调用——research R3）；缺省 10_000
  read_ms : Int // 读窗（收头调用/每次体读——research R4）；缺省 10_000
  call_ms : Int // call 伞（execute 全程；0=不建窗——INV-T1）；缺省 0
} derive(@debug.Debug)

///|
// 消除 implicit_impl_as_method [0079] 的配套写法（本包错误变体两件式
// 同款先例）——判别/调试展示面，非行为方法（「无方法」指无业务行为，
// Debug 展示沿 core Request/RequestBuilder 先例保留）。
pub extend Timeouts with @debug.Debug::{to_repr}

///|
// Timeouts 全缺省字面量（FR-001 缺省单点）：connect/write/read =
// 10s、call = 0（不限）。包内构造点（HttpClient::new/new_builder/
// builder() 直派）与白盒断言共用此单点，杜绝缺省值漂移。
fn Timeouts::default() -> Timeouts {
  { connect_ms: 10_000, write_ms: 10_000, read_ms: 10_000, call_ms: 0 }
}

///|
// 门面（data-model 实体 1）：唯一必需状态＝P04 池实例。P09 并发闸门
// 字段不建（YAGNI）。直连形态唯一构造（FR-008）。P07：
// retry_on_connection_failure 为构造期不可变开关（FR-010，缺省
// true＝OkHttp 默认行为面；builder 化归 P08/C4）——priv 字段不进公开面
// （FR-011 冻结面：公开增量恰为 new 的可选参数一项）；开关值不复制进
// Call，判定处经 client 同包 priv 直读（qod-2 点 4-5）。P08：超时与
// 跟随开关为构造期不可变标量（FR-001/FR-010，data-model 实体 3——
// priv 不进公开面，派生面归 HttpClientBuilder，FR-009）。
pub struct HttpClient {
  priv pool : ConnectionPool
  priv retry_on_connection_failure : Bool
  priv timeouts : Timeouts
  priv follow_redirects : Bool
  priv follow_ssl_redirects : Bool
}

///|
// 消除 implicit_impl_as_method [0079] 的配套写法（P01 HeadersError 先例）
pub extend CallCancelled with @debug.Debug::{to_repr}

///|
pub extend CallStateError with @debug.Debug::{to_repr}

///|
pub extend TooManyFollowUps with @debug.Debug::{to_repr}

///|
// 直连构造（FR-008）：持池引用、零网络动作、无 builder。P07 增尾随可选
// 参 retry_on_connection_failure~（缺省 true，FR-010/C4）——本参数为本包
// 公开面唯一增量（FR-011 冻结面，contracts §1 对账）。P08：HttpClient
// 签名冻结不变（FR-012 底线）——新增 priv 标量以字面量补缺省
// （Timeouts{} 全缺省 10s/10s/10s/0、两开关 true＝P06 行为面）。
pub fn HttpClient::new(
  pool : ConnectionPool,
  retry_on_connection_failure~ : Bool = true,
) -> HttpClient {
  {
    pool,
    retry_on_connection_failure,
    timeouts: Timeouts::default(),
    follow_redirects: true,
    follow_ssl_redirects: true,
  }
}

///|
// Call 一次性状态机（data-model §3 图 1，I-1）：Pending→Executing→Done。
priv enum CallState {
  Pending
  Executing
  Done
}

///|
// 一次待执行请求的句柄（data-model 实体 2）：字段全 priv（I-7），白盒
// 经同包 call_wbtest.mbt 直读。fold_count 为 US-4 白盒断言面。
pub struct Call {
  priv request : @core.Request
  priv client : HttpClient
  priv mut state : CallState
  priv mut cancelled : Bool // 标记通道（FR-002a；I-5 幂等）
  priv mut task : @async.Task[@core.Response]? // 子任务句柄（FR-002b）
  priv mut lease : Lease? // 当前租约；处置完成即置 None（I-3 时序支点）
  priv mut folded : Map[@http.CaseInsensitiveString, String]? // L3 折叠缓存（I-2）
  priv mut folded_gen : Int32 // 折叠缓存所属代次（P06 C4/INV-3）
  priv mut gen : Int32 // 当前请求代次（P06：0 = 用户原请求，仅决定跟随后 +1）
  priv mut conn_close_seen : Bool // 本轮响应已见 Connection: close（P06 INV-7）
  priv mut fold_count : Int32 // 折叠计数（US-4 白盒断言面）
  priv mut body_delivered : Bool // 响应已交付调用方（Abandoned 判据前态，T018）
  priv mut body_consumed : Bool // Consumed 事件已见（on_event 通道，T018）
  priv mut body_dropped : Bool // Dropped 事件已见（T018）
  priv mut abandoned_fired : Bool // Abandoned 触发标记（T018 白盒断言面）
  // P07 阶段标记（data-model 实体 4）：当前 attempt 的失败阶段——子循环
  // 体首行复位 Connect（qod-2 必修④），exchange.mbt 调用点前置赋值刷新
  // （T009 插桩）；捕获分支据此取族（error_family 段相关）。
  priv mut last_stage : SendStage
  // P07：filler 已被调用（保守封锁口径 R3——调用即置位，每 attempt 复位）；
  // decide 的体可重放门消费（FR-003）。
  priv mut stream_body_entered : Bool
  // P08 call 伞看门者标记（data-model 实体 4，research R1）：看门者
  // sleep(call_ms) 到期先置位再 task.cancel()——execute 取消收尾分支
  // 按标记选终态变体（真 ⇒ HttpTimeout::Call，假 ⇒ 裸 CallCancelled）。
  // 置位先于取消（时序纪律）；一次性无复位（I-1 单 execute 生命周期）。
  priv mut call_timeout_fired : Bool
}

///|
// 装箱（FR-008）：Pending 态 Call；不做校验以外的工作、不校验 URL 可达性。
pub fn HttpClient::new_call(self : HttpClient, request : @core.Request) -> Call {
  {
    request,
    client: self,
    state: Pending,
    cancelled: false,
    task: None,
    lease: None,
    folded: None,
    folded_gen: 0,
    gen: 0,
    conn_close_seen: false,
    fold_count: 0,
    body_delivered: false,
    body_consumed: false,
    body_dropped: false,
    abandoned_fired: false,
    last_stage: Connect,
    stream_body_entered: false,
    call_timeout_fired: false,
  }
}

///|
// 换代步进（P06 C4/实体 2；包内私有）：仅在循环决定跟随后调用（T004
// exchange_loop advance 消费）；白盒 WB② 经同一直调点驱动换代。单调 +1。
fn Call::advance_generation(self : Call) -> Unit {
  self.gen = self.gen + 1
}

///|
// 取消标记直读（FR-012/I-5）：O(1) 无副作用。
pub fn Call::is_cancelled(self : Call) -> Bool {
  self.cancelled
}

///|
// 取消标记通道（FR-002/012，三通道接线完整版）：置标记 → Task::cancel
// （在途读写协程立即失败，R1/R4）→ lease 非 None 时 poison+release（同步
// 关连、清引用——I-3 时序是 FR-012 竞争安全的支点：处置完成即置 None，
// 迟到 cancel 只见 None ⇒ no-op 不触碰已归池连接）。重入幂等无错（I-5）。
pub fn Call::cancel(self : Call) -> Unit {
  if self.cancelled {
    return
  }
  self.cancelled = true
  match self.task {
    Some(task) => task.cancel()
    None => ()
  }
  // 同步毒化收尾（body 阶段取消的停摆读由关连立即失败，R4 对齐点）
  self.poison_release()
}

///|
// CallCancelled 映射后的收尾白名单（I-6，R1 证据）：handle_cancellation
// 返回 None 后未保护的 async 操作立即取消——收尾只允许同步操作
// （Lease::poison / Lease::release / Client::close），零 await。
// protect_from_cancel 零使用（T009⑩ 结构审判据）。

///|
/// execute（FR-001/002/006/009；contracts §3）：Pending 首检（非 Pending →
/// CallStateError；cancelled → CallCancelled 零网络，FR-002a）→ 组内 spawn
/// 单轮 exchange → wait → handle_cancellation 把取消 None 映射为
/// CallCancelled（FR-003）。成功/失败/取消三路终态均置 Done（图 1，I-1）。
///
/// FR-013 并发语义（C4 文档义务，T019/T024 挂接本 API——P09 之前无
/// Dispatcher 闸门）：本方法不做任何并发限制——同一 HttpClient 上并发 Call
/// 各自独立租借连接、互不串响应；并发上限/排队闸门归 P09 Dispatcher
/// （未在场），调用方自行控制并发度。
///
/// 【护栏/落笔即绿，T024 显式标注】本段由 `//` 行注释改为 `///` 文档注释
/// （moon doc 可见；内容不缩水）。冒烟判据 P05-US1⑦（并发 8 Call 互不串
/// 响应）已在场，无红绿对。
pub async fn Call::execute(self : Call) -> @core.Response {
  // I-1 一次性：Pending 才可 execute；单线程模型 Pending→Executing 同步
  // 置位，无重入窗口
  match self.state {
    Pending => ()
    Executing | Done => raise CallStateError
  }
  if self.cancelled {
    // 预取消首检（FR-002a 零网络）：前态定格为 Done（图 1 取消终态），
    // 使「已取消」二次 execute 得 CallStateError（T011③ 穷尽面）
    self.state = Done
    raise CallCancelled
  }
  self.state = Executing
  // P08 call 伞标记入态清零（I-1 一次性语义的防御性入态复位——
  // new_call 已置 false，此处钉死「入 Executing 即 false」不变量，
  // 使标记读取只可能目睹本 execute 生命周期内看门者的置位）。
  self.call_timeout_fired = false
  // T021（I-1/图 1）：上游 with_task_group 在子任务失败时于组退出重抛
  // （task_group.mbt worker catch 先置组态 Fail，body 内 catch 不改组态），
  // 故组后终态置位在失败路径不可达——兜底置位移到组外（errdefer 形态，
  // [0092] 建议；失败 ⇒ state=Done + 清 task 后错误原样透传，图 1
  // 「失败──▶ Done」落实）。取消/成功两路终态置位见组后常规路径
  errdefer {
    self.state = Done
    self.task = None
  }
  let outcome : ExchangeOutcome = @async.with_task_group() <| group => {
    let task = group.spawn(() => self.exchange_loop())
    self.task = Some(task)
    try {
      match @async.handle_cancellation(() => task.wait()) {
        Some(resp) => Delivered(resp)
        None => Cancelled
      }
    } catch {
      err =>
        // R1 修订（implement 实证）：Task::cancel 后 task.wait 以
        // WaitedTaskAlreadyCancelled 呈现（非 None 通道）——同样映射取消；
        // 其余错误直接 rethrow（T021：失败沿组退出重抛走组外兜底，
        // Failed 中转变体已删）
        if err is @async.WaitedTaskAlreadyCancelled {
          Cancelled
        } else {
          raise err
        }
    }
  }
  // 终态置位（图 1：成功/取消两路均 Done；失败路已由组外 errdefer 兜底
  // 置位）
  self.state = Done
  self.task = None
  match outcome {
    Delivered(resp) => {
      // Abandoned 判据前态（T018）：以「交付调用方」为体在场的起点——
      // 组内构建但未及交付（取消/失败）无消费方可弃，不进入判据
      self.body_delivered = true
      resp
    }
    Cancelled => {
      // FR-003 映射；I-6：随后收尾仅同步操作（poison/release/close）。
      // P08 call 伞变体选择（data-model 实体 4，R1）：标记真 ⇒
      // HttpTimeout::Call（看门者到期取消）、假 ⇒ 裸 CallCancelled
      // （用户取消路径现状逐位不变——反向隔离）。T002 骨架期看门者
      // 未派生、标记恒 false ⇒ 行为与现状逐位一致；派生接线归 T013。
      self.poison_release()
      if self.call_timeout_fired {
        raise HttpTimeout::Call
      } else {
        raise CallCancelled
      }
    }
  }
}

///|
// execute 子任务结果两分支（Delivered 正常交付 / Cancelled 正常取消——
// handle_cancellation 语义，research R1）。T021 死分支清理：失败沿「组退出
// 重抛 → 组外兜底置位」直达 execute 异常通道，原 Failed 中转变体已删
// （源码推定+WB⑮ 实测一致：组态 Fail 下组后代码不可达）。
priv enum ExchangeOutcome {
  Delivered(@core.Response)
  Cancelled
}
