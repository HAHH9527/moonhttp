///|
// sc003_sc004_test：US-5 的性能/确定性/断言辅助元测试。
//   - FR-009 断言辅助参数化三形态（T021）：GET /、PUT /x、POST /p?a=b
//     经同一辅助 CapturedRequest::assert_matches 断言（辅助不预设方法/路径，
//     取代 core 侧硬编码 POST / 的旧前提）
//   - SC-003/SC-004（T022）：2MB/8MB 捕获线性与 2s 判据、相位确定性端到端

///|
// FR-009①：GET / —— 同一辅助断言请求行前缀
async test "P03-FR009① 断言辅助参数化：GET / 经 assert_matches" {
  @async.with_task_group() <| group => {
    let peer = @fixtures.ScriptedPeer::start()
    peer.mount(Capture)
    let capture = group.spawn(() => peer.run(timeout_ms=2000))
    let client = @http.Client::Client("http://127.0.0.1:\{peer.port()}/")
    client.request(Get, "/")
    let resp = client.end_request()
    client.close()
    let cap = capture.wait()
    peer.close()
    assert_eq(resp.code, 200)
    let expect : @fixtures.RequestLineExpect = { method: "GET", target: "/", }
    cap.assert_matches(expect, "FR009①")
  }
}

///|
// FR-009②：PUT /x —— 非 POST 方法经同一辅助
async test "P03-FR009② 断言辅助参数化：PUT /x 经 assert_matches" {
  @async.with_task_group() <| group => {
    let peer = @fixtures.ScriptedPeer::start()
    peer.mount(Capture)
    let capture = group.spawn(() => peer.run(timeout_ms=2000))
    let client = @http.Client::Client("http://127.0.0.1:\{peer.port()}/")
    client.request(Put, "/x")
    client.write(b"payload")
    let resp = client.end_request()
    client.close()
    let cap = capture.wait()
    peer.close()
    assert_eq(resp.code, 200)
    let expect : @fixtures.RequestLineExpect = { method: "PUT", target: "/x", }
    cap.assert_matches(expect, "FR009②")
  }
}

///|
// FR-009③：POST /p?a=b —— 带查询串路径经同一辅助
async test "P03-FR009③ 断言辅助参数化：POST /p?a=b 经 assert_matches" {
  @async.with_task_group() <| group => {
    let peer = @fixtures.ScriptedPeer::start()
    peer.mount(Capture)
    let capture = group.spawn(() => peer.run(timeout_ms=2000))
    let client = @http.Client::Client("http://127.0.0.1:\{peer.port()}/")
    client.request(Post, "/p?a=b")
    client.write(b"k=v")
    let resp = client.end_request()
    client.close()
    let cap = capture.wait()
    peer.close()
    assert_eq(resp.code, 200)
    let expect : @fixtures.RequestLineExpect = {
      method: "POST",
      target: "/p?a=b",
    }
    cap.assert_matches(expect, "FR009③")
  }
}
