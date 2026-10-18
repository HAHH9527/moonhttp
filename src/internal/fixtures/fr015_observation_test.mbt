///|
// fr015_observation_test：B-10/FR-015 关闭形态观测清单生成器。
//
// owner 验收口径：**实测产出、禁止手写断言代替**。矩阵 = target(native /
// wasm(moonrun)) × 在途未读前置条件（覆盖双方向，见 contracts
// /wire-observations.md 2026-10-18 修正后的 pending_unread 定义）：
//   ① 无在途未读：客户端 connect 后不写，夹具 accept 后即 close；
//   ② 方向①（客户端请求未被夹具读走）：客户端先写请求，夹具不读即 close
//      ——正是 T013 实测「未读请求即 close → Windows RST」的形态；
//   ③ 方向②（夹具写入未被客户端读走）：夹具写 15B 后 close，客户端在
//      close 后才读。
// 断言仅「结局 ∈ {@io.ReaderClosed, @os_error.OSError}」（E5）；真实结局
// 以 println 打点；跨机器/跨次结局可能不同——如实打点正是清单的目的。

///|
// target 标注：声明级条件编译（upstream 同款语法，tcp.mbt:222-233）
#cfg(target="native")
fn fr015_target() -> String {
  "native"
}

///|
#cfg(target="wasm")
fn fr015_target() -> String {
  "wasm(moonrun)"
}

///|
// 读结局分类：循环 read 至终态——0/EOF ⇒ ReaderClosed；OSError ⇒ OSError；
// 限时 2s 未终态 ⇒ Timeout（集合外形态）。读到的字节如实累计打点。
async fn fr015_read_outcome(conn : @socket.Tcp) -> String {
  let outcome = @async.with_timeout_opt(2000) <| () => {
    try {
      let buf = FixedArray::make(256, b'\x00')
      for ;; {
        let n = conn.read(buf, max_len=256)
        if n == 0 {
          return "ReaderClosed"
        }
      }
    } catch {
      _ => return "OSError"
    } noraise {
      _ => "Timeout"
    }
  }
  match outcome {
    Some(kind) => kind
    None => "Timeout"
  }
}

///|
// ①无在途未读：connect 即 close（夹具不读不写）
async test "P03-B10① FR-015 观测：pending_unread=no（connect 即 close）" {
  @async.with_task_group() <| group => {
    let peer = @fixtures.ScriptedPeer::start()
    peer.mount(CloseObservation)
    let running = group.spawn(() => peer.run(timeout_ms=2000))
    let conn = connect_peer(peer.port())
    let _ = running.wait()
    let kind = fr015_read_outcome(conn)
    conn.close()
    peer.close()
    println(
      "[FR-015 观测] target=\{fr015_target()} pending_unread=no outcome=\{kind}",
    )
    assert_true(
      kind == "ReaderClosed" || kind == "OSError",
      msg="结局 \{kind} 落在 {ReaderClosed, OSError} 之外（集合外形态）",
    )
  }
}

///|
// ②方向①（客户端请求未被夹具读走）：客户端先写请求，夹具不读即 close
// ——T013 集合外形态（Windows RST）的正源，观测清单如实记录其结局。
async test "P03-B10② FR-015 观测：pending_unread=yes（客户端请求未读，方向①）" {
  @async.with_task_group() <| group => {
    let peer = @fixtures.ScriptedPeer::start()
    peer.mount(CloseObservation)
    let running = group.spawn(() => peer.run(timeout_ms=2000))
    let conn = connect_peer(peer.port())
    conn.write(b"GET /pending HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")
    let _ = running.wait()
    let kind = fr015_read_outcome(conn)
    conn.close()
    peer.close()
    println(
      "[FR-015 观测] target=\{fr015_target()} pending_unread=yes direction=client->fixture outcome=\{kind}",
    )
    assert_true(
      kind == "ReaderClosed" || kind == "OSError",
      msg="结局 \{kind} 落在 {ReaderClosed, OSError} 之外（集合外形态）",
    )
  }
}

///|
// ③方向②（夹具写入未被客户端读走）：夹具 drain 请求后写 15B 再 close，
// 客户端在 close 后才读——close 时客户端接收队列有 15B 未读。
async test "P03-B10③ FR-015 观测：pending_unread=yes（夹具写入未读，方向②）" {
  @async.with_task_group() <| group => {
    let peer = @fixtures.ScriptedPeer::start()
    peer.mount(PartialResponse(MidStatusLine(15), true))
    let running = group.spawn(() => peer.run(timeout_ms=2000))
    let conn = connect_peer(peer.port())
    conn.write(b"GET /pending HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")
    let _ = running.wait()
    let kind = fr015_read_outcome(conn)
    conn.close()
    peer.close()
    println(
      "[FR-015 观测] target=\{fr015_target()} pending_unread=yes direction=fixture->client outcome=\{kind}",
    )
    assert_true(
      kind == "ReaderClosed" || kind == "OSError",
      msg="结局 \{kind} 落在 {ReaderClosed, OSError} 之外（集合外形态）",
    )
  }
}
