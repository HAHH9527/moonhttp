///|
// http_url_resolve_test：相对引用解析 resolve 的黑盒测试（T011）。
//
// 用例来源：
//  1. spec US-2 验收场景与 contracts/http-url.md 锚点表（含决策 L6-A 的
//     三条补充锚点：query-only / 仅 fragment / base 无 path）；
//  2. OkHttp 5.5.0 HttpUrlTest（Apache-2.0）resolve 组移植：
//     rfc3886NormalExamples / rfc3886AbnormalExamples（RFC 3986 §5.4）/
//     resolveNoScheme / resolveUnsupportedScheme / resolveSchemeLikePath /
//     relativePath / relativePathWithTrailingSlash / pathWithBackslash /
//     relativePathWithSameScheme。
//     差异：OkHttp 对不可解析 location 返回 null，本包 raise 可判别的
//     HttpUrlError（spec US-2 场景 3），断言按错误变体改写。
//
// 敏感样例值纪律（R3-M1 → spec A8）：只用合成占位串，禁真实凭证。

///|
// 黑盒辅助：断言 resolve(base, location) == parse(expected)
fn expect_resolve(
  base : String,
  location : String,
  expected : String,
) -> Unit raise {
  let b = @core.HttpUrl::parse(base)
  let want = @core.HttpUrl::parse(expected)
  assert_eq(@core.HttpUrl::resolve(b, location), want)
}

///|
// 黑盒辅助：断言 resolve 必 raise 且错误满足判别谓词
fn expect_resolve_error(
  base : String,
  location : String,
  check : (@core.HttpUrlError) -> Bool,
) -> Unit raise {
  let b = @core.HttpUrl::parse(base)
  try @core.HttpUrl::resolve(b, location) catch {
    e => assert_true(check(e))
  } noraise {
    _ => fail("应当 raise HttpUrlError：\{location}")
  }
}

///|
test "US-2 场景1：base + 相对引用 ../up" {
  expect_resolve("http://a.com/dir/page", "../up", "http://a.com/up")
}

///|
test "US-2 场景2：绝对路径 /root 与网络路径 //b.com/x" {
  expect_resolve("http://a.com/dir/page", "/root", "http://a.com/root")
  // scheme 自 base 继承
  expect_resolve("http://a.com/dir/page", "//b.com/x", "http://b.com/x")
  expect_resolve("https://a.com/dir/page", "//b.com/x", "https://b.com/x")
}

///|
test "US-2 场景2 补充：绝对 location 直接解析" {
  expect_resolve(
    "http://a.com/dir/page", "https://other.com/y?z=1", "https://other.com/y?z=1",
  )
  expect_resolve("http://a.com/dir/page", "http://c.com/", "http://c.com/")
}

///|
test "US-2 场景2 补充：空 location → base 去 fragment（对齐 OkHttp）" {
  expect_resolve("http://a.com/dir/page#frag", "", "http://a.com/dir/page")
  expect_resolve("http://a.com/dir/page?x=1#f", "", "http://a.com/dir/page?x=1")
}

///|
test "US-2 场景3：非法 location raise 可判别 HttpUrlError" {
  expect_resolve_error("http://a.com/", "ftp://b/", e => {
    e is @core.HttpUrlError::UnsupportedScheme
  })
  expect_resolve_error("http://a.com/", "http://[::1", e => {
    e is @core.HttpUrlError::InvalidHost
  })
  expect_resolve_error("http://a.com/", "http://h:notaport/", e => {
    e is @core.HttpUrlError::InvalidPort
  })
}

///|
test "L6-A 锚点1：query-only 参考（fragment 丢弃）" {
  expect_resolve("http://a.com/dir/page#f", "?x=1", "http://a.com/dir/page?x=1")
  expect_resolve("http://a.com/dir/page", "?x=1", "http://a.com/dir/page?x=1")
}

///|
test "L6-A 锚点2：仅 fragment 参考（path/query 保持）" {
  expect_resolve("http://a.com/dir/page", "#f", "http://a.com/dir/page#f")
  expect_resolve(
    "http://a.com/dir/page?x=1", "#f", "http://a.com/dir/page?x=1#f",
  )
}

///|
test "L6-A 锚点3：base 无 path（http://a.com + ../up）" {
  expect_resolve("http://a.com", "../up", "http://a.com/up")
  expect_resolve("http://a.com/", "../up", "http://a.com/up")
  expect_resolve("http://a.com", "up", "http://a.com/up")
}

///|
test "移植：rfc3886NormalExamples（OkHttp，RFC 3986 §5.4.1）" {
  // base "http://a/b/c/d;p?q"；"g:h" 在本包为 UnsupportedScheme（OkHttp 为 null）
  expect_resolve_error("http://a/b/c/d;p?q", "g:h", e => {
    e is @core.HttpUrlError::UnsupportedScheme
  })
  expect_resolve("http://a/b/c/d;p?q", "g", "http://a/b/c/g")
  expect_resolve("http://a/b/c/d;p?q", "./g", "http://a/b/c/g")
  expect_resolve("http://a/b/c/d;p?q", "g/", "http://a/b/c/g/")
  expect_resolve("http://a/b/c/d;p?q", "/g", "http://a/g")
  expect_resolve("http://a/b/c/d;p?q", "//g", "http://g/")
  expect_resolve("http://a/b/c/d;p?q", "?y", "http://a/b/c/d;p?y")
  expect_resolve("http://a/b/c/d;p?q", "g?y", "http://a/b/c/g?y")
  expect_resolve("http://a/b/c/d;p?q", "#s", "http://a/b/c/d;p?q#s")
  expect_resolve("http://a/b/c/d;p?q", "g#s", "http://a/b/c/g#s")
  expect_resolve("http://a/b/c/d;p?q", "g?y#s", "http://a/b/c/g?y#s")
  expect_resolve("http://a/b/c/d;p?q", ";x", "http://a/b/c/;x")
  expect_resolve("http://a/b/c/d;p?q", "g;x", "http://a/b/c/g;x")
  expect_resolve("http://a/b/c/d;p?q", "g;x?y#s", "http://a/b/c/g;x?y#s")
  expect_resolve("http://a/b/c/d;p?q", "", "http://a/b/c/d;p?q")
  expect_resolve("http://a/b/c/d;p?q", ".", "http://a/b/c/")
  expect_resolve("http://a/b/c/d;p?q", "./", "http://a/b/c/")
  expect_resolve("http://a/b/c/d;p?q", "..", "http://a/b/")
  expect_resolve("http://a/b/c/d;p?q", "../", "http://a/b/")
  expect_resolve("http://a/b/c/d;p?q", "../g", "http://a/b/g")
  expect_resolve("http://a/b/c/d;p?q", "../..", "http://a/")
  expect_resolve("http://a/b/c/d;p?q", "../../", "http://a/")
  expect_resolve("http://a/b/c/d;p?q", "../../g", "http://a/g")
}

///|
test "移植：rfc3886AbnormalExamples（OkHttp，RFC 3986 §5.4.2）" {
  expect_resolve("http://a/b/c/d;p?q", "../../../g", "http://a/g")
  expect_resolve("http://a/b/c/d;p?q", "../../../../g", "http://a/g")
  expect_resolve("http://a/b/c/d;p?q", "/./g", "http://a/g")
  expect_resolve("http://a/b/c/d;p?q", "/../g", "http://a/g")
  expect_resolve("http://a/b/c/d;p?q", "g.", "http://a/b/c/g.")
  expect_resolve("http://a/b/c/d;p?q", ".g", "http://a/b/c/.g")
  expect_resolve("http://a/b/c/d;p?q", "g..", "http://a/b/c/g..")
  expect_resolve("http://a/b/c/d;p?q", "..g", "http://a/b/c/..g")
  expect_resolve("http://a/b/c/d;p?q", "./../g", "http://a/b/g")
  expect_resolve("http://a/b/c/d;p?q", "./g/.", "http://a/b/c/g/")
  expect_resolve("http://a/b/c/d;p?q", "g/./h", "http://a/b/c/g/h")
  expect_resolve("http://a/b/c/d;p?q", "g/../h", "http://a/b/c/h")
  expect_resolve("http://a/b/c/d;p?q", "g;x=1/./y", "http://a/b/c/g;x=1/y")
  expect_resolve("http://a/b/c/d;p?q", "g;x=1/../y", "http://a/b/c/y")
  expect_resolve("http://a/b/c/d;p?q", "g?y/./x", "http://a/b/c/g?y/./x")
  expect_resolve("http://a/b/c/d;p?q", "g?y/../x", "http://a/b/c/g?y/../x")
  expect_resolve("http://a/b/c/d;p?q", "g#s/./x", "http://a/b/c/g#s/./x")
  expect_resolve("http://a/b/c/d;p?q", "g#s/../x", "http://a/b/c/g#s/../x")
  // 同 scheme 无 authority 形式按相对引用处理（OkHttp/WHATWG 口径）
  expect_resolve("http://a/b/c/d;p?q", "http:g", "http://a/b/c/g")
}

///|
test "移植：resolveNoScheme（OkHttp）" {
  expect_resolve("http://host/a/b", "//host2", "http://host2/")
  expect_resolve("http://host/a/b", "/path", "http://host/path")
  expect_resolve("http://host/a/b", "path", "http://host/a/path")
  expect_resolve("http://host/a/b", "?query", "http://host/a/b?query")
  expect_resolve("http://host/a/b", "#fragment", "http://host/a/b#fragment")
  expect_resolve("http://host/a/b", "", "http://host/a/b")
  expect_resolve("http://host/a/b", "\\path", "http://host/path")
}

///|
test "移植：resolveUnsupportedScheme（OkHttp；null → raise UnsupportedScheme）" {
  expect_resolve_error("http://a/", "ftp://b", e => {
    e is @core.HttpUrlError::UnsupportedScheme
  })
  expect_resolve_error("http://a/", "ht+tp://b", e => {
    e is @core.HttpUrlError::UnsupportedScheme
  })
  expect_resolve_error("http://a/", "ht-tp://b", e => {
    e is @core.HttpUrlError::UnsupportedScheme
  })
  expect_resolve_error("http://a/", "ht.tp://b", e => {
    e is @core.HttpUrlError::UnsupportedScheme
  })
}

///|
test "移植：resolveSchemeLikePath（OkHttp）——无冒号前缀形似 scheme 的路径" {
  expect_resolve("http://a/", "http//b/", "http://a/http//b/")
  expect_resolve("http://a/", "ht+tp//b/", "http://a/ht+tp//b/")
  expect_resolve("http://a/", "ht-tp//b/", "http://a/ht-tp//b/")
  expect_resolve("http://a/", "ht.tp//b/", "http://a/ht.tp//b/")
}

///|
test "移植：relativePath（OkHttp，含 %2e 点段变体）" {
  expect_resolve("http://host/a/b/c", "d/e/f", "http://host/a/b/d/e/f")
  expect_resolve("http://host/a/b/c", "../../d/e/f", "http://host/d/e/f")
  expect_resolve("http://host/a/b/c", "..", "http://host/a/")
  expect_resolve("http://host/a/b/c", "../..", "http://host/")
  expect_resolve("http://host/a/b/c", "../../..", "http://host/")
  expect_resolve("http://host/a/b/c", ".", "http://host/a/b/")
  expect_resolve("http://host/a/b/c", "././..", "http://host/a/")
  expect_resolve("http://host/a/b/c", "c/d/../e/../", "http://host/a/b/c/")
  expect_resolve("http://host/a/b/c", "..e/", "http://host/a/b/..e/")
  expect_resolve("http://host/a/b/c", "e/f../", "http://host/a/b/e/f../")
  // %2e 变体在解码后判定为点段（与 OkHttp isDotDot 集合等价）
  expect_resolve("http://host/a/b/c", "%2E.", "http://host/a/")
  expect_resolve("http://host/a/b/c", ".%2E", "http://host/a/")
  expect_resolve("http://host/a/b/c", "%2E%2E", "http://host/a/")
  expect_resolve("http://host/a/b/c", "%2e.", "http://host/a/")
  expect_resolve("http://host/a/b/c", ".%2e", "http://host/a/")
  expect_resolve("http://host/a/b/c", "%2e%2e", "http://host/a/")
  expect_resolve("http://host/a/b/c", "%2E", "http://host/a/b/")
  expect_resolve("http://host/a/b/c", "%2e", "http://host/a/b/")
}

///|
test "移植：relativePathWithTrailingSlash（OkHttp）" {
  expect_resolve("http://host/a/b/c/", "..", "http://host/a/b/")
  expect_resolve("http://host/a/b/c/", "../", "http://host/a/b/")
  expect_resolve("http://host/a/b/c/", "../..", "http://host/a/")
  expect_resolve("http://host/a/b/c/", "../../", "http://host/a/")
  expect_resolve("http://host/a/b/c/", "../../..", "http://host/")
  expect_resolve("http://host/a/b/c/", "../../../", "http://host/")
  expect_resolve("http://host/a/b/c/", "../../../..", "http://host/")
  expect_resolve("http://host/a/b/c/", "../../../../", "http://host/")
  expect_resolve("http://host/a/b/c/", "../../../../a", "http://host/a")
  expect_resolve("http://host/a/b/c/", "../../../../a/..", "http://host/")
  expect_resolve("http://host/a/b/c/", "../../../../a/b/..", "http://host/a/")
}

///|
test "移植：pathWithBackslash（OkHttp）——反斜杠等价于分隔符" {
  expect_resolve("http://host/a/b/c", "d\\e\\f", "http://host/a/b/d/e/f")
  expect_resolve("http://host/a/b/c", "../..\\d\\e\\f", "http://host/d/e/f")
  expect_resolve("http://host/a/b/c", "..\\..", "http://host/")
}

///|
test "移植：relativePathWithSameScheme（OkHttp）" {
  expect_resolve("http://host/a/b/c", "http:d/e/f", "http://host/a/b/d/e/f")
  expect_resolve("http://host/a/b/c", "http:../../d/e/f", "http://host/d/e/f")
}

///|
test "移植：parseTrimsAsciiWhitespace 的 resolve 侧（OkHttp）" {
  expect_resolve("http://host/", "   ", "http://host/")
  expect_resolve("http://host/", "  .  ", "http://host/")
}

///|
test "resolve 复用 base 的 authority：port/host/scheme 继承（FR-002）" {
  let base = @core.HttpUrl::parse("https://Example.ORG:8443/base/dir")
  let r = @core.HttpUrl::resolve(base, "sib")
  assert_eq(r.scheme(), @http.Protocol::Https)
  assert_eq(r.host(), "example.org")
  assert_eq(r.port(), 8443)
  assert_eq(r.to_string(), "https://example.org:8443/base/sib")
}
