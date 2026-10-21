///|
// scripted_server_test：P03 第 1 类夹具（@http 声明式编排服务端）的自证元测试。
//
// 覆盖面（specs/003-m1-p03-test-fixtures/tasks.md Phase 3 / US-1）：
//   - B-01 头延迟 / B-02 滴流（US-1 场景 1，示踪弹垂直切片）
//   - B-03 重定向链（US-1 场景 2：301/302/303 + 307/308 + 畸形 Location）
//   - B-04 echo 唯一 id（US-1 场景 3，并发 N，FR-013）
//   - B-05 定长/chunked 线上帧形态（一律以线上字节为准，不信任调用序）
//   - B-06 Connection: close 头 + 实际关闭 / B-08 401/407 挑战
//   - B-07 gzip：M1 缺口·推迟（裁决 D4），不建模、不排任务
//
// FR-012 审计口径：本文件测试代码只出现「脚本声明 + 一次性启动/收尾 +
// serve_once 编排」，不出现 while/逐连接 accept/应答循环（服务端逻辑全部
// 收口在 scripted_server.mbt 夹具内）。
//
// 红绿纪律（宪法 IV）：每任务先落元测试观察红因符合预期（「夹具还没有该
// 行为」），再最小转绿。

///|
// 取证渲染（同 raw_peer_test 的 visible/latin1 手法；黑盒测试单元只见包内
// pub API，故此处自带局部助手）
fn bytes_text(buf : Bytes) -> String {
  let sb = StringBuilder()
  let len = buf.length()
  let mut i = 0
  while i < len {
    match buf[i].to_int().to_char() {
      Some(c) => sb.write_char(c)
      None => sb.write_char('\u{fffd}')
    }
    i = i + 1
  }
  sb.to_string()
}

///|
// 声明 GET /hello → 200 Static "hello" 的最小脚本（T005 骨架判据）
async test "P03-US1⓪ 骨架：mount 后 serve_once 按脚本应答一次 Static 200" {
  @async.with_task_group() <| group => {
    let server = @fixtures.ScriptedServer::start()
    assert_true(server.port() > 0)
    server.mount("GET", "/hello", {
      status: 200,
      headers: [],
      framing: Fixed,
      body: Static(b"hello"),
      head_delay_ms: 0,
      close_after_response: true,
    })
    let serving = group.spawn(() => server.serve_once(timeout_ms=3000))
    let client = @http.Client::Client("http://127.0.0.1:\{server.port()}/")
    client.request(Get, "/hello")
    let resp = client.end_request()
    let body = client.read_all().text()
    client.close()
    serving.wait()
    server.close()
    assert_eq(resp.code, 200)
    assert_eq(body, "hello")
  }
}

///|
// US-1 场景 1（B-01 头延迟 + B-02 滴流）——首颗示踪弹：声明→服务端→客户端
// 观测贯通。判据：头时延与 body 到达节奏符合编排。
// 节奏参数取可调小步长（head 150ms / 3 块 × 60ms；spec 场景原值 300ms/100ms
// 等比缩小，容差维持 ±50ms），总时长 ~300ms，不拖门禁（owner 耗时纪律）。
async test "P03-B01① US-1 场景1：GET /slow 头延迟与滴流间隔符合编排" {
  @async.with_task_group() <| group => {
    let server = @fixtures.ScriptedServer::start()
    assert_true(server.port() > 0)
    let head_delay = 150
    let interval = 60
    server.mount("GET", "/slow", {
      status: 200,
      headers: [],
      framing: Fixed,
      body: Drip(32, 3, interval),
      head_delay_ms: head_delay,
      close_after_response: true,
    })
    let serving = group.spawn(() => server.serve_once(timeout_ms=3000))
    let client = @http.Client::Client("http://127.0.0.1:\{server.port()}/")
    let t0 = @async.now()
    client.request(Get, "/slow")
    let resp = client.end_request()
    let head_ms = @async.now() - t0
    // 逐次读体并记录到达时刻与字节（协同式调度下读粒度可能合并，故断言
    // 总量与整体窗口，不逐块手算到达序——以实际到达为准）
    let t_body0 = @async.now()
    let arrivals : Array[(Int64, String)] = []
    for ;; {
      match client.read_some() {
        Some(bytes) => arrivals.push((@async.now(), bytes_text(bytes)))
        None => break
      }
    }
    client.close()
    serving.wait()
    server.close()
    let mut total = 0
    let mut body_text = ""
    for arrival in arrivals {
      total = total + arrival.1.length()
      body_text = body_text + arrival.1
    }
    // B-01：头时延符合编排（±50ms 容差；上界留调度余量）
    assert_eq(
      resp.code,
      200,
      msg="夹具未按脚本应答 200——红因应为「延迟/滴流编排尚未实现」(501)",
    )
    assert_true(
      head_ms >= (head_delay - 50).to_int64() &&
      head_ms <= (head_delay + 150).to_int64(),
      msg="头时延 \{head_ms}ms 不在编排窗 [100, 300]ms 内（B-01）",
    )
    // B-02：总量精确、填充内容符合声明、节奏成滴（窗口下界证明非一次突发，
    // 上界防异常滞留）
    assert_eq(total, 96, msg="滴流总字节数不符（3 块 × 32B）")
    let mut expected = ""
    for _i in 0..<96 {
      expected = expected + "x"
    }
    assert_eq(body_text, expected, msg="滴流填充字节不符")
    let window_ms = arrivals[arrivals.length() - 1].0 - t_body0
    assert_true(
      window_ms >= (2 * interval - 50).to_int64() &&
      window_ms <= (2 * interval + 280).to_int64(),
      msg="body 到达窗口 \{window_ms}ms 不在滴流窗 [70, 400]ms 内（B-02）",
    )
  }
}

///|
// US-1 场景 2（B-03 重定向链）：301→/a、302→相对 ../b、303→绝对 URL 逐跳
// 状态码与 Location 逐项符合。客户端不自动跟随（上游 Client 无 follow 语义），
// 逐跳用独立连接请求，夹具按声明原样下发 status + Location。
async test "P03-B03① US-1 场景2：301/302/303 重定向链逐跳符合" {
  @async.with_task_group() <| group => {
    let server = @fixtures.ScriptedServer::start()
    server.mount("GET", "/start", {
      status: 301,
      headers: [("Location", "/a")],
      framing: Fixed,
      body: Static(b""),
      head_delay_ms: 0,
      close_after_response: true,
    })
    server.mount("GET", "/a", {
      status: 302,
      headers: [("Location", "../b")],
      framing: Fixed,
      body: Static(b""),
      head_delay_ms: 0,
      close_after_response: true,
    })
    server.mount("GET", "/b", {
      status: 303,
      headers: [("Location", "http://127.0.0.1:\{server.port()}/c")],
      framing: Fixed,
      body: Static(b""),
      head_delay_ms: 0,
      close_after_response: true,
    })
    server.mount("GET", "/c", {
      status: 200,
      headers: [],
      framing: Fixed,
      body: Static(b"done"),
      head_delay_ms: 0,
      close_after_response: true,
    })
    // 逐跳驱动：每跳一次性 spawn serve_once + 独立客户端（编排声明在 mount，
    // 测试代码无服务端循环——FR-012 审计口径）
    let hops = [
      ("GET", "/start", 301, "/a"),
      ("GET", "/a", 302, "../b"),
      ("GET", "/b", 303, "http://127.0.0.1:\{server.port()}/c"),
    ]
    let mut landing_code = 0
    let mut landing_body = ""
    for hop in hops {
      let serving = group.spawn(() => server.serve_once(timeout_ms=2000))
      let client = @http.Client::Client("http://127.0.0.1:\{server.port()}/")
      client.request(Get, hop.1)
      let resp = client.end_request()
      let location = resp.headers.get(@http.CaseInsensitiveString("Location"))
      client.close()
      serving.wait()
      assert_eq(
        resp.code,
        hop.2,
        msg="跳 \{hop.1} 状态码不符（红因应为 501 占位）",
      )
      assert_eq(location, Some(hop.3), msg="跳 \{hop.1} Location 不符")
      if hop.1 == "/b" {
        // 末跳落地目标 /c 一并验证（链终点 200）
        let serving_c = group.spawn(() => server.serve_once(timeout_ms=2000))
        let client_c = @http.Client::Client(
          "http://127.0.0.1:\{server.port()}/",
        )
        client_c.request(Get, "/c")
        let resp_c = client_c.end_request()
        landing_body = client_c.read_all().text()
        client_c.close()
        serving_c.wait()
        landing_code = resp_c.code
      }
    }
    server.close()
    assert_eq(
      landing_code,
      200,
      msg="重定向链终点 /c 未按脚本应答 200",
    )
    assert_eq(landing_body, "done")
  }
}

///|
// B-03 补充：307/308 与畸形 Location 各一例——声明值原样下发（夹具不校验、
// 不改写 Location，跟随语义归 P07 的重试/跟随策略）
async test "P03-B03② 307/308 与畸形 Location 声明值原样下发" {
  @async.with_task_group() <| group => {
    let server = @fixtures.ScriptedServer::start()
    server.mount("GET", "/r307", {
      status: 307,
      headers: [("Location", "/next")],
      framing: Fixed,
      body: Static(b""),
      head_delay_ms: 0,
      close_after_response: true,
    })
    server.mount("GET", "/r308", {
      status: 308,
      headers: [("Location", "/next")],
      framing: Fixed,
      body: Static(b""),
      head_delay_ms: 0,
      close_after_response: true,
    })
    server.mount("GET", "/badloc", {
      status: 301,
      headers: [("Location", "http://[malformed-not-a-url")],
      framing: Fixed,
      body: Static(b""),
      head_delay_ms: 0,
      close_after_response: true,
    })
    let cases = [
      ("GET", "/r307", 307, "/next"),
      ("GET", "/r308", 308, "/next"),
      ("GET", "/badloc", 301, "http://[malformed-not-a-url"),
    ]
    for case in cases {
      let serving = group.spawn(() => server.serve_once(timeout_ms=2000))
      let client = @http.Client::Client("http://127.0.0.1:\{server.port()}/")
      client.request(Get, case.1)
      let resp = client.end_request()
      let location = resp.headers.get(@http.CaseInsensitiveString("Location"))
      client.close()
      serving.wait()
      assert_eq(
        resp.code,
        case.2,
        msg="\{case.1} 状态码不符（红因应为 501 占位）",
      )
      assert_eq(
        location,
        Some(case.3),
        msg="\{case.1} Location 未原样下发",
      )
    }
    server.close()
  }
}

///|
// US-1 场景 3（B-04 echo 唯一 id，FR-013）：并发 N≥8 个带唯一 id 的请求，
// 响应体 = "<单调id>:<请求体原样>"，id↔请求体一一对应、无串号无重复。
// 客户端侧真实并发发起 N=8（task group × Client），行为判据不弱化；
// 服务侧 accept 收口在夹具 serve_n（串行 accept + spawn_bg 并发处理，
// 上游 run_forever 同款形态；owner T008 裁决 A——并发 serve_once 触发
// 上游缺口：native PanicError / wasm 悬挂，欠账 F18）。
// 交错自证（owner 裁决 2026-10-18 升级）：并发处理的证明为**结构性证据**——
// 夹具内并发处理高水位 peak_concurrent() >= 2（每连接进入 +1/退出 -1 的
// 共享计数）；墙钟总耗时仅 println 留痕，不再作判据（慢机 flake 源）。
// 体含多字节 UTF-8（负载）以顺带钉死字节保真回显。
async test "P03-B04① US-1 场景3：并发 N=8 echo 唯一 id 一一对应" {
  @async.with_task_group() <| group => {
    let server = @fixtures.ScriptedServer::start()
    server.mount("POST", "/echo", {
      status: 200,
      headers: [],
      framing: Fixed,
      body: Echo,
      head_delay_ms: 120,
      close_after_response: true,
    })
    let n = 8
    // 服务侧：单次 serve_n 调用（FR-012 审计口径：测试代码零 accept 循环）
    let t0 = @async.now()
    let serving = group.spawn(() => server.serve_n(n, timeout_ms=6000))
    // 客户端侧：并发 N 个带唯一 id 的请求；各自把回显体落入自己的槽位
    let bodies : Array[String?] = Array::make(n, None)
    let client_tasks = []
    for i in 0..<n {
      let k = i
      let task = group.spawn(() => {
        let client = @http.Client::Client("http://127.0.0.1:\{server.port()}/")
        client.request(Post, "/echo")
        client.write("req-\{k}:负载\{k}")
        let resp = client.end_request()
        let body = client.read_all().text()
        client.close()
        assert_eq(
          resp.code,
          200,
          msg="echo 请求 \{k} 未按脚本应答（红因应为 501 占位）",
        )
        bodies[k] = Some(body)
      })
      client_tasks.push(task)
    }
    for task in client_tasks {
      task.wait()
    }
    serving.wait()
    server.close()
    // 交错自证：结构性证据（高水位 ≥2 即真并发处理）＋墙钟 println 留痕
    let total_ms = @async.now() - t0
    let peak = server.peak_concurrent()
    println(
      "[B-04 交错自证] N=8 并发处理高水位=\{peak}（≥2 即真并发）；总耗时留痕=\{total_ms}ms（串行化形态 native≥960ms / wasm≥1.2s）",
    )
    assert_true(
      peak >= 2,
      msg="并发处理高水位 \{peak} < 2——连接处理被串行化（结构性判据）",
    )
    // 对账：N 个响应、id 段（首个 ':' 前）全为数字且两两不同、
    // 每个响应体精确为 "<id>:req-<k>:负载<k>"（无串号）
    let ids : Array[StringView] = []
    for i in 0..<n {
      let body = match bodies[i] {
        Some(body) => body
        None => fail("echo 请求 \{i} 未收到响应体")
      }
      let colon = match body.find(":") {
        Some(colon) => colon
        None => fail("响应体缺少 id 前缀：\{body}")
      }
      assert_true(colon > 0, msg="响应体 id 段为空：\{body}")
      let id_view = body[:colon]
      let mut all_digits = true
      for ch in id_view {
        if ch < '0' || ch > '9' {
          all_digits = false
        }
      }
      assert_true(all_digits, msg="id 段非单调数字：\{body}")
      assert_eq(
        body,
        "\{id_view}:req-\{i}:负载\{i}",
        msg="echo 串号：id \{id_view} 应答 \{body}",
      )
      ids.push(id_view)
    }
    let mut distinct = true
    for i in 0..<n {
      for j in 0..<n {
        if i != j && ids[i] == ids[j] {
          distinct = false
        }
      }
    }
    assert_true(distinct, msg="echo id 出现重复")
  }
}

///|
// 子串计数（手工扫描；StringView 比对经 to_owned，避免依赖未取证 API）
fn count_sub(s : String, sub : String) -> Int32 {
  let sub_len = sub.length()
  let total = s.length() - sub_len
  let mut count = 0
  let mut i = 0
  while i <= total {
    if s[i:i + sub_len].to_owned() == sub {
      count = count + 1
      i = i + sub_len
    } else {
      i = i + 1
    }
  }
  count
}

///|
// B-05① Fixed 定长帧线上形态：线上字节含 Content-Length: 10、无
// Transfer-Encoding，体恰 10 字节且逐字节等于声明负载（一律以线上字节为
// 准，不信任调用序；R3：不按写入粒度手算线上字节）。
// 说明：Fixed+Static 的 CL 契约在 T005 骨架即落地——本测试预期落笔即绿，
// 定位为帧形态回归护栏（未红判据，见任务产出）。
async test "P03-B05① Fixed 定长帧线上形态：CL 精确、无 TE、体恰 n 字节" {
  @async.with_task_group() <| group => {
    let server = @fixtures.ScriptedServer::start()
    server.mount("GET", "/fixed", {
      status: 200,
      headers: [],
      framing: Fixed,
      body: Static(b"0123456789"),
      head_delay_ms: 0,
      close_after_response: true,
    })
    let serving = group.spawn(() => server.serve_once(timeout_ms=2000))
    let conn = connect_peer(server.port())
    conn.write(b"GET /fixed HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")
    let raw = bytes_text(conn.read_all().binary())
    conn.close()
    serving.wait()
    server.close()
    let head_end = match raw.find("\r\n\r\n") {
      Some(pos) => pos
      None => fail("响应缺少头体分隔：\{raw}")
    }
    let head = raw[:head_end].to_owned()
    let body = raw[head_end + 4:].to_owned()
    assert_true(
      head.contains("HTTP/1.1 200 OK"),
      msg="状态行缺失：\{head}",
    )
    assert_true(
      head.contains("Content-Length: 10"),
      msg="线上头缺 Content-Length: 10：\{head}",
    )
    assert_true(
      !head.contains("Transfer-Encoding"),
      msg="定长帧线上头不得出现 TE：\{head}",
    )
    assert_eq(body, "0123456789", msg="线上体与声明负载不符")
    assert_eq(body.length(), 10, msg="线上体长度不等于 CL 声明")
  }
}

///|
// B-05② Chunked 帧线上形态：无 Content-Length、有 TE: chunked；小体单写
// 在上游发送缓冲（send.mbt:85，1024B）内整块提交——线上为「hex 大小行 +
// 数据 + CRLF」单块 + 终止块（send.mbt:149-169 形态取证），不按写入粒度
// 之外的假设手算。
async test "P03-B05② Chunked 帧线上形态：无 CL、TE chunked、块框架与终止块" {
  @async.with_task_group() <| group => {
    let server = @fixtures.ScriptedServer::start()
    server.mount("GET", "/chunked", {
      status: 200,
      headers: [],
      framing: Chunked,
      body: Static(b"abcdefghij"),
      head_delay_ms: 0,
      close_after_response: true,
    })
    let serving = group.spawn(() => server.serve_once(timeout_ms=2000))
    let conn = connect_peer(server.port())
    conn.write(b"GET /chunked HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")
    let raw = bytes_text(conn.read_all().binary())
    conn.close()
    serving.wait()
    server.close()
    let head_end = match raw.find("\r\n\r\n") {
      Some(pos) => pos
      None =>
        fail(
          "响应缺少头体分隔（红因应为 501 占位无体）：\{raw}",
        )
    }
    let head = raw[:head_end].to_owned()
    assert_true(
      head.contains("HTTP/1.1 200 OK"),
      msg="状态行缺失：\{head}",
    )
    assert_true(
      !head.contains("Content-Length"),
      msg="chunked 帧线上头不得出现 CL：\{head}",
    )
    assert_true(
      head.contains("Transfer-Encoding: chunked"),
      msg="chunked 帧线上头缺 TE: chunked：\{head}",
    )
    // 10 字节 → hex 大小行 "a"；单块框架 + 0 终止块原样上线
    assert_true(
      raw.contains("a\r\nabcdefghij\r\n0\r\n\r\n"),
      msg="线上缺少预期块框架（a + 数据 + 0 终止块）：\{raw}",
    )
  }
}

///|
// B-05③ Chunked 滴流：3 块 × 32B 逐块 write+flush——线上应出现 3 个
// "20\r\n"（32 的 hex）块大小行 + 终止块；块边界经 flush 保真（R3 对策），
// 且不得出现 CL。
async test "P03-B05③ Chunked 滴流：逐块大小行可见、无 CL、终止块收尾" {
  @async.with_task_group() <| group => {
    let server = @fixtures.ScriptedServer::start()
    server.mount("GET", "/drip-chunked", {
      status: 200,
      headers: [],
      framing: Chunked,
      body: Drip(32, 3, 40),
      head_delay_ms: 0,
      close_after_response: true,
    })
    let serving = group.spawn(() => server.serve_once(timeout_ms=2000))
    let conn = connect_peer(server.port())
    conn.write(b"GET /drip-chunked HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")
    let raw = bytes_text(conn.read_all().binary())
    conn.close()
    serving.wait()
    server.close()
    assert_true(
      !raw.contains("Content-Length"),
      msg="chunked 滴流线上不得出现 CL：\{raw}",
    )
    assert_true(
      raw.contains("Transfer-Encoding: chunked"),
      msg="chunked 滴流线上缺 TE 头：\{raw}",
    )
    assert_eq(
      count_sub(raw, "20\r\n"),
      3,
      msg="3 个 32B 块应在线上留下 3 个 hex 大小行 20：\{raw}",
    )
    assert_true(
      raw.contains("0\r\n\r\n"),
      msg="chunked 滴流缺终止块：\{raw}",
    )
  }
}

///|
// B-06：close_after_response=true ⇒ 响应携带 Connection: close 头，
// 且应答后连接实际关闭。实际关闭的可观测证明：raw 客户端 read_all 以
// EOF 收尾的耗时必须远小于夹具 serve 超时（若服务端不主动关，read_all
// 只能等 serve_once 超时关连接才返回）。
async test "P03-B06① close_after_response：Connection: close 头 + 实际关闭" {
  @async.with_task_group() <| group => {
    let server = @fixtures.ScriptedServer::start()
    server.mount("GET", "/close", {
      status: 200,
      headers: [],
      framing: Fixed,
      body: Static(b"bye"),
      head_delay_ms: 0,
      close_after_response: true,
    })
    let serving = group.spawn(() => server.serve_once(timeout_ms=2000))
    let conn = connect_peer(server.port())
    let t0 = @async.now()
    conn.write(b"GET /close HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")
    let raw = bytes_text(conn.read_all().binary())
    let elapsed_ms = @async.now() - t0
    conn.close()
    serving.wait()
    server.close()
    let head_end = match raw.find("\r\n\r\n") {
      Some(pos) => pos
      None => fail("响应缺少头体分隔：\{raw}")
    }
    let head = raw[:head_end].to_owned()
    assert_true(
      head.contains("Connection: close"),
      msg="线上头缺 Connection: close（红因＝close_after_response 语义未实现）：\{head}",
    )
    assert_eq(body_slice(raw, head_end), "bye", msg="应答体不符")
    // 实际关闭：远早于 serve 超时（2000ms）返回即证明服务端主动关连接
    assert_true(
      elapsed_ms < 1000L,
      msg="read_all 耗时 \{elapsed_ms}ms——服务端未在应答后主动关闭（等到夹具超时才收尾）",
    )
  }
}

///|
// 头体分隔切片助手（B-05/B-06 共用）
fn body_slice(raw : String, head_end : Int32) -> String {
  raw[head_end + 4:].to_owned()
}

///|
// B-08：401/407 挑战——status + 对应 Authenticate 头按声明下发（M1 仅
// 编排 + 自证；凭证语义归 M2/F6）。说明：status+headers 透传面在 T007
// 建立，本测试预期落笔即绿＝未红判据（显式记录），定位为挑战编排护栏。
async test "P03-B08① 401/407 挑战脚本声明下发" {
  @async.with_task_group() <| group => {
    let server = @fixtures.ScriptedServer::start()
    server.mount("GET", "/private", {
      status: 401,
      headers: [("WWW-Authenticate", "Basic realm=\"moonhttp-test\"")],
      framing: Fixed,
      body: Static(b""),
      head_delay_ms: 0,
      close_after_response: true,
    })
    server.mount("GET", "/via-proxy", {
      status: 407,
      headers: [("Proxy-Authenticate", "Basic realm=\"moonhttp-test\"")],
      framing: Fixed,
      body: Static(b""),
      head_delay_ms: 0,
      close_after_response: true,
    })
    let cases = [
      (
        "GET", "/private", 401, "WWW-Authenticate", "Basic realm=\"moonhttp-test\"",
      ),
      (
        "GET", "/via-proxy", 407, "Proxy-Authenticate", "Basic realm=\"moonhttp-test\"",
      ),
    ]
    for case in cases {
      let serving = group.spawn(() => server.serve_once(timeout_ms=2000))
      let client = @http.Client::Client("http://127.0.0.1:\{server.port()}/")
      client.request(Get, case.1)
      let resp = client.end_request()
      let challenge = resp.headers.get(@http.CaseInsensitiveString(case.3))
      client.close()
      serving.wait()
      assert_eq(resp.code, case.2, msg="\{case.1} 挑战状态码不符")
      assert_eq(
        challenge,
        Some(case.4),
        msg="\{case.1} 挑战头未按声明下发",
      )
    }
    server.close()
  }
}

///|
// US-4 场景（T023，P08 超时语义预验证）：每 200ms 滴 1KB、共 15 块的 body
// （总 15360B，墙钟 ≥3s），read_ms=1000 的**按操作超时**下不触发超时——
// 每块间隔（200ms）远小于单次读操作的超时阈值，读调用应逐块正常返回直至
// EOF。判据取稳健形态：① 响应 200；② 15KB 全量收齐（任何一次读触发超时
// 都会中断收齐）；③ 头后 body 到达批次数 ≥ 2（滴流形态粗验，节奏精判归
// B-01①）。实现侧仅组合 T006 的 BodyPlan::Drip(1024, 15, 200)——纯参数
// 组合任务，落笔即绿符合预期（未红判据：Drip 通用签名 T006 已按
// (block_bytes, blocks, interval_ms) 落地，无新实现面）。
async test "P03-US4① 滴流场景：按操作超时 1s 下 15KB 滴流不触发超时" {
  @async.with_task_group() <| group => {
    let server = @fixtures.ScriptedServer::start()
    server.mount("GET", "/slow-us4", {
      status: 200,
      headers: [],
      framing: Fixed,
      body: Drip(1024, 15, 200),
      head_delay_ms: 0,
      close_after_response: true,
    })
    let serving = group.spawn(() => server.serve_once(timeout_ms=8000))
    let client = @http.Client::Client("http://127.0.0.1:\{server.port()}/")
    client.request(Get, "/slow-us4")
    let head = client.end_request()
    // 按操作读：read_ms=1000 语义下逐块到达（间隔 200ms < 1000ms）。
    // 外层 None＝单次读 1s 超时（=触发超时，判据破坏）；内层 None＝EOF
    //（体收完，正常终点）
    let mut total = 0
    let mut batches = 0
    let mut timed_out = false
    for ;; {
      let r = @async.with_timeout_opt(1000) <| () => { client.read_some() }
      match r {
        None => {
          timed_out = true
          break
        }
        Some(inner) =>
          match inner {
            None => break
            Some(bytes) => {
              total = total + bytes.length()
              batches = batches + 1
            }
          }
      }
    }
    client.close()
    serving.wait()
    server.close()
    // ① 响应码与头
    assert_eq(head.code, 200, msg="US-4 场景未按脚本应答 200")
    // ② 15KB 全量收齐（不触发超时的直接后果）
    assert_eq(
      total,
      15360,
      msg="滴流 body 未全量收齐——疑似触发超时中断",
    )
    assert_false(timed_out, msg="读操作触发超时")
    // ③ 滴流形态粗验：body 分多批到达（单批到达即非滴流）
    assert_true(
      batches >= 2,
      msg="body 单批到达——滴流编排未生效",
    )
  }
}

///|
// P04-FIX①（F-5 累计 accept 连接数，P04 R5/T002）：每条被接受的连接 +1，
// 累计不回落。归因：FR-009 外部证据 / US-2 场景 2（长跑无泄漏双证据的
// 服务侧证据面）。红判据：accepted_total 访问器不存在（编译红）。
async test "P04-FIX① accepted_total：逐连接累计接受数" {
  @async.with_task_group() <| group => {
    let server = @fixtures.ScriptedServer::start()
    server.mount("GET", "/hi", {
      status: 200,
      headers: [],
      framing: Fixed,
      body: Static(b"hi"),
      head_delay_ms: 0,
      close_after_response: true,
    })
    assert_eq(
      server.accepted_total(),
      0,
      msg="动工前累计接受数应为 0",
    )
    // 第 1 条连接
    let serving1 = group.spawn(() => server.serve_once(timeout_ms=3000))
    let client1 = @http.Client::Client("http://127.0.0.1:\{server.port()}/")
    client1.request(Get, "/hi")
    let _resp1 = client1.end_request()
    client1.close()
    serving1.wait()
    assert_eq(
      server.accepted_total(),
      1,
      msg="第 1 条连接后累计接受数应为 1",
    )
    // 第 2 条连接（独立 TCP 连接，非 keep-alive 复用）
    let serving2 = group.spawn(() => server.serve_once(timeout_ms=3000))
    let client2 = @http.Client::Client("http://127.0.0.1:\{server.port()}/")
    client2.request(Get, "/hi")
    let _resp2 = client2.end_request()
    client2.close()
    serving2.wait()
    server.close()
    assert_eq(
      server.accepted_total(),
      2,
      msg="第 2 条连接后累计接受数应为 2",
    )
  }
}

///|
// P04-FIX②（F-6 每连接请求数，P04 R5/T002）：按 accept 序号记账，单连接
// keep-alive 承载两个请求记 [2]；访问器拷贝语义（改返回值不影响内部）。
// 归因：长跑 keep-alive 复用自证 / US-2 场景 2。红判据：无每连接请求数
// 访问器（编译红）。
async test "P04-FIX② conn_request_counts：单连接两请求记 [2] 且拷贝语义" {
  @async.with_task_group() <| group => {
    let server = @fixtures.ScriptedServer::start()
    // close_after_response=false：保持连接，第二条请求骑同一 keep-alive 连接
    server.mount("GET", "/count", {
      status: 200,
      headers: [],
      framing: Fixed,
      body: Static(b"ok"),
      head_delay_ms: 0,
      close_after_response: false,
    })
    let serving = group.spawn(() => server.serve_once(timeout_ms=3000))
    let client = @http.Client::Client("http://127.0.0.1:\{server.port()}/")
    // 同一连接上顺序两个请求（F-1 keep-alive 多请求路径）
    client.request(Get, "/count")
    let _r1 = client.end_request()
    let _b1 = client.read_all().text()
    client.request(Get, "/count")
    let _r2 = client.end_request()
    let _b2 = client.read_all().text()
    client.close()
    serving.wait()
    server.close()
    assert_eq(
      server.accepted_total(),
      1,
      msg="两请求应骑同一连接（accept 数=1）",
    )
    assert_eq(
      server.conn_request_counts(),
      [2],
      msg="单连接两次请求应记 [2]（按 accept 序号）",
    )
    // 拷贝语义：改写返回数组不影响夹具内部记账
    let copied = server.conn_request_counts()
    copied[0] = 999
    assert_eq(
      server.conn_request_counts(),
      [2],
      msg="访问器必须拷贝语义（内部状态不可经返回值篡改）",
    )
  }
}

///|
// P04-FIX③（F-7 per-route 次序脚本，P04 R5/T002）：mount_sequence 声明
// [first, second]，同路由第 i 次命中取 min(i, len-1)——第 1/2/3 次命中
// 依次 200/201/201（末位驻留）；且每条命中连接独立（跨连接按路由计序，
// 不按连接计序）。归因：FR-010 集成桩 / US-4 场景 2。红判据：无次序脚本
// 入口 mount_sequence（编译红）。
async test "P04-FIX③ mount_sequence：同路由次序编排、末位驻留" {
  @async.with_task_group() <| group => {
    let server = @fixtures.ScriptedServer::start()
    server.mount_sequence("GET", "/seq", [
      {
        status: 200,
        headers: [],
        framing: Fixed,
        body: Static(b"first"),
        head_delay_ms: 0,
        close_after_response: true,
      },
      {
        status: 201,
        headers: [],
        framing: Fixed,
        body: Static(b"second"),
        head_delay_ms: 0,
        close_after_response: true,
      },
    ])
    // 三次独立命中（各自 serve_once：证明命中序按路由累计、跨连接有效）
    let codes : Array[Int32] = []
    for _i in 0..<3 {
      let serving = group.spawn(() => server.serve_once(timeout_ms=3000))
      let client = @http.Client::Client("http://127.0.0.1:\{server.port()}/")
      client.request(Get, "/seq")
      let resp = client.end_request()
      let _body = client.read_all().text()
      client.close()
      serving.wait()
      codes.push(resp.code)
    }
    server.close()
    assert_eq(
      codes,
      [200, 201, 201],
      msg="次序脚本应 200→201→201（末位驻留）",
    )
  }
}
