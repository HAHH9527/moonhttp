///|
// percent_wbtest：percent 编解码白盒测试（T007，红阶段先行）。
// 编码集对齐 OkHttp 5.5.0（research R8）：
//   - path 段编码集：PATH_SEGMENT_ENCODE_SET = " \"<>^`{}|/\\?#"
//     （即 ASCII 可见字符中除 space " < > ^ ` { } | / \ ? # 外均允许）
//   - query/fragment 编码集：QUERY_ENCODE_SET = " \"'<>#"
//     （data-model：fragment 同 query 口径）
//   - 解码：合法 %XX 解码；孤立 % / 非法转义按字面量保留；
//     非法 UTF-8 序列以 U+FFFD 替换（对齐 OkHttp malformedUtf8Encoding）
// 来源：okhttp/src/commonJvmAndroid/kotlin/okhttp3/internal/url/-Url.kt
// （OkHttp 5.5.0，Apache-2.0）
test "percent_decode：合法 %XX 与 UTF-8 多字节序列" {
  assert_eq(percent_decode("a%20b"), "a b")
  assert_eq(percent_decode("%E4%B8%AD"), "中")
  assert_eq(percent_decode("%C2%A0"), " ")
  assert_eq(percent_decode("100%25"), "100%")
  assert_eq(percent_decode("a%2fb"), "a/b")
  // 大写十六进制同样解码
  assert_eq(percent_decode("%2F"), "/")
}

///|
test "percent_decode：非法转义与孤立 % 按字面量保留（对齐 OkHttp malformedPercentEncoding）" {
  assert_eq(percent_decode("a%f"), "a%f")
  assert_eq(percent_decode("%zz"), "%zz")
  assert_eq(percent_decode("%"), "%")
  assert_eq(percent_decode("%%30%30"), "%00")
  assert_eq(percent_decode("a%2"), "a%2")
}

///|
test "percent_decode：非法 UTF-8 序列以 U+FFFD 替换（maximal subpart）" {
  // OkHttp: parse("http://host/a/%E2%98x/c").pathSegments == ["a", "\ufffdx", "c"]
  assert_eq(percent_decode("%E2%98x"), "\u{fffd}x")
  assert_eq(percent_decode("%80"), "\u{fffd}")
  assert_eq(percent_decode("%FF%FF"), "\u{fffd}\u{fffd}")
  // 合法 4 字节序列（非 BMP）
  assert_eq(percent_decode("%F0%9F%98%80"), "😀")
}

///|
test "percent_decode：无转义串零行为（恒等）" {
  assert_eq(percent_decode("plain"), "plain")
  assert_eq(percent_decode(""), "")
}

///|
test "编码集判定：path 段（PATH_SEGMENT_ENCODE_SET 对拍）" {
  // 未列出的可打印 ASCII 一律允许（含 ! $ & ' ( ) * + , ; = @ - _ . ~ 等）
  for
    c in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~!$&'()*+,;=:@" {
    assert_true(is_path_segment_char(c))
  }
  // 编码集内字符一律拒绝
  for c in " \"<>^`{}|/\\?#" {
    assert_false(is_path_segment_char(c))
  }
  // 控制字符与 DEL 拒绝
  assert_false(is_path_segment_char('\t'))
  assert_false(is_path_segment_char('\n'))
  assert_false(is_path_segment_char('\u{0}'))
  assert_false(is_path_segment_char('\u{7f}'))
  // 非 ASCII 拒绝（路径按 UTF-8 百分号编码）
  assert_false(is_path_segment_char('中'))
  assert_false(is_path_segment_char('\u{a0}'))
}

///|
test "编码集判定：query/fragment（QUERY_ENCODE_SET 对拍）" {
  for
    c in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~!$&()*+,;=:@/?\\`[]{}|^" {
    assert_true(is_query_char(c))
  }
  for c in " \"'<>#" {
    assert_false(is_query_char(c))
  }
  assert_false(is_query_char('\t'))
  assert_false(is_query_char('\n'))
  assert_false(is_query_char('\u{1}'))
  assert_false(is_query_char('\u{7f}'))
  assert_false(is_query_char('中'))
}

///|
test "percent_encode_path_segment：解码后段重编码（to_string 载体）" {
  assert_eq(percent_encode_path_segment("a b"), "a%20b")
  assert_eq(percent_encode_path_segment("中"), "%E4%B8%AD")
  assert_eq(percent_encode_path_segment("a/b"), "a%2Fb")
  assert_eq(percent_encode_path_segment("a?b#c"), "a%3Fb%23c")
  assert_eq(percent_encode_path_segment("a\\b"), "a%5Cb")
  assert_eq(percent_encode_path_segment("a<b>c"), "a%3Cb%3Ec")
  assert_eq(percent_encode_path_segment("%"), "%25")
  // 允许字符原样保留（不二次编码的另一半：解码后形态重编码仍稳定）
  assert_eq(
    percent_encode_path_segment("a-b_c~!$&'()*+,;=:@x"),
    "a-b_c~!$&'()*+,;=:@x",
  )
  assert_eq(percent_encode_path_segment(""), "")
  // 大写十六进制输出（对齐 OkHttp HEX_DIGITS）
  assert_eq(percent_encode_path_segment("\u{0}"), "%00")
  assert_eq(percent_encode_path_segment("\u{7f}"), "%7F")
}

///|
test "canonicalize_query：既有 %XX 不二次编码、裸非法字符补编码（A2）" {
  // 合法 %XX 原样保留
  assert_eq(canonicalize_query("x=1%2B&x=1"), "x=1%2B&x=1")
  // 裸非法字符（编码集内）按 UTF-8 补编码
  assert_eq(canonicalize_query("a b"), "a%20b")
  assert_eq(canonicalize_query("a'b"), "a%27b")
  assert_eq(canonicalize_query("a<b>c"), "a%3Cb%3Ec")
  assert_eq(canonicalize_query("中"), "%E4%B8%AD")
  // 孤立 % 与非法转义原样保留（不视为需要补编码的裸非法字符——对齐 OkHttp
  // alreadyEncoded=true 且 strict=false 的解析期口径）
  assert_eq(canonicalize_query("100%zz"), "100%zz")
  assert_eq(canonicalize_query("100%"), "100%")
  // \t \n \f \r 在解析期被跳过（OkHttp writeCanonicalized 分支一）
  assert_eq(canonicalize_query("a\tb\nc\u{c}d\rd"), "abcdd")
  // 允许字符（含 ? / : @ & 等）原样保留
  assert_eq(canonicalize_query("a?b/c:d@e&f=g"), "a?b/c:d@e&f=g")
  // fragment 同 query 口径（data-model）
  assert_eq(canonicalize_fragment("a b'c"), "a%20b%27c")
  assert_eq(canonicalize_fragment("x%2Fy"), "x%2Fy")
}

///|
test "canonicalize_query：快路径恒等（无非法字符零改动）" {
  assert_eq(canonicalize_query("k=v&k2=v2"), "k=v&k2=v2")
  assert_eq(canonicalize_query(""), "")
}
