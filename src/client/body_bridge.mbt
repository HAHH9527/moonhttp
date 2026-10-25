///|
// body_bridge：BodyBridge 读适配器 + 租约处置状态机（data-model 实体 4，
// 包内私有——FR-014 不进公开面）。职责三行：
//   - EOF（读到底）→ ResponseBody 触发 Consumed → release 回池 + lease 置
//     None（I-3：处置后立刻置 None，FR-005 回池）；
//   - 读中网络错误 → poison+release + lease 置 None；未取消 ⇒ 错误原样透传
//     （不包装，FR-011）、cancelled ⇒ 映射裸 CallCancelled（FR-002a）；
//   - 读边界发现 cancelled → raise CallCancelled（cancel 已完成
//     poison+release，US-3-3）。
// 所有权（data-model 实体 4，2026-10-25 analyze C1）：处置动作统一经
// Call.lease 单点生效（bridge 持 Call 引用触发处置，不自持租约副本）。
// 宪法 I：仅包装 @http.Client 公开 Reader 面（read_some/等经 _direct_read
// 单点委托）。

///|
// 读适配器：包装 @http.Client（内持），读边界检查取消标记。
// 注：不委托上游弃用面 `_get_internal_buffer`/`_direct_read`（--deny-warn
// 门零弃用引用）——读语义经公开 `read_some` 委托单点收口，内部缓冲给
// 空桩（ResponseBody 读取路径只走 read_some，桩不被消费路径触达）。
priv struct BodyBridge {
  call : Call
  inner : @http.Client
}

///|
// 处置单点：poison+release + lease 置 None（同一步，杜绝双写错位——I-3）。
// lease 已 None（cancel/前序处置已完成）⇒ no-op（FR-012 迟到竞争安全）。
fn Call::poison_release(self : Call) -> Unit {
  match self.lease {
    Some(lease) => {
      lease.poison()
      lease.release()
      self.lease = None
    }
    None => ()
  }
}

///|
// 处置单点：release 回池 + lease 置 None（I-3 同上；已 None ⇒ no-op）。
fn Call::release_lease(self : Call) -> Unit {
  match self.lease {
    Some(lease) => {
      lease.release()
      self.lease = None
    }
    None => ()
  }
}

///|
// Consumed 事件处置（同步；P02 契约 data-model §4）：读到底 → 回池。
fn Call::on_body_event(self : Call, event : @core.ResponseBodyEvent) -> Unit {
  if event is @core.ResponseBodyEvent::Consumed {
    self.release_lease()
  } else {
    // Dropped：仅状态（真实处置在 dispose 的 on_dispose 异步步，
    // contracts §2 条款 2）；Abandoned 由毒化收尾按查询触发（T010）。
    ()
  }
}

///|
// on_dispose 注入（T010，R3 裁决）：skip 收尾落在消费者协程（组不可在
// execute 返回后收留 skip——R1 组生命周期硬约束）。
//   - `call.cancelled` 或 lease 已 None ⇒ no-op（与 cancel 竞争收敛）；
//   - skip 成功 → release 回池（I-4：发送完成 ∧ skip 成功）；
//   - skip 失败 → poison+release 后透传错误（0 错路由另一半）。
async fn Call::dispose_skip(self : Call, bridge : BodyBridge) -> Unit {
  if self.cancelled || self.lease is None {
    return
  }
  // skip 失败 ⇒ poison+release 后透传（errdefer 收尾；0 错路由另一半）
  errdefer self.poison_release()
  bridge.inner.skip_response_body()
  self.release_lease()
}

///|
// Reader 委托：内部缓冲直通内层（经 trait 面 `@io.Reader::_get_internal_
// buffer` 访问，规避弃用的隐式提升方法调用；返回类型不写、由内层推断，
// 不点名内部 ReaderBuffer 类型）。
impl @io.Reader for BodyBridge with fn _get_internal_buffer(self) {
  @io.Reader::_get_internal_buffer(self.inner)
}

///|
// 读路径检查+委托（私有单点，read_some 与 _direct_read 共用）。
async fn BodyBridge::read_checked(
  self : BodyBridge,
  max_len : Int32?,
) -> Bytes? {
  // 读边界发现 cancelled（cancel 已毒化+关连，这里只负责错误呈现，
  // FR-002a/US-3-3）
  if self.call.cancelled {
    raise CallCancelled
  }
  // 读中网络错误：毒化不回池（FR-011/图 2，errdefer 收尾+透传）；随后按
  // 取消态映射错误形态（未取消 ⇒ 原样透传不包装；cancelled ⇒ 裸
  // CallCancelled，FR-002a）
  errdefer self.call.poison_release()
  let chunk = self.inner.read_some(max_len?)
  if self.call.cancelled {
    raise CallCancelled
  }
  chunk
}

///|
// 读路径单点（公开 read_some 委托，规避上游弃用面）：
// 边界取消检查 → 委托内层 → 错误处置（FR-011/FR-002a）。
impl @io.Reader for BodyBridge with fn read_some(self, max_len? : Int32) -> Bytes? raise {
  self.read_checked(max_len)
}

///|
// _direct_read：经同一检查单点实现（供上游默认 read/read_exactly 复用；
// BodyBridge 消费路径只走 read_some，此实现保默认方法一致性）。
impl @io.Reader for BodyBridge with fn _direct_read(
  self,
  buf : FixedArray[Byte],
  offset~ : Int32,
  max_len~ : Int32,
) -> Int32 raise {
  match self.read_checked(Some(max_len)) {
    Some(chunk) => {
      let n = chunk.length()
      buf.blit_from_bytes(offset, chunk, 0, n)
      n
    }
    None => 0
  }
}

///|
// 构造桥接体并组装挂租约的 ResponseBody（exchange 管线的收头步骤共用）。
// on_event 挂 Consumed 处置；on_dispose 注入 skip 收尾（FR-015 裁决面）。
fn Call::make_response_body(
  self : Call,
  bridge : BodyBridge,
) -> @core.ResponseBody {
  @core.ResponseBody::stream(
    bridge,
    on_event=fn(event) { self.on_body_event(event) },
    on_dispose=async fn() { self.dispose_skip(bridge) },
  )
}
