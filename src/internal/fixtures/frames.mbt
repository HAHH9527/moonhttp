///|
// frames：P03 裸 TCP 对端夹具的**帧边界判定**面（判停，不是 HTTP 解析）——
// 包内私有，不进公开面。
//
// 判停口径（T018 重写后的新状态机口径，取代旧的「全量重扫 + 绝对偏移
// 上界」描述）：
//   - FrameScanner.feed(bytes) -> Signal 为**纯推进增量状态机**：每字节
//     恰好被处理一次，判定只依赖 (state, 字节序列)，与读取分片相位无关
//     （FR-006）；raw 的累加由调用方负责，feed 不重扫历史字节（FR-010，
//     旧实现的每 8KiB 全量 to_bytes() 重扫已废弃）；
//   - 头部态：增量查找 CRLFCRLF（4 字节匹配进度机，跨块无歧义），头部
//     字节计数受 max_head_bytes 约束；
//   - chunked 态：大小行以**行缓冲**累积，行缓冲受 max_size_line_bytes
//     （大小行自身长度上界——不再用流内绝对偏移充当上界，此为 FR-006 的
//     判定性修正点）；数据块按剩余计数消费，块尾必须 CRLF；
//     累计负载受 max_body_bytes 封顶（超限即时 Broken，绝不无限累加）；
//   - 0 长度块后 trailer 区找 CRLFCRLF 收尾（trailer 计数同受
//     max_head_bytes 防无限累加，FR-014）；
//   - 畸形输入不 panic，如实回报 Failed(note)；已匹配字节由调用方原样
//     留存（FR-005）。
//   - 数值解析与重复头语义：Content-Length 十进制、chunk 大小行十六进制
//     （';' 后为 chunk-ext 忽略）；重复 Content-Length 与 TE 分派语义由
//     头解析处判定（T019/T020 增量收紧）。
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
/// 帧判定结果（对调用方的稳定口径）。Complete：头部区长度（含最后一行的
/// CRLF，不含空行的 CRLF）、重组后的负载（定长截取或 chunk 拼接）、是否
/// 按块编码收完；Broken：可判定的头部区长度（未知则 None）与如实说明。
priv enum Frame {
  Complete(Int32, Bytes, Bool)
  Broken(Int32?, String)
}

///|
// feed 的输出信号（状态机内部口径）。feed 返回 Signal?：None＝尚需更多
// 字节（Pending 语义，不设变体以规避与 Frame 枚举同名变体的构造器统计
// 歧义）。
priv enum Signal {
  Done(Int32, Bytes, Bool)
  Failed(String)
}

///|
// 状态机的推进状态（data-model 实体 5）
priv enum ScanState {
  Head // 增量查找 CRLFCRLF（进度机跨块无歧义）
  BodyFixed // CL 定长计数消费
  ChunkSizeLine // 大小行行缓冲（≤ max_size_line_bytes）
  ChunkData // 数据块按剩余计数消费
  ChunkDataCrlf // 数据块后期待 CR
  ChunkDataLf // CR 后期待 LF
  Trailer // 0 长度块后找 CRLFCRLF
}

///|
// 增量帧扫描状态机：feed 是 (state, 字节) → state 的纯推进，每字节恰好
// 处理一次（摊还 O(1)，FR-010）；终态（Done/Failed）后 feed 幂等返回同
// 信号。不改动、不丢弃任何字节（FR-005——字节留存是调用方 raw 缓冲的
// 职责）。
priv struct FrameScanner {
  mut st : ScanState
  mut crlf_progress : Int32 // Head/Trailer 的 CRLFCRLF 匹配进度（0..4）
  head_buf : Buffer // 头部字节累计（完成后一次解析）
  mut head_count : Int32 // Head 态字节计数（max_head_bytes 上界）
  mut head_end : Int32? // 头部区终点（完成后快照，供 EOF/Failed 兜底）
  payload : Buffer // 重组负载累计
  mut remaining : Int32 // BodyFixed / ChunkData 剩余计数
  mut line_buf : Buffer // 大小行行缓冲
  mut line_len : Int32 // 行缓冲字节数（max_size_line_bytes 上界）
  mut trailer_count : Int32 // Trailer 态字节计数（防无限累加，FR-014）
  mut terminal : Signal? // 终态信号缓存（feed 幂等）
}

///|
fn FrameScanner::new() -> FrameScanner {
  {
    st: Head,
    crlf_progress: 0,
    head_buf: Buffer(),
    head_count: 0,
    head_end: None,
    payload: Buffer(),
    remaining: 0,
    line_buf: Buffer(),
    line_len: 0,
    trailer_count: 0,
    terminal: None,
  }
}

///|
// 头部区终点快照：头完成后为 Some；Head 态未完成（EOF/超时兜底）为 None。
fn FrameScanner::head_end_hint(self : FrameScanner) -> Int32? {
  self.head_end
}

///|
// 喂入一片字节，返回当前信号。终态后幂等。
fn FrameScanner::feed(self : FrameScanner, bytes : BytesView) -> Signal? {
  match self.terminal {
    Some(sig) => return Some(sig)
    None => ()
  }
  let len = bytes.length()
  let mut i = 0
  while i < len {
    match self.step(bytes[i]) {
      None => i = i + 1
      Some(sig) => {
        self.terminal = Some(sig)
        return Some(sig)
      }
    }
  }
  None
}

///|
// 单字节推进：唯一的状态转移入口（每字节恰好处理一次）。返回 Pending
// 表示尚需更多字节；返回 Done/Failed 即终态。
fn FrameScanner::step(self : FrameScanner, b : Byte) -> Signal? {
  match self.st {
    Head => self.step_head(b)
    BodyFixed => {
      self.payload.write_byte(b)
      self.remaining = self.remaining - 1
      if self.remaining == 0 {
        self.finish(false)
      } else {
        None
      }
    }
    ChunkSizeLine => self.step_size_line(b)
    ChunkData => {
      self.payload.write_byte(b)
      self.remaining = self.remaining - 1
      if self.remaining == 0 {
        self.st = ChunkDataCrlf
      }
      None
    }
    ChunkDataCrlf =>
      if b == cr {
        self.st = ChunkDataLf
        None
      } else {
        Some(Failed("chunk 数据块结尾非 CRLF"))
      }
    ChunkDataLf =>
      if b == lf {
        self.st = ChunkSizeLine
        self.line_buf = Buffer()
        self.line_len = 0
        None
      } else {
        Some(Failed("chunk 数据块结尾非 CRLF"))
      }
    Trailer => self.step_trailer(b)
  }
}

///|
// Head 态：字节进头缓冲，CRLFCRLF 进度机判定头部终点。进度机跨块无歧义
// （匹配进度 0..4，失配按模式前缀回退）。
fn FrameScanner::step_head(self : FrameScanner, b : Byte) -> Signal? {
  self.head_buf.write_byte(b)
  self.head_count = self.head_count + 1
  if self.head_count > max_head_bytes {
    return Some(Failed("头部超出上限仍未出现 CRLFCRLF"))
  }
  // CRLFCRLF 进度转移（模式 P = CR LF CR LF）
  self.crlf_progress = match (self.crlf_progress, b) {
    (0, x) => if x == cr { 1 } else { 0 }
    (1, x) => if x == lf { 2 } else if x == cr { 1 } else { 0 }
    (2, x) => if x == cr { 3 } else { 0 }
    (3, x) => if x == lf { 4 } else if x == cr { 1 } else { 0 }
    (_, _) => 0
  }
  if self.crlf_progress == 4 {
    // 头部终点：已读 N 字节含 CRLFCRLF，头部区 [0, N-2)
    let n : Int32 = self.head_count
    let head_end = n - 2
    self.head_end = Some(head_end)
    self.resolve_head(self.head_buf.to_bytes(), head_end)
  } else {
    None
  }
}

///|
// Trailer 态：找 CRLFCRLF 收尾；字节计数受 max_head_bytes（防无限累加，
// FR-014）。
fn FrameScanner::step_trailer(self : FrameScanner, b : Byte) -> Signal? {
  self.trailer_count = self.trailer_count + 1
  if self.trailer_count > max_head_bytes {
    return Some(Failed("trailer 超出上限仍未出现 CRLFCRLF"))
  }
  self.crlf_progress = match (self.crlf_progress, b) {
    (0, x) => if x == cr { 1 } else { 0 }
    (1, x) => if x == lf { 2 } else if x == cr { 1 } else { 0 }
    (2, x) => if x == cr { 3 } else { 0 }
    (3, x) => if x == lf { 4 } else if x == cr { 1 } else { 0 }
    (_, _) => 0
  }
  if self.crlf_progress == 4 {
    self.finish(true)
  } else {
    None
  }
}

///|
// ChunkSizeLine 态：字节进行缓冲，LF 结行；行缓冲受 max_size_line_bytes
// （FR-006 判定支点：大小行自身长度上界，与流内绝对偏移无关）。
fn FrameScanner::step_size_line(self : FrameScanner, b : Byte) -> Signal? {
  self.line_buf.write_byte(b)
  self.line_len = self.line_len + 1
  if self.line_len > max_size_line_bytes {
    return Some(Failed("chunk 大小行超出自身长度上限"))
  }
  if b != lf {
    return None
  }
  // 行完：去尾 CRLF 后解析（';' 之后为 chunk-ext，忽略）
  let line = self.line_buf.to_bytes()
  let line_len = line.length()
  if line_len < 2 {
    return Some(Failed("chunk 大小行非十六进制"))
  }
  let content_end = line_len - 2
  let size_end = match index_of_byte(line, 0, content_end, b';') {
    Some(s) => s
    None => content_end
  }
  match parse_hex(line, 0, size_end) {
    Bad => Some(Failed("chunk 大小行非十六进制"))
    // FR-007 封顶累加：单块即超上限在累加途中即时出现（回绕不可能）
    Overflow => Some(Failed("chunk 超出夹具上限"))
    Num(0) => {
      // 0 长度块：trailer 区以 CRLFCRLF 收尾。0 行自身的 CRLF 即 CRLFCRLF
      // 的前半（现行语义「自 idx 含本行 CRLF 起找空行」同构），故进度预设
      // 为 2，后续字节从已匹配 \r\n 起步
      self.st = Trailer
      self.crlf_progress = 2
      self.trailer_count = 0
      None
    }
    Num(size) =>
      // 累计负载约束：封顶累加已保证单块 ≤ 上限，此处只查「累计」不超
      if size > max_body_bytes - self.payload.length() {
        Some(Failed("chunk 累计负载超出夹具上限"))
      } else {
        self.remaining = size
        self.st = ChunkData
        None
      }
  }
}

///|
// 头部解析（完成后一次）：TE/CL 分派。chunked → 大小行态；TE 非 chunked →
// 如实拒绝；CL 十进制解析 + 上限检查（T019 将收紧为封顶累加）；重复 CL
// 语义在头解析处判定（T020 增量收紧）；无 CL 无 TE = 无体消息
// （send.mbt:252-258）。
fn FrameScanner::resolve_head(
  self : FrameScanner,
  head : Bytes,
  head_end : Int32,
) -> Signal? {
  let te = header_value(head, head_end, b"transfer-encoding")
  let cl = header_value(head, head_end, b"content-length")
  if te is Some((vs, ve)) && ci_contains(head, vs, ve, b"chunked") {
    self.st = ChunkSizeLine
    self.line_buf = Buffer()
    self.line_len = 0
    None
  } else if te is Some(_) {
    Some(Failed("Transfer-Encoding 非 chunked，夹具不判定该帧"))
  } else {
    match cl {
      Some((vs, ve)) =>
        match parse_decimal(head, vs, ve) {
          Bad => Some(Failed("Content-Length 值非十进制"))
          // FR-007 封顶累加：溢出在累加途中即时出现（回绕不可能）
          Overflow => Some(Failed("Content-Length 超出夹具上限"))
          Num(0) =>
            // CL:0：头部即整条消息（send.mbt:106 空体形态），不进入体消费态
            self.finish(false)
          Num(n) => {
            self.remaining = n
            self.st = BodyFixed
            None
          }
        }
      None => self.finish(false)
    }
  }
}

///|
// 终态收尾：负载一次成型（终态单次复制，FR-005/FR-010）。
fn FrameScanner::finish(self : FrameScanner, chunked : Bool) -> Signal? {
  let head_end = match self.head_end {
    Some(h) => h
    None => 0
  }
  let sig = Some(Done(head_end, self.payload.to_bytes(), chunked))
  self.terminal = sig
  sig
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
// 从 from 起查找空行 CRLFCRLF，返回首个 CR 的偏移（broken_early 兜底用）
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
// 只取首个同名行；无冒号的行跳过（T020 将收紧重复 CL 语义）。
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
// 数值解析结果（FR-007 封顶累加）：Num(n)＝未超上限的合法值；
// Overflow＝累加途中超过 max_body_bytes（即时判停依据）；Bad＝畸形
// （非数字/空）。回绕在构造上不可能：一旦超过上限立即返回，不再累加。
priv enum NumParse {
  Num(Int32)
  Overflow
  Bad
}

///|
// 十进制非负整数解析（封顶累加）：逐位累加，累加值一旦超过
// max_body_bytes 即时返回 Overflow——Int32 回绕在构造上不可能。
fn parse_decimal(buf : Bytes, start : Int32, end : Int32) -> NumParse {
  if start >= end {
    Bad
  } else {
    let mut acc : Int32 = 0
    let mut i = start
    let mut state : NumParse = Num(0)
    while i < end {
      let d = buf[i].to_int() - 0x30
      if d < 0 || d > 9 {
        state = Bad
        break
      } else {
        acc = acc * 10 + d
        if acc > max_body_bytes {
          state = Overflow
          break
        }
      }
      i = i + 1
    }
    match state {
      Num(0) => Num(acc)
      other => other
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
// 十六进制非负整数解析（chunk 大小行，封顶累加同 parse_decimal）
fn parse_hex(buf : Bytes, start : Int32, end : Int32) -> NumParse {
  if start >= end {
    Bad
  } else {
    let mut acc : Int32 = 0
    let mut i = start
    let mut state : NumParse = Num(0)
    while i < end {
      match hex_value(buf[i]) {
        None => {
          state = Bad
          break
        }
        Some(d) => {
          acc = acc * 16 + d
          if acc > max_body_bytes {
            state = Overflow
            break
          }
        }
      }
      i = i + 1
    }
    match state {
      Num(0) => Num(acc)
      other => other
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
