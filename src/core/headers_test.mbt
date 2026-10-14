///|
// headers_test：HeadersV/HeadersVBuilder 容器语义黑盒测试（T013）。
//
// 用例来源：spec US-3 验收场景 1–5、Edge Cases 头相关条目、
// contracts/headers.md 锚点表（FR-004/006/012/013）。
//
// 敏感样例值纪律（R3-M1 → spec A8）：Authorization 头样例值为明显合成的
// 占位串 Bearer test-token-123，禁真实凭证。
//
// 输出面口径（FR-013，R3-H1-A）：derive(Debug) 默认明文形态即本包唯一
// 输出面（宪法 v1.2.0 :112-117 展示例外程序，留痕 R3-M1）；判等/哈希与
// 输出行为无关、恒稳。

///|
// 黑盒辅助：断言 add/set 必 raise 且错误满足判别谓词
fn expect_builder_error(
  op : (@core.HeadersVBuilder, String, String) -> Unit raise @core.HeadersError,
  builder : @core.HeadersVBuilder,
  name : String,
  value : String,
  check : (@core.HeadersError) -> Bool,
) -> Unit raise {
  try op(builder, name, value) catch {
    e => assert_true(check(e))
  } noraise {
    _ => fail("应当 raise HeadersError：\{name}")
  }
}

///|
test "US-3 场景1：add 追加、values 保序收集、get 大小写不敏感取首个" {
  let builder = @core.HeadersVBuilder::new()
  builder.add("Accept", "a")
  builder.add("Accept", "b")
  let headers = builder.build()
  // 决策 M2-A：values 返回保序 Iter，断言前先收集为数组（迭代器不作断言对象）
  let collected : Array[String] = headers.values("accept").to_array()
  assert_eq(collected, ["a", "b"])
  // 大小写不敏感、保插入序：get 取首个
  assert_eq(headers.get("ACCEPT"), Some("a"))
  assert_eq(headers.get("accept"), Some("a"))
  assert_eq(headers.get("Accept"), Some("a"))
  assert_eq(headers.get("missing"), None)
}

///|
test "US-3 场景2：set 覆盖全部同名" {
  let builder = @core.HeadersVBuilder::new()
  builder.add("Accept", "a")
  builder.add("accept", "b")
  builder.set("ACCEPT", "c")
  let headers = builder.build()
  assert_eq(headers.values("accept").to_array(), ["c"])
  assert_eq(headers.get("Accept"), Some("c"))
}

///|
test "remove 删全部同名（大小写不敏感）" {
  let builder = @core.HeadersVBuilder::new()
  builder.add("X-Multi", "a")
  builder.add("x-multi", "b")
  builder.add("Other", "keep")
  builder.remove("X-MULTI")
  let headers = builder.build()
  assert_eq(headers.values("x-multi").to_array(), [])
  assert_eq(headers.get("X-Multi"), None)
  assert_eq(headers.get("Other"), Some("keep"))
}

///|
test "US-3 场景3：相同顺序构造相同列表 → 相等且哈希一致（P04 池键前提）" {
  fn build_sample() -> @core.HeadersV raise {
    let b = @core.HeadersVBuilder::new()
    b.add("Accept", "text/html")
    b.add("Accept-Encoding", "gzip")
    b.add("X-Multi", "1")
    b.add("X-Multi", "2")
    b.build()
  }
  let h1 = build_sample()
  let h2 = build_sample()
  assert_true(h1.equal(h2))
  assert_true(h2.equal(h1))
  assert_eq(h1.hash(), h2.hash())
  assert_false(h1.not_equal(h2))
  // 顺序参与判等：不同顺序的头列表不相等（重放字节级一致的前提）
  let b3 = @core.HeadersVBuilder::new()
  b3.add("Accept-Encoding", "gzip")
  b3.add("Accept", "text/html")
  b3.add("X-Multi", "1")
  b3.add("X-Multi", "2")
  let h3 = b3.build()
  assert_true(h1.not_equal(h3))
}

///|
test "FR-012：头名非法 → raise InvalidName，容器不变" {
  let b = @core.HeadersVBuilder::new()
  b.add("Good", "v")
  // 含空格 / 空名 / 非 token 字符（:、CR/LF、非 ASCII 等）
  expect_builder_error(@core.HeadersVBuilder::add, b, "Bad Name", "v", e => {
    e is @core.HeadersError::InvalidName
  })
  expect_builder_error(@core.HeadersVBuilder::add, b, "", "v", e => {
    e is @core.HeadersError::InvalidName
  })
  expect_builder_error(@core.HeadersVBuilder::add, b, "Bad:Name", "v", e => {
    e is @core.HeadersError::InvalidName
  })
  expect_builder_error(@core.HeadersVBuilder::add, b, "a\r\nb", "v", e => {
    e is @core.HeadersError::InvalidName
  })
  expect_builder_error(@core.HeadersVBuilder::add, b, "名", "v", e => {
    e is @core.HeadersError::InvalidName
  })
  expect_builder_error(@core.HeadersVBuilder::set, b, "Bad Name", "v", e => {
    e is @core.HeadersError::InvalidName
  })
  expect_builder_error(@core.HeadersVBuilder::set, b, "", "v", e => {
    e is @core.HeadersError::InvalidName
  })
  // 违例后容器不变：仍只有 Good 一条
  let headers = b.build()
  assert_eq(headers.get("Good"), Some("v"))
  assert_eq(headers.values("Bad Name").to_array(), [])
}

///|
test "FR-012：头值含 CR/LF → raise InvalidValue（防头注入），容器不变" {
  let b = @core.HeadersVBuilder::new()
  b.add("Good", "v")
  expect_builder_error(@core.HeadersVBuilder::add, b, "X", "a\r\nY: 1", e => {
    e is @core.HeadersError::InvalidValue
  })
  expect_builder_error(@core.HeadersVBuilder::add, b, "X", "a\nY: 1", e => {
    e is @core.HeadersError::InvalidValue
  })
  expect_builder_error(@core.HeadersVBuilder::add, b, "X", "a\rY: 1", e => {
    e is @core.HeadersError::InvalidValue
  })
  expect_builder_error(@core.HeadersVBuilder::set, b, "X", "a\r\nInjected: 1", e => {
    e is @core.HeadersError::InvalidValue
  })
  let headers = b.build()
  assert_eq(headers.get("Good"), Some("v"))
  assert_eq(headers.values("X").to_array(), [])
}

///|
test "FR-012：remove 对非法名静默无操作、不 raise" {
  let b = @core.HeadersVBuilder::new()
  b.add("Good", "v")
  b.remove("Bad Name")
  b.remove("")
  b.remove("a\r\nb")
  let headers = b.build()
  assert_eq(headers.get("Good"), Some("v"))
}

///|
test "边界：值为空串的头合法保留" {
  let b = @core.HeadersVBuilder::new()
  b.add("X-Empty", "")
  let headers = b.build()
  assert_eq(headers.get("X-Empty"), Some(""))
  assert_eq(headers.values("x-empty").to_array(), [""])
}

///|
test "Builder 双入口（R2-C1）：new() 造空；HeadersV::builder() 回转不重跑校验" {
  // 入口一：new() 造空
  let empty = @core.HeadersVBuilder::new().build()
  assert_eq(empty.get("any"), None)
  assert_eq(empty.values("any").to_array(), [])
  // 入口二：已固化值回转为可变 Builder，不重跑 FR-012 校验（源数据已验证）
  let b = @core.HeadersVBuilder::new()
  b.add("A", "1")
  b.add("B", "2")
  let v1 = b.build()
  let rb = v1.builder()
  // 回转后可继续变更，再 build 得新值
  rb.add("C", "3")
  let v2 = rb.build()
  assert_eq(v2.get("A"), Some("1"))
  assert_eq(v2.get("C"), Some("3"))
  assert_true(v1.not_equal(v2))
  // 回转-再固化幂等：不加变更时与原值相等
  assert_true(v1.builder().build().equal(v1))
  // 回转入口对无效名的后续 add 仍然校验（新数据必须走 FR-012）
  expect_builder_error(
    @core.HeadersVBuilder::add,
    v1.builder(),
    "Bad Name",
    "v",
    e => e is @core.HeadersError::InvalidName,
  )
}

///|
test "Builder 与值的隔离：build 后继续操作 Builder 不影响已产出值" {
  let b = @core.HeadersVBuilder::new()
  b.add("A", "1")
  let v1 = b.build()
  b.add("B", "2")
  b.remove("A")
  assert_eq(v1.get("A"), Some("1"))
  assert_eq(v1.get("B"), None)
  // HeadersV::builder 的防御性复制：回转后变更不影响原值
  let rb = v1.builder()
  rb.remove("A")
  assert_eq(v1.get("A"), Some("1"))
}

///|
test "US-3 场景5 / SC-005：输出面为 derive(Debug) 默认明文形态（R3-H1-A）" {
  // 样例值为合成占位串（R3-M1 纪律）：任何真实/可用凭证禁止入库
  let b = @core.HeadersVBuilder::new()
  b.add("Authorization", "Bearer test-token-123")
  b.add("X-Trace", "trace-id-000")
  let v = b.build()
  // derive 默认明文形态：debug 输出包含该占位串
  let repr = Repr::Repr(v).to_string()
  assert_true(repr.contains("Bearer test-token-123"))
  // 判等/哈希与输出行为无关、恒稳：相同构造判等且哈希一致
  let b2 = @core.HeadersVBuilder::new()
  b2.add("Authorization", "Bearer test-token-123")
  b2.add("X-Trace", "trace-id-000")
  let v2 = b2.build()
  assert_true(v.equal(v2))
  assert_eq(v.hash(), v2.hash())
  // Builder 同为 derive(Debug) 默认实现（R2-D1/R2-B1：统一口径，无例外）
  let builder_repr = Repr::Repr(v.builder()).to_string()
  assert_true(builder_repr.contains("Bearer test-token-123"))
  // 快照锚点（content 由 moon test --update 冻结后人工审视）
  debug_inspect(
    v,
    content=(
      #|{
      #|  entries: [
      #|    ("Authorization", "Bearer test-token-123"),
      #|    ("X-Trace", "trace-id-000"),
      #|  ],
      #|}
    ),
  )
}

///|
test "token 字符集边界：RFC 9110 tchar 全集合法" {
  let b = @core.HeadersVBuilder::new()
  // !#$%&'*+-.^_`|~ 与字母数字均为合法 token 字符
  b.add("!#$%&'*+-.^_`|~", "ok")
  b.add("X-09azAZ", "ok")
  let headers = b.build()
  assert_eq(headers.get("!#$%&'*+-.^_`|~"), Some("ok"))
  assert_eq(headers.get("x-09azaz"), Some("ok"))
}
