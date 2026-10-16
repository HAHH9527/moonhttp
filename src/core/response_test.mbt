///|
// response_test：Response/ResponseBody（buffered 态）黑盒测试（T010）。
//
// 用例来源：contracts/response.md 验收锚点表（spec US-3、FR-007/008/010、
// Edge Cases）；from_http 重建与 P01 折叠互逆（P01 SC-003 不变量②）、
// charset 三态（**2026-10-16 owner 裁决 B 覆写 C4**：集外按 UTF-8 降级
// 解码 + stderr 告警，不抛错）、0 字节、Debug 抽查。
//
// OkHttp 移植对拍清单（SC-005，宪法 III/IV；T018 固化）：
//   来源：OkHttp 5.5.0 (Apache-2.0)
//   【移植组】MediaType charset 参数解析口径（首个 charset= 参数、名值
//     大小写不敏感、引号值，research R5）；`string()` 替换式解码语义
//     （畸形 UTF-8 → U+FFFD 替换、从不抛错，经 @utf8.decode_lossy 对齐，
//     research R6）。
//   【显式差异组】BOM 不嗅探（OkHttp string() 嗅探并剥 BOM，本包保留
//     BOM 于结果中，R6）；响应头序不保真（from_http 重建为遍历序，
//     验收不断言线上序，FR-008）；cookies 不建 Jar（M1 透传）。
//
// 流式态生命周期事件测试见 response_body_lifecycle_test.mbt（T013）。

///|
// 黑盒辅助：由键值对构造上游响应头 Map（值已按上游语义合并）
fn response_headers_map(entries : Array[(String, String)]) -> @http.Headers {
  let map : @http.Headers = Map([])
  for entry in entries {
    let (name, value) = entry
    map[@http.CaseInsensitiveString(name)] = value
  }
  map
}

///|
// 黑盒辅助：构造 buffered 态响应体并经 from_http 组装（charset 上下文由
// 响应头经组装路径注入——research R5「取响应头 Map 中 Content-Type」）
fn buffered_response(
  data : Bytes,
  header_entries~ : Array[(String, String)] = [],
) -> @core.Response {
  @core.Response::from_http(
    200,
    "OK",
    response_headers_map(header_entries),
    [],
    body=Some(@core.ResponseBody::buffered(data)),
  )
}

///|
// ① from_http 重建：同名逗号合并值拆回多条（"a,b" → ["a","b"]），且与
// P01 折叠互逆（P01 SC-003 不变量②回读）；条目序 = Map 遍历序，不断言
// 线上序（FR-008）
test "T010① from_http 重建：逗号合并值拆回多条且与 P01 折叠互逆" {
  let resp = @core.Response::from_http(
    200,
    "OK",
    response_headers_map([
      ("Accept", "a,b"),
      ("X-Multi", "1,2,3"),
      ("X-Single", "keep"),
    ]),
    [],
  )
  // 拆回多条（大小写不敏感读取）
  assert_eq(resp.headers.values("accept").to_array(), ["a", "b"])
  assert_eq(resp.headers.values("x-multi").to_array(), ["1", "2", "3"])
  assert_eq(resp.headers.values("x-single").to_array(), ["keep"])
  // 与 P01 折叠互逆：重建值再折叠 → 回到合并单值（无空格逗号）
  let refolded = resp.headers.to_http_map()
  assert_eq(refolded.get(@http.CaseInsensitiveString("Accept")), Some("a,b"))
  assert_eq(refolded.get(@http.CaseInsensitiveString("X-Multi")), Some("1,2,3"))
}

///|
// ② buffered 态 bytes() 返回完整负载；0 字节 → 空不报错
async test "T010② bytes()：完整负载与 0 字节边界" {
  let resp = buffered_response(b"hello world")
  match resp.body {
    Some(body) => assert_eq(body.bytes(), b"hello world")
    None => fail("body 应当就位")
  }
  let empty = buffered_response(b"")
  match empty.body {
    Some(body) => assert_eq(body.bytes(), b"")
    None => fail("body 应当就位")
  }
}

///|
// ③ text() charset 三态（**2026-10-16 owner 裁决 B 覆写 C4** / research
//    R5）：charset=UTF-8（任意大小写/带引号）→ UTF-8 解码；charset=gbk
//    → 按 UTF-8 降级解码（返回 decode_lossy 结果、不抛错；stderr 告警为
//    人工可见诊断——core 无 stdout/stderr 捕获 API，告警文本无法在测试内
//    断言，测试只断言降级后的返回值）；无 Content-Type → 缺省 UTF-8
async test "T010③ text() charset 三态（裁决 B：集外降级不抛）" {
  let data = b"caf\xc3\xa9" // "café" 的 UTF-8 字节
  // 三态一：任意大小写 + 带引号 → UTF-8 解码
  for
    ct in [
      "text/html; charset=UTF-8", "text/html; charset=utf-8", "text/html; Charset=\"UTF-8\"",
    ] {
    let resp = buffered_response(data, header_entries=[("Content-Type", ct)])
    match resp.body {
      Some(body) => assert_eq(body.text(), "café")
      None => fail("body 应当就位")
    }
  }
  // 三态二：集外 charset → 按 UTF-8 降级解码，不抛错（裁决 B）。
  // 补锚：同一 gbk 声明下 text() 返回值 == @utf8.decode_lossy(原始字节)
  let gbk = buffered_response(data, header_entries=[
    ("Content-Type", "text/html; charset=gbk"),
  ])
  match gbk.body {
    Some(body) => {
      let decoded = body.text()
      assert_eq(decoded, "café")
      assert_eq(decoded, @utf8.decode_lossy(data[0:data.length()]))
    }
    None => fail("body 应当就位")
  }
  // 三态三：无 Content-Type → 缺省 UTF-8
  let no_ct = buffered_response(data)
  match no_ct.body {
    Some(body) => assert_eq(body.text(), "café")
    None => fail("body 应当就位")
  }
}

///|
// ③ 补（裁决 B）：集外声明下 bytes()/consumed 状态机不受 text() 降级
// 影响（buffered 态降级不改变负载与状态语义）
async test "T010③ 补：集外 charset 下 bytes()/consumed 不受影响" {
  let gbk = buffered_response(b"payload-bytes", header_entries=[
    ("Content-Type", "text/html; charset=gbk"),
  ])
  match gbk.body {
    Some(body) => {
      let _ : String = body.text()
      // bytes() 仍返回完整负载；consumed 状态查询正常
      assert_eq(body.bytes(), b"payload-bytes")
      assert_false(body.consumed())
      assert_false(body.dropped())
    }
    None => fail("body 应当就位")
  }
}

///|
// ④ 畸形 UTF-8 字节 → U+FFFD 替换不抛（decode_lossy；对齐 OkHttp
// string() 替换式解码语义，R6）
async test "T010④ 畸形 UTF-8：U+FFFD 替换不抛" {
  // "a" + \xc3（截断的双字节序列首字节）→ 替换为 U+FFFD
  let resp = buffered_response(b"a\xc3")
  match resp.body {
    Some(body) => assert_eq(body.text(), "a\ufffd")
    None => fail("body 应当就位")
  }
}

///|
// ⑤ 六要素访问器与 prior 字段就位（None，不产链；P06 填充）
test "T010⑤ 六要素访问器与 prior 就位" {
  let cookie = @http.Cookie::Cookie("sid", "test-session-123")
  let resp = @core.Response::from_http(
    404,
    "Not Found",
    response_headers_map([("Server", "synthetic")]),
    [cookie],
    body=Some(@core.ResponseBody::buffered(b"")),
  )
  assert_eq(resp.code(), 404)
  assert_eq(resp.reason(), "Not Found")
  assert_eq(resp.headers().values("server").to_array(), ["synthetic"])
  assert_eq(resp.cookies().length(), 1)
  assert_true(resp.body() is Some(_))
  assert_true(resp.prior() is None)
}

///|
// ⑥ Debug 抽查（R10）：ResponseBody/RequestBody 的 Debug 输出不含体字节
// 内容（输出实用性——避免调试打印转储大块字节；非脱敏验收项，掩码归
// M3 F13/F12）
test "T010⑥ Debug 输出不含体字节" {
  // ResponseBody：buffered 态印状态与长度元信息
  debug_inspect(
    @core.ResponseBody::buffered(b"secret-body-bytes"),
    content="\"ResponseBody(state=buffered, buffered_len=17)\"",
  )
  // RequestBody：Bytes 形态印元信息（长度），不印内容
  debug_inspect(
    @core.RequestBody::bytes(b"secret-body-bytes", 17L),
    content="\"RequestBody(content_type=None, content_length=17, source=Bytes(len=17))\"",
  )
}
