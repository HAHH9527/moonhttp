///|
// address_test：Address 直连三元组池键（FR-014）的黑盒元测试（P04 T003）。
//
// 判据面（工单 P04-E①～⑤）：跨端口不同键、跨 scheme 不同键、host 大小写
// 规范化同键、IPv6 括号剥离、equal/hash 一致且可作 Map 键。
// 键含端口的物理依据＝上游 @http.Client 构造期固化 Host 头（research R4.3，
// client.mbt:58）——跨 host:port 复用同一连接会把请求发到错误源站。
//
// 红绿纪律（宪法 IV）：红判据＝无 Address 类型（编译红），再实现转绿。

///|
// P04-E①（FR-014）：跨端口必为不同键——同 host 同 scheme 不同端口互不租借。
test "P04-E① Address 跨端口必为不同键" {
  let a = @client.Address::new(scheme="http", host="127.0.0.1", port=8080)
  let b = @client.Address::new(scheme="http", host="127.0.0.1", port=8081)
  assert_true(
    !a.equal(b),
    msg="不同端口必须是不同键（FR-014/R4.3）",
  )
  // 访问器面：三元组逐字段可读
  assert_eq(a.scheme(), "http")
  assert_eq(a.host(), "127.0.0.1")
  assert_eq(a.port(), 8080)
  assert_eq(b.port(), 8081)
}

///|
// P04-E②（FR-014）：跨 scheme 必为不同键；scheme 大小写规范化同键
// （规范化单点收口的 scheme 侧镜像断言）。
test "P04-E② Address 跨 scheme 必为不同键且 scheme 小写化" {
  let a = @client.Address::new(scheme="http", host="example.com", port=80)
  let b = @client.Address::new(scheme="https", host="example.com", port=80)
  assert_true(!a.equal(b), msg="不同 scheme 必须是不同键（FR-014）")
  let c = @client.Address::new(scheme="HTTP", host="example.com", port=80)
  assert_true(a.equal(c), msg="scheme 大小写应规范化为同键")
  assert_eq(c.scheme(), "http", msg="scheme 访问器返回小写化形态")
}

///|
// P04-E③（FR-014）：host 大小写规范化同键——DNS 名大小写不敏感，规范化
// 在 new 内部单点收口（data-model 实体 1）。
test "P04-E③ Address host 大小写规范化同键" {
  let a = @client.Address::new(scheme="http", host="Example.COM", port=80)
  let b = @client.Address::new(scheme="http", host="example.com", port=80)
  assert_true(a.equal(b), msg="host 大小写应规范化为同键")
  assert_eq(a.host(), "example.com", msg="host 访问器返回小写化形态")
  assert_eq(a.hash(), b.hash(), msg="同键必同 hash")
}

///|
// P04-E④（FR-014）：IPv6 字面量剥方括号——"[::1]" 与 "::1" 同键，访问器
// 返回剥括号形态（对齐 P01 HttpUrl 存储不变量，R4.3）。
test "P04-E④ Address IPv6 字面量剥方括号" {
  let a = @client.Address::new(scheme="http", host="[::1]", port=8080)
  let b = @client.Address::new(scheme="http", host="::1", port=8080)
  assert_true(a.equal(b), msg="IPv6 括号应剥离为同键")
  assert_eq(a.host(), "::1", msg="host 访问器返回剥括号形态")
  assert_eq(a.hash(), b.hash(), msg="同键必同 hash")
}

///|
// P04-E⑤（FR-014）：equal/hash 一致且可作 Map 键——equal ⇒ 同 hash；
// 规范化异形同键在 Map 中命中同一条目；不同键互不串。
test "P04-E⑤ Address equal/hash 一致且可作 Map 键" {
  let a = @client.Address::new(scheme="http", host="Example.com", port=80)
  let b = @client.Address::new(scheme="http", host="example.com", port=80)
  let c = @client.Address::new(scheme="http", host="example.com", port=8080)
  let d = @client.Address::new(scheme="https", host="example.com", port=80)
  // equal ⇒ hash 相等；不等键 hash 允许碰撞但不串 Map 条目
  assert_eq(a.hash(), b.hash(), msg="equal ⇒ 同 hash")
  let m : Map[@client.Address, Int32] = Map([], capacity=8)
  m[a] = 1
  assert_eq(m.get(b), Some(1), msg="规范化同键应命中同一条目")
  assert_eq(m.get(c), None, msg="跨端口不得命中")
  assert_eq(m.get(d), None, msg="跨 scheme 不得命中")
  m[b] = 2
  assert_eq(m.get(a), Some(2), msg="同键写入互见（键语义一致）")
}
