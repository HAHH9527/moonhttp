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
// 门面（data-model 实体 1）：唯一必需状态＝P04 池实例。P08/P09 配置位
// 字段不建（YAGNI，plan 宪法核查 VI）。直连形态唯一构造（FR-008）。
pub struct HttpClient {
  priv pool : ConnectionPool
}

///|
// 消除 implicit_impl_as_method [0079] 的配套写法（P01 HeadersError 先例）
pub extend CallCancelled with @debug.Debug::{to_repr}

///|
pub extend CallStateError with @debug.Debug::{to_repr}

///|
pub extend TooManyFollowUps with @debug.Debug::{to_repr}

///|
// 直连构造（FR-008）：持池引用、零网络动作、无 builder。
pub fn HttpClient::new(pool : ConnectionPool) -> HttpClient {
  { pool, }
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
      // FR-003 映射；I-6：随后收尾仅同步操作（poison/release/close）
      self.poison_release()
      raise CallCancelled
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
