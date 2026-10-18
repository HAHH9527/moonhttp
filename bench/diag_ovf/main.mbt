///|
// D3a：11 位以上 Content-Length 的实际症状观测（只回报，不修）。
// 每例独立 RawPeer 生命周期；高危例（可能触发 slice 越界 abort）置于最后。
// 宪法 IV：仅 127.0.0.1。

///|
// ASCII 字符串转 Bytes（探针内自建；用例全 ASCII）
fn ascii_bytes(s : String) -> Bytes {
  let buf = Buffer()
  let len = s.length()
  let mut i = 0
  while i < len {
    buf.write_byte(s[i].to_int().to_byte())
    i = i + 1
  }
  buf.to_bytes()
}

///|
// 对一个独立 RawPeer 发送带指定 Content-Length 行的裸请求并回报捕获结果
async fn probe_case(tag : String, cl_line : String, timeout_ms : Int32) -> Unit {
  let peer = @fixtures.RawPeer::start()
  let port = peer.port()
  let slot : Array[@fixtures.CapturedRequest] = []
  let _ = @async.with_task_group() <| group => {
    group.spawn_bg(() => slot.push(peer.capture_one(timeout_ms~)))
    let conn = @socket.Tcp::connect(@socket.Addr::parse("127.0.0.1:\{port}"))
    let head = "POST /ovf HTTP/1.1\r\nHost: 127.0.0.1\r\n\{cl_line}\r\n"
    conn.write(ascii_bytes(head))
    conn.write(b"abc") // 少量体字节：覆盖「声明巨大/异常长度」的读入路径
    let _echoed = conn.read_all()
    conn.close()
    slot
  }
  peer.close()
  guard! slot.length() == 1
  let cap = slot[0]
  let note = match cap.note {
    Some(n) => n
    None => "（无）"
  }
  println(
    "[D3a] \{tag} CL行=\{cl_line.replace_all(old="\r\n", new="")} → complete=\{cap.complete} chunked=\{cap.chunked} body_len=\{cap.body.length()} raw_len=\{cap.raw.length()} note=\{note} head保留=\{cap.head_text().contains("POST /ovf")}",
  )
}

///|
async fn main {
  println("[diag] D3a parse_decimal 溢出症状观测")
  // 例 1：11 个 9 —— 溢出 wrap 后为正且大于夹具上限，预期 Broken「超出夹具上限」
  probe_case("例1", "Content-Length: 99999999999\r\n", 3000)
  // 例 2：前导零 11 位 —— 无溢出，声明 100 而体只有 3，预期 NeedMore→超时 note
  probe_case("例2", "Content-Length: 00000000100\r\n", 1200)
  // 例 3：3+10 个 0 —— 溢出 wrap 后为负，预期「空 body 误报 Complete」或 slice 越界 abort（高危，置于最后）
  probe_case("例3", "Content-Length: 30000000000\r\n", 3000)
  println(
    "[diag] D3a done（若上行缺失，说明例3 触发了进程级 abort）",
  )
}
