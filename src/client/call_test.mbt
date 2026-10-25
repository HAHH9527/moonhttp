///|
// call_test：P05 黑盒场景测试（US-1/2/3/5；quickstart §2 口径）。
// 全部基于 P03 本地夹具（ScriptedServer/ScriptedPeer，宪法 IV 只触
// loopback）；断言优先 assert_eq / `err is`；禁 sleep 串联——取消/滴流以
// 夹具节奏推进。夹具收尾范式：客户端侧 pool.evict_all() 关闭空闲归池
// 连接，令服务端处理循环以 EOF 收尾后 serving.wait() 返回。

///|
// 构造 GET Call 的辅助（黑盒仅公开面）。
fn get_call_to(
  client : @client.HttpClient,
  port : Int32,
  path : String,
) -> @client.Call raise {
  let url = @core.HttpUrl::parse("http://127.0.0.1:\{port}\{path}")
  let request = @core.RequestBuilder::new(url).method(@core.Method::Get).build()
  client.new_call(request)
}

///|
// 构造 Bytes 体 POST Call 的辅助。
fn echo_post_call_to(
  client : @client.HttpClient,
  port : Int32,
  path : String,
  payload : Bytes,
) -> @client.Call raise {
  let url = @core.HttpUrl::parse("http://127.0.0.1:\{port}\{path}")
  let body = @core.RequestBody::bytes(payload, payload.length().to_int64())
  let request = @core.RequestBuilder::new(url)
    .method(@core.Method::Post)
    .body(body)
    .build()
  client.new_call(request)
}

///|
// P05-US1①（FR-009，T007）：echo 夹具 POST（Bytes 体）——code/headers/body
// 正确、回显一致。
async test "P05-US1① echo POST：完整 Response 与回显一致" {
  @async.with_task_group() <| group => {
    let server = @fixtures.ScriptedServer::start()
    server.mount("POST", "/echo", {
      status: 200,
      headers: [("X-Route", "echo")],
      framing: Fixed,
      body: Echo,
      head_delay_ms: 0,
      close_after_response: false,
    })
    let serving = group.spawn(() => server.serve_once(timeout_ms=3000))
    let pool = @client.ConnectionPool::new()
    let client = @client.HttpClient::new(pool)
    let call = echo_post_call_to(
      client,
      server.port(),
      "/echo",
      b"ping-payload",
    )
    let resp = call.execute()
    assert_eq(resp.code(), 200, msg="响应码应为 200（FR-009）")
    assert_eq(
      resp.headers().get("X-Route"),
      Some("echo"),
      msg="响应头应完整在场（FR-009）",
    )
    assert_eq(
      resp.body().unwrap().text(),
      "1:ping-payload",
      msg="echo 体应为 \"<id>:<请求体原样>\"（FR-009/FR-013）",
    )
    pool.evict_all()
    server.close()
    serving.wait()
  }
}

///|
// P05-US1②（SC-002 双证据，T007）：同一 HttpClient 连续 3 次 execute 同一
// Address——夹具侧新建连接数==1（accepted_total/conn_request_counts）且
// 池侧计数一致。
async test "P05-US1② 连续 3 次 execute 复用同一连接" {
  @async.with_task_group() <| group => {
    let server = @fixtures.ScriptedServer::start()
    server.mount("GET", "/pipe", {
      status: 200,
      headers: [],
      framing: Fixed,
      body: Static(b"ok"),
      head_delay_ms: 0,
      close_after_response: false,
    })
    let serving = group.spawn(() => server.serve_n(1, timeout_ms=5000))
    let pool = @client.ConnectionPool::new()
    let client = @client.HttpClient::new(pool)
    let addr = @client.Address::new(
      scheme="http",
      host="127.0.0.1",
      port=server.port(),
    )
    for i in 0..<3 {
      let call = get_call_to(client, server.port(), "/pipe")
      let resp = call.execute()
      assert_eq(resp.body().unwrap().text(), "ok")
      assert_eq(
        pool.per_host_total(addr),
        1,
        msg="第 \{i} 次.execute 出现新建——连接复用断裂（SC-002）",
      )
    }
    pool.evict_all()
    server.close()
    serving.wait()
    assert_eq(
      server.accepted_total(),
      1,
      msg="夹具侧新建连接数应为 1（SC-002 双证据）",
    )
    assert_eq(
      server.conn_request_counts(),
      [3],
      msg="单连接应承载全部 3 个请求（keep-alive 复用）",
    )
  }
}

///|
// P05-US1③（FR-007，T007）：Connection: close 响应读完后再次 execute——
// 新建连接计数 +1（旧连接未回池）。
async test "P05-US1③ Connection:close 读完不回池、再执行新建 +1" {
  @async.with_task_group() <| group => {
    let server = @fixtures.ScriptedServer::start()
    server.mount_sequence("GET", "/closing", [
      {
        status: 200,
        headers: [],
        framing: Fixed,
        body: Static(b"first"),
        head_delay_ms: 0,
        close_after_response: true,
      },
      {
        status: 200,
        headers: [],
        framing: Fixed,
        body: Static(b"second"),
        head_delay_ms: 0,
        close_after_response: false,
      },
    ])
    let serving = group.spawn(() => server.serve_n(2, timeout_ms=5000))
    let pool = @client.ConnectionPool::new()
    let client = @client.HttpClient::new(pool)
    let addr = @client.Address::new(
      scheme="http",
      host="127.0.0.1",
      port=server.port(),
    )
    let first = get_call_to(client, server.port(), "/closing")
    let resp1 = first.execute()
    assert_eq(resp1.body().unwrap().text(), "first")
    let second = get_call_to(client, server.port(), "/closing")
    let resp2 = second.execute()
    assert_eq(resp2.body().unwrap().text(), "second")
    assert_eq(
      pool.per_host_total(addr),
      2,
      msg="close 后旧连接未回池，第二次 execute 必须新建（FR-007）",
    )
    pool.evict_all()
    server.close()
    serving.wait()
    assert_eq(
      server.accepted_total(),
      2,
      msg="夹具侧应恰好接受 2 条连接（FR-007 双证据）",
    )
  }
}

///|
// P05-US1④（FR-009 帧形态，T007）：未知长度 Stream 体——捕获 chunked==true
// 且内容逐字节一致（帧形态由 P02 判定，本包不改写）。捕获经
// ScriptedPeer::Capture（池直连裸对端端口，线上字节为准）。
async test "P05-US1④ 未知长度 Stream 体以 chunked 发送且内容一致" {
  @async.with_task_group() <| group => {
    let peer = @fixtures.ScriptedPeer::start()
    peer.mount(Capture)
    let running = group.spawn(() => peer.run(timeout_ms=3000))
    let pool = @client.ConnectionPool::new()
    let client = @client.HttpClient::new(pool)
    let url = @core.HttpUrl::parse("http://127.0.0.1:\{peer.port()}/stream")
    let body = @core.RequestBody::stream(w => w.write(b"chunked-payload"))
    let request = @core.RequestBuilder::new(url)
      .method(@core.Method::Post)
      .body(body)
      .build()
    let call = client.new_call(request)
    let resp = call.execute()
    assert_eq(resp.code(), 200, msg="canned 200 应正常收头")
    let captured = running.wait()
    assert_true(
      captured.chunked,
      msg="未知长度 Stream 体必须以 chunked 帧上线（FR-009）",
    )
    assert_eq(
      captured.body,
      b"chunked-payload",
      msg="Stream 体内容应逐字节一致（FR-009）",
    )
    peer.close()
  }
}

///|
// P05-US1⑤（FR-010，T007，消费 T002 结论）：1xx-then-200 组合响应——
// execute 返回最终响应、缺省回调不暴露（C3）。
async test "P05-US1⑤ 1xx 透传：execute 返回最终 200" {
  @async.with_task_group() <| group => {
    let server = @fixtures.ScriptedServer::start()
    server.mount_interim("GET", "/info", 100, {
      status: 200,
      headers: [],
      framing: Fixed,
      body: Static(b"final-body"),
      head_delay_ms: 0,
      close_after_response: false,
    })
    let serving = group.spawn(() => server.serve_once(timeout_ms=3000))
    let pool = @client.ConnectionPool::new()
    let client = @client.HttpClient::new(pool)
    let call = get_call_to(client, server.port(), "/info")
    let resp = call.execute()
    assert_eq(
      resp.code(),
      200,
      msg="1xx 应被跳过，execute 返回最终响应",
    )
    assert_eq(resp.body().unwrap().text(), "final-body")
    pool.evict_all()
    server.close()
    serving.wait()
  }
}

///|
// P05-US1⑥（US-1 GET 覆盖，analyze C2 补）：GET 冒烟——捕获请求行方法为
// GET 且无 body 发送（捕获经 ScriptedPeer::Capture，serve_once 无捕获返回）。
async test "P05-US1⑥ GET 冒烟：请求行 GET、零请求体" {
  @async.with_task_group() <| group => {
    let peer = @fixtures.ScriptedPeer::start()
    peer.mount(Capture)
    let running = group.spawn(() => peer.run(timeout_ms=3000))
    let pool = @client.ConnectionPool::new()
    let client = @client.HttpClient::new(pool)
    let call = get_call_to(client, peer.port(), "/smoke")
    let resp = call.execute()
    assert_eq(resp.code(), 200, msg="canned 200 应正常收头")
    let captured = running.wait()
    captured.assert_matches(
      @fixtures.expect_request_line(meth="GET", target="/smoke"),
      "US1⑥",
    )
    assert_eq(captured.body, b"", msg="GET 不得发送请求体")
    peer.close()
  }
}
