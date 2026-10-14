///|
// http_url：HttpUrl 值、解析、规范化序列化（spec US-1，FR-001/002/003/009/010）。
//
// 行为基准：OkHttp 5.5.0 HttpUrl（Apache-2.0）+ RFC 3986/9110；与 OkHttp 的
// 裁决差异见 spec A6（userinfo 拒绝、IPv6 逐字存储不做压缩规范化、fragment
// 编码集取 query 口径等在测试文件头与 T017 清单显式记录）。
//
// 存储不变量（data-model §1）：
//   - scheme 复用上游 @http.Protocol（N2-A：本包不自立枚举、不重复默认端口）
//   - host 已 percent-decode、ASCII、小写；IPv6 剥方括号逐字存储（含 ':' 与
//     可选 zone-id，不解码 %25）；末尾点保留
//   - port 为生效端口（1..=65535，缺省填 scheme 默认值）；等于默认端口时
//     to_string 省略
//   - path_segments 为解码后形态：不含 "." / ".."（解析时消解）、不含内部
//     空段；末元素 "" 表示尾随斜杠；[""] 表示根路径（对齐 OkHttp 表示法）
//   - query/fragment 保留 encoded 形态（合法 %XX 不二次编码）；None 与空串
//     可区分
pub struct HttpUrl {
  scheme : @http.Protocol
  host : String
  port : Int32
  path_segments : Array[String]
  query : String?
  fragment : String?
} derive(Eq, Hash, Debug)

///|
// 消除 implicit_impl_as_method 警告 [0079] 的配套写法（决策 N1-A，research R4）
pub extend HttpUrl with Eq::{equal, not_equal}

///|
pub extend HttpUrl with Hash::{hash, hash_combine}

///|
pub extend HttpUrl with Debug::{to_repr}

///|
// scheme 后的斜杠/反斜杠连续计数（对齐 OkHttp slashCount：两者等价）
fn count_slashes(s : String, from : Int32, until : Int32) -> Int32 {
  let mut n = 0
  let mut i = from
  while i < until {
    let c = s[i]
    if c == '/' || c == '\\' {
      n += 1
      i += 1
    } else {
      break
    }
  }
  n
}

///|
// 首个非 ASCII 空白位置（\t \n \f \r 空格；\v 不在裁剪集，对齐 OkHttp）
fn first_non_ws(s : String) -> Int32 {
  let len = s.length()
  let mut i = 0
  while i < len {
    let c = s[i]
    if c == '\t' || c == '\n' || c == '\u{c}' || c == '\r' || c == ' ' {
      i += 1
    } else {
      break
    }
  }
  i
}

///|
// 最后一个非 ASCII 空白之后的位置
fn last_non_ws(s : String, from : Int32) -> Int32 {
  let mut i = s.length()
  while i > from {
    let c = s[i - 1]
    if c == '\t' || c == '\n' || c == '\u{c}' || c == '\r' || c == ' ' {
      i -= 1
    } else {
      break
    }
  }
  i
}

///|
// scheme 分隔符位置：[a-zA-Z][a-zA-Z0-9+.-]* 后紧跟 ':'；无则 -1
fn scheme_delimiter_offset(s : String, from : Int32, until : Int32) -> Int32 {
  if from >= until {
    return -1
  }
  let first = s[from].to_int()
  let is_alpha = (first >= 0x41 && first <= 0x5a) ||
    (first >= 0x61 && first <= 0x7a)
  if !is_alpha {
    return -1
  }
  let mut i = from + 1
  while i < until {
    let c = s[i]
    if c == ':' {
      return i
    }
    let n = c.to_int()
    let ok = (n >= 0x41 && n <= 0x5a) ||
      (n >= 0x61 && n <= 0x7a) ||
      (n >= 0x30 && n <= 0x39) ||
      c == '+' ||
      c == '-' ||
      c == '.'
    if !ok {
      return -1
    }
    i += 1
  }
  -1
}

///|
fn ascii_lowercase(s : String) -> String {
  let sb = StringBuilder()
  for c in s {
    sb.write_char(c.to_ascii_lowercase())
  }
  sb.to_string()
}

///|
// reg-name host 校验：percent-decode 后必须为 ASCII 且字符限于字母数字与 -._~
// （空格等 → InvalidHost；非 ASCII → InvalidHost，FR-003）
fn validate_regname_host(raw : String) -> String raise HttpUrlError {
  let decoded = percent_decode(raw)
  for c in decoded {
    let ok = if c.is_ascii_alphabetic() || c.is_ascii_digit() {
      true
    } else {
      c is ('-' | '.' | '_' | '~')
    }
    if !ok {
      raise HttpUrlError::InvalidHost
    }
  }
  ascii_lowercase(decoded)
}

///|
// IPv6 host 校验：剥括号后的内芯必须含 ':'，地址部分字符限于十六进制与 :.，
// zone-id（'%' 之后）保留原样（spec 边界用例；本包不做压缩规范化）
fn validate_ipv6_host(inner : String) -> String raise HttpUrlError {
  let lowered = ascii_lowercase(inner)
  let chars = lowered.to_array()
  let mut has_colon = false
  let mut in_zone = false
  for i in 0..<chars.length() {
    let c = chars[i]
    if in_zone {
      // zone-id：接口名形态（字母数字与 -._~）
      let ok = if c.is_ascii_alphabetic() || c.is_ascii_digit() {
        true
      } else {
        c is ('-' | '.' | '_' | '~')
      }
      if !ok {
        raise HttpUrlError::InvalidHost
      }
    } else if c == '%' {
      if i == 0 || i == chars.length() - 1 {
        raise HttpUrlError::InvalidHost
      }
      in_zone = true
    } else if c == ':' {
      has_colon = true
    } else if !c.is_ascii_hexdigit() && !(c is '.') {
      raise HttpUrlError::InvalidHost
    }
  }
  if !has_colon {
    raise HttpUrlError::InvalidHost
  }
  lowered
}

///|
// authority 的 host:port 切分与校验（括号感知）
fn split_authority(
  s : String,
  from : Int32,
  until : Int32,
) -> (String, String?) raise HttpUrlError {
  if from >= until {
    // authority 为空 → 缺 host
    raise HttpUrlError::MalformedUrl
  }
  let mut port_text : String? = None
  if s[from] == '[' {
    // IPv6 字面量：找配对 ']'；未闭合 / 多重括号 → InvalidHost
    let mut close = -1
    let mut i = from + 1
    while i < until {
      if s[i] == ']' {
        close = i
        break
      }
      if s[i] == '[' {
        raise HttpUrlError::InvalidHost
      }
      i += 1
    }
    if close == -1 {
      raise HttpUrlError::InvalidHost
    }
    let inner = s[from + 1:close].to_owned()
    if inner.contains("[") || inner.contains("]") {
      raise HttpUrlError::InvalidHost
    }
    // ']' 之后只能是空或 ":port"
    let rest_start = close + 1
    if rest_start < until {
      if s[rest_start] != ':' {
        raise HttpUrlError::InvalidHost
      }
      port_text = Some(s[rest_start + 1:until].to_owned())
    }
    (validate_ipv6_host(inner), port_text)
  } else {
    // reg-name：首个 ':' 为端口分隔符
    let mut colon = -1
    let mut i = from
    while i < until {
      if s[i] == ':' {
        colon = i
        break
      }
      i += 1
    }
    let host_raw = if colon == -1 {
      s[from:until].to_owned()
    } else {
      port_text = Some(s[colon + 1:until].to_owned())
      s[from:colon].to_owned()
    }
    if host_raw.length() == 0 {
      // 裸 IPv6（如 http://::1/）等：首个 ':' 前为空 → 缺 host
      raise HttpUrlError::MalformedUrl
    }
    (validate_regname_host(host_raw), port_text)
  }
}

///|
// 端口解析：空串 → 默认；非数字或越界（1..=65535 之外）→ InvalidPort（M1-A）
fn parse_port(
  port_text : String?,
  scheme : @http.Protocol,
) -> Int32 raise HttpUrlError {
  match port_text {
    None => scheme.default_port()
    Some("") => scheme.default_port()
    Some(text) => {
      let mut value = 0
      let mut overflow = false
      for c in text {
        if !c.is_ascii_digit() {
          raise HttpUrlError::InvalidPort
        }
        if !overflow {
          value = value * 10 + (c.to_int() - 0x30)
          if value > 65535 {
            overflow = true
          }
        }
      }
      if overflow || value < 1 {
        raise HttpUrlError::InvalidPort
      }
      value
    }
  }
}

///|
// 路径段推进（对齐 OkHttp Builder.push/pop 的段算法；点段判定在解码后进行，
// 与 OkHttp 的 isDot/isDotDot 集合（".", "%2e", "..", "%2e.", ".%2e",
// "%2e%2e"，忽略大小写）等价）："." 跳过；".." 弹出一段并保证尾随斜杠
fn push_path_segment(
  segs : Array[String],
  decoded : String,
  trailing : Bool,
) -> Unit {
  if decoded == "." {
    return
  }
  if decoded == ".." {
    // pop：删除一段；删除后保证末元素为 ""（尾随斜杠）
    if segs.length() > 0 {
      let removed = segs.remove(segs.length() - 1)
      if removed == "" && segs.length() > 0 {
        segs[segs.length() - 1] = ""
      } else {
        segs.push("")
      }
    } else {
      segs.push("")
    }
    return
  }
  let last = segs.length() - 1
  if segs[last] == "" {
    segs[last] = decoded
  } else {
    segs.push(decoded)
  }
  if trailing {
    segs.push("")
  }
}

///|
// 解析期路径处理：剥离段内 \t\n\f\r → 解码 → 点段消解（对齐 OkHttp resolvePath：
//'/' 与 '\' 均为段分隔符）
fn resolve_path(
  input : String,
  from : Int32,
  until : Int32,
  segs : Array[String],
) -> Unit {
  if from == until {
    return // 空路径：保持现状（绝对解析为根 [""]；相对继承 base）
  }
  let mut pos = from
  if input[pos] == '/' || input[pos] == '\\' {
    // 绝对路径：重置为根
    segs.clear()
    segs.push("")
    pos += 1
  } else {
    // 相对路径：截去 base 的最后一段
    segs[segs.length() - 1] = ""
  }
  let mut i = pos
  while i < until {
    // 找段边界
    let mut j = i
    while j < until {
      let c = input[j]
      if c == '/' || c == '\\' {
        break
      }
      j += 1
    }
    let has_trailing = j < until
    let raw = strip_component_ws(input[i:j].to_owned())
    push_path_segment(segs, percent_decode(raw), has_trailing)
    i = j + 1
  }
}

///|
// 剥离组件内 \t \n \f \r（对齐 OkHttp canonicalize 的 alreadyEncoded 分支）
fn strip_component_ws(s : String) -> String {
  let mut has = false
  for c in s {
    if is_stripped_ws(c) {
      has = true
      break
    }
  }
  if !has {
    return s
  }
  let sb = StringBuilder()
  for c in s {
    if !is_stripped_ws(c) {
      sb.write_char(c)
    }
  }
  sb.to_string()
}

///|
// 解析核心：base 为 None 时为绝对 parse；Some 时为 RFC 3986 §5 相对引用解析
// （对齐 OkHttp 的统一 parse(base, input) 算法：同 scheme 且斜杠数 < 2 的
// location 按相对引用处理，scheme 后任意斜杠数均进入 authority）
fn parse_with_base(
  base : HttpUrl?,
  input : String,
) -> HttpUrl raise HttpUrlError {
  let start = first_non_ws(input)
  let end = last_non_ws(input, start)
  if start >= end {
    if base is Some(b) {
      // 空 location：base 去 fragment（对齐 OkHttp）
      return { ..b, fragment: None, }
    }
    raise HttpUrlError::MalformedUrl
  }
  // ── scheme ──
  let delim = scheme_delimiter_offset(input, start, end)
  let (scheme, scheme_end) : (@http.Protocol, Int32) = if delim != -1 {
    let scheme_text = ascii_lowercase(input[start:delim].to_owned())
    if scheme_text == "http" {
      (@http.Protocol::Http, delim + 1)
    } else if scheme_text == "https" {
      (@http.Protocol::Https, delim + 1)
    } else {
      raise HttpUrlError::UnsupportedScheme
    }
  } else if base is Some(b) {
    (b.scheme, start)
  } else {
    raise HttpUrlError::MalformedUrl // 缺 scheme
  }
  let mut pos = scheme_end
  // ── authority ──
  let slashes = count_slashes(input, pos, end)
  let base_scheme_differs = match base {
    Some(b) => b.scheme != scheme
    None => true
  }
  let read_authority = slashes >= 2 || base_scheme_differs
  let mut host = ""
  let mut port = 0
  let segs : Array[String] = [""]
  let mut query : String? = None
  let mut query_from_base = false
  if read_authority {
    pos += slashes
    // authority 终于首个 @ / \ ? #
    let mut authority_end = pos
    while authority_end < end {
      let c = input[authority_end]
      if c == '@' || c == '/' || c == '\\' || c == '?' || c == '#' {
        break
      }
      authority_end += 1
    }
    // userinfo 显式拒绝（FR-008）：authority 区间终于首个 @ / \ ? #；
    // 终止符为 '@' 即存在 userinfo，一律 MalformedUrl
    if authority_end < end && input[authority_end] == '@' {
      raise HttpUrlError::MalformedUrl
    }
    let (h, port_text) = split_authority(input, pos, authority_end)
    host = h
    port = parse_port(port_text, scheme)
    pos = authority_end
  } else {
    // 相对引用：继承 base 的 authority 与 path；空 location 或以 '#' 开头时
    // 继承 base 的 query（对齐 OkHttp：pos == limit || input[pos] == '#'）
    let b : HttpUrl = match base {
      Some(b) => b
      // 不可达：read_authority 为假蕴含 base 存在且 scheme 相同
      None => raise HttpUrlError::MalformedUrl
    }
    host = b.host
    port = b.port
    segs.clear()
    for seg in b.path_segments {
      segs.push(seg)
    }
    if pos == end || input[pos] == '#' {
      query_from_base = true
    }
  }
  // ── path ──
  let mut path_end = pos
  while path_end < end {
    let c = input[path_end]
    if c == '?' || c == '#' {
      break
    }
    path_end += 1
  }
  resolve_path(input, pos, path_end, segs)
  pos = path_end
  // ── query ──
  if pos < end && input[pos] == '?' {
    let mut q_end = pos + 1
    while q_end < end {
      if input[q_end] == '#' {
        break
      }
      q_end += 1
    }
    query = Some(canonicalize_query(input[pos + 1:q_end].to_owned()))
    pos = q_end
  } else if query_from_base && base is Some(b) {
    query = b.query
  }
  // ── fragment ──
  let fragment : String? = if pos < end && input[pos] == '#' {
    Some(canonicalize_fragment(input[pos + 1:end].to_owned()))
  } else {
    None
  }
  { scheme, host, port, path_segments: segs, query, fragment, }
}

///|
/// 解析并规范化 URL；畸形输入 raise HttpUrlError，绝不 panic（FR-001）。
pub fn HttpUrl::parse(input : String) -> HttpUrl raise HttpUrlError {
  parse_with_base(None, input)
}

///|
/// 规范化序列化：parse 产物满足 parse(to_string(u)) == u（FR-001 往返幂等）。
/// 默认端口省略、小写 scheme/host、path 以 "/" 起始、None 不输出 "?"/"#"。
pub fn HttpUrl::to_string(self : HttpUrl) -> String {
  let sb = StringBuilder()
  match self.scheme {
    @http.Protocol::Http => sb.write_string("http://")
    @http.Protocol::Https => sb.write_string("https://")
  }
  if self.host.contains(":") {
    // IPv6：序列化时重新包上方括号
    sb.write_string("[")
    sb.write_string(self.host)
    sb.write_string("]")
  } else {
    sb.write_string(self.host)
  }
  if self.port != self.scheme.default_port() {
    sb.write_string(":\{self.port}")
  }
  for seg in self.path_segments {
    sb.write_string("/")
    sb.write_string(percent_encode_path_segment(seg))
  }
  match self.query {
    Some(q) => {
      sb.write_string("?")
      sb.write_string(q)
    }
    None => ()
  }
  match self.fragment {
    Some(f) => {
      sb.write_string("#")
      sb.write_string(f)
    }
    None => ()
  }
  sb.to_string()
}

///|
/// scheme 复用上游 @http.Protocol（决策 N2-A：本包不自立 Scheme 枚举）。
pub fn HttpUrl::scheme(self : HttpUrl) -> @http.Protocol {
  self.scheme
}

///|
/// host：已 decode、ASCII、小写；IPv6 已剥方括号（FR-010）。
pub fn HttpUrl::host(self : HttpUrl) -> String {
  self.host
}

///|
/// port：显式或默认，恒在 1..=65535（缺省为 scheme 默认端口，FR-002）。
pub fn HttpUrl::port(self : HttpUrl) -> Int32 {
  self.port
}

///|
/// path 段序列：已 percent-decode；末元素 "" 表示尾随斜杠；[""] 表示根路径。
/// 返回防御性副本（值不可变纪律：外部突变不影响判等/哈希）。
pub fn HttpUrl::path_segments(self : HttpUrl) -> Array[String] {
  let copy : Array[String] = []
  for seg in self.path_segments {
    copy.push(seg)
  }
  copy
}

///|
/// query：保留 encoded 形态（不二次编码）；None 与空串可区分。
pub fn HttpUrl::query(self : HttpUrl) -> String? {
  self.query
}

///|
/// fragment：同 query 口径；None（无 "#"）与空串（"#" 后为空）可区分。
pub fn HttpUrl::fragment(self : HttpUrl) -> String? {
  self.fragment
}
