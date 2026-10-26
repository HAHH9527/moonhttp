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
