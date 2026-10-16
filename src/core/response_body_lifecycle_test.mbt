///|
// response_body_lifecycle_test：流式 ResponseBody 生命周期黑盒测试（T013）。
//
// 用例来源：contracts/response.md 生命周期锚点表 + data-model.md §4 状态机
// （spec US-4、FR-006）。桩 = @io.MemoryReader（上游公开原语，research R3）
// 零外部网络（宪法 IV）。
//
// OkHttp 移植对拍清单（SC-005，宪法 III/IV；T018 固化）：
//   来源：OkHttp 5.5.0 (Apache-2.0)
//   【移植组】响应体消费/关闭生命周期语义（OkHttp body.close() 显式释放、
//   读完即连接归池的语义模型）。
//   【显式差异组】MoonBit 无 GC 析构钩子——「未读完即弃」的 Abandoned
//   事件触发权显式划归 P04/P05 所有者（research R9；OkHttp 由 close/finalize
//   语义承载），本包只交付状态查询与默认 no-op 行为。
//
// Abandoned 断言口径：本包不模拟其触发（触发权在 P04/P05 所有者），只断言
// 状态查询契约（consumed()/dropped() 双 false 的中间态可查）。

///|
// 黑盒辅助：事件收集器（回调闭包 + 收集数组）
fn event_collector() -> (
  Array[@core.ResponseBodyEvent],
  (@core.ResponseBodyEvent) -> Unit,
) {
  let events : Array[@core.ResponseBodyEvent] = []
  (events, e => events.push(e))
}

///|
// ① 流式体读到底（bytes()）→ 恰收到一次 Consumed、consumed() 为 true
async test "T013① 读到底：恰一次 Consumed" {
  let (events, on_event) = event_collector()
  let mr = @io.MemoryReader() <| w => { w.write(b"stream-data") }
  let body = @core.ResponseBody::stream(mr, on_event~)
  // 读到底
  assert_eq(body.bytes(), b"stream-data")
  // 状态与事件
  assert_true(body.consumed())
  assert_false(body.dropped())
  assert_eq(events.length(), 1)
  assert_true(events[0] is @core.ResponseBodyEvent::Consumed)
}

///|
// ① 补：read_some 逐段读至耗尽同样触发 Consumed（EOF 置 consumed/触发事件）
async test "T013① 补：read_some 耗尽至 EOF 触发 Consumed" {
  let (events, on_event) = event_collector()
  let mr = @io.MemoryReader() <| w => {
    w.write(b"ab")
    w.write(b"cd")
  }
  let body = @core.ResponseBody::stream(mr, on_event~)
  let mut collected : Bytes = b""
  let mut chunks = 0
  while body.read_some() is Some(chunk) {
    chunks += 1
    collected = collected.add(chunk)
  }
  assert_true(chunks >= 1)
  assert_eq(collected, b"abcd")
  assert_true(body.consumed())
  assert_eq(events.length(), 1)
  assert_true(events[0] is @core.ResponseBodyEvent::Consumed)
}

///|
// ② 未读完 drop() → 恰收到一次 Dropped、dropped() 为 true、重复 drop()
// 幂等无二次事件
async test "T013② 未读完 drop：恰一次 Dropped、幂等" {
  let (events, on_event) = event_collector()
  let mr = @io.MemoryReader() <| w => { w.write(b"never-fully-read") }
  let body = @core.ResponseBody::stream(mr, on_event~)
  // 读一段（未到 EOF）
  let chunk = body.read_some()
  assert_true(chunk is Some(_))
  // 显式释放
  body.drop()
  body.drop() // 幂等：无二次事件
  assert_true(body.dropped())
  assert_false(body.consumed())
  assert_eq(events.length(), 1)
  assert_true(events[0] is @core.ResponseBodyEvent::Dropped)
}

///|
// ③ Consumed 后再 drop() 静默无事件（互斥时序：Consumed/Dropped 至多其一）
async test "T013③ Consumed 后 drop：静默无事件" {
  let (events, on_event) = event_collector()
  let mr = @io.MemoryReader() <| w => { w.write(b"will-be-consumed") }
  let body = @core.ResponseBody::stream(mr, on_event~)
  // 读到底 → Consumed
  let _ = body.bytes()
  assert_true(body.consumed())
  // drop 静默：无 Dropped 事件，dropped() 保持 false
  body.drop()
  assert_false(body.dropped())
  assert_eq(events.length(), 1)
  assert_true(events[0] is @core.ResponseBodyEvent::Consumed)
}

///|
// ④ 中间态可查：consumed()/dropped() 均为 false（Abandoned 触发权在
// P04/P05 所有者，本包只断言状态查询契约，不模拟其触发）
async test "T013④ 中间态：双 false 可查（Abandoned 触发权归 P04/P05）" {
  let (events, on_event) = event_collector()
  let mr = @io.MemoryReader() <| w => { w.write(b"partially-read") }
  let body = @core.ResponseBody::stream(mr, on_event~)
  // 读一段（未到 EOF、未 drop）→ 中间态
  let _ = body.read_some()
  assert_false(body.consumed())
  assert_false(body.dropped())
  assert_eq(events.length(), 0)
  // 状态查询即 P04/P05 收尾判定 Abandoned 的依据（毒化信号由所有者触发）
}

///|
// ⑤ 默认构造（无 on_event）三路径不 panic（默认 no-op 行为，FR-006）
async test "T013⑤ 默认构造：三路径 no-op 不 panic" {
  // 路径一：读到底
  let mr1 = @io.MemoryReader() <| w => { w.write(b"default-noop-1") }
  let body1 = @core.ResponseBody::stream(mr1)
  let _ = body1.bytes()
  assert_true(body1.consumed())
  // 路径二：未读完 drop
  let mr2 = @io.MemoryReader() <| w => { w.write(b"default-noop-2") }
  let body2 = @core.ResponseBody::stream(mr2)
  let _ = body2.read_some()
  body2.drop()
  body2.drop()
  assert_true(body2.dropped())
  // 路径三：读到底后再 drop（互斥静默）
  let mr3 = @io.MemoryReader() <| w => { w.write(b"default-noop-3") }
  let body3 = @core.ResponseBody::stream(mr3)
  let _ = body3.read_some()
  let _ = body3.bytes()
  body3.drop()
  assert_true(body3.consumed())
  assert_false(body3.dropped())
}
