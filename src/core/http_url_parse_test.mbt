///|
// http_url_parse_test：HttpUrl 解析与规范化的黑盒测试（T006）。
//
// 用例来源：
//  1. spec US-1 验收场景 1–5 与 Edge Cases 的 URL 侧条目（specs/.../spec.md）；
//  2. OkHttp 5.5.0 HttpUrlTest（Apache-2.0）畸形输入组/规范化组/IPv6 组/
//     percent-encoding 组的移植（完整对拍清单见文件尾部 T017 固化的清单块）。
//
// 敏感样例值纪律（R3-M1 → spec A8）：只用合成占位串，禁真实凭证。

///|
// ============================================================================
// OkHttp 移植对拍清单（SC-002，research R9；T017 固化）
// 来源：OkHttp 5.5.0 HttpUrlTest（Apache-2.0）
// 对照文件：okhttp/src/jvmTest/kotlin/okhttp3/HttpUrlTest.kt（tag
// parent-5.5.0）；编码集对照 okhttp/src/commonJvmAndroid/kotlin/okhttp3/
// internal/url/-Url.kt
//
// 【移植组】
// 1. 畸形输入组：parseTrimsAsciiWhitespace（首尾裁剪子集）、
//    parseHostAsciiNonPrintable、hostContainsIllegalCharacter、
//    hostIpv6Malformed（[::g]）、端口越界/非数字（http://h:0/、
//    http://h:65536/、http://h:notaport/ 等；OkHttp 为抛异常/返回 null，
//    本包按四变体 raise 可判别 HttpUrlError，spec FR-009）
// 2. 规范化组：hostnameLowercase/Uppercase（ASCII 子集）、
//    trailingDotIsOkay、默认端口省略（80/443）、空路径规范化为 "/"、
//    parseAuthoritySlashCountDoesntMatter（子集：0–4 斜杠/反斜杠）、
//    pathWithBackslash（解析侧）、parseDoesNotTrimOtherWhitespaceCharacters
//    （子集：\u000b/\u0085/\u00a0/\u3000）
// 3. resolve 组（见 http_url_resolve_test.mbt）：rfc3886NormalExamples、
//    rfc3886AbnormalExamples（RFC 3986 §5.4.1/5.4.2 全表）、
//    resolveNoScheme、resolveUnsupportedScheme、resolveSchemeLikePath、
//    relativePath（含 %2e 点段变体全表）、relativePathWithTrailingSlash、
//    pathWithBackslash、relativePathWithSameScheme；另补决策 L6-A 三条
//    锚点：query-only（"?x=1"）、仅 fragment（"#f"）、base 无 path
//    （http://a.com + ../up → http://a.com/up）
// 4. IPv6 组：hostIpv6 核心（剥方括号存储/toString 复括号/端口不与冒号
//    冲突）、括号畸形（未闭合/多重/空括号/括号后杂项）、hostIpv6Malformed
//    （[::g]）、zone-id 保留原样
// 5. percent-encoding 组：percentDecode、malformedPercentEncoding、
//    malformedUtf8Encoding（U+FFFD 替换，maximal subpart）、编码集对拍
//    （percent_wbtest.mbt，对照 PATH_SEGMENT_ENCODE_SET 与
//    QUERY_ENCODE_SET）
//
// 【略去组及理由】
// - IDN/punycode 组（hostname* 系列的 σ→xn--4xa、电话符号映射等）：M1
//   显式拒绝非 ASCII host（FR-003），IDN 随 M3 回补（spec A7）
// - userinfo 组（username/usernameAndPassword/authorityWithMultipleAtSigns/
//   authorityWithMultipleColons 等）：M1 显式拒绝 userinfo（FR-008，裁决
//   Q3-A），建模随 M3 回补（spec A6 ①）
// - IPv6 地址结构规范化组（hostIpv6AddressDifferentFormats/
//   hostIpv6CanonicalForm/hostIpv6AddressMisplacedColons/压缩与 IPv4 后缀
//   族）：本包 IPv6 逐字存储（剥括号 + ASCII 小写），不做 Inet6Address 式
//   压缩重排与深度结构校验（data-model §1 只约束括号形态；往返幂等仍由
//   FR-001 保证）。OkHttp 5.5.0 拒绝 scoped address
//   （hostIpv6ScopedAddress），本包按 spec 边界用例保留 zone-id 原样
//   （spec A6 对齐 4.x 口径，M3 IDN 回补时统一复核）
// - Builder/组合组（compose*、addPathSegment*、setPathSegment*、
//   removePathSegment、queryParameter 系列等）：本包公开面无 URL Builder
//   与 query 参数 API（YAGNI，宪法 VI；需求出现时按 spec 变更流程评估）
// - redactedUrl 组：P01 输出面收敛为 derive(Debug)（FR-013，R3-H1-A），
//   无 redact API（脱敏专版挂欠账 F13，归 M3）
//
// 【已记录的残余差异】（宪法 III：与 OkHttp 的语义差异显式记录，不作悄悄偏移）
// - 错误面：OkHttp 抛 IllegalArgumentException / 返回 null；本包 raise
//   可判别的 HttpUrlError 四变体（spec US-1 场景 3、A6）
// - 路径 %41 等非必要转义被规范化（解码存储 → 重编码仅按需），OkHttp
//   保留原编码形态（存储模型差异；spec A2 的「不二次编码」指合法 %XX 不
//   重复编码，解码存储下 %41 → "A" 为规范化而非二次编码）
// - fragment 编码集取 query 口径（data-model §1「同 query 口径」）；
//   OkHttp 5.5.0 的 FRAGMENT_ENCODE_SET 为空集（除控制字符外几乎全保留）
// - query/fragment 解析期孤立 "%" 与非法转义原样保留（对齐 OkHttp 解析期
//   alreadyEncoded=true 且 strict=false 的行为；OkHttp Builder 的 strict
//   模式不在本包范围）
// ============================================================================

///|
// 黑盒辅助：断言 parse 必 raise 且错误满足判别谓词
fn expect_url_error(
  input : String,
  check : (@core.HttpUrlError) -> Bool,
) -> Unit raise {
  try @core.HttpUrl::parse(input) catch {
    e => assert_true(check(e))
  } noraise {
    _ => fail("应当 raise HttpUrlError：\{input}")
  }
}

///|
// 黑盒辅助：断言 parse 成功
fn expect_url_ok(input : String) -> @core.HttpUrl raise {
  @core.HttpUrl::parse(input) catch {
    _ => fail("应当解析成功：\{input}")
  }
}

///|
test "US-1 场景1：scheme/host 小写、点段消解、默认端口省略、空段压缩" {
  let u = expect_url_ok("http://Example.COM:80/a/./b/../c?x=1#frag")
  assert_eq(u.to_string(), "http://example.com/a/c?x=1#frag")
  assert_eq(u.scheme(), @http.Protocol::Http)
  assert_eq(u.host(), "example.com")
  assert_eq(u.port(), 80)
}

///|
test "US-1 场景2：IPv6 剥方括号存储，端口不与冒号冲突" {
  let u = expect_url_ok("http://[::1]:8080/x")
  assert_eq(u.host(), "::1")
  assert_eq(u.port(), 8080)
  assert_eq(u.to_string(), "http://[::1]:8080/x")
  // 移植自 OkHttp hostIpv6：方括号不出现在 host()，但出现在 to_string()
  let u2 = expect_url_ok("http://[::1]/")
  assert_eq(u2.host(), "::1")
  assert_eq(u2.to_string(), "http://[::1]/")
}

///|
test "US-1 场景3：畸形输入 raise 类型可判别" {
  expect_url_error("http://bad host/", e => e is @core.HttpUrlError::InvalidHost)
  expect_url_error("http://host:notaport/", e => {
    e is @core.HttpUrlError::InvalidPort
  })
}

///|
test "US-1 场景4：非 ASCII host → InvalidHost（IDN 随 M3 回补）" {
  expect_url_error("http://☃.net/", e => e is @core.HttpUrlError::InvalidHost)
  expect_url_error("http://例え.jp/", e => {
    e is @core.HttpUrlError::InvalidHost
  })
}

///|
test "US-1 场景5：往返幂等 parse(to_string(parse(s))) == parse(s)（FR-001）" {
  let corpus = [
    "http://example.com/a/c?x=1#frag", "http://[::1]:8080/x", "http://example.com/",
    "https://a.b/c/d/", "http://h/a%2Fb/%41", "http://h/a%f/b", "http://h/%%30%30",
    "http://h/a/%E2%98x/c", "http://h?x=1%2B&x=1", "http://h#", "http://h#f", "http://a.com./",
    "http://[fe80::1%25eth0]/", "http://[2001:db8::1]/x", "http://h:65535/", "https://h:8080/a?b c#d e",
    "http://h/a\\b", "http://ABCD/x", "http://host/a\u{b}b",
  ]
  for s in corpus {
    let u1 = expect_url_ok(s)
    let u2 = expect_url_ok(u1.to_string())
    assert_eq(u2, u1)
  }
}

///|
test "边界：空串/仅 scheme/缺 host → MalformedUrl，不 panic" {
  expect_url_error("", e => e is @core.HttpUrlError::MalformedUrl)
  expect_url_error("http", e => e is @core.HttpUrlError::MalformedUrl)
  expect_url_error("http:", e => e is @core.HttpUrlError::MalformedUrl)
  expect_url_error("http://", e => e is @core.HttpUrlError::MalformedUrl)
  expect_url_error("example.com", e => e is @core.HttpUrlError::MalformedUrl)
  expect_url_error("://h/", e => e is @core.HttpUrlError::MalformedUrl)
}

///|
test "边界：端口合法区间 1..=65535（含 0 与 65536 越界，M1-A）" {
  expect_url_error("http://h:0/", e => e is @core.HttpUrlError::InvalidPort)
  expect_url_error("http://h:65536/", e => e is @core.HttpUrlError::InvalidPort)
  expect_url_error("http://h:notaport/", e => {
    e is @core.HttpUrlError::InvalidPort
  })
  expect_url_error("http://h:80x/", e => e is @core.HttpUrlError::InvalidPort)
  expect_url_error("http://h:+80/", e => e is @core.HttpUrlError::InvalidPort)
  expect_url_error("http://h: 80/", e => e is @core.HttpUrlError::InvalidPort)
  // 合法边界值
  assert_eq(expect_url_ok("http://h:65535/").port(), 65535)
  assert_eq(expect_url_ok("http://h:1/").port(), 1)
  // 空端口按默认（对齐 OkHttp：portColonOffset+1 == componentDelimiterOffset）
  assert_eq(expect_url_ok("http://h:/x").port(), 80)
  // 前导零按十进制解析
  assert_eq(expect_url_ok("http://h:080/").port(), 80)
  // 缺省填 scheme 默认端口（上游 @http.Protocol::default_port，FR-002）
  assert_eq(expect_url_ok("http://h/").port(), 80)
  assert_eq(expect_url_ok("https://h/").port(), 443)
}

///|
test "边界：path 空规范化为 /（访问器与序列化）" {
  let u = expect_url_ok("http://example.com")
  assert_eq(u.to_string(), "http://example.com/")
  assert_eq(u.path_segments(), [""])
  let u2 = expect_url_ok("http://example.com?")
  assert_eq(u2.to_string(), "http://example.com/?")
  let u3 = expect_url_ok("http://example.com#")
  assert_eq(u3.to_string(), "http://example.com/#")
}

///|
test "边界：query 保留字符与既有 %XX 不二次编码、重复键原样保留" {
  let u = expect_url_ok("http://h/a?x=1%2B&x=1")
  assert_eq(u.query(), Some("x=1%2B&x=1"))
  // 裸空格按编码集补编码
  assert_eq(expect_url_ok("http://h/a?b c").query(), Some("b%20c"))
  // 孤立 % 原样保留（不二次编码，也不视为非法）
  assert_eq(expect_url_ok("http://h/a?100%").query(), Some("100%"))
  // 无 query 为 None
  assert_eq(expect_url_ok("http://h/a").query(), None)
}

///|
test "边界：fragment None 与空串可区分（# 的有无）" {
  assert_eq(expect_url_ok("http://h/").fragment(), None)
  assert_eq(expect_url_ok("http://h/#").fragment(), Some(""))
  assert_eq(expect_url_ok("http://h/#f").fragment(), Some("f"))
  // to_string 时 # 的有无随 None / 空串区分
  assert_eq(expect_url_ok("http://h/#").to_string(), "http://h/#")
  assert_eq(expect_url_ok("http://h/").to_string(), "http://h/")
  // query 与 fragment 共存
  assert_eq(
    expect_url_ok("http://h/a?x=1#frag").to_string(),
    "http://h/a?x=1#frag",
  )
}

///|
test "边界：IPv6 畸形括号报错；zone-id 保留原样" {
  // 未闭合
  expect_url_error("http://[::1/", e => e is @core.HttpUrlError::InvalidHost)
  expect_url_error("http://[::1", e => e is @core.HttpUrlError::InvalidHost)
  // 多重括号 / 空括号 / 括号后杂项
  expect_url_error("http://[[::1]]/", e => e is @core.HttpUrlError::InvalidHost)
  expect_url_error("http://[]/", e => e is @core.HttpUrlError::InvalidHost)
  expect_url_error("http://[::1]x/", e => e is @core.HttpUrlError::InvalidHost)
  // 非 IPv6 字符（移植自 OkHttp hostIpv6Malformed：[::g]）
  expect_url_error("http://[::g]/", e => e is @core.HttpUrlError::InvalidHost)
  // zone-id 保留原样（对齐 OkHttp；本包不解码 %25，逐字存储）
  let z = expect_url_ok("http://[fe80::1%25eth0]/")
  assert_eq(z.host(), "fe80::1%25eth0")
  assert_eq(z.to_string(), "http://[fe80::1%25eth0]/")
  // 括号内非十六进制且无冒号 → InvalidHost
  expect_url_error("http://[abc]/", e => e is @core.HttpUrlError::InvalidHost)
}

///|
test "边界：host 末尾点保留（移植自 OkHttp trailingDotIsOkay）" {
  let u = expect_url_ok("http://a.com./")
  assert_eq(u.host(), "a.com.")
  assert_eq(u.to_string(), "http://a.com./")
}

///|
test "边界：userinfo 显式拒绝（FR-008，Q3-A）→ MalformedUrl" {
  expect_url_error("http://user:pass@example.com/", e => {
    e is @core.HttpUrlError::MalformedUrl
  })
  expect_url_error("http://user@example.com/", e => {
    e is @core.HttpUrlError::MalformedUrl
  })
  expect_url_error("http://@example.com/", e => {
    e is @core.HttpUrlError::MalformedUrl
  })
  // authority 中任何 '@' 均视为 userinfo 存在
  expect_url_error("http://foo@bar@baz/path", e => {
    e is @core.HttpUrlError::MalformedUrl
  })
}

///|
test "边界：非 http/https scheme → UnsupportedScheme" {
  expect_url_error("ftp://host/", e => {
    e is @core.HttpUrlError::UnsupportedScheme
  })
  expect_url_error("file:///etc/passwd", e => {
    e is @core.HttpUrlError::UnsupportedScheme
  })
  expect_url_error("mailto:user", e => {
    e is @core.HttpUrlError::UnsupportedScheme
  })
}

///|
test "SC-005 ③：to_string 不输出 userinfo（结构性保证的断言载体）" {
  // userinfo 输入被 FR-008 拒绝：不存在可产出 userinfo 的 HttpUrl 值
  try @core.HttpUrl::parse("http://user:pass@example.com/") catch {
    e => {
      assert_true(e is @core.HttpUrlError::MalformedUrl)
      // 错误输出只携带定位片段，不回显 userinfo（SC-005 ② 补充载体）
      let repr = Repr::Repr(e).to_string()
      assert_false(repr.contains("user:pass"))
      assert_false(repr.contains("user"))
    }
  } noraise {
    _ => fail("userinfo 应当被拒绝")
  }
  // 合法 URL 的 to_string 亦不可能包含 '@'（host 字符集不含 '@'）
  assert_false(
    expect_url_ok("http://example.com/a@b")
    .to_string()
    .contains("@example.com/"),
  )
}

///|
test "移植：parseTrimsAsciiWhitespace（OkHttp）——首尾 ASCII 空白裁剪" {
  let expected = expect_url_ok("http://host/")
  assert_eq(expect_url_ok(" http://host/ "), expected)
  assert_eq(expect_url_ok("\r\n\u{c} \thttp://host/"), expected)
  assert_eq(expect_url_ok("http://host/\u{c}\n\t \r"), expected)
  assert_eq(expect_url_ok("    http://host/    "), expected)
}

///|
test "移植：parseDoesNotTrimOtherWhitespaceCharacters（OkHttp）——其他空白按路径补编码" {
  // 竖向制表符 \u000b 不裁剪，编码为 %0B
  assert_eq(expect_url_ok("http://h/\u{b}").to_string(), "http://h/%0B")
  // 不换行空格 / 不间断空格 / 表意空格按 UTF-8 补编码
  assert_eq(expect_url_ok("http://h/\u{85}").to_string(), "http://h/%C2%85")
  assert_eq(expect_url_ok("http://h/\u{a0}").to_string(), "http://h/%C2%A0")
  assert_eq(
    expect_url_ok("http://h/\u{3000}").to_string(),
    "http://h/%E3%80%80",
  )
  // 已编码形态不二次编码
  assert_eq(expect_url_ok("http://h/%0B").to_string(), "http://h/%0B")
}

///|
test "移植：hostContainsIllegalCharacter 与 parseHostAsciiNonPrintable（OkHttp）" {
  expect_url_error("http://\n/", e => e is @core.HttpUrlError::InvalidHost)
  expect_url_error("http:// /", e => e is @core.HttpUrlError::InvalidHost)
  // %20 解码为空格后非法
  expect_url_error("http://%20/", e => e is @core.HttpUrlError::InvalidHost)
  expect_url_error("http://host\u{1}/", e => {
    e is @core.HttpUrlError::InvalidHost
  })
}

///|
test "移植：hostnameLowercase/Uppercase（OkHttp ASCII 子集）——host 小写规范化" {
  assert_eq(expect_url_ok("http://abcd").host(), "abcd")
  assert_eq(expect_url_ok("http://ABCD").host(), "abcd")
  assert_eq(
    expect_url_ok("http://aBcD.eXaMpLe.CoM/").host(),
    "abcd.example.com",
  )
  // IPv6 十六进制同样小写
  assert_eq(expect_url_ok("http://[2001:DB8::1]/").host(), "2001:db8::1")
}

///|
test "移植：parseAuthoritySlashCountDoesntMatter（OkHttp 子集）——scheme 后斜杠数不限" {
  let expected = expect_url_ok("http://host/path")
  assert_eq(expect_url_ok("http:host/path"), expected)
  assert_eq(expect_url_ok("http:/host/path"), expected)
  assert_eq(expect_url_ok("http:\\host/path"), expected)
  assert_eq(expect_url_ok("http:///host/path"), expected)
  assert_eq(expect_url_ok("http:////host/path"), expected)
  assert_eq(expect_url_ok("http:\\/host/path"), expected)
  assert_eq(expect_url_ok("http:/\\host/path"), expected)
}

///|
test "移植：pathWithBackslash（OkHttp）——反斜杠视作路径分隔符" {
  let u = expect_url_ok("http://host/a\\b")
  assert_eq(u.path_segments(), ["a", "b"])
  assert_eq(u.to_string(), "http://host/a/b")
}

///|
test "移植：malformedPercentEncoding（OkHttp）——非法转义按字面量保留" {
  assert_eq(expect_url_ok("http://host/a%f/b").path_segments(), ["a%f", "b"])
  assert_eq(expect_url_ok("http://host/%/b").path_segments(), ["%", "b"])
  assert_eq(expect_url_ok("http://host/%").path_segments(), ["%"])
  assert_eq(expect_url_ok("http://host/%%30%30").path_segments(), ["%00"])
}

///|
test "移植：malformedUtf8Encoding（OkHttp）——非法 UTF-8 以 U+FFFD 替换" {
  assert_eq(expect_url_ok("http://host/a/%E2%98x/c").path_segments(), [
    "a", "\u{fffd}x", "c",
  ])
}

///|
test "移植：默认端口省略（OkHttp toString 语义）——等于默认端口时省略" {
  assert_eq(expect_url_ok("http://h:80/").to_string(), "http://h/")
  assert_eq(expect_url_ok("https://h:443/").to_string(), "https://h/")
  // 非默认端口保留
  assert_eq(expect_url_ok("https://h:80/").to_string(), "https://h:80/")
  assert_eq(expect_url_ok("http://h:8080/").to_string(), "http://h:8080/")
  // 相等性：显式默认端口与缺省等价
  assert_eq(expect_url_ok("http://h:80/"), expect_url_ok("http://h/"))
  assert_eq(
    expect_url_ok("http://h:80/").hash(),
    expect_url_ok("http://h/").hash(),
  )
}

///|
test "访问器：六字段齐全（FR-002），derive 判等/哈希可用（N1-A 口径）" {
  let u = expect_url_ok("https://Example.COM:8443/a/b?x=1#f")
  assert_eq(u.scheme(), @http.Protocol::Https)
  assert_eq(u.host(), "example.com")
  assert_eq(u.port(), 8443)
  assert_eq(u.path_segments(), ["a", "b"])
  assert_eq(u.query(), Some("x=1"))
  assert_eq(u.fragment(), Some("f"))
  // Eq/Hash/Debug 经显式 pub extend 以方法形态可用
  let v = expect_url_ok("https://example.com:8443/a/b?x=1#f")
  assert_true(u.equal(v))
  assert_true(u.not_equal(expect_url_ok("http://h/")))
  assert_eq(u.hash(), v.hash())
  ignore(u.to_repr())
  // path_segments 返回防御性副本：外部突变不影响值
  let segs = u.path_segments()
  segs.push("mutated")
  assert_eq(u.path_segments(), ["a", "b"])
}
