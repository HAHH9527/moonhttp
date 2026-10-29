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
    let serving = group.spawn(
      () => server.serve_once(timeout_ms=3000),
      allow_failure=true,
    )
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
    let serving = group.spawn(
      () => server.serve_n(1, timeout_ms=5000),
      allow_failure=true,
    )
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
    let serving = group.spawn(
      () => server.serve_n(2, timeout_ms=5000),
      allow_failure=true,
    )
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
    let serving = group.spawn(
      () => server.serve_once(timeout_ms=3000),
      allow_failure=true,
    )
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

///|
// P05-US1⑧（FR-007/SC-002，T022 先红）：Connection: Close（大小写形态）
// ——读完不回池：再次 execute 新建连接 +1（池侧计数 + 夹具 accepted_total
// 双证据，仿 US1③）。现状精确小写比较漏判 ⇒ 红。
async test "P05-US1⑧ Connection:Close（大小写）读完不回池、新建 +1" {
  @async.with_task_group() <| group => {
    let server = @fixtures.ScriptedServer::start()
    server.mount("GET", "/closing-upper", {
      status: 200,
      headers: [("Connection", "Close")],
      framing: Fixed,
      body: Static(b"first"),
      head_delay_ms: 0,
      close_after_response: false,
    })
    let serving = group.spawn(
      () => server.serve_n(2, timeout_ms=5000),
      allow_failure=true,
    )
    let pool = @client.ConnectionPool::new()
    let client = @client.HttpClient::new(pool)
    let addr = @client.Address::new(
      scheme="http",
      host="127.0.0.1",
      port=server.port(),
    )
    let first = get_call_to(client, server.port(), "/closing-upper")
    let resp1 = first.execute()
    assert_eq(resp1.code(), 200, msg="大小写形态响应应正常收头")
    assert_eq(resp1.body().unwrap().text(), "first")
    let second = get_call_to(client, server.port(), "/closing-upper")
    let resp2 = second.execute()
    assert_eq(resp2.code(), 200)
    assert_eq(
      pool.per_host_total(addr),
      2,
      msg="Connection: Close 大小写必须毒化不回池，第二次 execute 新建（FR-007/T022）",
    )
    pool.evict_all()
    server.close()
    serving.wait()
    assert_eq(
      server.accepted_total(),
      2,
      msg="夹具侧应恰好接受 2 条连接（FR-007 双证据，T022）",
    )
  }
}

///|
// P05-US1⑨（FR-007/SC-002，T022 先红）：Connection: keep-alive, close
// （多值形态，重复头以 "," 拼接同款）——token 解析任一命中即毒化。
async test "P05-US1⑨ Connection 多值 close 读完不回池、新建 +1" {
  @async.with_task_group() <| group => {
    let server = @fixtures.ScriptedServer::start()
    server.mount("GET", "/closing-multi", {
      status: 200,
      headers: [("Connection", "keep-alive, close")],
      framing: Fixed,
      body: Static(b"first"),
      head_delay_ms: 0,
      close_after_response: false,
    })
    let serving = group.spawn(
      () => server.serve_n(2, timeout_ms=5000),
      allow_failure=true,
    )
    let pool = @client.ConnectionPool::new()
    let client = @client.HttpClient::new(pool)
    let addr = @client.Address::new(
      scheme="http",
      host="127.0.0.1",
      port=server.port(),
    )
    let first = get_call_to(client, server.port(), "/closing-multi")
    let resp1 = first.execute()
    assert_eq(resp1.code(), 200, msg="多值形态响应应正常收头")
    assert_eq(resp1.body().unwrap().text(), "first")
    let second = get_call_to(client, server.port(), "/closing-multi")
    let resp2 = second.execute()
    assert_eq(resp2.code(), 200)
    assert_eq(
      pool.per_host_total(addr),
      2,
      msg="keep-alive, close 多值必须 token 毒化不回池，新建 +1（FR-007/T022）",
    )
    pool.evict_all()
    server.close()
    serving.wait()
    assert_eq(
      server.accepted_total(),
      2,
      msg="夹具侧应恰好接受 2 条连接（FR-007 双证据，T022）",
    )
  }
}

///|
// ===== US-3：cancel 三阶段（Phase 4，T008/T009 黑盒面）=====

///|
// P05-US3①（FR-002a/US-3-1，T008）：预取消后 execute——立即
// `err is CallCancelled` 且 accepted_total==0（零网络动作）。
async test "P05-US3① 预取消：零网络动作、CallCancelled" {
  @async.with_task_group() <| group => {
    let server = @fixtures.ScriptedServer::start()
    server.mount("GET", "/never", {
      status: 200,
      headers: [],
      framing: Fixed,
      body: Static(b"never"),
      head_delay_ms: 0,
      close_after_response: false,
    })
    let serving = group.spawn(
      () => server.serve_once(timeout_ms=2000),
      allow_failure=true,
    )
    let pool = @client.ConnectionPool::new()
    let client = @client.HttpClient::new(pool)
    let call = get_call_to(client, server.port(), "/never")
    call.cancel()
    let cancelled = try {
      let _ = call.execute()
      false
    } catch {
      err => err is @client.CallCancelled
    }
    assert_true(
      cancelled,
      msg="预取消 execute 必须以 CallCancelled 收场（FR-002a）",
    )
    assert_eq(
      server.accepted_total(),
      0,
      msg="预取消不得产生任何网络动作（US-3-1 零网络）",
    )
    pool.evict_all()
    server.close()
    serving.wait()
  }
}

///|
// P05-US3②（FR-002b/US-3-2，T008）：大 Stream 体写入中 cancel（服务端
// Static 脚本不读请求体 ⇒ 客户端写停摆等待窗口）——写路径以裸
// CallCancelled 失败；per_host_total 不变（毒化 ⇒ 不回池的等价断言一半，
// 「再现次数 0」级断言落 P05-WB 白盒直读——analyze B2）。
async test "P05-US3② 写入中取消：CallCancelled 且连接毒化" {
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
    let serving = group.spawn(
      () => server.serve_n(1, timeout_ms=5000),
      allow_failure=true,
    )
    let pool = @client.ConnectionPool::new()
    let client = @client.HttpClient::new(pool)
    let addr = @client.Address::new(
      scheme="http",
      host="127.0.0.1",
      port=server.port(),
    )
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
    // 推进到写停摆窗口（对端不读体 ⇒ 传输窗口填满后写入阻塞）
    @async.sleep(150)
    call.cancel()
    let cancelled = try {
      let _ = executing.wait()
      false
    } catch {
      err => err is @client.CallCancelled
    }
    assert_true(
      cancelled,
      msg="写中取消必须以裸 CallCancelled 收场（FR-002b）",
    )
    assert_true(call.is_cancelled())
    assert_eq(
      pool.per_host_total(addr),
      1,
      msg="毒化连接不得触发新建（计数守恒）",
    )
    pool.evict_all()
    // 夹具收尾：注入关闭引发的写侧错误按注入语义吞（不判失败）
    server.close()
    serving.wait() catch {
      _ => ()
    }
  }
}

///|
// P05-US3③（US-3-3，T008）：Drip 滴流读中 cancel——读路径以裸
// CallCancelled 失败、连接毒化（池计数断言：后续 execute 新建 +1 证明
// 旧连接未回池）。
async test "P05-US3③ 读中取消：CallCancelled 且毒化不回池" {
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
    let pool = @client.ConnectionPool::new()
    let client = @client.HttpClient::new(pool)
    let addr = @client.Address::new(
      scheme="http",
      host="127.0.0.1",
      port=server.port(),
    )
    let call = get_call_to(client, server.port(), "/drip")
    let resp = call.execute()
    let body = resp.body().unwrap()
    // 读两块（滴流节奏内），随后取消
    let _ = body.read_some()
    let _ = body.read_some()
    call.cancel()
    let cancelled = try {
      while body.read_some() is Some(_) {
        ()
      }
      false
    } catch {
      err => err is @client.CallCancelled
    }
    assert_true(
      cancelled,
      msg="读中取消必须以裸 CallCancelled 收场（US-3-3）",
    )
    assert_eq(
      pool.per_host_total(addr),
      1,
      msg="取消毒化的连接不得回池（计数未变）",
    )
    // 连接 1 收尾：注入关闭引发的夹具写侧错误按注入语义吞
    s1.wait() catch {
      _ => ()
    }
    assert_eq(server.accepted_total(), 1, msg="取消阶段恰好 1 条连接")
    // 再现次数 0 的等价断言：后续 execute 必须新建（若旧连接回池则复用、
    // 计数不动）——新开夹具服务第二条连接
    server.mount("GET", "/drip2", {
      status: 200,
      headers: [],
      framing: Fixed,
      body: Static(b"xxxxxxxxxxxxxxxxxxxxx"),
      head_delay_ms: 0,
      close_after_response: false,
    })
    let s2 = group.spawn(
      () => server.serve_once(timeout_ms=5000),
      allow_failure=true,
    )
    let next = get_call_to(client, server.port(), "/drip2")
    let resp2 = next.execute()
    assert_eq(resp2.code(), 200)
    assert_eq(
      pool.per_host_total(addr),
      2,
      msg="被取消连接在其后租借中再现次数必须为 0（SC-003）",
    )
    assert_eq(resp2.body().unwrap().text(), "xxxxxxxxxxxxxxxxxxxxx")
    pool.evict_all()
    server.close()
    s2.wait() catch {
      _ => ()
    }
    assert_eq(server.accepted_total(), 2, msg="夹具侧应恰好 2 条连接")
  }
}

///|
// P05-US3④（FR-012 前半/I-5，T008）：cancel 后 is_cancelled==true、重复
// cancel 幂等无错。
async test "P05-US3④ cancel 幂等" {
  @async.with_task_group() <| _group => {
    let pool = @client.ConnectionPool::new()
    let client = @client.HttpClient::new(pool)
    let call = get_call_to(client, 1, "/x")
    call.cancel()
    call.cancel()
    call.cancel()
    assert_true(
      call.is_cancelled(),
      msg="重复 cancel 幂等、标记保持（I-5）",
    )
  }
}

///|
// ===== US-5：响应体生命周期闭环（Phase 5，T010）=====

///|
// P05-US5①（FR-005/US-5-1，T010）：流式 body 读到最后一块——连接回池
// （下次 execute 复用、新建连接计数不增 + 夹具侧单连接承载 2 请求）。
async test "P05-US5① 读到底回池：复用双证据" {
  @async.with_task_group() <| group => {
    let server = @fixtures.ScriptedServer::start()
    server.mount("GET", "/pipe", {
      status: 200,
      headers: [],
      framing: Fixed,
      body: Static(b"payload-1"),
      head_delay_ms: 0,
      close_after_response: false,
    })
    let serving = group.spawn(
      () => server.serve_n(1, timeout_ms=5000),
      allow_failure=true,
    )
    let pool = @client.ConnectionPool::new()
    let client = @client.HttpClient::new(pool)
    let addr = @client.Address::new(
      scheme="http",
      host="127.0.0.1",
      port=server.port(),
    )
    let first = get_call_to(client, server.port(), "/pipe")
    let resp = first.execute()
    assert_eq(resp.body().unwrap().text(), "payload-1")
    let second = get_call_to(client, server.port(), "/pipe")
    let resp2 = second.execute()
    assert_eq(resp2.body().unwrap().text(), "payload-1")
    assert_eq(
      pool.per_host_total(addr),
      1,
      msg="读到底回池 ⇒ 第二次 execute 必须复用（US-5-1）",
    )
    pool.evict_all()
    server.close()
    serving.wait()
    assert_eq(
      server.accepted_total(),
      1,
      msg="夹具侧单连接（SC-005 双证据）",
    )
    assert_eq(server.conn_request_counts(), [2])
  }
}

///|
// P05-US5②（US-5-2，T010，端到端消费 core dispose 面）：读一半即弃 →
// dispose()——skip 清理回池 + 夹具侧下个请求读到干净流无残帧。
async test "P05-US5② 读半 dispose：skip 回池 + 下个请求干净流" {
  @async.with_task_group() <| group => {
    let server = @fixtures.ScriptedServer::start()
    server.mount("GET", "/big", {
      status: 200,
      headers: [],
      framing: Fixed,
      body: Static(Bytes::from_iter(Array::make(2048, b'a').iter())),
      head_delay_ms: 0,
      close_after_response: false,
    })
    server.mount("POST", "/echo", {
      status: 200,
      headers: [],
      framing: Fixed,
      body: Echo,
      head_delay_ms: 0,
      close_after_response: false,
    })
    let serving = group.spawn(
      () => server.serve_n(1, timeout_ms=5000),
      allow_failure=true,
    )
    let pool = @client.ConnectionPool::new()
    let client = @client.HttpClient::new(pool)
    let addr = @client.Address::new(
      scheme="http",
      host="127.0.0.1",
      port=server.port(),
    )
    // 大静态体（CL 已知），读一半即弃
    let call = get_call_to(client, server.port(), "/big")
    let resp = call.execute()
    let body = resp.body().unwrap()
    let _ = body.read_some()
    body.dispose()
    // skip 成功 ⇒ 回池：下个请求复用且服务端读到干净请求流
    let next_payload = Bytes::from_iter(Array::make(32, b'b').iter())
    let next = echo_post_call_to(client, server.port(), "/echo", next_payload)
    let resp2 = next.execute()
    let echoed = resp2.body().unwrap().text()
    assert_eq(
      echoed,
      "1:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      msg="下个请求体应干净无残帧（US-5-2 双证据）",
    )
    assert_eq(
      pool.per_host_total(addr),
      1,
      msg="dispose skip 成功必须回池复用（US-5-2）",
    )
    pool.evict_all()
    server.close()
    serving.wait()
    assert_eq(server.accepted_total(), 1, msg="夹具侧单连接（SC-005）")
  }
}

///|
// P05-US5③（US-5-3，T010）：skip 失败注入（mount_truncated 断连）——
// dispose 毒化关闭、池计数守恒（后续 execute 新建 +1）。
async test "P05-US5③ skip 失败：毒化关闭、池计数守恒" {
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
    let serving = group.spawn(
      () => server.serve_n(2, timeout_ms=5000),
      allow_failure=true,
    )
    let pool = @client.ConnectionPool::new()
    let client = @client.HttpClient::new(pool)
    let addr = @client.Address::new(
      scheme="http",
      host="127.0.0.1",
      port=server.port(),
    )
    let call = get_call_to(client, server.port(), "/cut")
    let resp = call.execute()
    let failed = try {
      resp.body().unwrap().dispose()
      false
    } catch {
      _ => true
    }
    assert_true(failed, msg="skip 失败必须透传错误（US-5-3）")
    assert_eq(pool.per_host_total(addr), 1, msg="毒化路径不新建")
    let next = get_call_to(client, server.port(), "/cut")
    let resp2 = next.execute()
    assert_eq(resp2.code(), 200)
    assert_eq(
      pool.per_host_total(addr),
      2,
      msg="skip 失败毒化 ⇒ 不回池，后续 execute 新建 +1（US-5-3）",
    )
    pool.evict_all()
    server.close()
    serving.wait()
    assert_eq(server.accepted_total(), 2)
  }
}

///|
// P05-US5④（FR-011，T010）：非取消错误毒化——RST/断连 → 错误原样透传
// （不包装为 CallCancelled）+ 连接不回池（重试判定归 P07）。
async test "P05-US5④ 断连读错误：透传 + 不回池" {
  @async.with_task_group() <| group => {
    let server = @fixtures.ScriptedServer::start()
    server.mount_truncated("GET", "/rst", {
      status: 200,
      headers: [],
      framing: Fixed,
      body: Static(b"partial"),
      head_delay_ms: 0,
      close_after_response: false,
    })
    let serving = group.spawn(
      () => server.serve_n(2, timeout_ms=5000),
      allow_failure=true,
    )
    let pool = @client.ConnectionPool::new()
    let client = @client.HttpClient::new(pool)
    let addr = @client.Address::new(
      scheme="http",
      host="127.0.0.1",
      port=server.port(),
    )
    let call = get_call_to(client, server.port(), "/rst")
    let resp = call.execute()
    let outcome = try {
      let _ = resp.body().unwrap().text()
      Ok(true)
    } catch {
      err =>
        if err is @client.CallCancelled {
          Err("非取消场景误映射 CallCancelled")
        } else {
          Ok(false)
        }
    }
    assert_true(
      outcome is Ok(_) && !(outcome is Ok(true)),
      msg="断连错误必须原样透传（FR-011 不包装）",
    )
    assert_eq(pool.per_host_total(addr), 1)
    let next = get_call_to(client, server.port(), "/rst")
    let resp2 = next.execute()
    assert_eq(resp2.code(), 200)
    assert_eq(
      pool.per_host_total(addr),
      2,
      msg="非取消错误毒化 ⇒ 不回池，后续新建 +1（FR-011）",
    )
    pool.evict_all()
    server.close()
    serving.wait()
    assert_eq(server.accepted_total(), 2)
  }
}

///|
// P05-US5⑤（边界，T010）：空 body（Content-Length: 0）——消费即刻完成、
// 连接回池。
async test "P05-US5⑤ 空 body 即刻消费完成且回池" {
  @async.with_task_group() <| group => {
    let server = @fixtures.ScriptedServer::start()
    server.mount("GET", "/empty", {
      status: 200,
      headers: [],
      framing: Fixed,
      body: Static(b""),
      head_delay_ms: 0,
      close_after_response: false,
    })
    let serving = group.spawn(
      () => server.serve_n(1, timeout_ms=5000),
      allow_failure=true,
    )
    let pool = @client.ConnectionPool::new()
    let client = @client.HttpClient::new(pool)
    let addr = @client.Address::new(
      scheme="http",
      host="127.0.0.1",
      port=server.port(),
    )
    let call = get_call_to(client, server.port(), "/empty")
    let resp = call.execute()
    assert_eq(resp.body().unwrap().bytes().length(), 0, msg="空体 0 字节")
    assert_true(resp.body().unwrap().consumed(), msg="空体消费即刻完成")
    let next = get_call_to(client, server.port(), "/empty")
    let _ = next.execute()
    assert_eq(
      pool.per_host_total(addr),
      1,
      msg="空体路径必须回池复用（US-5⑤ 边界）",
    )
    pool.evict_all()
    server.close()
    serving.wait()
    assert_eq(server.accepted_total(), 1)
  }
}

///|
// P05-US5⑥（FR-011/宪法 IV，T023 补判据）：execute 段非取消错误验收——
// 夹具 PeerProgram::AcceptClose（accept 后立即关连，收头前失败，零夹具
// 扩展）。断言：错误原样透传（非 CallCancelled 且非 CallStateError）+
// 毒化不回池（后续 execute 新建 +1；夹具侧证据＝第二次 run 重新 accept
// 到新连接且按 AcceptClose 语义 early-broken——ScriptedPeer 无
// accepted_total 计数，run 返回即 accept 发生的凭证）。
// 【补判据：落笔即绿，显式标注】exchange.mbt 的 errdefer poison_release
// 实现已在场（既有实现无测试的判据缺口），本用例补齐验收判据、首跑即绿
// （非红绿对；错误透传路径已由 T021 组外兜底落实）。
async test "P05-US5⑥ execute 段断连：错误透传 + 毒化不回池" {
  @async.with_task_group() <| group => {
    let peer = @fixtures.ScriptedPeer::start()
    peer.mount(AcceptClose)
    let running1 = group.spawn(() => peer.run(timeout_ms=3000))
    let pool = @client.ConnectionPool::new()
    let client = @client.HttpClient::new(pool)
    let addr = @client.Address::new(
      scheme="http",
      host="127.0.0.1",
      port=peer.port(),
    )
    let call = get_call_to(client, peer.port(), "/cut-early")
    let failed = try {
      let _ = call.execute()
      false
    } catch {
      err => !(err is @client.CallCancelled) && !(err is @client.CallStateError)
    }
    assert_true(
      failed,
      msg="execute 段非取消错误必须原样透传（FR-011，T023）",
    )
    // 夹具侧收尾：AcceptClose 的 run 正常返回（early-broken 捕获）
    let capture1 = running1.wait()
    assert_false(
      capture1.complete,
      msg="夹具语义确认：accept 后立即关连（AcceptClose）",
    )
    assert_eq(
      pool.per_host_total(addr),
      1,
      msg="毒化路径不新建（计数守恒）",
    )
    // 毒化不回池证据：后续 execute 必须新建（夹具第二次 accept）
    peer.mount(AcceptClose)
    let running2 = group.spawn(() => peer.run(timeout_ms=3000))
    let next = get_call_to(client, peer.port(), "/cut-early")
    let second_failed = try {
      let _ = next.execute()
      false
    } catch {
      _ => true
    }
    assert_true(second_failed, msg="第二条连接同按 AcceptClose 失败")
    let capture2 = running2.wait()
    assert_false(
      capture2.complete,
      msg="夹具侧第二次 accept 到新建连接（毒化不回池的夹具证据）",
    )
    assert_eq(
      pool.per_host_total(addr),
      2,
      msg="execute 段毒化 ⇒ 不回池，后续 execute 新建 +1（T023）",
    )
    pool.evict_all()
    peer.close()
  }
}

///|
// ===== US-2：Call 一次性语义（Phase 6，T011 黑盒穷尽面）=====

///|
// P05-US2①（FR-001，T011）：已完成（成功交付 Response）后二次 execute ⇒
// `err is CallStateError`。
async test "P05-US2① 完成后二次 execute：CallStateError" {
  @async.with_task_group() <| group => {
    let server = @fixtures.ScriptedServer::start()
    server.mount("GET", "/done", {
      status: 200,
      headers: [],
      framing: Fixed,
      body: Static(b"ok"),
      head_delay_ms: 0,
      close_after_response: false,
    })
    let serving = group.spawn(
      () => server.serve_once(timeout_ms=3000),
      allow_failure=true,
    )
    let pool = @client.ConnectionPool::new()
    let client = @client.HttpClient::new(pool)
    let call = get_call_to(client, server.port(), "/done")
    let resp = call.execute()
    assert_eq(resp.code(), 200)
    let state_error = try {
      let _ = call.execute()
      false
    } catch {
      err => err is @client.CallStateError
    }
    assert_true(
      state_error,
      msg="完成后二次 execute 必须 CallStateError（FR-001）",
    )
    pool.evict_all()
    server.close()
    serving.wait() catch {
      _ => ()
    }
  }
}

///|
// P05-US2②（FR-001，T011）：已失败（网络错误透传）后二次 execute ⇒
// CallStateError。失败注入＝port 0（建连拒绝，P04-E⑥ 同款形态）。
async test "P05-US2② 失败后二次 execute：CallStateError" {
  @async.with_task_group() <| _group => {
    let pool = @client.ConnectionPool::new()
    let client = @client.HttpClient::new(pool)
    let call = get_call_to(client, 1, "/x")
    let failed = try {
      let _ = call.execute()
      false
    } catch {
      err => !(err is @client.CallStateError) && !(err is @client.CallCancelled)
    }
    assert_true(
      failed,
      msg="建连失败应原样透传（网络错误不在此二层）",
    )
    let state_error = try {
      let _ = call.execute()
      false
    } catch {
      err => err is @client.CallStateError
    }
    assert_true(
      state_error,
      msg="失败后二次 execute 必须 CallStateError（FR-001）",
    )
  }
}

///|
// P05-US2③（FR-001，T011）：已取消（CallCancelled）后二次 execute ⇒
// CallStateError。
async test "P05-US2③ 取消后二次 execute：CallStateError" {
  @async.with_task_group() <| _group => {
    let pool = @client.ConnectionPool::new()
    let client = @client.HttpClient::new(pool)
    let call = get_call_to(client, 1, "/x")
    call.cancel()
    let cancelled = try {
      let _ = call.execute()
      false
    } catch {
      err => err is @client.CallCancelled
    }
    assert_true(cancelled)
    let state_error = try {
      let _ = call.execute()
      false
    } catch {
      err => err is @client.CallStateError
    }
    assert_true(
      state_error,
      msg="取消后二次 execute 必须 CallStateError（FR-001）",
    )
  }
}

///|
// ===== P06：US-1～US-6 场景（2026-10-27 起，spec 006）=====

///|
// P06 辅助：初始跳转场景请求（可选体 + 手设 Content-Type/Transfer-
// Encoding——body 无 CT 元信息 ⇒ 转换层不动用户头，保证三头在原请求
// HeadersV 在场，使降级 remove 可观测）。
// 【review 修复批 M6 口径】线上捕获面仅 Content-Type 判别：body=None ⇒
// 无 CL；上游 @http send 层 forbidden_headers 无条件丢调用方 TE——
// CL/TE 的线上缺席是结构性保证（删掉降级 remove() 也恒真），其去除
// 行为由 P06-WB⑦ 纯函数面（真实在场三头 + 去除断言）承载。
fn p06_call(
  client : @client.HttpClient,
  port : Int32,
  path : String,
  meth : @core.Method,
  body : @core.RequestBody?,
) -> @client.Call raise {
  let url = @core.HttpUrl::parse("http://127.0.0.1:\{port}\{path}")
  let builder = @core.RequestBuilder::new(url).method(meth)
  builder.header("Content-Type", "text/custom")
  builder.header("Transfer-Encoding", "chunked")
  match body {
    Some(b) => client.new_call(builder.body(b).build())
    None => client.new_call(builder.build())
  }
}

///|
// P06 辅助：serverA 挂跳转路由——绝对 Location 指向捕获对端（R7 双实例
// 口径）；中间响应体恒空（round8 I5 分期窗口：T005–T011 不引入带体中间
// 响应，INV-2 自 T012 drain_intermediate 起承载）。
fn p06_mount_redirect(
  server : @fixtures.ScriptedServer,
  meth~ : String,
  path~ : String,
  status~ : Int32,
  peer_port~ : Int32,
) -> Unit {
  server.mount(meth, path, {
    status,
    headers: [("Location", "http://127.0.0.1:\{peer_port}/b")],
    framing: Fixed,
    body: Static(b""),
    head_delay_ms: 0,
    close_after_response: false,
  })
}

///|
// P06-US1①（FR-003 行 1，T005）：POST /a → 301 Location → follow-up 为
// GET /b、无 body 与 Content-Length/Content-Type/Transfer-Encoding 头、
// 终态 200、prior 链长 1。
async test "P06-US1① POST 301 降级：GET 无体无三头、终态 200、prior 深 1" {
  @async.with_task_group() <| group => {
    let peer = @fixtures.ScriptedPeer::start()
    peer.mount(Capture)
    let running = group.spawn(() => peer.run(timeout_ms=5000))
    let server = @fixtures.ScriptedServer::start()
    p06_mount_redirect(
      server,
      meth="POST",
      path="/a",
      status=301,
      peer_port=peer.port(),
    )
    let s1 = group.spawn(
      () => server.serve_once(timeout_ms=5000),
      allow_failure=true,
    )
    let pool = @client.ConnectionPool::new()
    let client = @client.HttpClient::new(pool)
    let call = p06_call(
      client,
      server.port(),
      "/a",
      @core.Method::Post,
      Some(@core.RequestBody::bytes(b"post-payload", 12L)),
    )
    let resp = call.execute()
    assert_eq(
      resp.code(),
      200,
      msg="终态响应正确（跟随至捕获对端 canned 200）",
    )
    let p1 = resp.prior()
    assert_true(p1 is Some(_), msg="prior 链长 1（FR-006）")
    let p1 = p1.unwrap()
    assert_eq(p1.code(), 301, msg="prior 条目为跳转响应")
    assert_true(
      p1.prior() is None,
      msg="单跳链回溯即止（链长恰 1）",
    )
    assert_true(p1.body() is None, msg="prior 条目 body=None（INV-5）")
    let captured = running.wait()
    captured.assert_matches(
      @fixtures.expect_request_line(meth="GET", target="/b"),
      "US1①",
    )
    assert_eq(captured.body, b"", msg="降级 follow-up 无请求体")
    let head = captured.head_text()
    // 判别面（review 修复批 M6）：线上仅 CT 断言判别——CL 缺席因
    // body=None、TE 缺席因上游 send 层无条件丢弃（结构性保证）；CL/TE
    // 去除行为由 P06-WB⑦ 纯函数面钉死。
    assert_false(
      head.contains("Content-Type"),
      msg="降级去除 Content-Type（FR-003 行 1，线上判别面）：\{head}",
    )
    pool.evict_all()
    server.close()
    peer.close()
    s1.wait() catch {
      _ => ()
    }
  }
}

///|
// P06-US1②（FR-003 行 2，T005）：POST /a → 303 同判①。
async test "P06-US1② POST 303 降级：GET 无体无三头、终态 200、prior 深 1" {
  @async.with_task_group() <| group => {
    let peer = @fixtures.ScriptedPeer::start()
    peer.mount(Capture)
    let running = group.spawn(() => peer.run(timeout_ms=5000))
    let server = @fixtures.ScriptedServer::start()
    p06_mount_redirect(
      server,
      meth="POST",
      path="/a",
      status=303,
      peer_port=peer.port(),
    )
    let s1 = group.spawn(
      () => server.serve_once(timeout_ms=5000),
      allow_failure=true,
    )
    let pool = @client.ConnectionPool::new()
    let client = @client.HttpClient::new(pool)
    let call = p06_call(
      client,
      server.port(),
      "/a",
      @core.Method::Post,
      Some(@core.RequestBody::bytes(b"post-payload", 12L)),
    )
    let resp = call.execute()
    assert_eq(resp.code(), 200, msg="终态响应正确（303 降级跟随）")
    let p1 = resp.prior()
    assert_true(
      p1 is Some(_) && p1.unwrap().code() == 303 && p1.unwrap().prior() is None,
      msg="prior 链长 1 且条目为 303（FR-006）",
    )
    let captured = running.wait()
    captured.assert_matches(
      @fixtures.expect_request_line(meth="GET", target="/b"),
      "US1②",
    )
    assert_eq(captured.body, b"", msg="303 降级 follow-up 无请求体")
    let head = captured.head_text()
    // 判别面（review 修复批 M6，同 US1①）：线上仅 CT 断言判别
    assert_false(
      head.contains("Content-Type"),
      msg="303 降级去除 Content-Type（FR-003 行 2，线上判别面）：\{head}",
    )
    pool.evict_all()
    server.close()
    peer.close()
    s1.wait() catch {
      _ => ()
    }
  }
}

///|
// P06-US1④（FR-003 行 1/C2 修正固化，T005）：PUT /a → 302 Location →
// follow-up GET /b、body 丢弃、三头去除、prior 链长 1（5.5.0 对拍：非
// GET/HEAD 一律降级，种子「仅 POST」作废）。
async test "P06-US1④ PUT 302 降级：GET 无体无三头（C2 固化）" {
  @async.with_task_group() <| group => {
    let peer = @fixtures.ScriptedPeer::start()
    peer.mount(Capture)
    let running = group.spawn(() => peer.run(timeout_ms=5000))
    let server = @fixtures.ScriptedServer::start()
    p06_mount_redirect(
      server,
      meth="PUT",
      path="/a",
      status=302,
      peer_port=peer.port(),
    )
    let s1 = group.spawn(
      () => server.serve_once(timeout_ms=5000),
      allow_failure=true,
    )
    let pool = @client.ConnectionPool::new()
    let client = @client.HttpClient::new(pool)
    let call = p06_call(
      client,
      server.port(),
      "/a",
      @core.Method::Put,
      Some(@core.RequestBody::bytes(b"put-payload", 11L)),
    )
    let resp = call.execute()
    assert_eq(
      resp.code(),
      200,
      msg="终态响应正确（PUT 302 降级跟随）",
    )
    let p1 = resp.prior()
    assert_true(
      p1 is Some(_) && p1.unwrap().code() == 302,
      msg="prior 链长 1 且条目为 302（C2 固化）",
    )
    let captured = running.wait()
    captured.assert_matches(
      @fixtures.expect_request_line(meth="GET", target="/b"),
      "US1④",
    )
    assert_eq(captured.body, b"", msg="PUT 降级 body 丢弃")
    let head = captured.head_text()
    // 判别面（review 修复批 M6，同 US1①）：线上仅 CT 断言判别
    assert_false(
      head.contains("Content-Type"),
      msg="PUT 降级去除 Content-Type（FR-003 行 1，线上判别面）：\{head}",
    )
    pool.evict_all()
    server.close()
    peer.close()
    s1.wait() catch {
      _ => ()
    }
  }
}

///|
// P06-US1⑤（FR-003 行 1/300 修正固化，T005）：DELETE /a → 300 Location →
// follow-up GET /b（300 有 Location 即跟随，5.5.0 对拍）。
async test "P06-US1⑤ DELETE 300 降级：GET 跟随（300 修正固化）" {
  @async.with_task_group() <| group => {
    let peer = @fixtures.ScriptedPeer::start()
    peer.mount(Capture)
    let running = group.spawn(() => peer.run(timeout_ms=5000))
    let server = @fixtures.ScriptedServer::start()
    p06_mount_redirect(
      server,
      meth="DELETE",
      path="/a",
      status=300,
      peer_port=peer.port(),
    )
    let s1 = group.spawn(
      () => server.serve_once(timeout_ms=5000),
      allow_failure=true,
    )
    let pool = @client.ConnectionPool::new()
    let client = @client.HttpClient::new(pool)
    let call = p06_call(client, server.port(), "/a", @core.Method::Delete, None)
    let resp = call.execute()
    assert_eq(
      resp.code(),
      200,
      msg="终态响应正确（DELETE 300 降级跟随）",
    )
    let p1 = resp.prior()
    assert_true(
      p1 is Some(_) && p1.unwrap().code() == 300,
      msg="prior 链长 1 且条目为 300（300 修正固化）",
    )
    let captured = running.wait()
    captured.assert_matches(
      @fixtures.expect_request_line(meth="GET", target="/b"),
      "US1⑤",
    )
    assert_eq(captured.body, b"", msg="DELETE 降级 follow-up 无请求体")
    let head = captured.head_text()
    // 判别面（review 修复批 M6，同 US1①）：线上仅 CT 断言判别
    assert_false(
      head.contains("Content-Type"),
      msg="300 降级去除 Content-Type（FR-003 行 1，线上判别面）：\{head}",
    )
    pool.evict_all()
    server.close()
    peer.close()
    s1.wait() catch {
      _ => ()
    }
  }
}

///|
// P06-US1-prior（FR-006/INV-5，T006；机制测试不占 spec 场景号——round3
// D-1 编号对齐）：两跳同 host 链终态 .prior 链深 2、回溯顺序与夹具注入
// 的 3xx 序列逐项一致（code 断言）、prior 条目 body() 为 None（INV-5）。
// 中间响应恒空体（round8 I5 分期窗口口径）。
async test "P06-US1-prior 两跳链：链深 2、保序、条目无体" {
  @async.with_task_group() <| group => {
    let server = @fixtures.ScriptedServer::start()
    server.mount("GET", "/start", {
      status: 301,
      headers: [("Location", "/hop2")],
      framing: Fixed,
      body: Static(b""),
      head_delay_ms: 0,
      close_after_response: false,
    })
    server.mount("GET", "/hop2", {
      status: 302,
      headers: [("Location", "/final")],
      framing: Fixed,
      body: Static(b""),
      head_delay_ms: 0,
      close_after_response: false,
    })
    server.mount("GET", "/final", {
      status: 200,
      headers: [],
      framing: Fixed,
      body: Static(b"done"),
      head_delay_ms: 0,
      close_after_response: false,
    })
    let serving = group.spawn(
      () => server.serve_n(1, timeout_ms=5000),
      allow_failure=true,
    )
    let pool = @client.ConnectionPool::new()
    let client = @client.HttpClient::new(pool)
    let call = get_call_to(client, server.port(), "/start")
    let resp = call.execute()
    assert_eq(resp.code(), 200, msg="两跳链终态 200")
    assert_eq(resp.body().unwrap().text(), "done", msg="终态体正确")
    // 回溯顺序：终态.prior = 302（倒数第 2 跳）→ .prior = 301（最初 3xx）
    let p1 = resp.prior()
    assert_true(p1 is Some(_), msg="链深 2：第 1 级在场（FR-006）")
    let p1 = p1.unwrap()
    assert_eq(p1.code(), 302, msg="回溯首达倒数第 2 跳（保序）")
    assert_true(p1.body() is None, msg="prior 条目 body=None（INV-5）")
    let p2 = p1.prior()
    assert_true(p2 is Some(_), msg="链深 2：第 2 级在场（FR-006）")
    let p2 = p2.unwrap()
    assert_eq(p2.code(), 301, msg="回溯次达最初 3xx（保序）")
    assert_true(
      p2.prior() is None,
      msg="链止于最初响应（链深恰 2）",
    )
    assert_true(p2.body() is None, msg="prior 条目 body=None（INV-5）")
    pool.evict_all()
    server.close()
    serving.wait()
    assert_eq(
      server.conn_request_counts(),
      [3],
      msg="同 host 三请求承载于单连接（ensure_lease 复用）",
    )
  }
}

///|
// P06-US1③（FR-003 行 1/2 保持半边 + R1 第 2 条，T007）：HEAD /a → 303
// follow-up 保持 HEAD（GET/HEAD 不进改写块——permitsRequestBody 门；
// spec 场景 3，round3 D-1 编号对齐）。HEAD 中间响应体恒空（I5 分期窗口）。
async test "P06-US1③ HEAD 303 保持：follow-up 保持 HEAD" {
  @async.with_task_group() <| group => {
    let peer = @fixtures.ScriptedPeer::start()
    peer.mount(Capture)
    let running = group.spawn(() => peer.run(timeout_ms=5000))
    let server = @fixtures.ScriptedServer::start()
    p06_mount_redirect(
      server,
      meth="HEAD",
      path="/a",
      status=303,
      peer_port=peer.port(),
    )
    let s1 = group.spawn(
      () => server.serve_once(timeout_ms=5000),
      allow_failure=true,
    )
    let pool = @client.ConnectionPool::new()
    let client = @client.HttpClient::new(pool)
    let call = p06_call(client, server.port(), "/a", @core.Method::Head, None)
    let resp = call.execute()
    assert_eq(resp.code(), 200, msg="终态响应正确（HEAD 保持跟随）")
    let p1 = resp.prior()
    assert_true(
      p1 is Some(_) && p1.unwrap().code() == 303,
      msg="prior 链长 1 且条目为 303",
    )
    let captured = running.wait()
    captured.assert_matches(
      @fixtures.expect_request_line(meth="HEAD", target="/b"),
      "US1③",
    )
    assert_eq(captured.body, b"", msg="HEAD follow-up 无请求体")
    pool.evict_all()
    server.close()
    peer.close()
    s1.wait() catch {
      _ => ()
    }
  }
}

///|
// P06-US1③续（R1 第 2 条，T007）：GET → 301 同判保持——方法/自定义头
// 原样（保持行不进降级改写；跨 host 剥离仅 T011 的 Authorization/Cookie，
// X-Probe 必须存活）。
async test "P06-US1③续 GET 301 保持：方法与自定义头原样" {
  @async.with_task_group() <| group => {
    let peer = @fixtures.ScriptedPeer::start()
    peer.mount(Capture)
    let running = group.spawn(() => peer.run(timeout_ms=5000))
    let server = @fixtures.ScriptedServer::start()
    p06_mount_redirect(
      server,
      meth="GET",
      path="/a",
      status=301,
      peer_port=peer.port(),
    )
    let s1 = group.spawn(
      () => server.serve_once(timeout_ms=5000),
      allow_failure=true,
    )
    let pool = @client.ConnectionPool::new()
    let client = @client.HttpClient::new(pool)
    let url = @core.HttpUrl::parse("http://127.0.0.1:\{server.port()}/a")
    let b = @core.HeadersVBuilder::new()
    b.add("X-Probe", "keep-me")
    let request = @core.RequestBuilder::new(url)
      .method(@core.Method::Get)
      .headers(b.build())
      .build()
    let call = client.new_call(request)
    let resp = call.execute()
    assert_eq(resp.code(), 200, msg="终态响应正确（GET 保持跟随）")
    let captured = running.wait()
    captured.assert_matches(
      @fixtures.expect_request_line(meth="GET", target="/b"),
      "US1③续",
    )
    let head = captured.head_text()
    assert_true(
      head.contains("X-Probe: keep-me"),
      msg="保持行自定义头原样保留：\{head}",
    )
    assert_eq(captured.body, b"", msg="GET follow-up 无请求体")
    pool.evict_all()
    server.close()
    peer.close()
    s1.wait() catch {
      _ => ()
    }
  }
}

///|
// P06-US2①（FR-003 行 3，T008）：POST + Bytes body → 307 Location：方法
// 与 body 保持重放——对端捕获 follow-up 请求行为 `POST /b`、body 与原始
// payload 逐字节一致（原请求经 serverA 不可捕获，重放证据 = 捕获字节 ==
// 原始常量；R1 第 5 条 one-shot 判定归 T009）。
async test "P06-US2① POST 307 Bytes 重放：方法体保持" {
  @async.with_task_group() <| group => {
    let peer = @fixtures.ScriptedPeer::start()
    peer.mount(Capture)
    let running = group.spawn(() => peer.run(timeout_ms=5000))
    let server = @fixtures.ScriptedServer::start()
    p06_mount_redirect(
      server,
      meth="POST",
      path="/a",
      status=307,
      peer_port=peer.port(),
    )
    let s1 = group.spawn(
      () => server.serve_once(timeout_ms=5000),
      allow_failure=true,
    )
    let pool = @client.ConnectionPool::new()
    let client = @client.HttpClient::new(pool)
    let call = p06_call(
      client,
      server.port(),
      "/a",
      @core.Method::Post,
      Some(@core.RequestBody::bytes(b"replay-payload", 14L)),
    )
    let resp = call.execute()
    assert_eq(
      resp.code(),
      200,
      msg="终态响应正确（307 保持重放至 canned 200）",
    )
    let p1 = resp.prior()
    assert_true(
      p1 is Some(_) && p1.unwrap().code() == 307,
      msg="prior 链长 1 且条目为 307",
    )
    let captured = running.wait()
    captured.assert_matches(
      @fixtures.expect_request_line(meth="POST", target="/b"),
      "US2① follow-up",
    )
    assert_eq(
      captured.body,
      b"replay-payload",
      msg="307 保持：follow-up body 与原始 payload 逐字节一致（FR-003 行 3）",
    )
    pool.evict_all()
    server.close()
    peer.close()
    s1.wait() catch {
      _ => ()
    }
  }
}

///|
// P06-US2③（FR-003 行 3，T008）：308 同判①。
async test "P06-US2③ POST 308 Bytes 重放：方法体保持" {
  @async.with_task_group() <| group => {
    let peer = @fixtures.ScriptedPeer::start()
    peer.mount(Capture)
    let running = group.spawn(() => peer.run(timeout_ms=5000))
    let server = @fixtures.ScriptedServer::start()
    p06_mount_redirect(
      server,
      meth="POST",
      path="/a",
      status=308,
      peer_port=peer.port(),
    )
    let s1 = group.spawn(
      () => server.serve_once(timeout_ms=5000),
      allow_failure=true,
    )
    let pool = @client.ConnectionPool::new()
    let client = @client.HttpClient::new(pool)
    let call = p06_call(
      client,
      server.port(),
      "/a",
      @core.Method::Post,
      Some(@core.RequestBody::bytes(b"replay-308", 10L)),
    )
    let resp = call.execute()
    assert_eq(resp.code(), 200, msg="终态响应正确（308 保持重放）")
    let captured = running.wait()
    captured.assert_matches(
      @fixtures.expect_request_line(meth="POST", target="/b"),
      "US2③ follow-up",
    )
    assert_eq(
      captured.body,
      b"replay-308",
      msg="308 保持：follow-up body 与原始 payload 逐字节一致（FR-003 行 3）",
    )
    pool.evict_all()
    server.close()
    peer.close()
    s1.wait() catch {
      _ => ()
    }
  }
}

///|
// P06-US2②（FR-003 行 3/R1 第 5 条，T009）：POST + Stream body → 307：
// 不跟随——调用方收到该 307 响应本体（code/headers 断言、prior=None）、
// body 可正常消费且连接处置符合 P05 语义（读到底 → Consumed → 回池，
// 同址后续 execute 复用零新建）。对端可见请求数恰 1（serve_once 承载
// 唯一一跳；Stream 场景单跳断言，tasks Phase 4 口径）。
async test "P06-US2② Stream 307 不跟随：原样返回、P05 收尾语义" {
  @async.with_task_group() <| group => {
    let server = @fixtures.ScriptedServer::start()
    server.mount("POST", "/a", {
      status: 307,
      headers: [("Location", "http://127.0.0.1:1/b")],
      framing: Fixed,
      body: Static(b"redirect-body"),
      head_delay_ms: 0,
      close_after_response: false,
    })
    let serving = group.spawn(
      () => server.serve_once(timeout_ms=5000),
      allow_failure=true,
    )
    let pool = @client.ConnectionPool::new()
    let client = @client.HttpClient::new(pool)
    let addr = @client.Address::new(
      scheme="http",
      host="127.0.0.1",
      port=server.port(),
    )
    let url = @core.HttpUrl::parse("http://127.0.0.1:\{server.port()}/a")
    let body = @core.RequestBody::stream(w => w.write(b"stream-payload"))
    let request = @core.RequestBuilder::new(url)
      .method(@core.Method::Post)
      .body(body)
      .build()
    let call = client.new_call(request)
    let resp = call.execute()
    // 不跟随：原 307 响应本体终态返回（prior=None——首轮无挂链）
    assert_eq(
      resp.code(),
      307,
      msg="Stream 不可重放 ⇒ 原样返回该 3xx（R1 第 5 条）",
    )
    assert_eq(
      resp.headers().get("Location"),
      Some("http://127.0.0.1:1/b"),
      msg="响应头完整在场（原响应本体）",
    )
    assert_true(resp.prior() is None, msg="首轮终态 prior=None")
    // 对端仅见一次请求：serve_once 即全部网络动作（无 follow-up 第二跳）
    // body 正常消费 + P05 收尾：读到底 → Consumed → 回池
    assert_eq(
      resp.body().unwrap().text(),
      "redirect-body",
      msg="307 响应体可正常消费",
    )
    // 连接处置 P05 语义：回池复用（同址后续 execute 零新建）
    server.mount("GET", "/a", {
      status: 200,
      headers: [],
      framing: Fixed,
      body: Static(b"ok"),
      head_delay_ms: 0,
      close_after_response: false,
    })
    let next = get_call_to(client, server.port(), "/a")
    let resp2 = next.execute()
    assert_eq(resp2.code(), 200, msg="后续请求照常")
    assert_eq(
      pool.per_host_total(addr),
      1,
      msg="Stream 终态体读毕回池，复用零新建（P05 语义不变）",
    )
    pool.evict_all()
    server.close()
    serving.wait() catch {
      _ => ()
    }
  }
}

///|
// P06-US3①（FR-008 三形态，T010）：Location 相对/绝对/网络路径分别
// resolve 到正确绝对 URL 后跟随。相对形态经三跳链间接捕获（相对引用
// 不跨源，第二跳必落 serverA；链路走通 + 末跳捕获行即分辨率证据——
// R7 夹具口径）；绝对形态同源两跳以终态体 + 单连接计数承载；网络路径
// 形态跨 host 直达捕获对端（请求行断言）。
async test "P06-US3①相对形态 ../b：resolve 正确后跟随" {
  @async.with_task_group() <| group => {
    let peer = @fixtures.ScriptedPeer::start()
    peer.mount(Capture)
    let running = group.spawn(() => peer.run(timeout_ms=5000))
    let server = @fixtures.ScriptedServer::start()
    // /x/y --301 ../b--> /b --302 绝对指向对端--> peer /b
    server.mount("GET", "/x/y", {
      status: 301,
      headers: [("Location", "../b")],
      framing: Fixed,
      body: Static(b""),
      head_delay_ms: 0,
      close_after_response: false,
    })
    server.mount("GET", "/b", {
      status: 302,
      headers: [("Location", "http://127.0.0.1:\{peer.port()}/b")],
      framing: Fixed,
      body: Static(b""),
      head_delay_ms: 0,
      close_after_response: false,
    })
    let serving = group.spawn(
      () => server.serve_n(1, timeout_ms=5000),
      allow_failure=true,
    )
    let pool = @client.ConnectionPool::new()
    let client = @client.HttpClient::new(pool)
    let call = get_call_to(client, server.port(), "/x/y")
    let resp = call.execute()
    assert_eq(
      resp.code(),
      200,
      msg="相对形态链路走通（../b 解析正确）",
    )
    let p1 = resp.prior()
    assert_true(
      p1 is Some(_) && p1.unwrap().code() == 302,
      msg="第 2 级 prior 为 302",
    )
    let p2 = p1.unwrap().prior()
    assert_true(
      p2 is Some(_) && p2.unwrap().code() == 301,
      msg="第 1 级 prior 为 301（相对形态跳进）",
    )
    let captured = running.wait()
    captured.assert_matches(
      @fixtures.expect_request_line(meth="GET", target="/b"),
      "US3①相对末跳",
    )
    pool.evict_all()
    server.close()
    peer.close()
    serving.wait() catch {
      _ => ()
    }
    assert_eq(
      server.conn_request_counts(),
      [2],
      msg="相对形态两跳同连接承载（末跳跨 host 至捕获对端）",
    )
  }
}

///|
async test "P06-US3①绝对形态 /b：同源两跳跟随" {
  @async.with_task_group() <| group => {
    let server = @fixtures.ScriptedServer::start()
    server.mount("GET", "/a", {
      status: 301,
      headers: [("Location", "/b")],
      framing: Fixed,
      body: Static(b""),
      head_delay_ms: 0,
      close_after_response: false,
    })
    server.mount("GET", "/b", {
      status: 200,
      headers: [],
      framing: Fixed,
      body: Static(b"abs-final"),
      head_delay_ms: 0,
      close_after_response: false,
    })
    let serving = group.spawn(
      () => server.serve_n(1, timeout_ms=5000),
      allow_failure=true,
    )
    let pool = @client.ConnectionPool::new()
    let client = @client.HttpClient::new(pool)
    let call = get_call_to(client, server.port(), "/a")
    let resp = call.execute()
    assert_eq(resp.code(), 200, msg="绝对形态跟随终态 200")
    assert_eq(
      resp.body().unwrap().text(),
      "abs-final",
      msg="绝对形态终态体",
    )
    pool.evict_all()
    server.close()
    serving.wait()
    assert_eq(server.conn_request_counts(), [2], msg="两跳单连接")
  }
}

///|
async test "P06-US3①网络路径形态 //host:x/b：跨 host 捕获" {
  @async.with_task_group() <| group => {
    let peer = @fixtures.ScriptedPeer::start()
    peer.mount(Capture)
    let running = group.spawn(() => peer.run(timeout_ms=5000))
    let server = @fixtures.ScriptedServer::start()
    server.mount("GET", "/a", {
      status: 301,
      headers: [("Location", "//127.0.0.1:\{peer.port()}/b")],
      framing: Fixed,
      body: Static(b""),
      head_delay_ms: 0,
      close_after_response: false,
    })
    let serving = group.spawn(
      () => server.serve_once(timeout_ms=5000),
      allow_failure=true,
    )
    let pool = @client.ConnectionPool::new()
    let client = @client.HttpClient::new(pool)
    let call = get_call_to(client, server.port(), "/a")
    let resp = call.execute()
    assert_eq(resp.code(), 200, msg="网络路径形态跟随终态 200")
    let captured = running.wait()
    captured.assert_matches(
      @fixtures.expect_request_line(meth="GET", target="/b"),
      "US3①网络路径",
    )
    pool.evict_all()
    server.close()
    peer.close()
    serving.wait() catch {
      _ => ()
    }
  }
}

///|
// P06-US3②（FR-008 回退半边，T010）：无 Location 头、非法 Location
// （resolve raise 形态）→ 原 3xx 终态返回且零 follow-up 请求。
async test "P06-US3②缺失与非法 Location：原 3xx 终态、零 follow-up" {
  @async.with_task_group() <| group => {
    let server = @fixtures.ScriptedServer::start()
    server.mount("GET", "/noloc", {
      status: 301,
      headers: [],
      framing: Fixed,
      body: Static(b"no-location"),
      head_delay_ms: 0,
      close_after_response: false,
    })
    server.mount("GET", "/badloc", {
      status: 302,
      headers: [("Location", "http://")],
      framing: Fixed,
      body: Static(b"bad-location"),
      head_delay_ms: 0,
      close_after_response: false,
    })
    let serving = group.spawn(
      () => server.serve_n(1, timeout_ms=5000),
      allow_failure=true,
    )
    let pool = @client.ConnectionPool::new()
    let client = @client.HttpClient::new(pool)
    let addr = @client.Address::new(
      scheme="http",
      host="127.0.0.1",
      port=server.port(),
    )
    let call1 = get_call_to(client, server.port(), "/noloc")
    let resp1 = call1.execute()
    assert_eq(
      resp1.code(),
      301,
      msg="无 Location ⇒ 原 301 终态（FR-008）",
    )
    assert_eq(resp1.body().unwrap().text(), "no-location")
    assert_true(resp1.prior() is None, msg="无跟随无挂链")
    let call2 = get_call_to(client, server.port(), "/badloc")
    let resp2 = call2.execute()
    assert_eq(
      resp2.code(),
      302,
      msg="非法 Location ⇒ 原 302 终态（resolve 回退）",
    )
    assert_eq(resp2.body().unwrap().text(), "bad-location")
    assert_true(resp2.prior() is None, msg="无跟随无挂链")
    // 零 follow-up：两请求均单轮（accepted 恰 1 连接、池新建恰 1）
    assert_eq(
      pool.per_host_total(addr),
      1,
      msg="零 follow-up——无新建连接",
    )
    pool.evict_all()
    server.close()
    serving.wait()
    assert_eq(server.accepted_total(), 1, msg="夹具侧恰 1 连接")
    assert_eq(server.conn_request_counts(), [2], msg="两终态请求单连接")
  }
}

///|
// P06-US4①（FR-004/SC-004，T011）：跨 host 剥头——带 Authorization
// （大写变体注入，钉 remove 大小写不敏感性——research 附加核实第 3 条）
// 与 Cookie 的 POST → 301 跨 host：捕获 follow-up 字节不含这两头。
async test "P06-US4① 跨 host 301：剥 Authorization（含大小写变体）与 Cookie" {
  @async.with_task_group() <| group => {
    let peer = @fixtures.ScriptedPeer::start()
    peer.mount(Capture)
    let running = group.spawn(() => peer.run(timeout_ms=5000))
    let server = @fixtures.ScriptedServer::start()
    p06_mount_redirect(
      server,
      meth="POST",
      path="/a",
      status=301,
      peer_port=peer.port(),
    )
    let s1 = group.spawn(
      () => server.serve_once(timeout_ms=5000),
      allow_failure=true,
    )
    let pool = @client.ConnectionPool::new()
    let client = @client.HttpClient::new(pool)
    let url = @core.HttpUrl::parse("http://127.0.0.1:\{server.port()}/a")
    let b = @core.HeadersVBuilder::new()
    b.add("AUTHORIZATION", "Bearer x") // 大小写变体：remove 不敏感性钉死
    b.add("Cookie", "a=1")
    let request = @core.RequestBuilder::new(url)
      .method(@core.Method::Post)
      .headers(b.build())
      .body(@core.RequestBody::bytes(b"cred-payload", 12L))
      .build()
    let call = client.new_call(request)
    let resp = call.execute()
    assert_eq(resp.code(), 200, msg="终态响应正确（跨 host 跟随）")
    let captured = running.wait()
    captured.assert_matches(
      @fixtures.expect_request_line(meth="GET", target="/b"),
      "US4① follow-up",
    )
    let head = captured.head_text().to_lower()
    assert_false(
      head.contains("authorization"),
      msg="跨 host 剥 Authorization（FR-004，大小写变体不豁免）：\{captured.head_text()}",
    )
    assert_false(
      head.contains("cookie"),
      msg="跨 host 剥 Cookie（FR-004 C1 有意差异）：\{captured.head_text()}",
    )
    pool.evict_all()
    server.close()
    peer.close()
    s1.wait() catch {
      _ => ()
    }
  }
}

///|
// P06-US4②（FR-004 保留半边，T011）：同 host 301 两头完整保留。同 host
// 第二跳落 serverA（ScriptedServer 无请求头观测面——R7 夹具口径），保留
// 半边的字节级/单元级断言由白盒 rewrite_headers 直驱承载
// （follow_up_wbtest P06-WB④b），本黑盒以「保留链路端到端走通 + X-Probe
// 同 host 存活（US1③续在场）」补面。
async test "P06-US4② 同 host 301：凭证头保留链路走通" {
  @async.with_task_group() <| group => {
    let server = @fixtures.ScriptedServer::start()
    server.mount("POST", "/cred", {
      status: 301,
      headers: [("Location", "/cred-dst")],
      framing: Fixed,
      body: Static(b""),
      head_delay_ms: 0,
      close_after_response: false,
    })
    server.mount("GET", "/cred-dst", {
      status: 200,
      headers: [],
      framing: Fixed,
      body: Static(b"cred-kept"),
      head_delay_ms: 0,
      close_after_response: false,
    })
    let serving = group.spawn(
      () => server.serve_n(1, timeout_ms=5000),
      allow_failure=true,
    )
    let pool = @client.ConnectionPool::new()
    let client = @client.HttpClient::new(pool)
    let url = @core.HttpUrl::parse("http://127.0.0.1:\{server.port()}/cred")
    let b = @core.HeadersVBuilder::new()
    b.add("Authorization", "Bearer x")
    b.add("Cookie", "a=1")
    let request = @core.RequestBuilder::new(url)
      .method(@core.Method::Post)
      .headers(b.build())
      .body(@core.RequestBody::bytes(b"cred-body", 9L))
      .build()
    let call = client.new_call(request)
    let resp = call.execute()
    assert_eq(resp.code(), 200, msg="同 host 跟随链路走通")
    assert_eq(resp.body().unwrap().text(), "cred-kept")
    pool.evict_all()
    server.close()
    serving.wait()
    assert_eq(server.conn_request_counts(), [2], msg="同 host 两跳单连接")
  }
}

///|
// P06-US4②续（SC-004 保留半边证据闭合，T019；review 修复批 M7 措辞订正）：
// 同 host 301 两跳中，follow-up 请求头经 ScriptedServer 的请求头观测面
// captured_request_heads() 做「请求行+头表」级断言——原请求与 follow-up
// 均完整携带 Authorization/Cookie。观测面实况：捕获点在 read_request()
// 之后按解析后头表重建（无版本行、重复头以 "," 合并、无体）——「原始
// 字节级」半边由跨 host 的 ScriptedPeer CapturedRequest 承载（spec
// SC-004 分层口径，2026-10-28 订正）。归因：converge F1（severity HIGH）
// ——既有证据面只有跨 host 剥头半边的字节级黑盒（P06-US4①，Capture
// 比对捕获头文本）与同 host 保留半边的白盒纯函数断言（follow_up_wbtest
// P06-WB④b rewrite_headers 直驱）；owner 裁决①（2026-10-28）按 tasks
// Path Conventions「先红后绿最小扩展并逐处归因」给 P03 夹具补一字段一
// 捕获一访问器的观测面（例外登记见 contracts/follow-up-api.md §3）。
// 红证据（2026-10-28 首跑，moon test -p hahh9527/moonhttp/client
// --target native --deny-warn，编译期，call_test.mbt:2085）：
//   Error: [4015] Type
//   @hahh9527/moonhttp/internal/fixtures.ScriptedServer has no method
//   captured_request_heads（访问器缺失＝红，未动夹具先取证）。
async test "P06-US4②续 同 host 301：follow-up 凭证头保留（请求行+头表级观测面，SC-004 保留半边闭合，T019）" {
  @async.with_task_group() <| group => {
    let server = @fixtures.ScriptedServer::start()
    server.mount("POST", "/cred", {
      status: 301,
      headers: [("Location", "/cred-dst")],
      framing: Fixed,
      body: Static(b""),
      head_delay_ms: 0,
      close_after_response: false,
    })
    server.mount("GET", "/cred-dst", {
      status: 200,
      headers: [],
      framing: Fixed,
      body: Static(b"cred-kept"),
      head_delay_ms: 0,
      close_after_response: false,
    })
    let serving = group.spawn(
      () => server.serve_n(1, timeout_ms=5000),
      allow_failure=true,
    )
    let pool = @client.ConnectionPool::new()
    let client = @client.HttpClient::new(pool)
    let url = @core.HttpUrl::parse("http://127.0.0.1:\{server.port()}/cred")
    let b = @core.HeadersVBuilder::new()
    b.add("Authorization", "Bearer x")
    b.add("Cookie", "a=1")
    let request = @core.RequestBuilder::new(url)
      .method(@core.Method::Post)
      .headers(b.build())
      .body(@core.RequestBody::bytes(b"cred-body", 9L))
      .build()
    let call = client.new_call(request)
    let resp = call.execute()
    assert_eq(resp.code(), 200, msg="同 host 跟随链路走通")
    assert_eq(resp.body().unwrap().text(), "cred-kept")
    pool.evict_all()
    server.close()
    serving.wait()
    // 头表级观测（review 修复批 M7：解析后头表重建，非原始字节——真
    // 字节半边归跨 host CapturedRequest）：先证观测面自见凭证头（否则
    // 保留断言无意义），再证 follow-up 同样完整保留（SC-004 保留半边）。
    let heads = server.captured_request_heads()
    assert_true(
      heads.length() >= 2,
      msg="两跳请求均被捕获，实得 \{heads.length()} 条",
    )
    let original = heads[0].to_lower()
    assert_true(
      original.contains("authorization: bearer x"),
      msg="夹具可见原请求 Authorization（观测面自证）：\{heads[0]}",
    )
    assert_true(
      original.contains("cookie: a=1"),
      msg="夹具可见原请求 Cookie（观测面自证）：\{heads[0]}",
    )
    let follow_up = heads[1]
    assert_true(
      follow_up.has_prefix("GET /cred-dst"),
      msg="第 2 条应为 follow-up 请求行：\{follow_up}",
    )
    assert_true(
      follow_up.to_lower().contains("authorization: bearer x"),
      msg="SC-004 保留半边：follow-up 保留 Authorization：\{follow_up}",
    )
    assert_true(
      follow_up.to_lower().contains("cookie: a=1"),
      msg="SC-004 保留半边：follow-up 保留 Cookie：\{follow_up}",
    )
    assert_eq(server.conn_request_counts(), [2], msg="同 host 两跳单连接")
  }
}

///|
// P06-US6①（FR-002/FR-007/SC-003/SC-006，T012）：3 跳同 host 链（每跳
// 1KB body）——夹具侧新建连接数恰 1、终态响应体读完后同池连接的第 4 个
// 请求读到干净流（无上一跳残帧）。
async test "P06-US6① 3 跳同 host 带体链：连接数 1、第 4 请求干净流" {
  @async.with_task_group() <| group => {
    let server = @fixtures.ScriptedServer::start()
    let kbA = Bytes::from_iter(Array::make(1024, b'a').iter())
    let kbB = Bytes::from_iter(Array::make(1024, b'b').iter())
    let kbC = Bytes::from_iter(Array::make(1024, b'c').iter())
    server.mount("GET", "/h1", {
      status: 301,
      headers: [("Location", "/h2")],
      framing: Fixed,
      body: Static(kbA),
      head_delay_ms: 0,
      close_after_response: false,
    })
    server.mount("GET", "/h2", {
      status: 302,
      headers: [("Location", "/h3")],
      framing: Fixed,
      body: Static(kbB),
      head_delay_ms: 0,
      close_after_response: false,
    })
    server.mount("GET", "/h3", {
      status: 200,
      headers: [],
      framing: Fixed,
      body: Static(kbC),
      head_delay_ms: 0,
      close_after_response: false,
    })
    let serving = group.spawn(
      () => server.serve_n(1, timeout_ms=8000),
      allow_failure=true,
    )
    let pool = @client.ConnectionPool::new()
    let client = @client.HttpClient::new(pool)
    let addr = @client.Address::new(
      scheme="http",
      host="127.0.0.1",
      port=server.port(),
    )
    let call = get_call_to(client, server.port(), "/h1")
    let resp = call.execute()
    assert_eq(resp.code(), 200, msg="3 跳链终态 200")
    assert_eq(
      resp.body().unwrap().bytes(),
      kbC,
      msg="终态体干净（无中间跳残帧——SC-006）",
    )
    // 终态后同池连接的第 4 个请求：干净流 + 零新建（SC-003 同 host 保持）
    let fourth = get_call_to(client, server.port(), "/h3")
    let resp4 = fourth.execute()
    assert_eq(
      resp4.body().unwrap().bytes(),
      kbC,
      msg="第 4 请求读到干净流",
    )
    assert_eq(
      pool.per_host_total(addr),
      1,
      msg="同 host 全程零新建（US-6-1/SC-003）",
    )
    pool.evict_all()
    server.close()
    serving.wait()
    assert_eq(
      server.accepted_total(),
      1,
      msg="夹具侧新建连接数恰 1（US-6-1）",
    )
    assert_eq(
      server.conn_request_counts(),
      [4],
      msg="单连接承载全部 4 个请求（keep-alive + 排干正确）",
    )
  }
}

///|
// P06-US6 补②（FR-002 失败半边，round3 补；T012）：中间响应体截断
// （mount_truncated）→ skip_response_body 失败 → 毒化 → 错误透传
// （err 判别、非 panic/非静默）且连接不回池（后续同 Address 租借新建
// +1）。注：夹具 Truncated 恒派生 Connection: close——close-token 毒化
// 与排干失败毒化在本场景叠加，可观测结论（不回池 + 透传）一致。
async test "P06-US6 补② 中间体截断：排干失败毒化 + 错误透传 + 不回池" {
  @async.with_task_group() <| group => {
    let server = @fixtures.ScriptedServer::start()
    server.mount_truncated("GET", "/cut30x", {
      status: 301,
      headers: [("Location", "/never-reached")],
      framing: Fixed,
      body: Static(b"abcdef"),
      head_delay_ms: 0,
      close_after_response: false,
    })
    let s1 = group.spawn(
      () => server.serve_once(timeout_ms=5000),
      allow_failure=true,
    )
    let pool = @client.ConnectionPool::new()
    let client = @client.HttpClient::new(pool)
    let addr = @client.Address::new(
      scheme="http",
      host="127.0.0.1",
      port=server.port(),
    )
    let call = get_call_to(client, server.port(), "/cut30x")
    let failed = try {
      let _ = call.execute()
      false
    } catch {
      err => !(err is @client.CallCancelled)
    }
    assert_true(
      failed,
      msg="排干失败必须错误透传（FR-002 毒化半边，非静默非 panic）",
    )
    assert_eq(
      pool.per_host_total(addr),
      1,
      msg="毒化路径不新建（计数守恒）",
    )
    // 连接不回池：后续同 Address 租借必须新建 +1
    server.mount("GET", "/after", {
      status: 200,
      headers: [],
      framing: Fixed,
      body: Static(b"after-poison"),
      head_delay_ms: 0,
      close_after_response: false,
    })
    let s2 = group.spawn(
      () => server.serve_once(timeout_ms=5000),
      allow_failure=true,
    )
    let next = get_call_to(client, server.port(), "/after")
    let resp2 = next.execute()
    assert_eq(resp2.body().unwrap().text(), "after-poison")
    assert_eq(
      pool.per_host_total(addr),
      2,
      msg="毒化不回池 ⇒ 后续租借新建 +1（FR-002）",
    )
    pool.evict_all()
    server.close()
    s1.wait() catch {
      _ => ()
    }
    s2.wait() catch {
      _ => ()
    }
    assert_eq(server.accepted_total(), 2, msg="夹具侧恰 2 连接")
  }
}

///|
// P06-US6 补③（FR-002 毒化判别单点化，review 修复批 M3；contracts §3
// derive_close~ 登记例外）：中间体截断但**不派生 Connection: close**——
// 剥离 close-token 混淆后，「不回池 + 错误透传」只能由排干失败毒化路径
// 达成（补② 的 Truncated 恒派生 close，close-token 毒化与排干失败毒化
// 叠加，无法单点归因）。错误断言收窄：排除 client 包错误族
// （CallCancelled/CallStateError/TooManyFollowUps）——透传的必须是
// 网络/IO 族错误，非控制流错误。
async test "P06-US6 补③ 中间体截断无 close 派生：排干失败毒化单点判别" {
  @async.with_task_group() <| group => {
    let server = @fixtures.ScriptedServer::start()
    server.mount_truncated(
      "GET",
      "/cut302",
      {
        status: 302,
        headers: [("Location", "/never-reached")],
        framing: Fixed,
        body: Static(b"abcdef"),
        head_delay_ms: 0,
        close_after_response: false,
      },
      derive_close=false,
    )
    let s1 = group.spawn(
      () => server.serve_once(timeout_ms=5000),
      allow_failure=true,
    )
    let pool = @client.ConnectionPool::new()
    let client = @client.HttpClient::new(pool)
    let addr = @client.Address::new(
      scheme="http",
      host="127.0.0.1",
      port=server.port(),
    )
    let call = get_call_to(client, server.port(), "/cut302")
    let failed = try {
      let _ = call.execute()
      false
    } catch {
      // 收窄判别：非取消、非状态机、非上限——排干失败的 IO 族错误透传
      err =>
        !(err is @client.CallCancelled) &&
        !(err is @client.CallStateError) &&
        !(err is @client.TooManyFollowUps)
    }
    assert_true(
      failed,
      msg="排干失败必须以 IO 族错误透传（FR-002 毒化半边单点判别）",
    )
    assert_eq(
      pool.per_host_total(addr),
      1,
      msg="毒化路径不新建（计数守恒）",
    )
    // 连接不回池：无 close-token ⇒ 不回池只能来自排干失败毒化——后续
    // 同 Address 租借必须新建 +1
    server.mount("GET", "/after", {
      status: 200,
      headers: [],
      framing: Fixed,
      body: Static(b"after-poison"),
      head_delay_ms: 0,
      close_after_response: false,
    })
    let s2 = group.spawn(
      () => server.serve_once(timeout_ms=5000),
      allow_failure=true,
    )
    let next = get_call_to(client, server.port(), "/after")
    let resp2 = next.execute()
    assert_eq(resp2.body().unwrap().text(), "after-poison")
    assert_eq(
      pool.per_host_total(addr),
      2,
      msg="无 close 派生下仍不回池 ⇒ 排干失败毒化单点归因（FR-002）",
    )
    pool.evict_all()
    server.close()
    s1.wait() catch {
      _ => ()
    }
    s2.wait() catch {
      _ => ()
    }
    assert_eq(server.accepted_total(), 2, msg="夹具侧恰 2 连接")
  }
}

///|
// P06-US3④（FR-008/Location 保真端到端，review 修复批 H1）：302 的
// Location 值含逗号（"," 是 query 合法子分隔符）——follow-up 必须请求
// 完整目标 /b?ids=1,2。修复前 from_http 把头值按 "," 拆回多条、
// HeadersV::get 取首条，实际请求 /b?ids=1（错误资源）。捕获对端以原始
// 请求行钉死（真字节判别面）。
async test "P06-US3④ Location 含逗号：follow-up 请求完整目标（H1 端到端）" {
  @async.with_task_group() <| group => {
    let peer = @fixtures.ScriptedPeer::start()
    peer.mount(Capture)
    let running = group.spawn(() => peer.run(timeout_ms=5000))
    let server = @fixtures.ScriptedServer::start()
    server.mount("GET", "/a", {
      status: 302,
      headers: [("Location", "http://127.0.0.1:\{peer.port()}/b?ids=1,2")],
      framing: Fixed,
      body: Static(b""),
      head_delay_ms: 0,
      close_after_response: false,
    })
    let s1 = group.spawn(
      () => server.serve_once(timeout_ms=5000),
      allow_failure=true,
    )
    let pool = @client.ConnectionPool::new()
    let client = @client.HttpClient::new(pool)
    let call = get_call_to(client, server.port(), "/a")
    let resp = call.execute()
    assert_eq(
      resp.code(),
      200,
      msg="终态响应正确（跟随至捕获对端）",
    )
    assert_true(
      resp.prior() is Some(_),
      msg="单跳跟随 prior 链长 1（FR-006）",
    )
    let captured = running.wait()
    captured.assert_matches(
      @fixtures.expect_request_line(meth="GET", target="/b?ids=1,2"),
      "US3④",
    )
    pool.evict_all()
    server.close()
    peer.close()
    s1.wait() catch {
      _ => ()
    }
  }
}

///|
// P06-US6②（FR-007/W1 方案 B/SC-003，T013）：跨 host 跳——旧 host 连接
// 干净回池（后续同 Address 租借可复用、accepted 不增）、新 host 新建
// 连接 +1（双实例计数）。
async test "P06-US6② 跨 host 换租：旧连接干净回池可复用、新 host 新建 +1" {
  @async.with_task_group() <| group => {
    let peer = @fixtures.ScriptedPeer::start()
    peer.mount(Capture)
    let running = group.spawn(() => peer.run(timeout_ms=5000))
    let server = @fixtures.ScriptedServer::start()
    p06_mount_redirect(
      server,
      meth="GET",
      path="/away",
      status=301,
      peer_port=peer.port(),
    )
    let s1 = group.spawn(
      () => server.serve_once(timeout_ms=5000),
      allow_failure=true,
    )
    let pool = @client.ConnectionPool::new()
    let client = @client.HttpClient::new(pool)
    let addrA = @client.Address::new(
      scheme="http",
      host="127.0.0.1",
      port=server.port(),
    )
    let call = get_call_to(client, server.port(), "/away")
    let resp = call.execute()
    assert_eq(
      resp.code(),
      200,
      msg="跨 host 跟随终态 200（peer canned）",
    )
    let _ = resp.body().unwrap().bytes() // 消费终态体 → peer 租约处置
    // 新 host 新建连接 +1（peer 实例）
    assert_eq(
      pool.per_host_total(
        @client.Address::new(scheme="http", host="127.0.0.1", port=peer.port()),
      ),
      1,
      msg="新 host 新建连接 +1（SC-003）",
    )
    // 旧 host 干净回池：同址后续租借复用（accepted 不增——W1 方案 B）。
    // 复用请求由 s1 的连接服务循环承载（conn A 回池后 LIFO pop，无新建
    // accept——s2 形态的 serve_once 等待新连接永不满足，且关闭监听句柄
    // 时 parked accept 在 Windows 上有唤醒缺口，故不设第二 serve_once）。
    server.mount("GET", "/reuse", {
      status: 200,
      headers: [],
      framing: Fixed,
      body: Static(b"reused"),
      head_delay_ms: 0,
      close_after_response: false,
    })
    let back = get_call_to(client, server.port(), "/reuse")
    let resp2 = back.execute()
    assert_eq(
      resp2.body().unwrap().text(),
      "reused",
      msg="旧 host 复用照常",
    )
    assert_eq(
      pool.per_host_total(addrA),
      1,
      msg="旧 host 零新建——干净回池可复用（W1 方案 B/SC-003）",
    )
    pool.evict_all()
    server.close()
    peer.close()
    s1.wait() catch {
      _ => ()
    }
    assert_eq(
      server.accepted_total(),
      1,
      msg="夹具侧旧 host 恰 1 连接（复用）",
    )
    let _ = running.wait()
  }
}

///|
// P06-US6 补①（FR-009/INV-7，T013）：中间响应 Connection: close（同
// host 变体，强红形态）——该连接关闭不回池、follow-up 走新连接：
// accepted_total==2、每连接各 1 请求。
async test "P06-US6 补① 中间 close：旧连接关闭不回池、follow-up 新连接" {
  @async.with_task_group() <| group => {
    let server = @fixtures.ScriptedServer::start()
    server.mount("GET", "/c1", {
      status: 301,
      headers: [("Connection", "close"), ("Location", "/c2")],
      framing: Fixed,
      body: Static(b""),
      head_delay_ms: 0,
      close_after_response: false,
    })
    server.mount("GET", "/c2", {
      status: 200,
      headers: [],
      framing: Fixed,
      body: Static(b"after-close"),
      head_delay_ms: 0,
      close_after_response: false,
    })
    let serving = group.spawn(
      () => server.serve_n(2, timeout_ms=8000),
      allow_failure=true,
    )
    let pool = @client.ConnectionPool::new()
    let client = @client.HttpClient::new(pool)
    let call = get_call_to(client, server.port(), "/c1")
    let resp = call.execute()
    assert_eq(
      resp.code(),
      200,
      msg="中间 close 后 follow-up 走新连接完成",
    )
    assert_eq(resp.body().unwrap().text(), "after-close")
    assert_eq(
      pool.per_host_total(
        @client.Address::new(
          scheme="http",
          host="127.0.0.1",
          port=server.port(),
        ),
      ),
      2,
      msg="close 连接不回池 ⇒ follow-up 新建 +1（FR-009）",
    )
    pool.evict_all()
    server.close()
    serving.wait()
    assert_eq(
      server.accepted_total(),
      2,
      msg="夹具侧恰 2 连接（FR-009）",
    )
    assert_eq(
      server.conn_request_counts(),
      [1, 1],
      msg="close 连接不再承载后续请求（INV-7）",
    )
  }
}

///|
// P06-US5①（FR-005/SC-002，T014）：21 跳链与 A→B→A 循环链均以
// `err is TooManyFollowUps` 终止（非 panic/非静默终态）；超限 raise 后
// 连接干净回池（非关闭）——探针请求（独立 plain-200 mount）复用池内
// 连接：accepted_total 不增、conn_request_counts 同连接计数 +1
// （round3 D-2；Sequence 末位驻留语义——末位 200 供红阶段快速失败）。
async test "P06-US5① 21 跳链：TooManyFollowUps + 干净回池" {
  @async.with_task_group() <| group => {
    let server = @fixtures.ScriptedServer::start()
    let redirects : Array[@fixtures.ResponseScript] = []
    for _i in 0..<21 {
      redirects.push({
        status: 301,
        headers: [("Location", "/loop")],
        framing: Fixed,
        body: Static(b""),
        head_delay_ms: 0,
        close_after_response: false,
      })
    }
    // 末位驻留 200：无上限实现时循环于第 22 请求静默终态（红：非 err）
    redirects.push({
      status: 200,
      headers: [],
      framing: Fixed,
      body: Static(b"done"),
      head_delay_ms: 0,
      close_after_response: false,
    })
    server.mount_sequence("GET", "/loop", redirects)
    server.mount("GET", "/probe", {
      status: 200,
      headers: [],
      framing: Fixed,
      body: Static(b"probe-ok"),
      head_delay_ms: 0,
      close_after_response: false,
    })
    let serving = group.spawn(
      () => server.serve_n(1, timeout_ms=8000),
      allow_failure=true,
    )
    let pool = @client.ConnectionPool::new()
    let client = @client.HttpClient::new(pool)
    let addr = @client.Address::new(
      scheme="http",
      host="127.0.0.1",
      port=server.port(),
    )
    let call = get_call_to(client, server.port(), "/loop")
    let raised = try {
      let _ = call.execute()
      false
    } catch {
      err => err is @client.TooManyFollowUps
    }
    assert_true(
      raised,
      msg="21 跳链必须 raise TooManyFollowUps（SC-002，非 panic/非静默）",
    )
    // 干净回池：探针复用同一连接（accepted 不增、同连接计数 +1）
    let probe = get_call_to(client, server.port(), "/probe")
    let probed = probe.execute()
    assert_eq(probed.body().unwrap().text(), "probe-ok")
    assert_eq(
      pool.per_host_total(addr),
      1,
      msg="raise 后零新建（干净回池）",
    )
    pool.evict_all()
    server.close()
    serving.wait() catch {
      _ => ()
    }
    assert_eq(
      server.accepted_total(),
      1,
      msg="夹具侧恰 1 连接（非关闭）",
    )
    assert_eq(
      server.conn_request_counts(),
      [22],
      msg="21 请求（1+20 follow-up）+ 探针 = 22，单连接承载（INV-4/R1 第 8 条）",
    )
  }
}

///|
async test "P06-US5①续 A→B→A 循环链：TooManyFollowUps" {
  @async.with_task_group() <| group => {
    let server = @fixtures.ScriptedServer::start()
    server.mount("GET", "/a", {
      status: 301,
      headers: [("Location", "/b")],
      framing: Fixed,
      body: Static(b""),
      head_delay_ms: 0,
      close_after_response: false,
    })
    server.mount("GET", "/b", {
      status: 301,
      headers: [("Location", "/a")],
      framing: Fixed,
      body: Static(b""),
      head_delay_ms: 0,
      close_after_response: false,
    })
    let serving = group.spawn(
      () => server.serve_n(1, timeout_ms=8000),
      allow_failure=true,
    )
    let pool = @client.ConnectionPool::new()
    let client = @client.HttpClient::new(pool)
    let call = get_call_to(client, server.port(), "/a")
    let raised = try {
      let _ = call.execute()
      false
    } catch {
      err => err is @client.TooManyFollowUps
    }
    assert_true(
      raised,
      msg="A→B→A 循环链必须 raise TooManyFollowUps（SC-002）",
    )
    pool.evict_all()
    server.close()
    serving.wait() catch {
      _ => ()
    }
    assert_eq(
      server.conn_request_counts(),
      [21],
      msg="循环链恰 21 请求后受控终止",
    )
  }
}

///|
// P06-US5②③（FR-003 行 4 + 300 无 Location 闭环，T015）：304/305/306
// 各自原样返回（终态透传，连接处置符合 P05 语义——读毕回池复用零新
// 建）；300 无 Location 原样返回（US-3② 已钉缺失/非法回退，本任务固化
// 300 语义——C2/300 修正闭环）。
// 【I2 纪律注记落笔】首跑颜色实测＝绿（T002 Terminal 行实现先行），
// 本任务为黑盒固化面，登记「实现先行」归因备宪法 IV 审计。
async test "P06-US5②③ 不跟随集合：304/305/306/300无Location 终态透传" {
  @async.with_task_group() <| group => {
    let server = @fixtures.ScriptedServer::start()
    // 【判别面（review 修复批 Low）】304/305/306 挂载均带 Location——
    // 若跟随集放宽为范围判定误纳三码（T016 红测同源缺陷），会跟随
    // /unused-dst ⇒ 404/计数断言红；精确码集下 Location 在场也必终态。
    // 304 MUST 无体（上游 should_not_have_body 集）——夹具挂空体
    server.mount("GET", "/r304", {
      status: 304,
      headers: [("Location", "/unused-dst")],
      framing: Fixed,
      body: Static(b""),
      head_delay_ms: 0,
      close_after_response: false,
    })
    server.mount("GET", "/r305", {
      status: 305,
      headers: [("Location", "/unused-dst")],
      framing: Fixed,
      body: Static(b"use-proxy"),
      head_delay_ms: 0,
      close_after_response: false,
    })
    server.mount("GET", "/r306", {
      status: 306,
      headers: [("Location", "/unused-dst")],
      framing: Fixed,
      body: Static(b"unused"),
      head_delay_ms: 0,
      close_after_response: false,
    })
    server.mount("GET", "/r300nl", {
      status: 300,
      headers: [],
      framing: Fixed,
      body: Static(b"multiple-choices-no-location"),
      head_delay_ms: 0,
      close_after_response: false,
    })
    let serving = group.spawn(
      () => server.serve_n(1, timeout_ms=5000),
      allow_failure=true,
    )
    let pool = @client.ConnectionPool::new()
    let client = @client.HttpClient::new(pool)
    let addr = @client.Address::new(
      scheme="http",
      host="127.0.0.1",
      port=server.port(),
    )
    let r304 = get_call_to(client, server.port(), "/r304").execute()
    assert_eq(
      r304.code(),
      304,
      msg="304 终态透传（M1 无缓存层，D7）",
    )
    assert_true(r304.prior() is None, msg="304 无挂链")
    // 304 体恒空（上游 should_not_have_body 集）——读毕触发 Consumed 回池，
    // 供后续同址请求复用单连接
    let _ = r304.body().unwrap().bytes()
    let r305 = get_call_to(client, server.port(), "/r305").execute()
    assert_eq(
      r305.code(),
      305,
      msg="305 终态透传（带 Location 亦不跟随）",
    )
    assert_eq(r305.body().unwrap().text(), "use-proxy")
    let r306 = get_call_to(client, server.port(), "/r306").execute()
    assert_eq(
      r306.code(),
      306,
      msg="306 终态透传（带 Location 亦不跟随）",
    )
    let _ = r306.body().unwrap().bytes()
    let r300 = get_call_to(client, server.port(), "/r300nl").execute()
    assert_eq(
      r300.code(),
      300,
      msg="300 无 Location 终态（C2/300 闭环）",
    )
    assert_eq(r300.body().unwrap().text(), "multiple-choices-no-location")
    assert_true(r300.prior() is None, msg="300 无 Location 无挂链")
    // 连接处置 P05 语义：四请求单连接零新建
    assert_eq(
      pool.per_host_total(addr),
      1,
      msg="不跟随集合全程零新建（读毕回池复用）",
    )
    pool.evict_all()
    server.close()
    serving.wait()
    assert_eq(server.conn_request_counts(), [4], msg="单连接承载 4 请求")
  }
}

///|
// P05-US1⑦（FR-013，T013）：同一 HttpClient 并发 N=8 个 Call（对齐 004
// K=8 先例）——各自租借不同连接、互不串响应（peak_concurrent==N）。
// 【护栏判据】FR-013 文档义务随 execute 的 API 文档落位（非红绿），
// 显式标注（C4 文档义务）。
async test "P05-US1⑦ 并发 8 Call 互不串响应" {
  @async.with_task_group() <| group => {
    let server = @fixtures.ScriptedServer::start()
    server.mount("POST", "/echo", {
      status: 200,
      headers: [],
      framing: Fixed,
      body: Echo,
      head_delay_ms: 1000,
      close_after_response: false,
    })
    let serving = group.spawn(
      () => server.serve_n(8, timeout_ms=15000),
      allow_failure=true,
    )
    let pool = @client.ConnectionPool::new()
    let client = @client.HttpClient::new(pool)
    // 8 个独立 Call 并发执行，各带可识别 payload
    let tasks : Array[@async.Task[Unit]] = []
    for i in 0..<8 {
      let payload = Bytes::from_iter(Array::make(16, b'a' + i.to_byte()).iter())
      let call = echo_post_call_to(client, server.port(), "/echo", payload)
      tasks.push(
        group.spawn(() => {
          let resp = call.execute()
          let echoed = resp.body().unwrap().text()
          // 回显体 = "<id>:<payload>"；payload 段须与本 Call 一致（不串响应）
          assert_true(
            echoed.has_suffix(":") == false && echoed.length() == 18,
            msg="回显长度应含 id 前缀",
          )
          let mut j = 0
          for ch in echoed {
            if j >= 2 {
              assert_eq(
                ch.to_int(),
                b'a'.to_int() + i,
                msg="Call \{i} 响应被串扰（FR-013）",
              )
            }
            j += 1
          }
        }),
      )
    }
    for task in tasks {
      task.wait()
    }
    pool.evict_all()
    server.close()
    serving.wait() catch {
      _ => ()
    }
    let peak = server.peak_concurrent()
    assert_eq(
      peak,
      8,
      msg="8 并发 Call 应各自独立租借（FR-013 高水位）实测=\{peak}",
    )
  }
}
