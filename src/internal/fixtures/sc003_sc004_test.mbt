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

///|
// SC-003 性能自证（T022）：2MB 与 8MB chunked 捕获——t8 ≤ 5×t2 且
// t8 ≤ 2s（FR-010 线性判据；对照缺陷 3 旧实现 8MB ≈ 10.2s）。
// 计时口径：t = spawn run 之前 → capture 完成（写+判停+canned 全程）。
// chunked 流 = 单大块手写字节（hex 大小行），raw socket 写 64KB 分片。
// 判定走 T018 增量状态机（每字节一次，线性有结构性保证），墙钟为宿主实测。
// 注意：Buffer::write/write_string 写 UTF-16LE（弃用陷阱）——hex 行必须
// write_bytes 原始 ASCII 字节。
fn ascii_bytes_of(s : String) -> Bytes {
  let arr = FixedArray::make(s.length(), b'\x00')
  let mut i = 0
  for ch in s {
    arr[i] = ch.to_int().to_byte()
    i = i + 1
  }
  arr.unsafe_reinterpret_as_bytes()
}

///|
fn chunked_capture_stream(block_hex : String, block : Bytes) -> Bytes {
  let buf = Buffer()
  buf.write_bytes(
    b"POST /sc3 HTTP/1.1\r\nHost: h\r\nTransfer-Encoding: chunked\r\n\r\n",
  )
  let hex_line = Buffer()
  hex_line.write_bytes(ascii_bytes_of(block_hex))
  hex_line.write_bytes(b"\r\n")
  buf.write_bytes(hex_line.to_bytes())
  buf.write_bytes(block)
  buf.write_bytes(b"\r\n0\r\n\r\n")
  buf.to_bytes()
}

///|
// 分片写整条字节流（raw socket 客户端写循环）
async fn write_in_slices(
  conn : @socket.Tcp,
  data : Bytes,
  slice : Int32,
) -> Unit {
  let total = data.length()
  let mut off : Int32 = 0
  for ;; {
    let end = if off + slice < total { off + slice } else { total }
    conn.write(data[off:end])
    off = end
    if off >= total {
      break
    }
  }
}

///|
async test "P03-SC003① 2MB/8MB chunked 捕获线性与时长" {
  @async.with_task_group() <| group => {
    // ── 2MB 轮 ──
    let peer2 = @fixtures.ScriptedPeer::start()
    peer2.mount(Capture)
    let block2 = FixedArray::make(2097152, b'a').unsafe_reinterpret_as_bytes()
    let stream2 = chunked_capture_stream("200000", block2)
    let t2_0 = @async.now()
    let run2 = group.spawn(() => peer2.run(timeout_ms=15000))
    let conn2 = connect_peer(peer2.port())
    write_in_slices(conn2, stream2, 65536)
    let _ = conn2.read_all().text()
    conn2.close()
    let cap2 = run2.wait()
    let t2 = @async.now() - t2_0
    peer2.close()
    assert_true(cap2.complete, msg="2MB 帧未收完")
    assert_eq(cap2.body.length(), 2097152, msg="2MB 负载长度不符")
    // ── 8MB 轮 ──
    let peer8 = @fixtures.ScriptedPeer::start()
    peer8.mount(Capture)
    let block8 = FixedArray::make(8388608, b'b').unsafe_reinterpret_as_bytes()
    let stream8 = chunked_capture_stream("800000", block8)
    let t8_0 = @async.now()
    let run8 = group.spawn(() => peer8.run(timeout_ms=15000))
    let conn8 = connect_peer(peer8.port())
    write_in_slices(conn8, stream8, 65536)
    let _ = conn8.read_all().text()
    conn8.close()
    let cap8 = run8.wait()
    let t8 = @async.now() - t8_0
    peer8.close()
    assert_true(cap8.complete, msg="8MB 帧未收完")
    assert_eq(cap8.body.length(), 8388608, msg="8MB 负载长度不符")
    println(
      "[SC-003 实测] t2(2MB)=\{t2}ms t8(8MB)=\{t8}ms 比值=\{if t2 > 0L { t8 * 100L / t2 } else { 0L }}%（判据 t8 ≤ 5×t2 且 t8 ≤ 2s）",
    )
    assert_true(
      t8 <= t2 * 5L,
      msg="t8(\{t8}ms) > 5×t2(\{t2}ms)——线性破坏",
    )
    assert_true(t8 <= 2000L, msg="t8(\{t8}ms) 超过 2s 判据")
  }
}

///|
// SC-004 端到端确定性（T022）：同一 >64KiB chunked 流以两种不同客户端
// 写片（3000B / 50000B）重放捕获——判定/负载/raw 逐字节全同
// （白盒相位矩阵 P03-WB① 的端到端配对；FR-006）。
async test "P03-SC004① 真实 socket 不同写片重放捕获一致" {
  let block = FixedArray::make(200000, b'c').unsafe_reinterpret_as_bytes()
  let stream = chunked_capture_stream("30d40", block)
  @async.with_task_group() <| group => {
    // 轮 1：3000B 写片
    let peer1 = @fixtures.ScriptedPeer::start()
    peer1.mount(Capture)
    let run1 = group.spawn(() => peer1.run(timeout_ms=5000))
    let conn1 = connect_peer(peer1.port())
    write_in_slices(conn1, stream, 3000)
    let _ = conn1.read_all().text()
    conn1.close()
    let cap1 = run1.wait()
    peer1.close()
    // 轮 2：50000B 写片
    let peer2 = @fixtures.ScriptedPeer::start()
    peer2.mount(Capture)
    let run2 = group.spawn(() => peer2.run(timeout_ms=5000))
    let conn2 = connect_peer(peer2.port())
    write_in_slices(conn2, stream, 50000)
    let _ = conn2.read_all().text()
    conn2.close()
    let cap2 = run2.wait()
    peer2.close()
    // 判定/负载/raw 逐字节全同
    assert_eq(cap1.complete, true, msg="轮 1 帧未收完")
    assert_eq(cap2.complete, true, msg="轮 2 帧未收完")
    assert_eq(cap1.chunked, cap2.chunked)
    assert_eq(
      cap1.body,
      cap2.body,
      msg="两轮负载不同——判停相位相关",
    )
    assert_eq(
      cap1.raw,
      cap2.raw,
      msg="两轮 raw 不同——捕获保真破坏",
    )
    assert_eq(cap1.raw, stream, msg="捕获与线上字节不符")
  }
}
