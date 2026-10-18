///|
// scripted_peer_test：P03 裸 TCP 程序化对端（ScriptedPeer）的 US-2 元测试。
//
// 覆盖面（specs/003-m1-p03-test-fixtures/tasks.md Phase 4 / US-2）：
//   - B-09 accept 后立即 close（US-2 场景 1；为 P07 提供判据）
//   - B-11 半截响应头三截断点穷举（US-2 场景 2；错误落钉死可观测集合
//     {BadRequest, ReaderClosed}，集合≠可重试集合）
//   - B-12 慢速接收滴流（P08 写侧停滞预验证）
//   - B-10/FR-015 观测清单见 fr015_observation_test.mbt（独立文件）
//
// 红绿纪律（宪法 IV）：每程序先红再最小转绿；未红判据显式记录。

///|
// US-2 场景 1（B-09）：accept 后立即 close——已建立连接上写入请求后，
// 客户端读到 EOF/连接错误类结局（不悬挂）。实现注记（tasks T012）：本测试
// 以「已建立连接上写入后对端 close」等价驱动；真正的连接池复用判据归 P07。
// 未红判据（T012 显式记录）：T011 骨架的未实现收尾（accept→close）与
// AcceptClose 语义同形，本测试落笔即绿（骨架吸收红）。
async test "P03-B09① accept 后立即 close：客户端写入后收到 EOF/连接错误类结局" {
  @async.with_task_group() <| group => {
    let peer = @fixtures.ScriptedPeer::start()
    peer.mount(AcceptClose)
    let running = group.spawn(() => peer.run(timeout_ms=2000))
    let conn = connect_peer(peer.port())
    conn.write(
      b"POST /stale HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 4\r\n\r\nbody",
    )
    // 客户端读：对端 accept 后 close ⇒ EOF（read=0，ReaderClosed 类）
    // 或 OSError（连接被重置类）——限时 1s，不悬挂
    // （try/catch/noraise 语义：noraise 拿成功值，此处包成 Result 以区分
    // EOF(read=0) 与 OSError；不得在 try 块内手动再包一层 Ok——那会双层）
    let outcome : Result[Int32, Error]? = @async.with_timeout_opt(1000) <| () => {
      try {
        let buf = FixedArray::make(64, b'\x00')
        conn.read(buf, max_len=64)
      } catch {
        e => Err(e)
      } noraise {
        n => Ok(n)
      }
    }
    conn.close()
    let _ = running.wait()
    peer.close()
    match outcome {
      Some(Ok(n)) =>
        if n == 0 {
          // EOF：对端 FIN（ReaderClosed 类形态）
          println("[B-09 观测] 客户端结局=EOF(read=0)")
        } else {
          fail("对端 close 后仍读到数据——accept 后未立即 close")
        }
      // OSError：连接被重置类形态
      Some(Err(_)) => println("[B-09 观测] 客户端结局=OSError")
      None => fail("客户端读悬挂 1s——对端 accept 后未 close")
    }
  }
}

///|
// B-11 截断点穷举表：CutPoint 四变体（Nothing 与 AcceptClose 同形，保留
// 命名对齐截断点清单）；expected_bytes = canned 响应按声明截断后的线上
// 字节数（17 = "HTTP/1.1 200 OK\r\n" 状态行；25 = 17 + 头行前 8 字节）。
// US-2 场景 2 的 MidStatusLine(15) 在列。
fn cut_cases() -> Array[(@fixtures.CutPoint, String, Int32)] {
  [
    (Nothing, "Nothing", 0),
    (MidStatusLine(15), "MidStatusLine(15)", 15),
    (AfterStatusLine, "AfterStatusLine", 17),
    (MidHeaderLine(8), "MidHeaderLine(8)", 25),
  ]
}

///|
// B-11 判据层 a（夹具实现自证）：raw socket 计数「对端 close 前客户端实际
// 收到的字节数」＝声明截断长度。这层驱动实现（红阶段：骨架发 0 字节 ⇒
// 15/17/25 三例红）；Nothing 预期 0 与骨架同形＝未红判据（显式记录）。
async test "P03-B11① 三截断点穷举：线上截断字节计数与声明一致" {
  for case in cut_cases() {
    @async.with_task_group() <| group => {
      let peer = @fixtures.ScriptedPeer::start()
      peer.mount(PartialResponse(case.0, true))
      let running = group.spawn(() => peer.run(timeout_ms=2000))
      let conn = connect_peer(peer.port())
      conn.write(b"GET /cut HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")
      // 读到连接结束（EOF 或 OSError），累计线上实收字节数
      // （Windows 上「0 字节即 close」的客户端 read 可能以 OSError 收尾——
      // RST 类形态，见 T012/T015 观测留痕；此处不区分结局，字节计数交
      // ②层作客户端错误分类）
      let mut received = 0
      let buf = FixedArray::make(256, b'\x00')
      for ;; {
        let read_outcome = @async.with_timeout_opt(1000) <| () => {
          try conn.read(buf, max_len=256) catch {
            _ => Err(-1)
          } noraise {
            n => Ok(n)
          }
        }
        let n = match read_outcome {
          Some(Ok(n)) if n > 0 => n
          _ => break
        }
        received = received + n
      }
      conn.close()
      let _ = running.wait()
      peer.close()
      assert_eq(
        received,
        case.2,
        msg="截断点 \{case.1} 线上实收 \{received}B ≠ 声明 \{case.2}B（红因应为截断前缀未实现）",
      )
    }
  }
}

///|
// B-11 错误分类（D3 钉死可观测集合）：仅 BadRequest / ReaderClosed 两类；
// 其余形态返回 None＝集合外（spec 变更信号）。is 表达式判别。
fn classify_client_error(e : Error) -> String? {
  if e is @http.BadRequest {
    return Some("BadRequest")
  }
  if e is @io.ReaderClosed {
    return Some("ReaderClosed")
  }
  None
}

///|
// B-11 判据层 b（spec D3 钉死，US-2 场景 2）：逐截断点断言客户端错误落在
// 钉死可观测集合 {BadRequest, ReaderClosed} 内；出现集合外形态（含「拿到
// 完整响应」）即 fail——spec 变更信号，停手回报，不得扩集或放宽。
// 集合≠可重试集合（F17）：可重试分流归 P07，不在本判据。
// 2026-10-18 owner 裁决 A：未读请求即 close 曾致四截断点 × 双 target 全落
// OSError（raw 层 RST，@http 错误面未触达）；drain 无条件内置后 close 走
// FIN，判据集合不动。逐截断点 println 记录实测错误类型。
async test "P03-B11② 三截断点穷举：客户端错误落钉死集合 {BadRequest, ReaderClosed}" {
  for case in cut_cases() {
    @async.with_task_group() <| group => {
      let peer = @fixtures.ScriptedPeer::start()
      peer.mount(PartialResponse(case.0, true))
      let running = group.spawn(() => peer.run(timeout_ms=2000))
      let client = @http.Client::Client("http://127.0.0.1:\{peer.port()}/")
      client.request(Get, "/cut")
      let outcome = try {
        let resp = client.end_request()
        Ok(resp)
      } catch {
        e => Err(e)
      } noraise {
        r => r
      }
      client.close()
      let _ = running.wait()
      peer.close()
      match outcome {
        Ok(_) =>
          fail(
            "截断点 \{case.1}：客户端拿到完整响应——集合外形态（spec 变更信号）",
          )
        Err(e) =>
          match classify_client_error(e) {
            Some(kind) => println("[B-11 观测] \{case.1} → \{kind}")
            None =>
              fail(
                "截断点 \{case.1}：客户端错误落集合外——spec 变更信号（停手回报）",
              )
          }
      }
    }
  }
}

///|
// B-12 慢速接收（P08 写侧停滞场景预验证）：对端按声明节奏读、不读满。
// 判据口径与 T013 同源——不踩钉死错误集合：
// - 对端节奏：run 总耗时 ≥ 慢读间隔下界（2 次读间 1 个 interval）
// - 写侧停滞：客户端分片写大体（1MB，远超 loopback 发送缓冲），写循环
//   被对端慢读压制，总耗时 ≥ 停滞下界，且以「写完 / 对端 close 触发
//   OSError」收尾——客户端写完即主动 close（全关），对端收尾的 RST/FIN
//   无观测面，不把任何一侧推入集合外形态（T013 同源约束）
// 红阶段：SlowReceive 未实现 → run 报「未实现」可归因失败。
async test "P03-B12① 慢速接收：写侧停滞与对端节奏可观测" {
  @async.with_task_group() <| group => {
    let peer = @fixtures.ScriptedPeer::start()
    peer.mount(SlowReceive(16, 100))
    let t0 = @async.now()
    let running = group.spawn(() => peer.run(timeout_ms=3000))
    let conn = connect_peer(peer.port())
    // 客户端分片写 1MB（32 片 × 32KB）；对端 close 后 write 以 OSError 收尾
    let mut write_error = false
    let t_write0 = @async.now()
    for _i in 0..<32 {
      let w = try {
        conn.write(FixedArray::make(32768, b'x').unsafe_reinterpret_as_bytes())
        true
      } catch {
        _ => false
      } noraise {
        v => v
      }
      match w {
        true => continue
        false => {
          write_error = true
          break
        }
      }
    }
    let write_ms = @async.now() - t_write0
    conn.close()
    let _ = running.wait()
    peer.close()
    let total_ms = @async.now() - t0
    // 对端节奏：慢读 16B（块 8B + 1 个 100ms 间隔）须留下节奏下界
    assert_true(
      total_ms >= 80L,
      msg="run 总耗时 \{total_ms}ms 低于慢读节奏下界 ~100ms——对端未按声明节奏读",
    )
    // 写侧停滞：写循环被压制（远大于无停滞时 ~10ms 级的写完耗时）
    assert_true(
      write_ms >= 60L,
      msg="客户端写 1MB 耗时 \{write_ms}ms 未观测到停滞（\{write_error}）——对端未慢读",
    )
    println(
      "[B-12 观测] 写循环耗时=\{write_ms}ms（停滞下界 60ms）、run 总耗时=\{total_ms}ms、写收尾形态=\{if write_error { "OSError(对端close)" } else { "写完" }}",
    )
  }
}
