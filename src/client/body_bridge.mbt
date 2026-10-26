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
// 宪法 I：仅包装 @http.Client 公开 Reader 面（T025 零失真对齐：委托方向
// 为 read_some/_direct_read ⇒ read_checked ⇒ 内层 read_some；不点名/不
// 引用上游弃用面，--deny-warn 门核查项）。

///|
// 读适配器：包装 @http.Client（内持），读边界检查取消标记。
// 注（T025 零失真对齐，三入口委托拓扑如实陈述）：
//   - `read_some`（消费主面）与 `_direct_read` 均经私有 `read_checked`
//     单点收口（读边界取消检查 + 读中错误映射，FR-002a/FR-011）；
//   - `_get_internal_buffer` 直通内层缓冲——该直通**绕过** read_checked
//     的读边界取消/错误检查，显式注明适用范围：当前消费路径只走
//     read_some，此面不被触达，仅为 trait 完整性保留；
//   - `_direct_read` 为本包完整实现（经 read_checked），不委托内层同名
//     面，保默认 read/read_exactly 语义一致性。
priv struct BodyBridge {
  call : Call
  inner : @http.Client
}

///|
// 处置单点：poison+release + lease 置 None（同一步，杜绝双写错位——I-3）。
// lease 已 None（cancel/前序处置已完成）⇒ no-op（FR-012 迟到竞争安全）。
// 毒化收尾同步触发 Abandoned（T018，data-model §4）：dispose 失败路径
// body_dropped 已 true ⇒ 不触发（Dropped 先到者赢）；读到底回池走
// release_lease 不经此处 ⇒ 迟到 cancel 不误触发（WB⑨ 护栏）；
// 读错误毒化路径 ⇒ 触发（WB⑫ 原判据）。
fn Call::poison_release(self : Call) -> Unit {
  self.fire_abandoned_if_orphaned()
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
// Abandoned 触发判据（T018，data-model §4；P02 契约授予 owner 的收尾权）：
// 体已交付调用方、且未 Consumed 且未 Dropped ⇒ 经 on_event 通道触发
// Abandoned（幂等：abandoned_fired 拦截重入）。体未交付（execute 未
// Delivered——取消/失败在途、预取消；或白盒直调 exchange_once 的桩路径）
// ⇒ 无消费方可弃，不触发。
fn Call::fire_abandoned_if_orphaned(self : Call) -> Unit {
  let orphaned = self.body_delivered &&
    !self.body_consumed &&
    !self.body_dropped &&
    !self.abandoned_fired
  if orphaned {
    self.on_body_event(@core.ResponseBodyEvent::Abandoned)
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
// Consumed/Dropped/Abandoned 事件处置（同步；P02 契约 data-model §4，
// T018 三态标记落位）：
//   - Consumed：读到底 ⇒ 回池（FR-005）；
//   - Dropped：仅状态（真实处置在 dispose 的 on_dispose 异步步，contracts
//     §2 条款 2；先到者赢）；
//   - Abandoned：触发标记置位（触发点在毒化收尾，data-model §4）。
fn Call::on_body_event(self : Call, event : @core.ResponseBodyEvent) -> Unit {
  match event {
    @core.ResponseBodyEvent::Consumed => {
      self.body_consumed = true
      self.release_lease()
    }
    @core.ResponseBodyEvent::Dropped => self.body_dropped = true
    @core.ResponseBodyEvent::Abandoned => self.abandoned_fired = true
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
// 不点名内部 ReaderBuffer 类型）。T025 对齐：该直通绕过 read_checked 的
// 读边界取消/错误检查（显式注明适用范围——当前消费路径只走 read_some，
// 此面不被触达）。
impl @io.Reader for BodyBridge with fn _get_internal_buffer(self) {
  @io.Reader::_get_internal_buffer(self.inner)
}

///|
// 读错误映射单点（T020，FR-002a/US-3-3 收敛裁决）：读路径任何失败在
// cancelled 态一律映射裸 CallCancelled（「cancelled==true 时读路径任何失败
// 一律映射 CallCancelled」2026-10-24 二轮 clarify 裁决的落地点）；未取消 ⇒
// 原错误透传不包装（FR-011）。单一判定函数，白盒可直驱（P05-WB⑬⑭）。
fn Call::map_read_error(self : Call, err : Error) -> Error {
  if self.cancelled {
    CallCancelled
  } else {
    err
  }
}

///|
// 读路径检查+委托（私有单点，read_some 与 _direct_read 共用）。
async fn BodyBridge::read_checked(
  self : BodyBridge,
  max_len : Int32?,
) -> Bytes? {
  // 读边界发现 cancelled（cancel 已毒化+关连，这里只负责错误呈现，
  // FR-002a/US-3-3）——读前边界检查保持在错误处置段之外（T020）
  if self.call.cancelled {
    raise CallCancelled
  }
  // 读中网络错误（T020：errdefer 改 try/catch）：毒化先于映射——catch 内
  // 先 poison_release（FR-011/图 2 收尾不回池）再经 map_read_error 按
  // 取消态映射错误形态（cancelled ⇒ 裸 CallCancelled；未取消 ⇒ 原样透传，
  // FR-002a/FR-011）
  let chunk = self.inner.read_some(max_len?) catch {
    err => {
      self.call.poison_release()
      raise self.call.map_read_error(err)
    }
  }
  // 读后成功路径的取消边界检查（语义零变化：仅成功路径触达，T020）
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
