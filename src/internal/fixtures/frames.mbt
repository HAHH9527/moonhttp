///|
// frames：P03 裸 TCP 对端夹具的**帧边界判定**面（判停，不是 HTTP 解析）——
// 包内私有，不进公开面。
//
// 判停口径（工单技术方案 5）：
//   - 扫到 CRLFCRLF 判头部结束；
//   - 头部含 `Content-Length: n` → 再精确收 n 字节；
//   - 头部含 `Transfer-Encoding: chunked` → 按块大小逐块收，直到 0 长度块 +
//     CRLF（trailer 区以 CRLFCRLF 收尾）；
//   - 畸形输入不 panic，如实回报未收完；已匹配字节由调用方（raw_peer）原样留存。
//
// 上游写出形态取证（moonbitlang/async@0.22.4，本机 .mooncakes 解包，禁改）：
//   - src/http/send.mbt:103 — NON_EMPTY_MESSAGE_HEADER_END =
//     b"Transfer-Encoding: chunked\r\n\r\n"；无 Content-Length 时首次写体即落该串
//     并转入块编码（send.mbt:141-152 write_once 的 WaitingRequestBody 分支）
//   - src/http/send.mbt:106 — EMPTY_MESSAGE_HEADER_END = b"Content-Length: 0\r\n\r\n"
//   - src/http/send.mbt:121-133 — SendingFixed：按声明长度定长透传，写超 raise
//     IncorrectBodyLength（send.mbt:122）
//   - src/http/send.mbt:153-169 — 块编码线上形态：hex 大小行 + CRLF + 数据 + CRLF
//   - src/http/send.mbt:271-280 — end_body 对 SendingBody 终止块 b"0\r\n\r\n"
//   - src/http/send.mbt:252-258 — WaitingRequestBody（全程无体）end_body 只补一个
//     CRLF，即头部以 CRLFCRLF 结束且无负载
//   - src/http/send.mbt:285-311 — send_headers：Content-Length 解析后**原样透传**
//     （该分支无 continue），Transfer-Encoding 命中 forbidden_headers
//     （send.mbt:37-39）被丢弃
//   - src/http/send.mbt:338-342 — 上游自动补 `Accept-Encoding: gzip,identity`
//     （不在本项目的 header Map 里）→ 断言只看帧头与块编码，禁止整串字节相等
//
// T009/SC-002 引用：specs/002-m1-p02-request-response/tasks.md:207-237（T009）、
// spec.md:383-387（SC-002 四条线上字节形态）。

///|
let cr : Byte = b'\r'

///|
let lf : Byte = b'\n'

///|
// 夹具保护上限（三常量独立命名、集中一处——回滚口径：任一可单独回退，
// 不牵连状态机结构；T017 显式决策，data-model.md 常量表）。
//
// **定性：这些是测试夹具自身的保护上限，≠ moonhttp 客户端能力**——客户端
// 的报文上限由其自身规格（P02 定长帧等）定义，与夹具无关；放大夹具上限
// 不代表客户端能发/收更大的报文，反之亦然。
//
// - max_head_bytes：头部区长度上界（64KiB 不变——无场景需要更大头部）
// - max_body_bytes：负载累计上界 8MiB→16MiB（SC-003 需 8MB 级捕获留余量；
//   贴边测试脆弱；仍 ≪ 2^31，封顶累加安全）
// - max_size_line_bytes：chunk 大小行**自身长度**上界（新增，1KiB——
//   RFC 9112 允许 chunk-ext，1KiB 对测试足够宽；FR-006 判定支点，
//   取代旧实现误用的「流内绝对偏移」上界）
let max_head_bytes : Int32 = 65536

///|
let max_body_bytes : Int32 = 16777216

///|
let max_size_line_bytes : Int32 = 1024

///|
/// 帧判定结果（按位取字段）。Complete：头部区长度（含最后一行的 CRLF，不含
/// 空行的 CRLF）、重组后的负载（定长截取或 chunk 拼接）、是否按块编码收完；
/// Broken：可判定的头部区长度（未知则 None）与如实说明。
priv enum Frame {
  NeedMore
  Complete(Int32, Bytes, Bool)
  Broken(Int32?, String)
}

///|
// ASCII 大写 → 小写（仅 A–Z，其余原样）。头字段名大小写不敏感比较用。
fn ascii_lower(b : Byte) -> Byte {
  if b >= b'A' && b <= b'Z' {
    (b.to_int() + 0x20).to_byte()
  } else {
    b
  }
}

///|
// buf[start:end] 与全小写 ASCII 名字 name 的大小写不敏感等值比较
fn ci_equal(buf : Bytes, start : Int32, end : Int32, name : Bytes) -> Bool {
  let n = end - start
  if n != name.length() {
    false
  } else {
    let mut i = 0
    let mut ok = true
    while i < n && ok {
      if ascii_lower(buf[start + i]) != name[i] {
        ok = false
      }
      i = i + 1
    }
    ok
  }
}

///|
// buf[start:end] 是否含 needle（全小写 ASCII，大小写不敏感）
fn ci_contains(buf : Bytes, start : Int32, end : Int32, needle : Bytes) -> Bool {
  let m = needle.length()
  let mut i = start
  let mut hit = false
  while i + m <= end && !hit {
    hit = ci_equal(buf, i, i + m, needle)
    i = i + 1
  }
  hit
}

///|
// 从 from 起查找 CRLF，返回 CR 的偏移（行结束符）
fn find_crlf(buf : Bytes, from : Int32) -> Int32? {
  let len = buf.length()
  let mut i = from
  let mut found : Int32? = None
  while i + 1 < len && found is None {
    if buf[i] == cr && buf[i + 1] == lf {
      found = Some(i)
    } else {
      i = i + 1
    }
  }
  found
}

///|
// 从 from 起查找空行 CRLFCRLF，返回首个 CR 的偏移（头部区终点判定）
fn find_blank_line(buf : Bytes, from : Int32) -> Int32? {
  let len = buf.length()
  let mut i = from
  let mut found : Int32? = None
  while i + 3 < len && found is None {
    if buf[i] == cr && buf[i + 1] == lf && buf[i + 2] == cr && buf[i + 3] == lf {
      found = Some(i)
    } else {
      i = i + 1
    }
  }
  found
}

///|
// 在 [from, to) 内查找字节 target，返回其偏移
fn index_of_byte(
  buf : Bytes,
  from : Int32,
  to : Int32,
  target : Byte,
) -> Int32? {
  let mut i = from
  let mut found : Int32? = None
  while i < to && found is None {
    if buf[i] == target {
      found = Some(i)
    } else {
      i = i + 1
    }
  }
  found
}

///|
// OWS（SP / HTAB）——头值首尾裁剪用
fn is_ows(b : Byte) -> Bool {
  b == b' ' || b == b'\t'
}

///|
// 裁剪 [from, to) 首尾 OWS，返回值区间
fn value_bounds(buf : Bytes, from : Int32, to : Int32) -> (Int32, Int32) {
  let mut s = from
  let mut e = to
  while s < e && is_ows(buf[s]) {
    s = s + 1
  }
  while e > s && is_ows(buf[e - 1]) {
    e = e - 1
  }
  (s, e)
}

///|
// 头部区 [0, head_end) 内查找字段名 name（全小写 ASCII），返回值的字节区间。
// 只取首个同名行；无冒号的行跳过。
fn header_value(buf : Bytes, head_end : Int32, name : Bytes) -> (Int32, Int32)? {
  let mut line_start = 0
  let mut result : (Int32, Int32)? = None
  while line_start < head_end && result is None {
    match find_crlf(buf, line_start) {
      None => line_start = head_end
      Some(idx) => {
        match index_of_byte(buf, line_start, idx, b':') {
          None => ()
          Some(colon) =>
            if ci_equal(buf, line_start, colon, name) {
              result = Some(value_bounds(buf, colon + 1, idx))
            }
        }
        line_start = idx + 2
      }
    }
  }
  result
}

///|
// 十进制非负整数解析；含非数字即失败（畸形，不 panic）
fn parse_decimal(buf : Bytes, start : Int32, end : Int32) -> Int32? {
  if start >= end {
    None
  } else {
    let mut acc = 0
    let mut i = start
    let mut ok = true
    while i < end && ok {
      let d = buf[i].to_int() - 0x30
      if d < 0 || d > 9 {
        ok = false
      } else {
        acc = acc * 10 + d
        i = i + 1
      }
    }
    if ok {
      Some(acc)
    } else {
      None
    }
  }
}

///|
// 单个十六进制数字面值
fn hex_value(b : Byte) -> Int32? {
  let n = b.to_int()
  if n >= 0x30 && n <= 0x39 {
    Some(n - 0x30)
  } else if n >= 0x41 && n <= 0x46 {
    Some(n - 0x41 + 10)
  } else if n >= 0x61 && n <= 0x66 {
    Some(n - 0x61 + 10)
  } else {
    None
  }
}

///|
// 十六进制非负整数解析（chunk 大小行）；含非十六进制字符即失败
fn parse_hex(buf : Bytes, start : Int32, end : Int32) -> Int32? {
  if start >= end {
    None
  } else {
    let mut acc = 0
    let mut i = start
    let mut ok = true
    while i < end && ok {
      match hex_value(buf[i]) {
        None => ok = false
        Some(d) => {
          acc = acc * 16 + d
          i = i + 1
        }
      }
    }
    if ok {
      Some(acc)
    } else {
      None
    }
  }
}

///|
// 块编码逐块推进：大小行（';' 之后为 chunk 扩展，忽略）→ 数据 + CRLF →
// 下一块；0 长度块后 trailer 区以 CRLFCRLF 收尾。payload 累加重组负载。
fn walk_chunks(
  buf : Bytes,
  head_end : Int32,
  payload : Buffer,
  pos : Int32,
) -> Frame {
  match find_crlf(buf, pos) {
    None =>
      if pos > max_head_bytes {
        Broken(Some(head_end), "chunk 大小行超出上限仍未出现 CRLF")
      } else {
        NeedMore
      }
    Some(idx) => {
      let size_end = match index_of_byte(buf, pos, idx, b';') {
        Some(s) => s
        None => idx
      }
      match parse_hex(buf, pos, size_end) {
        None => Broken(Some(head_end), "chunk 大小行非十六进制")
        Some(0) =>
          // 末块行之后的 trailer 区以空行收尾：无 trailer 时即 b"0\r\n" + b"\r\n"
          // （send.mbt:271-280），故自 idx（含本行 CRLF）起找 CRLFCRLF
          match find_blank_line(buf, idx) {
            Some(_) => Complete(head_end, payload.to_bytes(), true)
            None => NeedMore
          }
        Some(size) => {
          let data = idx + 2
          if size > max_body_bytes - payload.length() {
            Broken(Some(head_end), "chunk 累计负载超出夹具上限")
          } else if buf.length() < data + size + 2 {
            NeedMore
          } else if buf[data + size] != cr || buf[data + size + 1] != lf {
            Broken(Some(head_end), "chunk 数据块结尾非 CRLF")
          } else {
            payload.write_bytes(buf[data:data + size])
            walk_chunks(buf, head_end, payload, data + size + 2)
          }
        }
      }
    }
  }
}

///|
/// 帧边界判定入口：对当前已捕获缓冲做判定，不改动、不丢弃任何字节。
fn scan_frame(buf : Bytes) -> Frame {
  match find_blank_line(buf, 0) {
    None =>
      if buf.length() > max_head_bytes {
        Broken(None, "头部超出上限仍未出现 CRLFCRLF")
      } else {
        NeedMore
      }
    Some(pos) => {
      // pos 是空行 CRLFCRLF 的首个 CR：头部区 [0, pos+2)，负载自 pos+4 起
      let head_end = pos + 2
      let body_start = pos + 4
      let te = header_value(buf, head_end, b"transfer-encoding")
      let cl = header_value(buf, head_end, b"content-length")
      if te is Some((vs, ve)) && ci_contains(buf, vs, ve, b"chunked") {
        walk_chunks(buf, head_end, Buffer(), body_start)
      } else if te is Some(_) {
        Broken(
          Some(head_end),
          "Transfer-Encoding 非 chunked，夹具不判定该帧",
        )
      } else {
        match cl {
          Some((vs, ve)) =>
            match parse_decimal(buf, vs, ve) {
              None => Broken(Some(head_end), "Content-Length 值非十进制")
              Some(n) =>
                if n > max_body_bytes {
                  Broken(Some(head_end), "Content-Length 超出夹具上限")
                } else if buf.length() < body_start + n {
                  NeedMore
                } else {
                  Complete(
                    head_end,
                    slice_bytes(buf, body_start, body_start + n),
                    false,
                  )
                }
            }
          // 无 CL 无 TE：上游无体请求（send.mbt:252-258），头部即整条消息
          None => Complete(head_end, b"", false)
        }
      }
    }
  }
}

///|
// 截取 [start, end) 为独立 Bytes（复制，避免与累加缓冲共享底层）
fn slice_bytes(buf : Bytes, start : Int32, end : Int32) -> Bytes {
  let out = Buffer()
  out.write_bytes(buf[start:end])
  out.to_bytes()
}

///|
// 兜底判定（EOF / 超时）：帧必然未收完，但头部若已完整就把其区间一并交回，
// 让取证面尽量保留已匹配的字节。
fn broken_early(buf : Bytes, note : String) -> Frame {
  match find_blank_line(buf, 0) {
    Some(pos) => Broken(Some(pos + 2), note)
    None => Broken(None, note)
  }
}
