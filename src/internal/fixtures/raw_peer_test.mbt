///|
// raw_peer_test：P03 裸 TCP 对端夹具（ScriptedPeer）的自证元测试。
//
// 存在理由（宪法 V/验收先行）：T009 的四条线上字节断言全部建立在本夹具
// 「原样捕获、按帧判停、不 panic、不悬挂」之上，故先用**裸 @socket.Tcp 手写
// 字节**驱动夹具自证，再谈驱动 @http.Client 的线上断言。
//
// 取证引用：
//   - ①「连通性自证」对应工单技术方案 2 的前置门：bind 127.0.0.1:0 成功、
//     取到非 0 端口、@socket.Tcp::connect 真能连上
//     （async src/socket/tcp.mbt:85-115 构造 + :111-113 getsockname 回填、
//     src/socket/pkg.generated.mbti:29 Addr::port、tcp.mbt:51 Tcp::connect）。
//   - 帧判停口径与上游写出形态的行号锚点见 frames.mbt 文件头。
//   - 服务于 specs/002-m1-p02-request-response/tasks.md:207-237（T009）、
//     spec.md:383-387（SC-002）。
//
// 宪法 IV：只连 127.0.0.1。roadmap 差异 D8：上游 test_programs/examples/mio
// 测试资产未搬运，本夹具代码自建（手法参考 async src/socket/getsockname_test.mbt:17-43）。

///|
// 取证渲染：CRLF 转为可见转义，断言失败时能读到线上原样帧头
fn visible(s : String) -> String {
  s.replace_all(old="\r\n", new="\\r\\n")
}

///|
// 连到夹具的实际监听端口（127.0.0.1，宪法 IV）
async fn connect_peer(port : Int32) -> @socket.Tcp {
  @socket.Tcp::connect(@socket.Addr::parse("127.0.0.1:\{port}"))
}

///|
// ① 连通性自证（前置门）：bind :0 → 端口非 0 → Tcp::connect 连通 → 夹具收完
//    无体请求 → canned 200 被客户端回读。
async test "P03① 连通性自证：bind 127.0.0.1:0 取非 0 端口、Tcp::connect 可连通、canned 200 可回读" {
  @async.with_task_group() <| group => {
    let peer = @fixtures.ScriptedPeer::start()
    peer.mount(Capture)
    let port = peer.port()
    assert_true(port > 0)
    let capture = group.spawn(() => peer.run())
    let conn = connect_peer(port)
    conn.write(b"GET /probe HTTP/1.1\r\nHost: 127.0.0.1\r\nAccept: */*\r\n\r\n")
    let echoed = conn.read_all().text()
    let cap = capture.wait()
    conn.close()
    peer.close()
    assert_true(cap.complete)
    // head 含各行结尾 CRLF、不含空行的 CRLF（判停口径见 frames.mbt 的 FrameScanner.feed 状态机）
    assert_eq(
      visible(cap.head_text()),
      "GET /probe HTTP/1.1\\r\\nHost: 127.0.0.1\\r\\nAccept: */*\\r\\n",
    )
    assert_eq(cap.chunked, false)
    assert_eq(cap.body, b"")
    assert_eq(
      visible(echoed),
      "HTTP/1.1 200 OK\\r\\nContent-Length: 0\\r\\n\\r\\n",
    )
  }
}

///|
// ② 定长帧：Content-Length 声明的字节数被精确收完；跨多次 write 的分片
//    保序拼接、原样留存（工单方案 4/5）
async test "P03② 定长帧：Content-Length: 10 跨分片精确收完、body 原样" {
  @async.with_task_group() <| group => {
    let peer = @fixtures.ScriptedPeer::start()
    peer.mount(Capture)
    let port = peer.port()
    let capture = group.spawn(() => peer.run())
    let conn = connect_peer(port)
    conn.write(
      b"POST /fixed HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 10\r\n\r\n0123456",
    )
    conn.write(b"789")
    let _ = conn.read_all().text()
    let cap = capture.wait()
    conn.close()
    peer.close()
    assert_true(cap.complete)
    assert_eq(cap.body, b"0123456789")
    assert_eq(cap.chunked, false)
    assert_true(cap.head_text().contains("Content-Length: 10"))
    // 原样留存：raw = 头部 + 空行 CRLF + 体，不多不少
    assert_eq(cap.raw.length(), cap.head.length() + 2 + cap.body.length())
  }
}

///|
// ③ 块编码帧：按块大小逐块推进直到 0 长度块 + CRLF，重组负载
//    （线上形态锚点 send.mbt:153-169/:271-280）
async test "P03③ chunked 帧：多块 + 0 长度终止块收完、负载重组正确" {
  @async.with_task_group() <| group => {
    let peer = @fixtures.ScriptedPeer::start()
    peer.mount(Capture)
    let port = peer.port()
    let capture = group.spawn(() => peer.run())
    let conn = connect_peer(port)
    conn.write(
      b"POST /chunked HTTP/1.1\r\nHost: 127.0.0.1\r\nTransfer-Encoding: chunked\r\n\r\n3\r\nabc\r\n4\r\n",
    )
    conn.write(b"defg\r\n0\r\n\r\n")
    let _ = conn.read_all().text()
    let cap = capture.wait()
    conn.close()
    peer.close()
    assert_true(cap.complete)
    assert_eq(cap.chunked, true)
    assert_eq(cap.body, b"abcdefg")
    assert_true(cap.head_text().contains("Transfer-Encoding: chunked"))
    // 判停不解析：块框架在线上原样留存，未被剥壳或改写
    assert_true(
      visible(cap.raw_text()).contains(
        "3\\r\\nabc\\r\\n4\\r\\ndefg\\r\\n0\\r\\n\\r\\n",
      ),
      msg="块框架未按原样留存：\{visible(cap.raw_text())}",
    )
  }
}

///|
// ④ 畸形头部（Content-Length 非十进制）：不 panic，如实回报未收完，
//    已匹配的头部区间仍交回（工单方案 5）
async test "P03④ 畸形：Content-Length 非十进制 → 不 panic、complete=false、头部区间保留" {
  @async.with_task_group() <| group => {
    let peer = @fixtures.ScriptedPeer::start()
    peer.mount(Capture)
    let port = peer.port()
    let capture = group.spawn(() => peer.run())
    let conn = connect_peer(port)
    let sent = b"POST /bad HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: abc\r\n\r\n"
    conn.write(sent)
    let _ = conn.read_all().text()
    let cap = capture.wait()
    conn.close()
    peer.close()
    assert_eq(cap.complete, false)
    assert_eq(cap.note, Some("Content-Length 值非十进制"))
    assert_true(cap.head_text().contains("POST /bad HTTP/1.1"))
    // 已匹配字节一个不丢
    assert_eq(cap.raw, sent)
  }
}

///|
// ⑤ 对端在帧收完前 EOF：如实回报、不丢弃已匹配字节（不 panic）
async test "P03⑤ EOF：帧未收完即断开 → complete=false、已捕获字节全数留存" {
  @async.with_task_group() <| group => {
    let peer = @fixtures.ScriptedPeer::start()
    peer.mount(Capture)
    let port = peer.port()
    let capture = group.spawn(() => peer.run())
    let conn = connect_peer(port)
    let sent = b"POST /eof HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 100\r\n\r\nshort"
    conn.write(sent)
    conn.close()
    let cap = capture.wait()
    peer.close()
    assert_eq(cap.complete, false)
    assert_eq(cap.note, Some("对端在帧收完前遇到 EOF"))
    assert_eq(cap.raw, sent)
    // 头部本身是完整的，兜底判定保留其区间
    assert_true(cap.head_text().contains("POST /eof HTTP/1.1"))
  }
}

///|
// ⑥ 超时兜底（工单方案 7）：帧始终收不完时不得无限等——经公开面
//    @async.with_timeout_opt（async src/pkg.generated.mbti:50）按时返回，
//    并关闭连接让客户端不至于悬挂。
async test "P03⑥ 超时兜底：400ms 内帧未收完即返回、客户端不悬挂" {
  @async.with_task_group() <| group => {
    let peer = @fixtures.ScriptedPeer::start()
    peer.mount(Capture)
    let port = peer.port()
    let capture = group.spawn(() => peer.run(timeout_ms=400))
    let conn = connect_peer(port)
    conn.write(
      b"POST /slow HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 100\r\n\r\n",
    )
    conn.write(b"partial")
    let cap = capture.wait()
    // 超时后夹具关闭连接：客户端读到 EOF，而不是永久悬挂
    let echoed = conn.read_all().text()
    conn.close()
    peer.close()
    assert_eq(cap.complete, false)
    match cap.note {
      Some(n) =>
        assert_true(n.contains("超时"), msg="超时 note 不如实：\{n}")
      None => fail("超时路径必须给出 note")
    }
    assert_eq(echoed, "")
    assert_true(cap.raw.length() > 0)
  }
}

///|
// ⑦ 非 HTTP 垃圾输入：不出现 CRLFCRLF 也必须安全返回（不 panic、不无限累加）
async test "P03⑦ 垃圾输入：无 CRLFCRLF 亦安全回报未收完" {
  @async.with_task_group() <| group => {
    let peer = @fixtures.ScriptedPeer::start()
    peer.mount(Capture)
    let port = peer.port()
    let capture = group.spawn(() => peer.run(timeout_ms=800))
    let conn = connect_peer(port)
    let sent = b"\x00\x01\x02not-http\xff"
    conn.write(sent)
    conn.close()
    let cap = capture.wait()
    peer.close()
    assert_eq(cap.complete, false)
    assert_eq(cap.head, b"")
    assert_eq(cap.raw, sent)
  }
}

///|
// ─── 生命周期/端口组（P03 T004：B-14 端口分配 + B-15 生命周期/超时保护）───
// 判据来源：specs/003-m1-p03-test-fixtures/tasks.md T004——close() 幂等、
// close 后新操作在超时上限内立即返回、port() 恒 > 0、stop 后不再接受新连接。
// 红绿纪律（宪法 IV）：本组先于 raw_peer.mbt 的共享辅助实现落地。

///|
// ⑧ 生命周期（B-14/B-15）：port() 恒 > 0（bind :0 回填）、close() 幂等
//    （连续两次 close 不 panic 不 raise）
async test "P03⑧ 生命周期：port() 恒 > 0、close() 幂等（二次 close 无害）" {
  let peer = @fixtures.ScriptedPeer::start()
  peer.mount(Capture)
  assert_true(peer.port() > 0)
  peer.close()
  peer.close()
}

///|
// ⑨ 生命周期（B-15）：close 后新操作在超时上限内立即返回——不悬挂、不 panic，
//    以 complete=false + 如实 note 收尾（优雅关闭语义）
async test "P03⑨ 生命周期：close 后 run(Capture) 在超时上限内如实返回" {
  @async.with_task_group() <| group => {
    let peer = @fixtures.ScriptedPeer::start()
    peer.mount(Capture)
    peer.close()
    let t0 = @async.now()
    let cap = group.spawn(() => peer.run(timeout_ms=500)).wait()
    let elapsed_ms = @async.now() - t0
    assert_eq(cap.complete, false)
    match cap.note {
      Some(n) =>
        assert_true(
          n.contains("关闭") || n.contains("超时"),
          msg="close 后 note 须如实：\{n}",
        )
      None => fail("close 后 run 必须给出如实 note")
    }
    assert_true(
      elapsed_ms < 500L,
      msg="close 后新操作须在超时上限内立即返回：实测 \{elapsed_ms}ms",
    )
  }
}

///|
// ⑩ 生命周期（B-14）：stop 后不再接受新连接——钉死夹具可控不变量：
//    **stop 后发起的连接绝不得到夹具的任何服务**（无 canned 200、无任何字节）。
//    客户端侧 connect 的结局形态依宿主而变（2026-10-18 Windows 实测：close 后
//    connect 悬挂 ≥1s 无快速拒绝——独立探针在裸 @socket 层复现，与夹具无关，
//    同 D2「上游无 shutdown/RST 不可构造」的能力缺口族），故拒绝/悬挂两形态
//    仅 println 观测留痕，不作跨宿主断言（FR-015 同款口径）。
async test "P03⑩ 生命周期：stop 后的连接绝不得到夹具服务（观测留痕）" {
  let peer = @fixtures.ScriptedPeer::start()
  peer.mount(Capture)
  let port = peer.port()
  assert_true(port > 0)
  peer.close()
  let t0 = @async.now()
  // 外层 1500ms 兜底整个探测（connect 悬挂宿主上由它收尾）；
  // 连上时写一条请求并限时 500ms 读——读到任何字节即「被服务」＝集合外形态。
  let outcome = @async.with_timeout_opt(1500) <| () => {
    try {
      let conn = @socket.Tcp::connect(@socket.Addr::parse("127.0.0.1:\{port}"))
      conn.write(b"GET /after-stop HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")
      let buf = FixedArray::make(128, b'\x00')
      let read_outcome = @async.with_timeout_opt(500) <| () => {
        conn.read(buf, max_len=128)
      }
      let served = match read_outcome {
        Some(n) if n > 0 => true
        _ => false
      }
      conn.close()
      served
    } catch {
      e => Err(e)
    } noraise {
      v => Ok(v)
    }
  }
  let elapsed_ms = @async.now() - t0
  peer.close()
  match outcome {
    Some(Err(_)) =>
      println(
        "[P03⑩ 观测] close 后探测快速失败（connect/read 报错，\{elapsed_ms}ms 内）",
      )
    Some(Ok(false)) =>
      println(
        "[P03⑩ 观测] close 后连接建立但未得服务（\{elapsed_ms}ms 内无应答字节）",
      )
    None =>
      println(
        "[P03⑩ 观测] close 后 connect 悬挂（\{elapsed_ms}ms 内无结局；宿主形态，不判失败）",
      )
    Some(Ok(true)) =>
      fail(
        "stop 后的连接得到了夹具服务——违背「关监听不再 accept」语义",
      )
  }
}

///|
// ─── US-3 判据补全（P03 T016：捕获判据回归锚点，spec US-3 场景 1/2）───
// 性质：Capture 底座已交付（spec 既定事实登记），**预期落笔即绿**；
// 若出现红＝底座回归，就地修复并停手回报红因。

///|
// ⑪ US-3 场景 1：定长 POST ⇒ 捕获可解析出 Content-Length，且**显式断言
//    不含 Transfer-Encoding**（定长帧与 TE 互斥的线上事实；P02 US-2 判据源）
async test "P03-B13⑪ US-3：定长 POST 捕获含 Content-Length 且不含 Transfer-Encoding" {
  @async.with_task_group() <| group => {
    let peer = @fixtures.ScriptedPeer::start()
    peer.mount(Capture)
    let capture = group.spawn(() => peer.run(timeout_ms=2000))
    let conn = connect_peer(peer.port())
    conn.write(
      b"POST /fixed-us3 HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 10\r\n\r\n0123456789",
    )
    let _ = conn.read_all().text()
    let cap = capture.wait()
    conn.close()
    peer.close()
    assert_true(cap.complete, msg="帧未收完——底座判停回归")
    // 可解析出 Content-Length
    assert_true(
      cap.head_text().contains("Content-Length: 10"),
      msg="捕获头缺 Content-Length: 10：\{visible(cap.head_text())}",
    )
    // 显式断言不含 Transfer-Encoding（定长帧互斥面）
    assert_true(
      !cap.head_text().contains("Transfer-Encoding"),
      msg="定长 POST 捕获头不得含 Transfer-Encoding：\{visible(cap.head_text())}",
    )
    assert_eq(cap.body, b"0123456789", msg="负载不符")
    assert_eq(cap.chunked, false)
  }
}

///|
// ⑫ US-3 场景 2：同一请求重放两次 ⇒ 两次捕获逐字节相同（raw/head/body/
// 判定面全同；捕获保真回归锚点）
async test "P03-B13⑫ US-3：同一请求重放两次捕获逐字节相同" {
  let sent = b"POST /replay HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 7\r\n\r\nreplay1"
  @async.with_task_group() <| group => {
    let peer = @fixtures.ScriptedPeer::start()
    peer.mount(Capture)
    // 第一轮
    let capture1 = group.spawn(() => peer.run(timeout_ms=2000))
    let conn1 = connect_peer(peer.port())
    conn1.write(sent)
    let _ = conn1.read_all().text()
    conn1.close()
    let cap1 = capture1.wait()
    // 第二轮（同字节重放）
    let capture2 = group.spawn(() => peer.run(timeout_ms=2000))
    let conn2 = connect_peer(peer.port())
    conn2.write(sent)
    let _ = conn2.read_all().text()
    conn2.close()
    let cap2 = capture2.wait()
    peer.close()
    // 逐字节相同（raw/head/body 三面 + 判定面）
    assert_eq(
      cap1.raw,
      cap2.raw,
      msg="两轮 raw 字节不同——捕获保真回归",
    )
    assert_eq(cap1.head, cap2.head, msg="两轮 head 字节不同")
    assert_eq(cap1.body, cap2.body, msg="两轮 body 字节不同")
    assert_eq(cap1.complete, cap2.complete)
    assert_eq(cap1.complete, true, msg="帧未收完——底座判停回归")
    assert_eq(
      cap1.raw,
      sent,
      msg="捕获与线上字节不符——保序保完整回归",
    )
  }
}

///|
// FR-008 端到端（T020 红阶段）：Capture 程序对双 CL 请求——complete=false、
// note 可辨认、raw/head 全留存。红阶段：现行按首个 CL 收完（complete=true）。
async test "P03-B13⑬ FR-008 端到端：双 CL 捕获 complete=false、note 可辨认、字节全留存" {
  let sent = b"POST /dup HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 5\r\nContent-Length: 4\r\n\r\nhello"
  @async.with_task_group() <| group => {
    let peer = @fixtures.ScriptedPeer::start()
    peer.mount(Capture)
    let capture = group.spawn(() => peer.run(timeout_ms=2000))
    let conn = connect_peer(peer.port())
    conn.write(sent)
    let _ = conn.read_all().text()
    conn.close()
    let cap = capture.wait()
    peer.close()
    assert_eq(
      cap.complete,
      false,
      msg="双 CL 未判畸形（红因：只取首个同名头）",
    )
    match cap.note {
      Some(n) =>
        assert_true(n.contains("重复"), msg="note 不可辨认：\{n}")
      None => fail("双 CL 必须给出 note")
    }
    // raw/head 全留存：畸形路径不丢已匹配字节
    assert_eq(cap.raw, sent, msg="捕获与线上字节不符")
    assert_true(
      cap.head_text().contains("Content-Length: 5"),
      msg="首个 CL 头不在 head 区间",
    )
    assert_true(
      cap.head_text().contains("Content-Length: 4"),
      msg="第二个 CL 头不在 head 区间",
    )
  }
}
