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
  priv mut fold_count : Int32 // 折叠计数（US-4 白盒断言面）
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
    fold_count: 0,
  }
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
// execute（FR-001/002/006/009；contracts §3）：Pending 首检（非 Pending →
// CallStateError；cancelled → CallCancelled 零网络，FR-002a）→ 组内 spawn
// 单轮 exchange → wait → handle_cancellation 把取消 None 映射为
// CallCancelled（FR-003）。成功/失败/取消三路终态均置 Done（图 1，I-1）。
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
  let outcome : ExchangeOutcome = @async.with_task_group() <| group => {
    let task = group.spawn(() => self.exchange_once())
    self.task = Some(task)
    try {
      match @async.handle_cancellation(() => task.wait()) {
        Some(resp) => Delivered(resp)
        None => Cancelled
      }
    } catch {
      err =>
        // R1 修订（implement 实证）：Task::cancel 后 task.wait 以
        // WaitedTaskAlreadyCancelled 呈现（非 None 通道）——同样映射取消
        if err is @async.WaitedTaskAlreadyCancelled {
          Cancelled
        } else {
          Failed(err)
        }
    }
  }
  // 终态置位（图 1：成功/失败/取消三路均 Done）
  self.state = Done
  self.task = None
  match outcome {
    Delivered(resp) => resp
    Cancelled => {
      // FR-003 映射；I-6：随后收尾仅同步操作（poison/release/close）
      self.poison_release()
      raise CallCancelled
    }
    Failed(err) => raise err
  }
}

///|
// execute 子任务结果三分支（Delivered 正常交付 / Cancelled 正常取消 /
// Failed 其他错误——handle_cancellation 语义，research R1）。
priv enum ExchangeOutcome {
  Delivered(@core.Response)
  Cancelled
  Failed(Error)
}

///|
// FR-013 并发语义文档（C4 文档义务，P09 之前无 Dispatcher 闸门）：
// 本方法不做任何并发限制——同一 HttpClient 上并发 Call 各自独立租借
// 连接、互不串响应；并发上限/排队闸门归 P09 Dispatcher（未在场）。
// 调用方自行控制并发度。
