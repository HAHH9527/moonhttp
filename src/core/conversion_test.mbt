///|
// conversion_test：Request::to_http_request 纯转换层黑盒测试（T007）。
//
// 用例来源：contracts/conversion-errors.md 验收锚点表（spec US-2、
// FR-004/005、SC-003）；转换层纯函数属性、请求目标重组、
// Content-Length/Content-Type 覆盖规则（2026-10-16 裁决 A，research R5）。
//
// OkHttp 移植对拍清单（SC-005，宪法 III/IV；T018 固化）：
//   来源：OkHttp 5.5.0 (Apache-2.0)
//   【移植组】BridgeInterceptor.kt:42-54 + Request.kt:247-256 的 body 覆盖
//     语义（2026-10-16 裁决 A：body 的 Content-Type/Content-Length 覆盖
//     用户同名头；Content-Length = None 时删除该键等价 removeHeader；
//     TE 由上游自管、不注入）；Content-Length 定长帧规则（已知长度体不落
//     chunked）。
//   【显式差异组】响应头序不保真（重建侧）；线上字节形态断言（含空体
//     POST 的 SC-002 锚点）前置 P03 裸 TCP 夹具（T009 登记欠账，随 P03
//     闭环）。
//
// 断言面说明：本包验收以转换层三元组（meth/path/folded headers）为准，
// 不触网络、不断言线上序。

///|
// 黑盒辅助：构造带 Bytes 体的 POST 请求
fn post_request_with_bytes(
  data : Bytes,
  content_type~ : String? = None,
) -> @core.Request raise {
  let body = @core.RequestBody::bytes(
    data,
    data.length().to_int64(),
    content_type~,
  )
  @core.RequestBuilder::new(sample_url())
  .method(@core.Method::Post)
  .body(body)
  .build()
}

///|
// 黑盒辅助：转换输出快照（纯函数性断言的比较面；headers 按该包 Map 遍历
// 序渲染——同一 Request 的多次转换逐字节可比。meth 不入快照：RequestMethod
// 的 Show impl 已弃用，封闭映射由独立用例断言）
fn conversion_snapshot(req : @core.Request) -> String {
  let out = req.to_http_request()
  let sb = StringBuilder()
  sb.write_string("path=\{out.path}")
  for name, value in out.headers {
    sb.write_string("|\{name.to_string()}=\{value}")
  }
  sb.to_string()
}

///|
// ① 纯函数性属性（SC-003）：同一 Request 重复转换 N 次输出逐字节相同
test "T007① 纯函数性：同一 Request 转换 N 次输出逐字节相同" {
  let req = post_request_with_bytes(b"payload", content_type=Some("text/plain"))
  let first = conversion_snapshot(req)
  for _ in 0..<5 {
    assert_eq(conversion_snapshot(req), first)
  }
}

///|
// ② path 重组：origin-form 请求目标 `/a/c`、有 query 追加 `?query`、
// fragment 剥除（research R3：上游把该串原样写入请求行）
test "T007② path 重组：/a/c 形态 + query 追加 + fragment 剥除" {
  // 基本形态：path 段以 / 重组
  let plain = @core.RequestBuilder::new(
    @core.HttpUrl::parse("http://example.com/a/c"),
  ).build()
  assert_eq(plain.to_http_request().path, "/a/c")
  // 有 query：追加 ?query
  let with_query = @core.RequestBuilder::new(
    @core.HttpUrl::parse("http://example.com/a/c?key=value"),
  ).build()
  assert_eq(with_query.to_http_request().path, "/a/c?key=value")
  // fragment 剥除：不出现在请求目标
  let with_fragment = @core.RequestBuilder::new(
    @core.HttpUrl::parse("http://example.com/a/c?key=value#frag"),
  ).build()
  let path = with_fragment.to_http_request().path
  assert_eq(path, "/a/c?key=value")
  assert_false(path.contains("#"))
  // 无 query：不追加 ?（?后缀不出现）
  assert_false(plain.to_http_request().path.contains("?"))
}

///|
// ③ Content-Length 覆盖/删除规则（FR-004 + 裁决 A）：Bytes 体（n=len）→
// 含 `Content-Length: n`；Stream 体（None）→ 输出无该键（→ 线上 chunked，
// 线上形态断言随 T009/P03）
test "T007③ Content-Length：Bytes 含、Stream(None) 不含" {
  // Bytes 体（n=7）
  let bytes_req = post_request_with_bytes(b"payload")
  let out = bytes_req.to_http_request()
  assert_eq(
    out.headers.get(@http.CaseInsensitiveString("Content-Length")),
    Some("7"),
  )
  // Stream 体（content_length=None）
  let stream_body = @core.RequestBody::stream(async fn(_writer) {
    @async.pause()
  })
  let stream_req = @core.RequestBuilder::new(sample_url())
    .method(@core.Method::Post)
    .body(stream_body)
    .build()
  let stream_out = stream_req.to_http_request()
  assert_eq(
    stream_out.headers.get(@http.CaseInsensitiveString("Content-Length")),
    None,
  )
  // Stream 体显式 Some(n) → 注入定长 Content-Length
  let fixed_stream = @core.RequestBody::stream(
    async fn(_writer) { @async.pause() },
    content_length=Some(12L),
  )
  let fixed_req = @core.RequestBuilder::new(sample_url())
    .method(@core.Method::Post)
    .body(fixed_stream)
    .build()
  assert_eq(
    fixed_req.to_http_request().headers.get(
      @http.CaseInsensitiveString("Content-Length"),
    ),
    Some("12"),
  )
}

///|
// ④ Content-Type 覆盖语义（2026-10-16 裁决 A，对齐 OkHttp
// BridgeInterceptor.kt:42-45 + Request.kt:247-256 替换语义）：body 带
// type → 覆盖用户同名头（大小写不敏感单键替换）；body 缺 type 或
// body = None → 用户头保持不动
test "T007④ Content-Type 覆盖语义：body 值覆盖、缺省不动" {
  // body 带 type → 覆盖用户同名 Content-Type
  let hb = @core.HeadersVBuilder::new()
  hb.add("content-type", "text/custom")
  let overriding = @core.RequestBuilder::new(sample_url())
    .method(@core.Method::Post)
    .headers(hb.build())
    .body(
      @core.RequestBody::bytes(
        b"payload",
        7L,
        content_type=Some("application/json"),
      ),
    )
    .build()
  assert_eq(
    overriding.to_http_request().headers.get(
      @http.CaseInsensitiveString("Content-Type"),
    ),
    Some("application/json"),
  )
  // body 不带 type → 无 Content-Type 可覆盖（无 body.content_type 时
  // 用户头保持不动；此处用户未设 → 输出无该键）
  let plain_body = @core.RequestBody::bytes(b"payload", 7L)
  let plain = @core.RequestBuilder::new(sample_url())
    .method(@core.Method::Post)
    .body(plain_body)
    .build()
  assert_eq(
    plain.to_http_request().headers.get(
      @http.CaseInsensitiveString("Content-Type"),
    ),
    None,
  )
}

///|
// ④ 补（裁决 A 锚点）：Content-Length 覆盖为 n、删除、body=None 透传
test "T007④ 补：Content-Length 覆盖/删除/透传三态" {
  // 用户设错 Content-Length + body Some(n) → 输出为 n（覆盖）
  let hb = @core.HeadersVBuilder::new()
  hb.add("Content-Length", "999")
  let wrong_cl = @core.RequestBuilder::new(sample_url())
    .method(@core.Method::Post)
    .headers(hb.build())
    .body(@core.RequestBody::bytes(b"payload", 7L))
    .build()
  assert_eq(
    wrong_cl.to_http_request().headers.get(
      @http.CaseInsensitiveString("Content-Length"),
    ),
    Some("7"),
  )
  // Stream(None) + 用户声明 Content-Length → 该键被删除（线上 chunked）
  let hb2 = @core.HeadersVBuilder::new()
  hb2.add("Content-Length", "5")
  let deleted = @core.RequestBuilder::new(sample_url())
    .method(@core.Method::Post)
    .headers(hb2.build())
    .body(@core.RequestBody::stream(async fn(_writer) { @async.pause() }))
    .build()
  assert_eq(
    deleted.to_http_request().headers.get(
      @http.CaseInsensitiveString("Content-Length"),
    ),
    None,
  )
  // body = None + 用户声明 Content-Length/Content-Type → 原样透传
  // （用 GET 构造：POST 缺体会被 C5 矩阵拒绝，与本用例无关）
  let hb3 = @core.HeadersVBuilder::new()
  hb3.add("Content-Length", "5")
  hb3.add("Content-Type", "text/custom")
  let passthrough = @core.RequestBuilder::new(sample_url())
    .headers(hb3.build())
    .build()
  let out = passthrough.to_http_request()
  assert_eq(
    out.headers.get(@http.CaseInsensitiveString("Content-Length")),
    Some("5"),
  )
  assert_eq(
    out.headers.get(@http.CaseInsensitiveString("Content-Type")),
    Some("text/custom"),
  )
}

///|
// ⑤ Bytes 体重放（SC-003 重放性）：同一 Request 重放 N 次，体源内容逐字节
// 一致（Bytes 为不可变引用值，克隆 O(1)）
test "T007⑤ Bytes 体可重放：N 次取用内容逐字节一致" {
  let data = b"replayable-bytes"
  let req = post_request_with_bytes(data)
  for _ in 0..<3 {
    match req.body {
      Some(body) =>
        match body.source {
          @core.BodySource::Bytes(snapshot) => assert_eq(snapshot, data)
          _ => fail("应为 Bytes 体源")
        }
      None => fail("body 应当就位")
    }
    // 转换层输出亦逐字节稳定（重放不改变元信息）
    assert_eq(
      req.to_http_request().headers.get(
        @http.CaseInsensitiveString("Content-Length"),
      ),
      Some("16"),
    )
  }
}

///|
// ⑥ 空体 Bytes（n=0）→ headers 含 `Content-Length: 0`（spec 边界用例
// 「空体 POST 不落 chunked」，U1 补锚 2026-10-15；线上形态断言随 T009/P03）
test "T007⑥ 空体 POST：Content-Length: 0 注入" {
  let empty = post_request_with_bytes(b"")
  assert_eq(
    empty.to_http_request().headers.get(
      @http.CaseInsensitiveString("Content-Length"),
    ),
    Some("0"),
  )
}

///|
// 补充锚点：meth 经 P01 Method::to_request_method 封闭映射（九方法全表）
test "T007 补：meth 封闭映射（九方法）" {
  let pairs = [
    (@core.Method::Get, @http.RequestMethod::Get),
    (@core.Method::Post, @http.RequestMethod::Post),
    (@core.Method::Put, @http.RequestMethod::Put),
    (@core.Method::Delete, @http.RequestMethod::Delete),
    (@core.Method::Head, @http.RequestMethod::Head),
    (@core.Method::Options, @http.RequestMethod::Options),
    (@core.Method::Trace, @http.RequestMethod::Trace),
    (@core.Method::Patch, @http.RequestMethod::Patch),
    (@core.Method::Connect, @http.RequestMethod::Connect),
  ]
  for pair in pairs {
    let (m, expected) = pair
    // 必体组（Post/Put/Patch）按 C5 矩阵带体构造
    let builder = @core.RequestBuilder::new(sample_url()).method(m)
    let builder = match m {
      @core.Method::Post | @core.Method::Put | @core.Method::Patch =>
        builder.body(@core.RequestBody::bytes(b"x", 1L))
      _ => builder
    }
    assert_eq(builder.build().to_http_request().meth, expected)
  }
}
