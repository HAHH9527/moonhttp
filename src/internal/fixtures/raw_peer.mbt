///|
// raw_peer：P03 裸 TCP 对端夹具——ScriptedPeer 程序化对端（T011 演进）。
// 一次 start 服务一条连接：mount 一个 PeerProgram，run() 按程序执行。
// 演进自 P02 的 RawPeer 捕获底座（CapturedRequest 五字段 + note 语义不变，
// 判停内核 read_frame 原样搬运），B-09～B-13 程序逐任务转绿（T012～T015）。
//
// 上游公开 API 取证（moonbitlang/async@0.22.4，本机 .mooncakes 解包，禁改、
// 不 vendor；宪法 I）：
//   - src/socket/tcp.mbt:85-115 — `TcpServer(addr, dual_stack?/reuse_addr?/
//     reuse_port_lb?)`；端口传 0 由 OS 分配，实际端口经 getsockname 回填
//   - src/socket/tcp.mbt:35-38 — `pub struct TcpServer { addr : Addr, priv io }`，
//     实际监听地址取公开字段 `.addr`（`TcpServer::addr()` 方法已标弃用，
//     用了会撞 --deny-warn 门，故走字段）
//   - src/socket/pkg.generated.mbti — `Addr::parse` / `Addr::port`
//   - src/socket/tcp.mbt:223/:231/:239 — `TcpServer::accept` 三 target 分支；
//     **并发调用不安全**（同句柄 2 个并发 accept：native PanicError /
//     wasm 悬挂，2026-10-18 实测，欠账 F18）——本包所有 accept 串行
//   - src/socket/tcp.mbt:141-172 — run_forever 的「循环内串行 accept +
//     spawn_bg 并发处理」为上游唯一自证可行形态（ScriptedServer::serve_n
//     同款；本对端一次 run 只 accept 一条，天然串行）
//   - src/socket/tcp.mbt:305-310 / :325-330 — Tcp 实现 @io.Reader/@io.Writer
//   - src/socket/tcp.mbt:23-26 — `Tcp::close`
//   - async 根包 mbti:50 — `with_timeout_opt(Int, async () -> X) -> X?`
//
// 手法参考（不搬运代码，roadmap 差异 D8）：上游 getsockname_test.mbt 的
// 「bind :0 → 取回填端口 → connect → accept」双任务范式。
//
// 宪法 IV：只监听/连接 127.0.0.1，绝不触外部网络。
// 宪法 VII：注释与文档中文。

///|
// FR-011：bind 冲突自动重试次数（data-model.md 常量表；ScriptedPeer 与
// ScriptedServer 共用）。bind :0 由 OS 分配空闲端口，冲突几乎不可达——
// 该重试分支为防御性设计，「防御性分支未测」显式记录见 T004 任务产出。
let bind_retry : Int32 = 3

///|
/// 裸 TCP 对端程序（data-model 实体 3；contracts/fixtures-api.md §2）。
/// 一次 mount 一个程序、服务一条连接、一次 run 断言。
/// 返回值语义（analyze F3 收窄）：仅 Capture 程序的返回值承载捕获断言；
/// 其余程序的返回值不承载断言语义——客户端侧结局由元测试分类并打点。
pub(all) enum PeerProgram {
  AcceptClose // B-09：accept 后立即 close
  CloseObservation // B-10：accept 后 close + 产出观测记录（T015）
  PartialResponse(CutPoint, Bool) // B-11：半截响应头（cut, then_close）
  SlowReceive(Int32, Int32) // B-12：慢速接收（read_bytes, interval_ms）
  Capture // B-13：既有捕获（判定内核 = P02 底座搬运）
}

///|
/// B-11 截断点参数化（spec FR-012/D3）：canned 响应字节的前缀长度语义。
/// Nothing 与 AcceptClose 同形（0 字节即断），保留命名以对齐截断点清单。
pub(all) enum CutPoint {
  Nothing
  MidStatusLine(Int32) // 状态行片段 n 字节（US-2 场景 2：n=15）
  AfterStatusLine // 状态行 + CRLF 后断
  MidHeaderLine(Int32) // 头行中间 n 字节后断
}

///|
/// 捕获到的一条线上报文。字段即取证面，全部原样留存：
/// - head：头部区字节（含最后一行的 CRLF，不含空行 CRLF）；未收到完整头部时为空
/// - body：重组后的负载（定长截取或 chunk 拼接；畸形/未收完时为空）
/// - raw：**已捕获的全部字节，保序、不改动、不丢弃**（含帧后多余字节，如有）
/// - chunked：负载是否按 Transfer-Encoding: chunked 帧收完
/// - complete：帧是否收完（判停口径见 frames.mbt 文件头）
/// - note：未收完时的如实说明（畸形/EOF/超时），收完则为 None
pub(all) struct CapturedRequest {
  head : Bytes
  body : Bytes
  raw : Bytes
  chunked : Bool
  complete : Bool
  note : String?
}

///|
// 字节 → String 的取证渲染：Byte 逐字节按 Latin-1 映射为码点，永不 raise、
// 不丢字节（HTTP 帧头为 ASCII；非 ASCII 也只作展示用途，不参与判等）
fn latin1_text(buf : Bytes) -> String {
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
/// 头部区文本（取证/断言面，含各行结尾的 CRLF）
pub fn CapturedRequest::head_text(self : CapturedRequest) -> String {
  latin1_text(self.head)
}

///|
/// 全部捕获字节的文本（取证面）
pub fn CapturedRequest::raw_text(self : CapturedRequest) -> String {
  latin1_text(self.raw)
}

///|
/// 只监听回环地址的裸 TCP 程序化对端。一次 mount 一个程序、服务一条连接。
pub struct ScriptedPeer {
  priv server : @socket.TcpServer
  priv mut closed : Bool
  priv mut program : PeerProgram? // 待执行的程序（mount 落位）
}

///|
// canned 收尾响应：HTTP/1.1 200 OK + Content-Length: 0 + 空行。让客户端
// end_request() 正常返回，不依赖 EOF（工单方案 6）。同时也是 B-11 半截
// 响应头的字节源（前缀形态取证见 frames.mbt 文件头）。
let canned_response : Bytes = b"HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n"

///|
// accept 到的连接句柄位：超时兜底路径需要它把 socket 关掉，避免客户端悬挂。
priv struct ConnSlot {
  mut conn : @socket.Tcp?
}

///|
/// 绑定 127.0.0.1:0（OS 分配随机端口）并开始监听；bind 冲突自动重试 ≤
/// bind_retry 次（FR-011，防御性分支未测口径同 T004 记录）。
pub async fn ScriptedPeer::start() -> ScriptedPeer {
  let mut last_error : Error? = None
  for _attempt in 0..<bind_retry {
    try {
      let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
      return { server, closed: false, program: None, }
    } catch {
      err => last_error = Some(err)
    }
  }
  raise last_error.unwrap()
}

///|
/// OS 回填的实际监听端口（bind 时传 0，故必然非 0；B-14）。
pub fn ScriptedPeer::port(self : ScriptedPeer) -> Int32 {
  self.server.addr.port()
}

///|
/// 挂载本次连接要执行的程序（一次一个；重复 mount 覆盖）。
pub fn ScriptedPeer::mount(self : ScriptedPeer, program : PeerProgram) -> Unit {
  if self.closed {
    return
  }
  self.program = Some(program)
}

///|
// 循环读入并原样累加，按帧边界判停（工单方案 4/5，Capture 程序判定内核）。
// 返回最后的判定结果；EOF 出现在帧收完之前时如实回报，已匹配字节留在
// raw 累加缓冲里。
async fn read_frame(conn : @socket.Tcp, raw : Buffer) -> Frame {
  let chunk = FixedArray::make(8192, b'\x00')
  for ;; {
    let n = conn.read(chunk, max_len=chunk.length())
    if n == 0 {
      // EOF：帧未收完。已匹配字节全部留在 raw 累加缓冲里，如实回报（工单方案 5）
      break broken_early(raw.to_bytes(), "对端在帧收完前遇到 EOF")
    }
    raw.write_bytes(chunk.unsafe_reinterpret_as_bytes()[:n])
    match scan_frame(raw.to_bytes()) {
      NeedMore => continue
      frame => break frame
    }
  }
}

///|
// 判定结果 + 累加缓冲 → 对外捕获值（不改动任何已捕获字节）
fn make_captured(raw : Bytes, frame : Frame) -> CapturedRequest {
  match frame {
    Complete(head_end, body, chunked) => {
      let head = slice_bytes(raw, 0, head_end)
      { head, body, raw, chunked, complete: true, note: None, }
    }
    NeedMore =>
      {
        head: b"",
        body: b"",
        raw,
        chunked: false,
        complete: false,
        note: Some("帧未收完"),
      }
    Broken(Some(head_end), note) => {
      let head = slice_bytes(raw, 0, head_end)
      {
        head,
        body: b"",
        raw,
        chunked: false,
        complete: false,
        note: Some(note),
      }
    }
    Broken(None, note) =>
      {
        head: b"",
        body: b"",
        raw,
        chunked: false,
        complete: false,
        note: Some(note),
      }
  }
}

///|
/// 执行挂载的程序：accept 一次 → 按程序服务这条连接。
///
/// timeout_ms（缺省 5000）为整体兜底：经公开面 `@async.with_timeout_opt`
/// 施加（FR-004），超时不无限等待——此时关闭连接（让客户端以错误尽快
/// 返回，而不是悬挂）。超时/畸形/EOF 均不 panic，也不丢弃已匹配字节。
/// 返回值语义：仅 Capture 程序的返回值承载捕获断言；其余程序返回不承载
/// 断言语义的占位捕获（complete=false）。
pub async fn ScriptedPeer::run(
  self : ScriptedPeer,
  timeout_ms~ : Int32 = 5000,
) -> CapturedRequest {
  // B-15 优雅关闭：stop 后不再 accept——新操作立即如实返回
  if self.closed {
    return {
      head: b"",
      body: b"",
      raw: b"",
      chunked: false,
      complete: false,
      note: Some("夹具已关闭（stop 后不再接受新连接）"),
    }
  }
  let program = match self.program {
    Some(program) => program
    None =>
      return {
        head: b"",
        body: b"",
        raw: b"",
        chunked: false,
        complete: false,
        note: Some("未 mount 任何 PeerProgram"),
      }
  }
  let raw = Buffer()
  let slot : ConnSlot = { conn: None, }
  let outcome = @async.with_timeout_opt(timeout_ms) <| () => {
    let (conn, _peer_addr) = self.server.accept()
    slot.conn = Some(conn)
    // 各程序分支均自带连接收尾并 return（不再有统一收尾路径）
    match program {
      // B-09（T012）：accept 后立即 close——客户端预期 EOF/ReaderClosed 类
      // 结局（为 P07 陈旧连接判据供证）。红阶段记录：T011 骨架的未实现
      // 收尾（accept→close）与本程序语义同形，客户端侧结局测试落笔即绿
      // ＝未红判据（骨架吸收红，显式记录）；本分支将其从「未实现」名单
      // 归位为显式语义，note 不再伪装「未实现」
      AcceptClose => {
        conn.close()
        slot.conn = None
        return broken_early(
          raw.to_bytes(),
          "AcceptClose：accept 后立即关闭",
        )
      }
      // B-13（T011 搬运）：原样捕获首个完整 HTTP 报文 → canned 200 → close
      Capture => {
        let frame = read_frame(conn, raw)
        // 帧完整才写 canned 200——帧未收完意味着对端已提前关闭或输入畸形，
        // 向其写入可能触发写错误并掩盖真实判定，故此路径只关闭连接
        match frame {
          Complete(_, _, _) => conn.write(canned_response)
          _ => ()
        }
        conn.close()
        slot.conn = None
        return frame
      }
      // B-11（T013，owner 裁决 A 收尾）：**先 drain 客户端请求（无条件内置，
      // 不加公开枚举字段）**，再按 CutPoint 上线 canned 前缀，再按
      // then_close 关闭。
      //
      // 为什么必须 drain（owner 裁决理由，锚点逐条）：
      // 1. spec.md Clarification D2（spec.md:32-35）明文「不得把 RST 写成
      //    可稳定断言的交付行为」，close 的 FIN/RST 归属 FR-015 观测清单；
      //    D3 判据 {BadRequest, ReaderClosed} 建立在 @http 错误面上，前提是
      //    客户端能走到 parser.mbt。未读请求即 close ⇒ raw socket 层就
      //    OSError ⇒ D3 推演根本没被触达。B-11 的诚实语义是「服务端已收到
      //    请求、开始回响应后中断」——spec.md:33「夹具 MUST 如实声明注入
      //    形态」正是要求补这一条（drain 即声明的一部分）。
      // 2. 2026-10-18 探针自证了不可稳定断言：骨架版 Nothing（不写直接
      //    close）落 ReaderClosed，转绿版 Nothing（同一路径）落 OSError——
      //    同一 socket 行为两种结局＝判据踩在竞态上。drain 清空接收队列 →
      //    close 走 FIN → 消除竞态。与本机实测事实一致：「唯一间接 RST
      //    途径是 close 时接收队列仍有未读数据，其结果依 OS 与在途数据
      //    而变」。
      // 3. PartialResponse(cut, then_close) 签名与 .mbti 公开面零新增，
      //    contracts §2 不动。
      //
      // drain 实现：复用 read_frame 读尽请求（只排空、不裁决内容）；
      // 帧未收完（客户端提前关/畸形）时不得写入——直接按如实 note 收尾。
      // 若客户端不发请求：read_frame 阻塞到 run 的超时兜底收尾（slot 清理
      // 关连接），不悬挂（FR-004）。
      PartialResponse(cut, then_close) => {
        let req_frame = read_frame(conn, raw)
        let total = canned_response.length()
        let status_line = 17
        let prefix = match cut {
          Nothing => 0
          MidStatusLine(n) => if n < status_line { n } else { status_line }
          AfterStatusLine => status_line
          MidHeaderLine(n) => {
            let p = status_line + n
            if p < total {
              p
            } else {
              total
            }
          }
        }
        match req_frame {
          Complete(_, _, _) => {
            // 帧收完才注入（帧未收完＝对端已关/畸形，写入会触发写错误并
            // 掩盖真实判定）
            if prefix > 0 {
              // 裸 Tcp 写无公开 flush 面；小体（≤38B）写后立即 close，
              // TCP 收发保证已写数据先行上线（close 不丢弃已排队字节）
              conn.write(canned_response[:prefix])
            }
            if then_close {
              conn.close()
              slot.conn = None
              return broken_early(
                raw.to_bytes(),
                "PartialResponse：drain 请求后按截断点上线 \{prefix}B 后关闭",
              )
            }
            // then_close=false：前缀已上线，连接保持（不 close、不清 slot——
            // 交由 run 的超时兜底收尾关闭连接）
            return broken_early(
              raw.to_bytes(),
              "PartialResponse：前缀已上线，连接保持",
            )
          }
          _ =>
            // 请求帧未收完：不写入，如实收尾（close 由 run 收尾路径执行）
            return broken_early(
              raw.to_bytes(),
              "PartialResponse：请求帧未收完，未注入",
            )
        }
      }
      // B-12（T014）：按声明节奏慢读 read_bytes 字节、不读满（P08 写侧
      // 停滞场景）。块 8B + 块间 sleep(interval_ms)；读满声明量或对端
      // EOF/写错误即收尾 close。收尾时接收队列可能仍有未读（「不读满」即
      // 程序语义）——测试编排保证客户端先写完即主动全关，收尾的 RST/FIN
      // 无客户端观测面（T013 同源约束：不踩钉死错误集合）
      SlowReceive(read_bytes, interval_ms) => {
        let mut got = 0
        let buf = FixedArray::make(8, b'\x00')
        for ;; {
          if got >= read_bytes {
            break
          }
          let n = conn.read(buf, max_len=8)
          if n == 0 {
            break
          }
          got = got + n
          if got < read_bytes {
            @async.sleep(interval_ms)
          }
        }
        conn.close()
        slot.conn = None
        return broken_early(
          raw.to_bytes(),
          "SlowReceive：慢读 \{got}B（声明 \{read_bytes}B）后关闭",
        )
      }
      // B-10（T015）：accept 后 close + 观测记录由客户端侧元测试产出
      // （fr015_observation_test.mbt）。未红判据：骨架未实现分支的 close
      // 收尾与本程序语义同形（同 T012），结局断言落笔即绿——显式记录。
      CloseObservation => {
        conn.close()
        slot.conn = None
        return broken_early(
          raw.to_bytes(),
          "CloseObservation：accept 后关闭",
        )
      }
    }
  }
  let bytes = raw.to_bytes()
  match outcome {
    Some(frame) => make_captured(bytes, frame)
    None => {
      match slot.conn {
        Some(conn) => conn.close()
        None => ()
      }
      make_captured(
        bytes,
        broken_early(bytes, "捕获超时（\{timeout_ms}ms 内帧未收完）"),
      )
    }
  }
}

///|
/// 关闭监听 socket（幂等，B-15）。
pub fn ScriptedPeer::close(self : ScriptedPeer) -> Unit {
  if self.closed {
    return
  }
  self.closed = true
  self.server.close()
}
