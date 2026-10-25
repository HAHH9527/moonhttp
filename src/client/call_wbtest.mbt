///|
// call_wbtest：P05 白盒测试（包内私有面直读——I-7，004 R7 先例）。
// 承载：状态机直驱（WB①②③⑪）、折叠缓存（WB⑧、US4①）、BodyBridge
// 读适配与租约处置（WB④～⑦⑫）、竞争与收尾（WB⑨⑩）。
//
// T004 先红后绿：本文件 P05-WB①②③（红）→ http_client.mbt 骨架（绿）。

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
