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
