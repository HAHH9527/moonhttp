///|
// call_wbtest：P05 白盒测试（包内私有面直读——I-7，004 R7 先例）。
// 承载：状态机直驱（WB①②③⑪）、折叠缓存（WB⑧、US4①）、BodyBridge
// 读适配与租约处置（WB④～⑦⑫）、竞争与收尾（WB⑨⑩）。
//
// T004 先红后绿：本文件 P05-WB①②③（红）→ http_client.mbt 骨架（绿）。

///|
// 白盒 GET Call 辅助（同包直构；HttpUrl::parse 可 raise）。
fn get_call_wb(client : HttpClient, port : Int32, path : String) -> Call raise {
  let url = @core.HttpUrl::parse("http://127.0.0.1:\{port}\{path}")
  let request = @core.RequestBuilder::new(url).method(@core.Method::Get).build()
  client.new_call(request)
}

///|
// P05-WB①（FR-008，T004）：HttpClient 持池零网络动作；new_call 装箱
// Pending 态 Call（state 白盒直读，I-1 初版；不校验 URL 可达性）。
async test "P05-WB① HttpClient 骨架：持池零网络、new_call 装 Pending" {
  @async.with_task_group() <| _group => {
    let server = @fixtures.ScriptedServer::start()
    let pool = ConnectionPool::new()
    let client = HttpClient::new(pool)
    let addr = Address::new(scheme="http", host="127.0.0.1", port=server.port())
    // 构造期零网络动作：池侧无任何租借
    assert_eq(
      pool.per_host_total(addr),
      0,
      msg="HttpClient::new 与 new_call 不得产生网络动作（FR-008）",
    )
    let url = @core.HttpUrl::parse("http://127.0.0.1:\{server.port()}/hello")
    let request = @core.RequestBuilder::new(url)
      .method(@core.Method::Get)
      .build()
    let call = client.new_call(request)
    // 白盒直读：Pending 初态、字段一次落位（data-model 实体 2）
    assert_true(
      call.state is Pending,
      msg="new_call 装箱的 Call 应为 Pending 态（I-1 初版）",
    )
    assert_false(call.cancelled)
    assert_true(call.lease is None, msg="初态不得持有租约")
    assert_true(call.task is None, msg="初态不得持有子任务句柄")
    assert_eq(call.fold_count, 0, msg="初态未折叠")
    server.close()
  }
}

///|
// P05-WB②（I-5 初版，T004）：is_cancelled 初始 false、cancel() 置 true
// 且重入幂等无错（标记通道初版；Task::cancel 与毒化接线归 T008）。
async test "P05-WB② cancel 标记通道：初 false、置 true、重入幂等" {
  @async.with_task_group() <| _group => {
    let pool = ConnectionPool::new()
    let client = HttpClient::new(pool)
    let url = @core.HttpUrl::parse("http://127.0.0.1:1/x")
    let request = @core.RequestBuilder::new(url)
      .method(@core.Method::Get)
      .build()
    let call = client.new_call(request)
    assert_false(call.is_cancelled(), msg="初态未取消")
    call.cancel()
    assert_true(call.is_cancelled(), msg="cancel 后标记为 true")
    call.cancel()
    call.cancel()
    assert_true(
      call.is_cancelled(),
      msg="重入 cancel 幂等无错、标记保持 true（I-5）",
    )
  }
}

///|
// P05-WB③（FR-003，T004）：CallCancelled/CallStateError derive(@debug.Debug)
// 且 `err is` 可判别；网络错误不在此二层（本测试只断言两变体判别面）。
async test "P05-WB③ 错误变体：Debug 可判别" {
  fn raise_cancelled() -> Unit raise {
    raise CallCancelled
  }

  fn raise_state() -> Unit raise {
    raise CallStateError
  }

  let got_cancelled = try {
    raise_cancelled()
    false
  } catch {
    err => err is CallCancelled
  }
  let got_state = try {
    raise_state()
    false
  } catch {
    err => err is CallStateError
  }
  let not_cross = try {
    raise_cancelled()
    false
  } catch {
    err => err is CallStateError
  }
  assert_true(got_cancelled, msg="CallCancelled 应可判别（FR-003）")
  assert_true(got_state, msg="CallStateError 应可判别（FR-001）")
  assert_false(not_cross, msg="两变体互不误判")
  // derive(@debug.Debug)：可渲染不 panic（经 trait 方法面）
  let _ = @debug.Debug::to_repr(CallCancelled)
  let _ = @debug.Debug::to_repr(CallStateError)
}

///|
// ===== P05-WB④～⑫（T005/T006/T008/T009/T010/T011/T012 白盒面）=====
// 桩形态：ScriptedPeer::Capture / ScriptedServer + 白盒私有字段直读
// （state/lease/folded/fold_count——I-7）。

///|
// WB④（FR-005 回池，T005）：EOF 读到底 ⇒ Consumed ⇒ release 回池 +
// lease 置 None（I-3：处置后立刻置 None）。
async test "P05-WB④ EOF 读到底：release 回池 + lease 置 None" {
  @async.with_task_group() <| group => {
    let server = @fixtures.ScriptedServer::start()
    server.mount("GET", "/eof", {
      status: 200,
      headers: [],
      framing: Fixed,
      body: Static(b"eof-body"),
      head_delay_ms: 0,
      close_after_response: false,
    })
    let s1 = group.spawn(
      () => server.serve_once(timeout_ms=3000),
      allow_failure=true,
    )
    let pool = ConnectionPool::new()
    let client = HttpClient::new(pool)
    let addr = Address::new(scheme="http", host="127.0.0.1", port=server.port())
    let call = get_call_wb(client, server.port(), "/eof")
    let resp = call.execute()
    assert_true(call.lease is Some(_), msg="响应交付时租约应在场")
    let _ = resp.body().unwrap().bytes()
    assert_true(
      call.lease is None,
      msg="EOF ⇒ Consumed ⇒ release 且 lease 立刻置 None（I-3）",
    )
    // 回池复用：第二条请求零新建（同连接由 s1 的服务循环承载）
    let next = get_call_wb(client, server.port(), "/eof")
    let _ = next.execute()
    assert_eq(pool.per_host_total(addr), 1, msg="读到底回池（WB④）")
    pool.evict_all()
    server.close()
    s1.wait() catch {
      _ => ()
    }
  }
}

///|
// WB⑤（FR-011 毒化 + FR-002a 形态，T005）：读中网络错误 ⇒ poison+release
// + lease 置 None；未取消 ⇒ 错误原样透传（不包装为 CallCancelled）。
async test "P05-WB⑤ 读中网络错误：毒化 + lease None + 透传" {
  @async.with_task_group() <| group => {
    let server = @fixtures.ScriptedServer::start()
    server.mount_truncated("GET", "/cut", {
      status: 200,
      headers: [],
      framing: Fixed,
      body: Static(b"abcdef"),
      head_delay_ms: 0,
      close_after_response: false,
    })
    let s1 = group.spawn(
      () => server.serve_once(timeout_ms=3000),
      allow_failure=true,
    )
    let pool = ConnectionPool::new()
    let client = HttpClient::new(pool)
    let addr = Address::new(scheme="http", host="127.0.0.1", port=server.port())
    let call = get_call_wb(client, server.port(), "/cut")
    let resp = call.execute()
    let not_cancelled = try {
      let _ = resp.body().unwrap().bytes()
      false
    } catch {
      err => !(err is CallCancelled)
    }
    assert_true(
      not_cancelled,
      msg="未取消的读错误必须原样透传（FR-011 不包装）",
    )
    assert_true(
      call.lease is None,
      msg="读错误 ⇒ poison+release + lease None（I-3）",
    )
    assert_eq(pool.per_host_total(addr), 1, msg="毒化不新建")
    let s2 = group.spawn(
      () => server.serve_once(timeout_ms=3000),
      allow_failure=true,
    )
    let next = get_call_wb(client, server.port(), "/cut")
    let _ = next.execute()
    assert_eq(
      pool.per_host_total(addr),
      2,
      msg="毒化连接不回池 ⇒ 后续新建 +1（FR-011）",
    )
    pool.evict_all()
    server.close()
    s1.wait() catch {
      _ => ()
    }
    s2.wait() catch {
      _ => ()
    }
  }
}

///|
// WB⑥（FR-002a/US-3-3 白盒，T005）：读边界发现 cancelled ⇒ raise
// CallCancelled（cancel 已完成 poison+release，lease 已 None）。
async test "P05-WB⑥ 读边界取消：CallCancelled 且 lease 已 None" {
  @async.with_task_group() <| group => {
    let server = @fixtures.ScriptedServer::start()
    server.mount("GET", "/drip", {
      status: 200,
      headers: [],
      framing: Fixed,
      body: Drip(4, 40, 30),
      head_delay_ms: 0,
      close_after_response: false,
    })
    let s1 = group.spawn(
      () => server.serve_once(timeout_ms=5000),
      allow_failure=true,
    )
    let pool = ConnectionPool::new()
    let client = HttpClient::new(pool)
    let call = get_call_wb(client, server.port(), "/drip")
    let resp = call.execute()
    let _ = resp.body().unwrap().read_some()
    call.cancel()
    assert_true(
      call.lease is None,
      msg="cancel 内完成 poison+release（R4）",
    )
    let cancelled = try {
      while resp.body().unwrap().read_some() is Some(_) {
        ()
      }
      false
    } catch {
      err => err is CallCancelled
    }
    assert_true(
      cancelled,
      msg="读边界发现 cancelled ⇒ 裸 CallCancelled（FR-002a）",
    )
    pool.evict_all()
    server.close()
    s1.wait() catch {
      _ => ()
    }
  }
}

///|
// WB⑦（FR-005 on_dispose 注入三分支，T005/T010）：skip 成功→release /
// skip 失败→poison+release 后透传 / cancelled 或 lease 已 None→no-op。
async test "P05-WB⑦ on_dispose 注入三分支" {
  @async.with_task_group() <| group => {
    let server = @fixtures.ScriptedServer::start()
    // (a) skip 成功 → release
    server.mount("GET", "/skip-ok", {
      status: 200,
      headers: [],
      framing: Fixed,
      body: Static(Bytes::from_iter(Array::make(1024, b'a').iter())),
      head_delay_ms: 0,
      close_after_response: false,
    })
    // (b) skip 失败 → poison+release + 透传
    server.mount_truncated("GET", "/skip-fail", {
      status: 200,
      headers: [],
      framing: Fixed,
      body: Static(b"abcdef"),
      head_delay_ms: 0,
      close_after_response: false,
    })
    let s1 = group.spawn(
      () => server.serve_once(timeout_ms=3000),
      allow_failure=true,
    )
    let pool = ConnectionPool::new()
    let client = HttpClient::new(pool)
    // 7a
    let call_a = get_call_wb(client, server.port(), "/skip-ok")
    let resp_a = call_a.execute()
    resp_a.body().unwrap().dispose()
    assert_true(
      call_a.lease is None,
      msg="skip 成功 ⇒ release + lease None（7a）",
    )
    // 7c（先于 7b：复用 7a 回池连接，避免夹具超时收尾关死连接）
    let call_c = get_call_wb(client, server.port(), "/skip-ok")
    let resp_c = call_c.execute()
    call_c.cancel()
    assert_true(call_c.lease is None, msg="cancel 已收尾（7c 前态）")
    // dispose 在已取消（lease None）态必须 no-op 无错
    resp_c.body().unwrap().dispose()
    pool.evict_all()
    s1.wait() catch {
      _ => ()
    }
    // 7b
    let s2 = group.spawn(
      () => server.serve_once(timeout_ms=3000),
      allow_failure=true,
    )
    let call_b = get_call_wb(client, server.port(), "/skip-fail")
    let resp_b = call_b.execute()
    let failed = try {
      resp_b.body().unwrap().dispose()
      false
    } catch {
      _ => true
    }
    assert_true(
      failed,
      msg="skip 失败 ⇒ poison+release 后透传错误（7b）",
    )
    assert_true(
      call_b.lease is None,
      msg="skip 失败 ⇒ lease 置 None（I-3，7b）",
    )
    // 【护栏/落笔即绿判据，显式标注】Dropped 先到者赢：dispose 失败路径
    // 不得再触发 Abandoned（T018 判据的互斥面）
    assert_false(
      call_b.abandoned_fired,
      msg="dispose 路径 Dropped 已触发 ⇒ Abandoned 不触发（T018）",
    )
    pool.evict_all()
    server.close()
    s2.wait() catch {
      _ => ()
    }
  }
}

///|
// WB⑧（FR-006/FR-004 接缝，T006）：桩直调 exchange_once——Address 推导
// 正确（请求达夹具）、单轮终止无 follow-up、首次折叠后 fold_count==1 且
// 再次直调不再折叠（I-2 初版）。
async test "P05-WB⑧ exchange_once 接缝：Address 推导 + 折叠恰一次" {
  @async.with_task_group() <| group => {
    let peer = @fixtures.ScriptedPeer::start()
    peer.mount(Capture)
    let running = group.spawn(() => peer.run(timeout_ms=3000))
    let pool = ConnectionPool::new()
    let client = HttpClient::new(pool)
    let url = @core.HttpUrl::parse("http://127.0.0.1:\{peer.port()}/seam")
    let request = @core.RequestBuilder::new(url)
      .method(@core.Method::Get)
      .build()
    let call = client.new_call(request)
    assert_eq(call.fold_count, 0, msg="初态未折叠")
    let resp1 = call.exchange_once()
    assert_eq(
      resp1.code(),
      200,
      msg="Address 推导正确：请求达夹具（canned 200）",
    )
    assert_eq(call.fold_count, 1, msg="首跑折叠恰一次（I-2）")
    let folded_first = call.folded
    // 再次直调：不再折叠（folded 复用同一实例）
    peer.mount(Capture)
    let running2 = group.spawn(() => peer.run(timeout_ms=3000))
    call.poison_release()
    let resp2 = call.exchange_once()
    assert_eq(resp2.code(), 200)
    assert_eq(call.fold_count, 1, msg="重放不重复折叠（I-2）")
    assert_true(
      call.folded is _ && call.folded == folded_first,
      msg="folded 复用同一实例（US-4 前置）",
    )
    peer.close()
    let _ = running
    let _ = running2
  }
}

///|
// WB⑨（FR-012/I-3 竞争，T009）：读到底 → release 回池 → 迟到 cancel →
// 无错、不 double-close、已归池连接不受影响（下个 execute 复用且新建
// 连接不增）。
async test "P05-WB⑨ 迟到 cancel 竞争：归池连接不受影响" {
  @async.with_task_group() <| group => {
    let server = @fixtures.ScriptedServer::start()
    server.mount("GET", "/race", {
      status: 200,
      headers: [],
      framing: Fixed,
      body: Static(b"race-ok"),
      head_delay_ms: 0,
      close_after_response: false,
    })
    let s1 = group.spawn(
      () => server.serve_once(timeout_ms=5000),
      allow_failure=true,
    )
    let pool = ConnectionPool::new()
    let client = HttpClient::new(pool)
    let addr = Address::new(scheme="http", host="127.0.0.1", port=server.port())
    let call = get_call_wb(client, server.port(), "/race")
    let resp = call.execute()
    let _ = resp.body().unwrap().bytes()
    assert_true(call.lease is None, msg="已读到底回池（lease None）")
    call.cancel()
    assert_true(call.is_cancelled(), msg="迟到 cancel 生效标记")
    assert_true(
      call.lease is None,
      msg="lease 已 None ⇒ cancel 无操作（FR-012）",
    )
    // 已归池连接不受影响：下个 execute 复用且新建连接不增
    let next = get_call_wb(client, server.port(), "/race")
    let resp2 = next.execute()
    assert_eq(resp2.body().unwrap().text(), "race-ok")
    assert_eq(
      pool.per_host_total(addr),
      1,
      msg="迟到 cancel 不得触发新建（不 double-close、复用如常，FR-012）",
    )
    // 【护栏/落笔即绿判据，显式标注】Consumed 先到者赢：迟到 cancel 不得
    // 触发 Abandoned（T018 判据的反向面——毒化收尾仅对未消费体触发）
    assert_false(
      call.abandoned_fired,
      msg="已消费体迟到 cancel 不得触发 Abandoned（T018）",
    )
    pool.evict_all()
    server.close()
    s1.wait() catch {
      _ => ()
    }
  }
}

///|
// WB⑩（I-6 收尾仅同步——【护栏/落笔即绿判据，004 T016 先例口径，非静默】）：
// handle_cancellation→None 映射后的清理路径仅 poison/release/close（白名单
// ——Lease::poison/Lease::release/Client::close，见 execute 注释块与
// body_bridge errdefer），零 await；protect_from_cancel 零使用列入 code
// review 检查单（T015 SC-006 同轮 grep 核查）。可执行代理判据：取消映射
// 后同一池上立即再 execute 成功（证明收尾同步完成、无残留异步收尾在途）。
async test "P05-WB⑩ 取消收尾仅同步：映射后立即复用池" {
  @async.with_task_group() <| group => {
    let server = @fixtures.ScriptedServer::start()
    server.mount("POST", "/big", {
      status: 200,
      headers: [],
      framing: Fixed,
      body: Static(b"ignored"),
      head_delay_ms: 0,
      close_after_response: false,
    })
    let s1 = group.spawn(
      () => server.serve_once(timeout_ms=5000),
      allow_failure=true,
    )
    let pool = ConnectionPool::new()
    let client = HttpClient::new(pool)
    let url = @core.HttpUrl::parse("http://127.0.0.1:\{server.port()}/big")
    // 大 Stream 体（未知长度 ⇒ chunked）：写远超服务端接收窗口 ⇒ 写停摆
    let body = @core.RequestBody::stream(async fn(w) {
      let chunk = Bytes::from_iter(Array::make(65536, b'x').iter())
      for _i in 0..<256 {
        w.write(chunk)
      }
    })
    let request = @core.RequestBuilder::new(url)
      .method(@core.Method::Post)
      .body(body)
      .build()
    let call = client.new_call(request)
    let executing = group.spawn(() => call.execute(), allow_failure=true)
    @async.sleep(150)
    call.cancel()
    let cancelled = try {
      let _ = executing.wait()
      false
    } catch {
      err => err is CallCancelled
    }
    assert_true(cancelled, msg="在途取消映射 CallCancelled（FR-003）")
    // 连接 1 收尾（毒化关闭引发的夹具错误按注入语义吞）
    pool.evict_all()
    s1.wait() catch {
      _ => ()
    }
    // 立即再执行（无 sleep）：若收尾混入 async 操作/未同步完成，此处即红
    server.mount("GET", "/slow2", {
      status: 200,
      headers: [],
      framing: Fixed,
      body: Static(b"after-cancel"),
      head_delay_ms: 0,
      close_after_response: false,
    })
    let s2 = group.spawn(
      () => server.serve_once(timeout_ms=3000),
      allow_failure=true,
    )
    let next = get_call_wb(client, server.port(), "/slow2")
    let resp = next.execute()
    assert_eq(resp.body().unwrap().text(), "after-cancel")
    pool.evict_all()
    server.close()
    s2.wait() catch {
      _ => ()
    }
  }
}

///|
// WB⑪（I-1 状态机直驱，T011 白盒）：Executing/Done 态 execute ⇒
// CallStateError；成功/失败/取消三路终态置 Done（黑盒穷尽面见 P05-US2*）。
async test "P05-WB⑪ 状态机直驱：Executing/Done 拒绝 execute" {
  @async.with_task_group() <| _group => {
    let pool = ConnectionPool::new()
    let client = HttpClient::new(pool)
    let call = get_call_wb(client, 1, "/x")
    call.state = Executing
    let rejected_executing = try {
      let _ = call.execute()
      false
    } catch {
      err => err is CallStateError
    }
    assert_true(
      rejected_executing,
      msg="Executing 态 execute ⇒ CallStateError",
    )
    call.state = Done
    let rejected_done = try {
      let _ = call.execute()
      false
    } catch {
      err => err is CallStateError
    }
    assert_true(rejected_done, msg="Done 态 execute ⇒ CallStateError")
  }
}

///|
// WB⑫（FR-005 第二轮 clarify/P02 owner 义务，T010）：读错误毒化路径上
// Abandoned 查询面——consumed()/dropped() 双 false 中间态可查（本包据此
// 在毒化收尾触发 Abandoned 处置；data-model §4）。
async test "P05-WB⑫ 毒化路径 Abandoned 已触发" {
  @async.with_task_group() <| group => {
    let server = @fixtures.ScriptedServer::start()
    server.mount_truncated("GET", "/abandoned", {
      status: 200,
      headers: [],
      framing: Fixed,
      body: Static(b"never-complete"),
      head_delay_ms: 0,
      close_after_response: false,
    })
    let s1 = group.spawn(
      () => server.serve_once(timeout_ms=3000),
      allow_failure=true,
    )
    let pool = ConnectionPool::new()
    let client = HttpClient::new(pool)
    let call = get_call_wb(client, server.port(), "/abandoned")
    let resp = call.execute()
    let body = resp.body().unwrap()
    let read_failed = try {
      let _ = body.bytes()
      false
    } catch {
      _ => true
    }
    assert_true(read_failed, msg="断连 ⇒ 体读失败")
    assert_false(
      body.consumed(),
      msg="未 Consumed（Abandoned 查询面前态）",
    )
    assert_false(
      body.dropped(),
      msg="未 Dropped（毒化收尾按查询触发 Abandoned）",
    )
    assert_true(call.lease is None, msg="毒化收尾已完成（I-3）")
    assert_true(
      call.abandoned_fired,
      msg="读错误毒化路径上 Abandoned 已触发（T010 原判据，T018 恢复）",
    )
    pool.evict_all()
    server.close()
    s1.wait() catch {
      _ => ()
    }
  }
}

///|
// ===== P05-US4①（FR-004/SC-004，T012；白盒——fold_count/folded 包内
// 私有黑盒不可读 E4091，004 R9 先例）=====

///|
// P05-US4①：带多条头与 Bytes 体（可重复体）的 Request 同一 Call 内桩接缝
// 强制重放 N=3 次：fold_count==1（SC-004）、folded 复用同一实例、
// ScriptedPeer Capture 逐连接捕获线上字节两两 assert_eq。
async test "P05-US4① 重放零折叠：fold 恰一次 + 线上字节逐字节一致" {
  @async.with_task_group() <| group => {
    let peer = @fixtures.ScriptedPeer::start()
    peer.mount(Capture)
    let pool = ConnectionPool::new()
    let client = HttpClient::new(pool)
    let url = @core.HttpUrl::parse("http://127.0.0.1:\{peer.port()}/replay")
    let headers = @core.HeadersVBuilder::new()
    headers.add("X-One", "1")
    headers.add("X-Two", "2")
    headers.add("X-Three", "3")
    let body = @core.RequestBody::bytes(b"replay-payload", 14L)
    let request = @core.RequestBuilder::new(url)
      .method(@core.Method::Post)
      .headers(headers.build())
      .body(body)
      .build()
    let call = client.new_call(request)
    let captures : Array[@fixtures.CapturedRequest] = []
    for _i in 0..<3 {
      let running = group.spawn(() => peer.run(timeout_ms=3000))
      let resp = call.exchange_once()
      assert_eq(resp.code(), 200)
      call.poison_release()
      captures.push(running.wait())
    }
    assert_eq(
      call.fold_count,
      1,
      msg="N 次重放折叠恰一次（SC-004/I-2）",
    )
    assert_true(call.folded is Some(_), msg="folded 缓存在场")
    // 线上字节两两一致（Capture 捕获 raw，含请求行/头/体）
    assert_eq(
      captures[0].raw,
      captures[1].raw,
      msg="第 1/2 次重放线上字节一致",
    )
    assert_eq(
      captures[1].raw,
      captures[2].raw,
      msg="第 2/3 次重放线上字节一致",
    )
    peer.close()
  }
}

///|
// ===== P05-WB⑬⑭（T020，FR-002a/US-3-3 收敛）：读错误路径取消映射单点
// `Call::map_read_error` 白盒直驱——cancelled ⇒ 裸 CallCancelled；未取消 ⇒
// 原错误透传不误映射。错误源取自 WB⑤ 同款夹具注入形态（mount_truncated
// 断连读失败的真实 Error），确定性、零 sleep（在途读跨协程关连悬挂为上游
// 能力限制（R9 偏差 3），故不取集成形态）。

///|
// P05-WB⑬（T020 先红）：cancelled==true 时直驱错误映射 ⇒ `is CallCancelled`
// ——读路径任何失败在取消态一律以裸 CallCancelled 呈现（FR-002a/US-3-3）。
async test "P05-WB⑬ 读错误映射：cancelled ⇒ CallCancelled" {
  @async.with_task_group() <| group => {
    let server = @fixtures.ScriptedServer::start()
    server.mount_truncated("GET", "/map-cut", {
      status: 200,
      headers: [],
      framing: Fixed,
      body: Static(b"abcdef"),
      head_delay_ms: 0,
      close_after_response: false,
    })
    let s1 = group.spawn(
      () => server.serve_once(timeout_ms=3000),
      allow_failure=true,
    )
    let pool = ConnectionPool::new()
    let client = HttpClient::new(pool)
    let call = get_call_wb(client, server.port(), "/map-cut")
    let resp = call.execute()
    // WB⑤ 同款注入形态：取真实读错误（非构造值，保证映射判据成立前提）
    let real_err : Error = try {
      let _ = resp.body().unwrap().bytes()
      abort("夹具应注入读错误")
    } catch {
      err => err
    }
    assert_true(
      !(real_err is CallCancelled),
      msg="前态确认：注入错误本身非 CallCancelled（对照基准）",
    )
    // 白盒直驱：置取消标记后映射
    call.cancelled = true
    let mapped = try {
      raise call.map_read_error(real_err)
      false
    } catch {
      err => err is CallCancelled
    }
    assert_true(
      mapped,
      msg="cancelled ⇒ 读错误映射裸 CallCancelled（FR-002a/US-3-3，T020）",
    )
    pool.evict_all()
    server.close()
    s1.wait() catch {
      _ => ()
    }
  }
}

///|
// P05-WB⑭（T020 先红）：cancelled==false 对照 ⇒ 原错误透传不误映射
// （FR-011 不包装——防映射函数单向过度）。
async test "P05-WB⑭ 读错误映射：未取消 ⇒ 原错误不误映射" {
  @async.with_task_group() <| group => {
    let server = @fixtures.ScriptedServer::start()
    server.mount_truncated("GET", "/map-passthru", {
      status: 200,
      headers: [],
      framing: Fixed,
      body: Static(b"abcdef"),
      head_delay_ms: 0,
      close_after_response: false,
    })
    let s1 = group.spawn(
      () => server.serve_once(timeout_ms=3000),
      allow_failure=true,
    )
    let pool = ConnectionPool::new()
    let client = HttpClient::new(pool)
    let call = get_call_wb(client, server.port(), "/map-passthru")
    let resp = call.execute()
    let real_err : Error = try {
      let _ = resp.body().unwrap().bytes()
      abort("夹具应注入读错误")
    } catch {
      err => err
    }
    assert_false(call.cancelled, msg="前态确认：未取消")
    let not_mapped = try {
      raise call.map_read_error(real_err)
      false
    } catch {
      err => !(err is CallCancelled)
    }
    assert_true(
      not_mapped,
      msg="未取消 ⇒ 原错误透传不包装（FR-011，T020 对照面）",
    )
    pool.evict_all()
    server.close()
    s1.wait() catch {
      _ => ()
    }
  }
}
