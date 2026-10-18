///|
// T009 复核追加诊断探针（D1/D2/D3b；一次性，跑完移 bench/）。
// 口径与 src/perf_probe 一致：转换层输出预构造、真实 @http.Client 驱动、
// 夹具捕获；D2 增加自建 CheapPeer 对照臂（只读不扫，隔离对端扫描成本）。
// 宪法 IV：全部连接仅 127.0.0.1。D8：代码自建，不搬运上游资产。

///|
// ASCII（保证 ≤0x7F）字符串转 Bytes（探针内自建，仅用于合成请求头）
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
// 取证渲染：Byte→Latin-1 码点（同 src/fixtures 手法，自建）
fn to_text(buf : Bytes) -> String {
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
// BytesView → Bytes 复制（Buffer::write_bytes 接受视图）
fn copy_bytes(v : BytesView) -> Bytes {
  let buf = Buffer()
  buf.write_bytes(v)
  buf.to_bytes()
}

///|
// 可见化 CRLF
fn vis(s : String) -> String {
  s.replace_all(old="\r\n", new="\\r\\n")
}

///|
// 打印载荷：64KiB，仅可打印字母（保证数据内不出现 b"0\r\n\r\n"，
// CheapPeer 的 5 字节后缀判停因此无假阳性）
fn make_block_printable(n : Int32) -> Bytes {
  let arr : FixedArray[Byte] = FixedArray::make(n, b'A')
  for i = 0; i < n; i = i + 1 {
    arr[i] = (65 + i % 26).to_byte()
  }
  arr.unsafe_reinterpret_as_bytes()
}

///|
// 字节域子串查找（自建，头解析用；头 ≤64KiB，线性即可）
fn find_sub(buf : Bytes, from : Int32, pat : Bytes) -> Int32? {
  let len = buf.length()
  let m = pat.length()
  let mut i = from
  let mut hit : Int32? = None
  while i + m <= len && hit is None {
    let mut ok = true
    let mut j = 0
    while j < m && ok {
      if buf[i + j] != pat[j] {
        ok = false
      }
      j = j + 1
    }
    if ok {
      hit = Some(i)
    }
    i = i + 1
  }
  hit
}

///|
// 头内取某头行的值区间（大小写精确匹配本探针自产请求；自建）
fn header_value_span(
  buf : Bytes,
  head_end : Int32,
  name : Bytes,
) -> (Int32, Int32)? {
  let mut line_start = 0
  let mut result : (Int32, Int32)? = None
  while line_start < head_end && result is None {
    match find_sub(buf, line_start, b"\r\n") {
      None => line_start = head_end
      Some(idx) => {
        // 行内找冒号
        let mut j = line_start
        let mut colon : Int32? = None
        while j < idx && colon is None {
          if buf[j] == b':' {
            colon = Some(j)
          }
          j = j + 1
        }
        match colon {
          Some(c) =>
            if c - line_start == name.length() {
              let mut ok = true
              let mut k = 0
              while k < name.length() && ok {
                if buf[line_start + k] != name[k] {
                  ok = false
                }
                k = k + 1
              }
              if ok {
                // 值区间 [c+1, idx)，裁 OWS
                let mut vs = c + 1
                let ve = idx
                while vs < ve && (buf[vs] == b' ' || buf[vs] == b'\t') {
                  vs = vs + 1
                }
                result = Some((vs, ve))
              }
            }
          None => ()
        }
        line_start = idx + 2
      }
    }
  }
  result
}

///|
// 十进制解析（自建，仅夹具对账用）
fn parse_dec(buf : Bytes, start : Int32, end : Int32) -> Int32? {
  if start >= end {
    return None
  }
  let mut acc = 0
  let mut i = start
  while i < end {
    let d = buf[i].to_int() - 0x30
    if d < 0 || d > 9 {
      return None
    }
    acc = acc * 10 + d
    i = i + 1
  }
  Some(acc)
}

///|
// 十六进制解析（自建）
fn parse_hex(buf : Bytes, start : Int32, end : Int32) -> Int32? {
  if start >= end {
    return None
  }
  let mut acc = 0
  let mut i = start
  while i < end {
    let c = buf[i].to_int()
    let d : Int32? = if c >= 0x30 && c <= 0x39 {
      Some(c - 0x30)
    } else if c >= 0x61 && c <= 0x66 {
      Some(c - 0x61 + 10)
    } else if c >= 0x41 && c <= 0x46 {
      Some(c - 0x41 + 10)
    } else {
      None
    }
    match d {
      None => return None
      Some(v) => acc = acc * 16 + v
    }
    i = i + 1
  }
  Some(acc)
}

///|
// D1 账目表（自建 walk，判停口径对齐 src/fixtures/frames.mbt）
priv struct SizeCount {
  size : Int32
  mut count : Int32
}

///|
priv struct Ledger {
  head_len : Int32
  body_start : Int32
  chunk_count : Int32
  size_line_bytes : Int32 // Σ(hex 位数 + CRLF 2B)
  data_crlf_bytes : Int32 // Σ(数据块尾 CRLF 2B)
  term_bytes : Int32 // 终止块 0\r\n\r\n = 5B
  body_len : Int32
  consumed : Int32 // 帧终止点（终止块后 CRLFCRLF 的下一字节）
  tail_extra : Int32 // raw.length() - consumed（帧后多余字节）
  sizes : String // 直方图渲染
  err : String?
}

///|
// 自建 walk：对捕获 raw 做与夹具同口径的帧解剖（不改字节、只统计）
fn dissect(raw : Bytes) -> Ledger {
  let blank : Int32 = match find_sub(raw, 0, b"\r\n\r\n") {
    Some(p) => p
    None =>
      return {
        head_len: -1,
        body_start: -1,
        chunk_count: 0,
        size_line_bytes: 0,
        data_crlf_bytes: 0,
        term_bytes: 0,
        body_len: 0,
        consumed: -1,
        tail_extra: raw.length(),
        sizes: "",
        err: Some("未找到 CRLFCRLF"),
      }
  }
  let head_len = blank + 2
  let body_start = blank + 4
  let counts : Array[SizeCount] = []
  let mut pos = body_start
  let mut chunk_count = 0
  let mut size_line_bytes = 0
  let mut data_crlf_bytes = 0
  let mut body_len = 0
  let mut consumed = -1
  let mut err : String? = None
  while consumed < 0 && err is None {
    match find_sub(raw, pos, b"\r\n") {
      None => err = Some("大小行无 CRLF（帧未收完？）")
      Some(idx) => {
        // 忽略 ';' 后的 chunk 扩展（本探针上游不产生，防御性保留）
        let mut size_end = idx
        let mut j = pos
        while j < idx {
          if raw[j] == b';' {
            size_end = j
            break
          }
          j = j + 1
        }
        match parse_hex(raw, pos, size_end) {
          None => err = Some("大小行非十六进制")
          Some(0) =>
            match find_sub(raw, idx, b"\r\n\r\n") {
              None => err = Some("终止块后无 CRLFCRLF")
              Some(p) => consumed = p + 4
              // 终止块字节 = 本大小行(1+2) + CRLFCRLF(4) —— "0\r\n" + "\r\n"
            }
          Some(size) => {
            let data = idx + 2
            if raw.length() < data + size + 2 {
              err = Some("数据块不完整")
            } else if raw[data + size] != b'\r' || raw[data + size + 1] != b'\n' {
              err = Some("数据块尾非 CRLF")
            } else {
              chunk_count = chunk_count + 1
              size_line_bytes = size_line_bytes + (idx - pos) + 2
              data_crlf_bytes = data_crlf_bytes + 2
              body_len = body_len + size
              let mut found = false
              for sc in counts {
                if sc.size == size {
                  sc.count = sc.count + 1
                  found = true
                  break
                }
              }
              if !found {
                counts.push({ size, count: 1, })
              }
              pos = data + size + 2
            }
          }
        }
      }
    }
  }
  let mut sizes = ""
  for i, sc in counts {
    if i > 0 {
      sizes = sizes + ", "
    }
    sizes = sizes + "\{sc.size}B×\{sc.count}"
  }
  {
    head_len,
    body_start,
    chunk_count,
    size_line_bytes,
    data_crlf_bytes,
    term_bytes: 5,
    body_len,
    consumed,
    tail_extra: if consumed < 0 {
      raw.length()
    } else {
      raw.length() - consumed
    },
    sizes,
    err,
  }
}

///|
// 定长臂转换层输出（同 perf_probe 口径）
fn fixed_out(payload : Bytes) -> @http.Request raise {
  let body = @core.RequestBody::bytes(
    payload,
    payload.length().to_int64(),
    content_type=Some("application/octet-stream"),
  )
  let builder = @core.RequestBuilder::new(
    @core.HttpUrl::parse("http://127.0.0.1:1/"),
  ).method(@core.Method::Post)
  builder.header("X-Probe", "perf")
  let builder = builder.body(body)
  builder.build().to_http_request()
}

///|
// chunked 臂转换层输出（content_length=None → 转换层删 CL，上游落 TE chunked）
fn chunked_out() -> @http.Request raise {
  let body = @core.RequestBody::stream(
    _writer => (),
    content_type=Some("application/octet-stream"),
  )
  let builder = @core.RequestBuilder::new(
    @core.HttpUrl::parse("http://127.0.0.1:1/"),
  ).method(@core.Method::Post)
  builder.header("X-Probe", "perf")
  let builder = builder.body(body)
  builder.build().to_http_request()
}

///|
// 无体 GET（底座地板臂）
fn get_out() -> @http.Request raise {
  let builder = @core.RequestBuilder::new(
    @core.HttpUrl::parse("http://127.0.0.1:1/"),
  ).method(@core.Method::Get)
  builder.header("X-Probe", "perf")
  builder.build().to_http_request()
}

///|
// RawPeer 路径单次发送（带扫描夹具，同 perf_probe）
async fn raw_once(
  out : @http.Request,
  writes : Array[Bytes],
  timeout_ms~ : Int32 = 10000,
) -> @fixtures.CapturedRequest {
  let peer = @fixtures.RawPeer::start()
  let port = peer.port()
  let slot : Array[@fixtures.CapturedRequest] = []
  let _ = @async.with_task_group() <| group => {
    group.spawn_bg(() => slot.push(peer.capture_one(timeout_ms~)))
    let client = @http.Client::Client("http://127.0.0.1:\{port}/")
    client.request(
      out.meth,
      out.path.to_string_view(),
      extra_headers=out.headers,
    )
    for w in writes {
      client.write(w)
    }
    let _ = client.end_request()
    client.close()
    slot
  }
  peer.close()
  guard! slot.length() == 1
  slot[0]
}

///|
// CheapPeer：自建最小完成判定对端（D2 对照）——accept → 8KiB 循环读 →
// 仅做 O(1) 完成检查（定长=计数；chunked=5 字节后缀；无体=头即帧），
// 不做 walk_chunks、不做 payload 重组、不做逐读全量 to_bytes 重扫。
// 收尾与夹具一致（canned 200 + close），读块大小同为 8192。
// 有效性前提：载荷仅可打印字母，数据内不可能出现 b"0\r\n\r\n"。
async fn cheap_once(
  out : @http.Request,
  writes : Array[Bytes],
  timeout_ms~ : Int32 = 10000,
) -> Int32 {
  let server = @socket.TcpServer(@socket.Addr::parse("127.0.0.1:0"))
  let port = server.addr.port()
  let slot : Array[Int32] = []
  let _ = @async.with_task_group() <| group => {
    group.spawn_bg(() => slot.push(cheap_capture(server, timeout_ms~)))
    let client = @http.Client::Client("http://127.0.0.1:\{port}/")
    client.request(
      out.meth,
      out.path.to_string_view(),
      extra_headers=out.headers,
    )
    for w in writes {
      client.write(w)
    }
    let _ = client.end_request()
    client.close()
    slot
  }
  server.close()
  guard! slot.length() == 1
  slot[0]
}

///|
// CheapPeer 服务端体（见 cheap_once 注释）
async fn cheap_capture(
  server : @socket.TcpServer,
  timeout_ms~ : Int32 = 10000,
) -> Int32 {
  let outcome = @async.with_timeout_opt(timeout_ms) <| () => {
    let (conn, _peer) = server.accept()
    let chunk : FixedArray[Byte] = FixedArray::make(8192, b'\x00')
    let head_buf = Buffer()
    let mut head_end = -1
    let mut body_start = 0
    let mut cl = -1
    let mut chunked = false
    let mut total = 0
    let tail : FixedArray[Byte] = FixedArray::make(4, b'\x00')
    let mut done = false
    while !done {
      let n = conn.read(chunk, max_len=8192)
      if n == 0 {
        break
      }
      let view = chunk.unsafe_reinterpret_as_bytes()[:n]
      if head_end < 0 {
        head_buf.write_bytes(view)
        total = head_buf.length()
        let hb = head_buf.to_bytes()
        match find_sub(hb, 0, b"\r\n\r\n") {
          None => if hb.length() > 65536 { done = true }
          Some(p) => {
            head_end = p
            body_start = p + 4
            match header_value_span(hb, head_end + 2, b"Content-Length") {
              Some((vs, ve)) =>
                match parse_dec(hb, vs, ve) {
                  Some(v) => cl = v
                  None => cl = -1
                }
              None => cl = -1
            }
            let mut is_chunked = false
            match header_value_span(hb, head_end + 2, b"Transfer-Encoding") {
              Some((vs, ve)) => {
                let pat = b"chunked"
                let mut i2 = vs
                while i2 + pat.length() <= ve && !is_chunked {
                  let mut ok = true
                  let mut j2 = 0
                  while j2 < pat.length() && ok {
                    if hb[i2 + j2] != pat[j2] {
                      ok = false
                    }
                    j2 = j2 + 1
                  }
                  if ok {
                    is_chunked = true
                  }
                  i2 = i2 + 1
                }
              }
              None => ()
            }
            chunked = is_chunked
            if chunked {
              // 记录本读尾部 4 字节（终结块跨读检查用）
              let base = if n >= 4 { n - 4 } else { 0 }
              let mut k = 0
              while k < 4 && base + k < n {
                tail[k] = view[base + k]
                k = k + 1
              }
            } else if cl >= 0 {
              if total - body_start >= cl {
                done = true
              }
            } else {
              done = true // 无 CL 无 TE：头即整帧（无体请求）
            }
          }
        }
      } else {
        total = total + n
        if chunked {
          // 终结块 b"0\r\n\r\n" 只可能整段在本读尾部或跨上读边界（载荷已排除假阳性）
          if n >= 5 {
            let mut ok = view[n - 5] == b'0'
            let mut j = 1
            while j < 5 && ok {
              if view[n - 5 + j] != b"\r\n\r\n"[j - 1] {
                ok = false
              }
              j = j + 1
            }
            if ok {
              done = true
            }
          }
          if !done {
            // 跨边界：终结块结束于本读第 k 字节（k=1..4）
            let mut k = 1
            while k <= 4 && k <= n && !done {
              let need = 5 - k // 取 tail 的末 need 字节
              let mut ok = true
              let mut t = 4 - need
              while t < 4 && ok {
                if tail[t] != b"0\r\n\r\n"[t - (4 - need)] {
                  ok = false
                }
                t = t + 1
              }
              let mut v = 0
              while v < k && ok {
                if view[v] != b"0\r\n\r\n"[need + v] {
                  ok = false
                }
                v = v + 1
              }
              if ok {
                done = true
              }
              k = k + 1
            }
          }
          // 更新尾部 4 字节
          if n >= 4 {
            let mut k = 0
            while k < 4 {
              tail[k] = view[n - 4 + k]
              k = k + 1
            }
          } else {
            let mut k = 0
            while k + n < 4 {
              tail[k] = tail[k + n]
              k = k + 1
            }
            let mut v = 0
            while v < n {
              tail[4 - n + v] = view[v]
              v = v + 1
            }
          }
        } else if cl >= 0 {
          if total - body_start >= cl {
            done = true
          }
        } else {
          done = true
        }
      }
    }
    conn.write(b"HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n")
    conn.close()
    total
  }
  match outcome {
    Some(t) => t
    None => raise Failure("cheap_capture 超时")
  }
}

///|
// 统一发送口：返回每请求线上字节数
async fn send_one(
  out : @http.Request,
  writes : Array[Bytes],
  cheap~ : Bool = false,
) -> Int32 {
  if cheap {
    cheap_once(out, writes)
  } else {
    let cap = raw_once(out, writes)
    cap.raw.length()
  }
}

///|
// 标定（同 perf_probe：预热 15 + 试点 25 → 每轮 ≥500ms，钳位 [30,400]）
async fn calibrate(
  tag : String,
  out : @http.Request,
  writes : Array[Bytes],
  cheap~ : Bool = false,
) -> Int32 {
  for i = 0; i < 15; i = i + 1 {
    let _ = send_one(out, writes, cheap~)
  }
  let t0 = @async.now()
  for i = 0; i < 25; i = i + 1 {
    let _ = send_one(out, writes, cheap~)
  }
  let pilot_ms = (@async.now() - t0).to_int()
  let n = if pilot_ms < 1 {
    400
  } else {
    let est = 500 * 25 / pilot_ms
    if est < 30 {
      30
    } else if est > 400 {
      400
    } else {
      est
    }
  }
  println("[diag] calibrate arm=\{tag} pilot25_ms=\{pilot_ms} n=\{n}")
  n
}

///|
// 单轮计时
async fn bench_round(
  tag : String,
  out : @http.Request,
  writes : Array[Bytes],
  cheap~ : Bool = false,
  n~ : Int32,
) -> Unit {
  let mut total_bytes = 0
  let t0 = @async.now()
  for i = 0; i < n; i = i + 1 {
    total_bytes = total_bytes + send_one(out, writes, cheap~)
  }
  let ms = @async.now() - t0
  let us = ms.to_double() * 1000.0 / n.to_double()
  println(
    "[diag] arm=\{tag} n=\{n} total_ms=\{ms} us_per_req=\{us} bytes_per_req=\{total_bytes / n}",
  )
}

///|
// D1：64KiB chunked 帧逐字节解剖 + 定长对照头
async fn d1_ledger() -> @fixtures.CapturedRequest {
  let payload = make_block_printable(65536)
  println("===== D1 定长对照（fixed 64KiB）=====")
  let cap_f = raw_once(fixed_out(payload), [payload])
  println(
    "[D1] fixed: head_len=\{cap_f.head.length()} blank=2 body=\{cap_f.body.length()} raw=\{cap_f.raw.length()} raw==head+2+body:\{cap_f.raw.length() == cap_f.head.length() + 2 + cap_f.body.length()}",
  )
  println("===== D1 chunked 64KiB（单次 64KiB write）逐字节解剖 =====")
  let cap = raw_once(chunked_out(), [payload])
  println("[D1] chunked 头部区逐行（bytes 含行尾 CRLF）：")
  let head = cap.head
  let mut line_start = 0
  let mut idx = 0
  while idx < head.length() {
    match find_sub(head, line_start, b"\r\n") {
      None => break
      Some(p) => {
        let line = to_text(copy_bytes(head[line_start:p + 2]))
        println("[D1]   +\{line.length()}B \{vis(line)}")
        line_start = p + 2
        idx = line_start
      }
    }
  }
  println("[D1]   空行 CRLFCRLF 贡献 2B（blank 行的 CRLF）")
  let ld = dissect(cap.raw)
  println(
    "[D1] head_len=\{ld.head_len} body_start=\{ld.body_start} raw_len=\{cap.raw.length()}",
  )
  println("[D1] chunk_count=\{ld.chunk_count} sizes=[\{ld.sizes}]")
  println(
    "[D1] 大小行合计=\{ld.size_line_bytes}B 数据块尾CRLF合计=\{ld.data_crlf_bytes}B 终止块=\{ld.term_bytes}B",
  )
  println("[D1] 帧内负载=\{ld.body_len}B（应=65536）")
  println(
    "[D1] 帧终止点 consumed=\{ld.consumed} 帧后多余字节 tail_extra=\{ld.tail_extra}（应为 0）",
  )
  println(
    "[D1] 对账: head(\{ld.head_len})+blank(2)+大小行(\{ld.size_line_bytes})+块CRLF(\{ld.data_crlf_bytes})+终止块(\{ld.term_bytes})+负载(\{ld.body_len}) = \{ld.head_len + 2 + ld.size_line_bytes + ld.data_crlf_bytes + ld.term_bytes + ld.body_len}；raw=\{cap.raw.length()}；误差=\{cap.raw.length() - (ld.head_len + 2 + ld.size_line_bytes + ld.data_crlf_bytes + ld.term_bytes + ld.body_len)}",
  )
  println(
    "[D1] complete=\{cap.complete} chunked=\{cap.chunked} note=\{cap.note is Some(_)} err=\{ld.err is Some(_)}",
  )
  cap
}

///|
// D2：同臂对照（Raw=夹具扫描 / Cheap=不扫描）分离发送方与对端成本
async fn d2_arms(chunked_raw : Bytes) -> Unit {
  println("===== D2 对照臂（64KiB，载荷可打印）=====")
  let payload = make_block_printable(65536)
  let out_f = fixed_out(payload)
  let out_c = chunked_out()
  let out_g = get_out()
  let arms : Array[(String, @http.Request, Array[Bytes], Bool)] = [
    ("raw-floor-GET", out_g, [], false),
    ("cheap-floor-GET", out_g, [], true),
    ("raw-fixed-64K", out_f, [payload], false),
    ("cheap-fixed-64K", out_f, [payload], true),
    ("raw-chunked-64K-1x", out_c, [payload], false),
    ("cheap-chunked-64K-1x", out_c, [payload], true),
  ]
  let ns : Array[Int32] = []
  for arm in arms {
    ns.push(calibrate(arm.0, arm.1, arm.2, cheap=arm.3))
  }
  for round = 1; round <= 3; round = round + 1 {
    for i, arm in arms {
      bench_round("\{arm.0} r\{round}", arm.1, arm.2, cheap=arm.3, n=ns[i])
    }
  }
  // 对端扫描成本微基准（佐证）：对 D1 捕获的 chunked raw 全量 walk 计时
  let iters = 200
  let t0 = @async.now()
  for i = 0; i < iters; i = i + 1 {
    let _ = dissect(chunked_raw)
  }
  let walk_us = (@async.now() - t0).to_double() * 1000.0 / iters.to_double()
  // Buffer::to_bytes 全量复制成本（夹具每读一次全量重扫前都复制一次）
  let buf = Buffer()
  let filler = make_block_printable(65536)
  for i = 0; i < 8; i = i + 1 {
    buf.write_bytes(filler)
  }
  let _ = buf.write_bytes(b"0\r\n\r\n")
  let t1 = @async.now()
  let copies = 20000
  for i = 0; i < copies; i = i + 1 {
    let _ = buf.to_bytes()
  }
  let copy_us = (@async.now() - t1).to_double() * 1000.0 / copies.to_double()
  println(
    "[diag] 微基准: 全量walk(chunked 66KB)=\{walk_us}us/次；Buffer(66KB)::to_bytes=\{copy_us}us/次",
  )
  println(
    "[diag] 夹具对端每请求≈9 次(8KiB 读)×(部分walk + 全量to_bytes)；以全量 walk×0.5×9 + copy×9 估上界",
  )
}

///|
// D3b：walk_chunks 自递归深度实测（配 diag_crashctl 栈对照）。
// 阶梯设计（结合 8192 mod 块长的边界相位分析）：
//   a) 6B 块（"1\r\nX\r\n"）×10k —— 对照组：walk 位相 ≤64KiB，预期 Complete；
//   b) 6B 块 ×100k —— 边界相位恒落在 CRLF 区（8192≡4 mod 6），walk 位相
//      越过 64KiB 后任一读边界即触发 frames.mbt:271-272 的 pos>max_head_bytes
//      判 Broken → 预期「假 Broken + 客户端写被 RST」（bug 取证，不修）；
//   c) 256B 块（"fa\r\n"+250B 数据，8192 mod 256=0 且头部偏移使边界恒落
//      数据区中）×32k —— 载荷 8MB 内、深 32k 递归的安全深度证明。
async fn d3b_tco() -> Unit {
  println("===== D3b walk_chunks 递归深度阶梯 =====")
  let cases : Array[(String, Bytes)] = []
  // a) 6B×10k
  cases.push(("6B-unit N=10000", build_units(b"1\r\nX\r\n", 10_000)))
  // b) 6B×100k（预期触发夹具假 Broken，只取证）
  cases.push(("6B-unit N=100000", build_units(b"1\r\nX\r\n", 100_000)))
  // c) 256B×32k（250B 数据 + "fa\r\n" + CRLF；递归深度 32k）
  let big = Buffer()
  let unit_big = ascii_bytes("fa\r\n")
  for i = 0; i < 32_000; i = i + 1 {
    big.write_bytes(unit_big)
    big.write_bytes(make_block_printable(250))
    big.write_bytes(b"\r\n")
  }
  big.write_bytes(b"0\r\n\r\n")
  cases.push(("256B-unit N=32000", big.to_bytes()))
  for case in cases {
    let tag = case.0
    try {
      let payload = case.1
      let peer = @fixtures.RawPeer::start()
      let port = peer.port()
      let slot : Array[@fixtures.CapturedRequest] = []
      let t0 = @async.now()
      let _ = @async.with_task_group() <| group => {
        group.spawn_bg(() => slot.push(peer.capture_one(timeout_ms=600000)))
        let conn = @socket.Tcp::connect(
          @socket.Addr::parse("127.0.0.1:\{port}"),
        )
        try {
          conn.write(
            ascii_bytes(
              "POST /tco HTTP/1.1\r\nHost: 127.0.0.1\r\nTransfer-Encoding: chunked\r\n\r\n",
            ),
          )
          let mut off = 0
          let total = payload.length()
          while off < total {
            let end = if off + 65536 < total { off + 65536 } else { total }
            conn.write(copy_bytes(payload[off:end]))
            off = end
          }
          let echoed = conn.read_all().text()
          conn.close()
          println(
            "[D3b] \{tag} client: write done(\{total}B) read_all done(\{echoed.length()}B)",
          )
        } catch {
          err => {
            println("[D3b] \{tag} client 写/读失败：\{err}")
            conn.close()
          }
        }
        slot
      }
      let ms = @async.now() - t0
      peer.close()
      if slot.length() == 1 {
        let cap = slot[0]
        let note = match cap.note {
          Some(x) => x
          None => "（无）"
        }
        println(
          "[D3b] \{tag} wire=\{payload.length() + 71}B wall_ms=\{ms} complete=\{cap.complete} body_len=\{cap.body.length()} note=\{note}",
        )
      } else {
        println("[D3b] \{tag} 捕获任务未产出结果")
      }
    } catch {
      err => println("[D3b] \{tag} 失败：\{err}")
    }
  }
}

///|
// 重复 unit 拼接为载荷（build_units）
fn build_units(unit : Bytes, n : Int32) -> Bytes {
  let buf = Buffer()
  for i = 0; i < n; i = i + 1 {
    buf.write_bytes(unit)
  }
  buf.write_bytes(b"0\r\n\r\n")
  buf.to_bytes()
}

///|
async fn main {
  println(
    "[diag] T009 复核追加诊断（D1/D2/D3b）；宪法 IV：仅 127.0.0.1",
  )
  let cap = d1_ledger()
  d2_arms(cap.raw)
  d3b_tco()
  println("[diag] done")
}
