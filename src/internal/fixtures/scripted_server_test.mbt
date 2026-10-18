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
