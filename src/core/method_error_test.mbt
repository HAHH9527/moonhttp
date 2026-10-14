///|
// method_error_test：Method 九值映射与两个错误枚举的可判别/输出面测试（T005）。
//
// SC-005 ② 断言载体在本文件：错误消息只携带定位片段、不整体回显原始输入。
// 本包错误变体均为无载荷单元变体（data-model §4），结构上不可能携带输入
// 回显——下面的占位串断言固化这一保证：无论触发输入为何（超长或含敏感
// 样式），debug 输出只出现变体名。
// 敏感样例值纪律（R3-M1 → spec A8）：只使用明显合成的占位串。
test "Method 九值与 @http.RequestMethod 双向映射往返穷举" {
  let methods : Array[@core.Method] = [
    @core.Method::Get,
    @core.Method::Post,
    @core.Method::Put,
    @core.Method::Delete,
    @core.Method::Head,
    @core.Method::Options,
    @core.Method::Trace,
    @core.Method::Patch,
    @core.Method::Connect,
  ]
  assert_eq(methods.length(), 9)
  for m in methods {
    // FR-007：封闭映射，无失败分支，往返必须还原
    assert_eq(@core.Method::from_request_method(m.to_request_method()), m)
  }
  // 反向穷举：上游九值逐一映射回本包 Method 后再往返
  let upstream : Array[@http.RequestMethod] = [
    @http.RequestMethod::Get,
    @http.RequestMethod::Head,
    @http.RequestMethod::Post,
    @http.RequestMethod::Put,
    @http.RequestMethod::Delete,
    @http.RequestMethod::Connect,
    @http.RequestMethod::Options,
    @http.RequestMethod::Trace,
    @http.RequestMethod::Patch,
  ]
  assert_eq(upstream.length(), 9)
  for u in upstream {
    let m = @core.Method::from_request_method(u)
    assert_eq(m.to_request_method(), u)
  }
}

///|
test "Method 判等与哈希可用（derive + pub extend 口径）" {
  // Eq/Hash/Debug 经显式 pub extend 以方法形态可用（决策 N1-A），供 P02/P04 组合
  assert_true(@core.Method::Get.equal(@core.Method::Get))
  assert_true(@core.Method::Get.not_equal(@core.Method::Post))
  assert_eq(@core.Method::Get.hash(), @core.Method::Get.hash())
  ignore(@core.Method::Get.to_repr())
}

///|
test "HttpUrlError 四变体可判别（is 风格，错误不判等）" {
  let invalid_host : @core.HttpUrlError = @core.HttpUrlError::InvalidHost
  let invalid_port : @core.HttpUrlError = @core.HttpUrlError::InvalidPort
  let malformed : @core.HttpUrlError = @core.HttpUrlError::MalformedUrl
  let unsupported : @core.HttpUrlError = @core.HttpUrlError::UnsupportedScheme
  assert_true(invalid_host is @core.HttpUrlError::InvalidHost)
  assert_true(invalid_port is @core.HttpUrlError::InvalidPort)
  assert_true(malformed is @core.HttpUrlError::MalformedUrl)
  assert_true(unsupported is @core.HttpUrlError::UnsupportedScheme)
  // 变体间可区分
  assert_false(invalid_host is @core.HttpUrlError::InvalidPort)
  assert_false(malformed is @core.HttpUrlError::UnsupportedScheme)
}

///|
test "HeadersError 两变体可判别（is 风格，错误不判等）" {
  let invalid_name : @core.HeadersError = @core.HeadersError::InvalidName
  let invalid_value : @core.HeadersError = @core.HeadersError::InvalidValue
  assert_true(invalid_name is @core.HeadersError::InvalidName)
  assert_true(invalid_value is @core.HeadersError::InvalidValue)
  assert_false(invalid_name is @core.HeadersError::InvalidValue)
}

///|
test "HttpUrlError debug 输出形态：仅变体名，不回显任何触发输入（SC-005 ②）" {
  // 以超长、含敏感样式（明显合成占位串）的触发输入构造的上下文，
  // 断言错误 debug 输出不包含该输入的整体回显。
  let long_sensitive_input = "http://user%3Apass%40example.com/a/very/long/path?token=Bearer test-token-123&secret=not-a-real-secret"
  let pairs : Array[(@core.HttpUrlError, String)] = [
    (@core.HttpUrlError::InvalidHost, "InvalidHost"),
    (@core.HttpUrlError::InvalidPort, "InvalidPort"),
    (@core.HttpUrlError::MalformedUrl, "MalformedUrl"),
    (@core.HttpUrlError::UnsupportedScheme, "UnsupportedScheme"),
  ]
  for (e, expected) in pairs {
    let repr = Repr::Repr(e).to_string()
    // 输出形态＝变体名（无载荷、无类型前缀、无任何输入回显）
    assert_eq(repr, expected)
    assert_false(repr.contains(long_sensitive_input))
    assert_false(repr.contains("test-token-123"))
    assert_false(repr.contains("not-a-real-secret"))
  }
  // 快照锚点（SC-005 ② 判据的可见形态）
  debug_inspect(@core.HttpUrlError::InvalidHost, content="InvalidHost")
  debug_inspect(@core.HttpUrlError::InvalidPort, content="InvalidPort")
  debug_inspect(@core.HttpUrlError::MalformedUrl, content="MalformedUrl")
  debug_inspect(
    @core.HttpUrlError::UnsupportedScheme,
    content="UnsupportedScheme",
  )
}

///|
test "HeadersError debug 输出形态：仅变体名，不回显任何触发输入（SC-005 ②）" {
  let bad_name_input = "Bad Name: a"
  let bad_value_input = "a\r\nY: 1"
  let pairs : Array[(@core.HeadersError, String)] = [
    (@core.HeadersError::InvalidName, "InvalidName"),
    (@core.HeadersError::InvalidValue, "InvalidValue"),
  ]
  for (e, expected) in pairs {
    let repr = Repr::Repr(e).to_string()
    assert_eq(repr, expected)
    assert_false(repr.contains(bad_name_input))
    assert_false(repr.contains(bad_value_input))
  }
  debug_inspect(@core.HeadersError::InvalidName, content="InvalidName")
  debug_inspect(@core.HeadersError::InvalidValue, content="InvalidValue")
}
