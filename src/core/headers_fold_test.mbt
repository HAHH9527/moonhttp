///|
// headers_fold_test：HeadersV → @http.Headers 边界折叠测试（T015）。
//
// 按 SC-003 的两个可满足不变量组织（决策 H1-A，2026-10-13——原「折叠后
// get 首个语义不变」在存在重复名时必然为假，已弃用）：
//   ① 无重复名：折叠对单值名是恒等映射——折叠后每个名字的 get 值与折叠前
//      逐字节相等；
//   ② 有重复名：折叠值 = 按插入序以无空格 "," 拼接，且该串经 @http 响应侧
//      合并的逆操作（按 "," 拆分）可还原原名值序列（进出互逆）。
//      对称基准：@http 响应侧 parser.mbt:282 的同名合并
//      `headers[key] = "\{v0},\{value}"`（逐字节对称，FR-005，用户裁决 Q1-A）。
//
// ⚠ 折叠不保证 quoted-string 边界（US-4 场景 2 的文档承诺落在代码注释）：
//   值内含引号串逗号（如 WWW-Authenticate: Basic realm="a, b"）时折叠结果
//   的字符串语义可能受损；认证路径 M2 绕过此转换（08-auth）。
//
// 敏感样例值纪律（R3-M1 → spec A8）：只用合成占位串，禁真实凭证。

///|
// @http 响应侧合并的逆操作：按 "," 拆分合并值，还原原值序列
// （parser.mbt:282 将重复名值合并为 "\{v0},\{value}"，本函数为其逆）
fn split_by_comma(s : String) -> Array[String] {
  let out : Array[String] = []
  for part in s.split(",") {
    out.push(part.to_owned())
  }
  out
}

///|
test "SC-003 不变量①：无重复名——折叠为恒等映射（逐字节相等）" {
  // @property 不可用，以确定性循环生成名字唯一的头列表（多规模）
  for n in [1, 2, 5, 17, 40] {
    let b = @core.HeadersVBuilder::new()
    for i in 0..<n {
      b.add("X-Unique-\{i}", "v\{i}")
    }
    let headers = b.build()
    let map = headers.to_http_map()
    assert_eq(map.length(), n)
    for i in 0..<n {
      // 折叠后每个名字的 get 值与折叠前逐字节相等
      assert_eq(
        map.get(@http.CaseInsensitiveString("X-Unique-\{i}")),
        Some("v\{i}"),
      )
    }
  }
  // 值含特殊字符时恒等映射仍逐字节成立（无重复名即无合并）
  let b = @core.HeadersVBuilder::new()
  b.add("Accept-Encoding", "gzip, br")
  b.add("X-Path", "/a/b?c=d#e")
  b.add("X-Empty", "")
  let map = b.build().to_http_map()
  assert_eq(
    map.get(@http.CaseInsensitiveString("accept-encoding")),
    Some("gzip, br"),
  )
  assert_eq(map.get(@http.CaseInsensitiveString("x-path")), Some("/a/b?c=d#e"))
  assert_eq(map.get(@http.CaseInsensitiveString("x-empty")), Some(""))
}

///|
test "SC-003 不变量②：有重复名——无空格逗号拼接且与响应侧互逆还原" {
  // X-Multi: a + X-Multi: b → 单值 "a,b"（与 @http parser.mbt:282 的
  // "\{v0},\{v}" 逐字节对称）
  let b = @core.HeadersVBuilder::new()
  b.add("X-Multi", "a")
  b.add("X-Multi", "b")
  let map = b.build().to_http_map()
  assert_eq(map.length(), 1)
  let folded = map.get(@http.CaseInsensitiveString("X-Multi"))
  assert_eq(folded, Some("a,b"))
  // 进出互逆：经响应侧拆分还原原名值序列
  assert_eq(split_by_comma(folded.unwrap()), ["a", "b"])
  // 大小写不敏感的重复名同样折叠
  let b2 = @core.HeadersVBuilder::new()
  b2.add("x-multi", "a")
  b2.add("X-MULTI", "b")
  let map2 = b2.build().to_http_map()
  assert_eq(map2.get(@http.CaseInsensitiveString("X-Multi")), Some("a,b"))
}

///|
test "SC-003 不变量②扩展：三个及以上重复名按插入序拼接并互逆" {
  let b = @core.HeadersVBuilder::new()
  b.add("Via", "1.0 proxy-a")
  b.add("Via", "1.1 proxy-b")
  b.add("Via", "1.1 proxy-c")
  b.add("Other", "solo")
  let map = b.build().to_http_map()
  assert_eq(map.length(), 2)
  let folded = map.get(@http.CaseInsensitiveString("via")).unwrap()
  assert_eq(folded, "1.0 proxy-a,1.1 proxy-b,1.1 proxy-c")
  // 响应侧拆分还原插入序值序列
  assert_eq(split_by_comma(folded), [
    "1.0 proxy-a", "1.1 proxy-b", "1.1 proxy-c",
  ])
  assert_eq(map.get(@http.CaseInsensitiveString("other")), Some("solo"))
}

///|
test "边界：空容器折叠为空 Map" {
  let map = @core.HeadersVBuilder::new().build().to_http_map()
  assert_eq(map.length(), 0)
}

///|
test "边界：值为空串的头折叠后值为空串" {
  let b = @core.HeadersVBuilder::new()
  b.add("X-Empty", "")
  let map = b.build().to_http_map()
  assert_eq(map.get(@http.CaseInsensitiveString("X-Empty")), Some(""))
  // 空串值参与重复名拼接："" + "a" → ",a"（插入序拼接的自然结果）
  let b2 = @core.HeadersVBuilder::new()
  b2.add("X-Seq", "")
  b2.add("X-Seq", "a")
  assert_eq(
    b2.build().to_http_map().get(@http.CaseInsensitiveString("X-Seq")),
    Some(",a"),
  )
}

///|
test "折叠保留首个插入的原名形态（不强制小写化，契约条款 3）" {
  let b = @core.HeadersVBuilder::new()
  b.add("X-CamelCase-Name", "v")
  let map = b.build().to_http_map()
  // 键遍历可见原名字符串原样保留
  let mut seen_original = false
  for k, _ in map {
    if k.to_string() == "X-CamelCase-Name" {
      seen_original = true
    }
  }
  assert_true(seen_original)
}
