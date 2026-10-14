///|
// percent：百分号编解码与组件编码集（research R8）。
//
// 编码集对齐 OkHttp 5.5.0（okhttp/src/commonJvmAndroid/kotlin/okhttp3/internal/url/-Url.kt，
// Apache-2.0）：
//   - PATH_SEGMENT_ENCODE_SET = " \"<>^`{}|/\\?#"（路径段编码集）
//   - QUERY_ENCODE_SET        = " \"'<>#"（查询串编码集；fragment 同口径，
//     data-model §1）
// 解析期语义（对齐 OkHttp canonicalize，alreadyEncoded=true、strict=false）：
//   - 既有 %XX（含非法转义与孤立 %）原样保留，不二次编码；
//   - \t \n \f \r 在组件内被跳过（剥离）；
//   - 编码集内字符、控制字符、非 ASCII 按 UTF-8 补编码（十六进制大写）。
// 解码语义（对齐 OkHttp percentDecode）：合法 %XX 解码为字节，其余按字面量
// 保留；字节流按 UTF-8 解码，非法序列以 U+FFFD 替换（maximal subpart）。

///|
// ASCII 可见字符中不属于 PATH_SEGMENT_ENCODE_SET 的字符允许裸出现在路径段
fn is_path_segment_char(c : Char) -> Bool {
  if c.is_ascii() {
    let n = c.to_int()
    // 控制字符、DEL、空格，以及 " \"<>^`{}|/\\?#" 一律拒绝
    n >= 0x21 &&
    n <= 0x7e &&
    !(c
    is ('"' | '<' | '>' | '^' | '`' | '{' | '}' | '|' | '/' | '\\' | '?' | '#'))
  } else {
    false
  }
}

///|
// query/fragment 允许裸出现的字符：ASCII 可见字符中不属于 QUERY_ENCODE_SET 者
fn is_query_char(c : Char) -> Bool {
  if c.is_ascii() {
    let n = c.to_int()
    n >= 0x21 && n <= 0x7e && !(c is (' ' | '"' | '\'' | '<' | '>' | '#'))
  } else {
    false
  }
}

///|
// 解析期需剥离的 ASCII 空白（对齐 OkHttp alreadyEncoded 分支：\t \n \f \r；
// 注意 \v（0x0b）与首尾裁剪集相同但语义不同——组件内 \v 不剥离而是补编码）
fn is_stripped_ws(c : Char) -> Bool {
  c is ('\t' | '\n' | '\u{c}' | '\r')
}

///|
fn hex_digit_value(c : Char) -> Int32? {
  let n = c.to_int()
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
fn hex_char(v : Int32) -> Char {
  "0123456789ABCDEF".to_array()[v]
}

///|
// 码点按 UTF-8 编码追加到字节缓冲
fn push_utf8_bytes(out : Array[Byte], cp : Int32) -> Unit {
  if cp < 0x80 {
    out.push(cp.to_byte())
  } else if cp < 0x800 {
    out.push((0xc0 | (cp >> 6)).to_byte())
    out.push((0x80 | (cp & 0x3f)).to_byte())
  } else if cp < 0x10000 {
    out.push((0xe0 | (cp >> 12)).to_byte())
    out.push((0x80 | ((cp >> 6) & 0x3f)).to_byte())
    out.push((0x80 | (cp & 0x3f)).to_byte())
  } else {
    out.push((0xf0 | (cp >> 18)).to_byte())
    out.push((0x80 | ((cp >> 12) & 0x3f)).to_byte())
    out.push((0x80 | ((cp >> 6) & 0x3f)).to_byte())
    out.push((0x80 | (cp & 0x3f)).to_byte())
  }
}

///|
fn is_continuation(b : Byte) -> Bool {
  b >= b'\x80' && b <= b'\xbf'
}

///|
// 字节流按 UTF-8 解码为 String；非法序列以 U+FFFD 替换（maximal subpart：
// 消费该序列的合法前缀、产出一个替换符，从首个非法字节继续）
fn utf8_decode_lossy(bytes : Array[Byte]) -> String {
  let sb = StringBuilder()
  let len = bytes.length()
  let mut i = 0
  while i < len {
    let b = bytes[i]
    if b < b'\x80' {
      let cu = (b.to_int() & 0xff).to_char()
      match cu {
        Some(c) => sb.write_char(c)
        None => ()
      }
      i += 1
      continue
    }
    // 多字节序列：确定长度并校验后续 continuation 字节
    let (cp_base, need, min_cp) : (Int32, Int32, Int32) = if b >= b'\xc2' &&
      b <= b'\xdf' {
      (b.to_int() & 0x1f, 1, 0x80)
    } else if b >= b'\xe0' && b <= b'\xef' {
      (b.to_int() & 0x0f, 2, 0x800)
    } else if b >= b'\xf0' && b <= b'\xf4' {
      (b.to_int() & 0x07, 3, 0x10000)
    } else {
      // 非法首字节（0x80..0xC1、0xF5..0xFF）
      sb.write_char('\u{fffd}')
      i += 1
      continue
    }
    // 收集连续的合法前缀
    let mut cp = cp_base
    let mut consumed = 1
    while consumed <= need &&
          i + consumed < len &&
          is_continuation(bytes[i + consumed]) {
      cp = (cp << 6) | (bytes[i + consumed].to_int() & 0x3f)
      consumed += 1
    }
    if consumed == need + 1 &&
      cp >= min_cp &&
      !(cp >= 0xd800 && cp <= 0xdfff) &&
      cp <= 0x10ffff {
      match cp.to_char() {
        Some(c) => sb.write_char(c)
        None => sb.write_char('\u{fffd}')
      }
      i += consumed
    } else {
      // 前缀合法但序列不完整或码点非法：maximal subpart 替换
      sb.write_char('\u{fffd}')
      i += consumed
    }
  }
  sb.to_string()
}

///|
// 百分号解码：合法 %XX 解码为字节（连同裸字符的 UTF-8 编码一并进入字节流），
// 孤立 % / 非法转义按字面量保留。整体再按 UTF-8 还原为 String（容错 U+FFFD）。
fn percent_decode(s : String) -> String {
  let has_percent = {
    let mut found = false
    for c in s {
      if c == '%' {
        found = true
        break
      }
    }
    found
  }
  if !has_percent {
    return s
  }
  let bytes : Array[Byte] = []
  let chars = s.to_array()
  let len = chars.length()
  let mut i = 0
  while i < len {
    let c = chars[i]
    if c == '%' && i + 2 < len {
      match (hex_digit_value(chars[i + 1]), hex_digit_value(chars[i + 2])) {
        (Some(hi), Some(lo)) => {
          bytes.push(((hi << 4) | lo).to_byte())
          i += 3
          continue
        }
        _ => ()
      }
    }
    push_utf8_bytes(bytes, c.to_int())
    i += 1
  }
  utf8_decode_lossy(bytes)
}

///|
// 解码后的路径段重编码（to_string 载体）：不允许的字符按 UTF-8 补编码，
// 十六进制大写（对齐 OkHttp HEX_DIGITS）；解码形态中的裸 '%' 一律重编码为
// %25（它来自原始输入的 "%25"，round-trip 依赖这一点）
fn percent_encode_with(s : String, allowed : (Char) -> Bool) -> String {
  let mut needs = false
  for c in s {
    if c == '%' || !allowed(c) {
      needs = true
      break
    }
  }
  if !needs {
    return s
  }
  let sb = StringBuilder()
  for c in s {
    if c != '%' && allowed(c) {
      sb.write_char(c)
    } else {
      let bytes : Array[Byte] = []
      push_utf8_bytes(bytes, c.to_int())
      for b in bytes {
        let v = b.to_int() & 0xff
        sb.write_char('%')
        sb.write_char(hex_char(v >> 4))
        sb.write_char(hex_char(v & 0x0f))
      }
    }
  }
  sb.to_string()
}

///|
fn percent_encode_path_segment(s : String) -> String {
  percent_encode_with(s, is_path_segment_char)
}

///|
// query/fragment 解析期规范化：剥离 \t\n\f\r、既有 %XX（含非法转义）原样保留、
// 其余不在允许集内的字符按 UTF-8 补编码
fn canonicalize_component(s : String, allowed : (Char) -> Bool) -> String {
  let mut needs = false
  for c in s {
    if is_stripped_ws(c) || !allowed(c) {
      needs = true
      break
    }
  }
  if !needs {
    return s
  }
  let sb = StringBuilder()
  for c in s {
    if is_stripped_ws(c) {
      continue
    }
    if allowed(c) {
      sb.write_char(c)
    } else {
      let bytes : Array[Byte] = []
      push_utf8_bytes(bytes, c.to_int())
      for b in bytes {
        let v = b.to_int() & 0xff
        sb.write_char('%')
        sb.write_char(hex_char(v >> 4))
        sb.write_char(hex_char(v & 0x0f))
      }
    }
  }
  sb.to_string()
}

///|
fn canonicalize_query(s : String) -> String {
  canonicalize_component(s, is_query_char)
}

///|
// fragment 同 query 口径（data-model §1）
fn canonicalize_fragment(s : String) -> String {
  canonicalize_component(s, is_query_char)
}
