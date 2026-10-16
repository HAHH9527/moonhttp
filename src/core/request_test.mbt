///|
// request_test：Request/RequestBuilder/RequestBody 黑盒测试。
//
// 用例来源（宪法 IV，红-绿-重构）：
//   - T002：RequestBody::bytes 构造期校验两态、HttpMessageError 二变体判别（裁决 B）、
//     错误输出只携带定位片段；
//   - T005：spec US-1 场景 1–3 与方法/体矩阵（contracts/request.md 验收
//     锚点表，C5 裁决矩阵）；
//   - T015：with_progress 进度回调（contracts/request.md with_progress
//     锚点，Phase 7 增量）。
//
// OkHttp 移植对拍清单（SC-005，宪法 III/IV；T018 固化）：
//   来源：OkHttp 5.5.0 (Apache-2.0)
//   【移植组】Request.Builder 方法/体矩阵（permitsRequestBody/
//     requiresRequestBody 语义，C5 裁决；research R2 佐证链）、
//     ProgressRequestBody 进度语义（累计单调递增、终值 = content_length，
//     FR-009）、MediaType charset 参数解析口径（响应侧 text()，见
//     response_test.mbt）。
//   【显式差异组】tag 占位 Unit?（OkHttp 为任意 Object tag，本包 C2 裁决
//     不做按 tag 定位）；File/json 体形态裁剪（spec A7）；失败路径无独立
//     失败事件（research R4：错误沿 async 写调用原样传播）。
//
// 敏感样例值纪律（A9）：测试不使用真实凭证；错误输出断言只覆盖定位片段。
//
// 红-绿口径（I7 处置修正 2026-10-15）：本文件与 T003/T004（message_error/
// request_body）合入后共同验证；先合入时因类型缺失必然编译失败（红）。

///|
// T002①：RequestBody::bytes 构造期 O(1) 校验两态（C3 裁决）
test "T002① bytes 构造期：长度相等成功、不等 raise IncorrectBodyLength" {
  let data = b"hello"
  // 相等 → 构造成功，元信息就位
  let body = @core.RequestBody::bytes(data, 5L)
  assert_eq(body.content_length, Some(5L))
  assert_eq(body.content_type, None)
  // 不等 → raise IncorrectBodyLength（超写）
  try {
    let _ = @core.RequestBody::bytes(data, 4L)
    fail("应当 raise IncorrectBodyLength（声明 4 < 实际 5）")
  } catch {
    e => assert_true(e is @core.HttpMessageError::IncorrectBodyLength)
  }
  // 不等 → raise IncorrectBodyLength（欠写）
  try {
    let _ = @core.RequestBody::bytes(data, 6L)
    fail("应当 raise IncorrectBodyLength（声明 6 > 实际 5）")
  } catch {
    e => assert_true(e is @core.HttpMessageError::IncorrectBodyLength)
  }
}

///|
// T002① 补：content_type 透传
test "T002① bytes 构造期：content_type 可选透传" {
  let body = @core.RequestBody::bytes(
    b"{}",
    2L,
    content_type=Some("application/json"),
  )
  assert_eq(body.content_type, Some("application/json"))
  assert_eq(body.content_length, Some(2L))
}

///|
// T002②：HttpMessageError 二变体可判别（封闭二变体，2026-10-16 裁决 B；
// 错误不判等，用 is 模式匹配）
test "T002② HttpMessageError 二变体可判别" {
  let e1 : @core.HttpMessageError = @core.HttpMessageError::MethodBodyMismatch
  assert_true(e1 is @core.HttpMessageError::MethodBodyMismatch)
  let e2 : @core.HttpMessageError = @core.HttpMessageError::IncorrectBodyLength
  assert_true(e2 is @core.HttpMessageError::IncorrectBodyLength)
  // 互斥判别
  assert_false(e1 is @core.HttpMessageError::IncorrectBodyLength)
  assert_false(e2 is @core.HttpMessageError::MethodBodyMismatch)
}

///|
// T002③：to_repr 输出形态——只携带定位片段（方法名/长度对），不整体
// 回显触发输入（宪法敏感信息口径；A9：样例值合成占位）。样例改用
// IncorrectBodyLength（裁决 B：UnsupportedCharset 变体已删除）
test "T002③ 错误输出只携带定位片段、不整体回显" {
  // 无载荷变体：只含变体名
  debug_inspect(
    @core.HttpMessageError::MethodBodyMismatch,
    content="MethodBodyMismatch",
  )
  debug_inspect(
    @core.HttpMessageError::IncorrectBodyLength,
    content="IncorrectBodyLength",
  )
}

///|
// T002④：本文件 moon check 无 [0079]/[0027] 警告——随 T020 质量门核验
// （错误类型走 N1-A：derive(Debug) + pub extend Debug::{to_repr}）。

///|
// ============================================================================
// T005（US1）：Request/RequestBuilder 矩阵校验与组装
// 锚点：contracts/request.md 验收锚点表；spec US-1 场景 1–3
// ============================================================================

///|
// 黑盒辅助：构造测试 URL（P01 HttpUrl）
fn sample_url() -> @core.HttpUrl raise {
  @core.HttpUrl::parse("http://example.com/a/c")
}

///|
// 黑盒辅助：断言 build() 必 raise HttpMessageError 且满足判别谓词
// （catch 以根 Error 接住后按子错误模式判别——错误不判等，R10）
fn expect_build_error(
  builder : @core.RequestBuilder,
  check : (Error) -> Bool,
) -> Unit raise {
  try {
    let _ = builder.build()
  } catch {
    e => assert_true(check(e))
  } noraise {
    _ => fail("应当 raise HttpMessageError")
  }
}

///|
// US-1 场景 1：链式设置五要素，逐项正确；headers 保序可重复
test "T005① US-1 场景1：链式五要素 + headers 保序可重复" {
  let hb = @core.HeadersVBuilder::new()
  hb.add("Accept", "text/html")
  hb.add("X-Multi", "1")
  hb.add("X-Multi", "2")
  let body = @core.RequestBody::bytes(b"payload", 7L)
  let req = @core.RequestBuilder::new(sample_url())
    .method(@core.Method::Post)
    .headers(hb.build())
    .tag(Some(()))
    .body(body)
    .build()
  assert_eq(req.url, sample_url())
  assert_eq(req.method, @core.Method::Post)
  assert_eq(req.headers.values("x-multi").to_array(), ["1", "2"])
  assert_eq(req.headers.get("ACCEPT"), Some("text/html"))
  assert_eq(req.tag, Some(()))
  // body 无判等（R10）：以元信息与形态判别断言
  match req.body {
    Some(b) => {
      assert_eq(b.content_length, Some(7L))
      assert_true(b.source is @core.BodySource::Bytes(_))
    }
    None => fail("body 应当就位")
  }
}

///|
// US-1 场景 2：未设 method/body → 默认 Get + None
test "T005① US-1 场景2：method 缺省 Get、body 缺省 None" {
  let req = @core.RequestBuilder::new(sample_url()).build()
  assert_eq(req.method, @core.Method::Get)
  assert_true(req.body is None)
  assert_eq(req.tag, None)
}

///|
// US-1 场景 3（C5 矩阵）：GET/HEAD 带 body 拒绝；POST/PUT/PATCH 缺 body 拒绝
test "T005① US-1 场景3：矩阵拒体组与必体组双向校验" {
  // GET + body → MethodBodyMismatch
  expect_build_error(
    @core.RequestBuilder::new(sample_url()).body(
      @core.RequestBody::bytes(b"x", 1L),
    ),
    e => e is @core.HttpMessageError::MethodBodyMismatch,
  )
  // HEAD + body → MethodBodyMismatch
  expect_build_error(
    @core.RequestBuilder::new(sample_url())
    .method(@core.Method::Head)
    .body(@core.RequestBody::bytes(b"x", 1L)),
    e => e is @core.HttpMessageError::MethodBodyMismatch,
  )
  // POST/PUT/PATCH 缺 body → MethodBodyMismatch
  for m in [@core.Method::Post, @core.Method::Put, @core.Method::Patch] {
    expect_build_error(@core.RequestBuilder::new(sample_url()).method(m), e => {
      e is @core.HttpMessageError::MethodBodyMismatch
    })
  }
}

///|
// C5 矩阵可选组：DELETE/OPTIONS/TRACE/CONNECT ± body 构造成功
test "T005② 矩阵可选组：四方法带体/不带体均成功" {
  for
    m in [
      @core.Method::Delete,
      @core.Method::Options,
      @core.Method::Trace,
      @core.Method::Connect,
    ] {
    // 不带体
    let bare = @core.RequestBuilder::new(sample_url()).method(m).build()
    assert_eq(bare.method, m)
    assert_true(bare.body is None)
    // 带体
    let with_body = @core.RequestBuilder::new(sample_url())
      .method(m)
      .body(@core.RequestBody::bytes(b"x", 1L))
      .build()
    assert_true(with_body.body is Some(_))
  }
}

///|
// `header(...)` 非法名/值 raise HeadersError（P01 委托继承，I12 消歧）
// 且 Builder 状态不变
test "T005③ header 非法输入：raise HeadersError 且 Builder 状态不变" {
  let builder = @core.RequestBuilder::new(sample_url())
  builder.header("Accept", "text/html")
  // 非法头名（含非 token 字符）
  try {
    builder.header("Bad Name", "v")
    fail("应当 raise HeadersError（非法名）")
  } catch {
    e => assert_true(e is @core.HeadersError::InvalidName)
  }
  // 非法头值（含 CR/LF 注入）
  try {
    builder.header("X-Inject", "a\r\nX-Evil: 1")
    fail("应当 raise HeadersError（非法值）")
  } catch {
    e => assert_true(e is @core.HeadersError::InvalidValue)
  }
  // Builder 状态不变：非法调用未污染既有头；build 仍成功
  let req = builder.build()
  assert_eq(req.headers.values("Accept").to_array(), ["text/html"])
  assert_eq(req.headers.values("Bad Name").to_array(), [])
  assert_eq(req.headers.values("X-Inject").to_array(), [])
}

///|
// `tag` 存取往返（Unit? 占位，无任何定位语义——C2 裁决）
test "T005④ tag 存取往返" {
  let req1 = @core.RequestBuilder::new(sample_url()).tag(None).build()
  assert_eq(req1.tag, None)
  let req2 = @core.RequestBuilder::new(sample_url()).tag(Some(())).build()
  assert_eq(req2.tag, Some(()))
}

///|
// 校验失败后修正再次 build() 成功（可重入）
test "T005⑤ build 失败后修正可重入" {
  let builder = @core.RequestBuilder::new(sample_url())
    .method(@core.Method::Get)
    .body(@core.RequestBody::bytes(b"x", 1L))
  // 第一次 build：GET 带体 → 失败
  expect_build_error(builder, e => {
    e is @core.HttpMessageError::MethodBodyMismatch
  })
  // 修正：改为 POST → 同一 Builder 再次 build 成功
  let fixed = builder.method(@core.Method::Post).build()
  assert_eq(fixed.method, @core.Method::Post)
  assert_true(fixed.body is Some(_))
}

///|
// ============================================================================
// T015（US5）：with_progress 上传进度回调
// 锚点：contracts/request.md with_progress 锚点 + conversion-errors.md
// 条款 7（组合不变式）；FR-009。
//
// 驱动口径说明：冻结契约的 Stream 回调为同步形态 `(&@io.Writer) -> Unit`
// （C1 裁决落点），写侧数据移动由异步上下文驱动——测试以「同步回调捕获
// 计数 Writer 引用 + 异步写驱动」组合完成（对齐 P05 将来的驱动方式：
// 回调只装配，写由发送循环执行）。FR-009 的累计不变式（单调递增、终值 =
// content_length）仅对 Stream 形态承诺并经本文件全量验证；Bytes 形态
// 不承诺回调（2026-10-16 owner 裁决 C——spec FR-009 裁剪，非欠账），
// 仅断言元信息与转换输出恒等（T015③/T015 补）。
//
// 桩纪律（管道语义，探针实证）：@io.pipe 的写侧必须有并发读侧排空，
// 且只以「关闭写端 → EOF」收尾；关闭读端/写后复写在本工具链为运行时
// 致命 abort（非可捕错误）——失败路径改用可控的 Writer 桩驱动。

///|
// 黑盒夹具：首次写成功、其后写抛桩错误的 Writer（T015④）。
// 以测试包自持的可判别错误充当「上游写错误」替身（research R4：错误沿
// async 写调用原样传播、不并入 FR-012 封闭错误类型——上游 @io.PipeClosed
// 为只读类型不可构造，传播路径语义不变）。
suberror SyntheticWriteError {
  UpstreamWriteFailed
} derive(Debug)

///|
struct OneShotWriter {
  mut spent : Bool
}

///|
impl @io.Writer for OneShotWriter with fn write_once(self, _data, offset~, len~) {
  ignore(offset)
  if self.spent {
    raise SyntheticWriteError::UpstreamWriteFailed
  }
  self.spent = true
  len
}

///|
// ② Stream 体：包计数 Writer 后写入，回调累计与实际写量一致
async test "T015② Stream 进度：计数 Writer 累计与写量一致" {
  @async.with_task_group() <| _root => {
    let holder : Array[&@io.Writer] = []
    let events : Array[Int64] = []
    let body = @core.RequestBody::stream(w => holder.push(w))
    let wrapped = body.with_progress(total => events.push(total))
    let (pipe_reader, pipe_writer) = @io.pipe()
    // 读侧排空（管道写侧必须有并发读者）；写端关闭后 EOF 结束
    _root.spawn_bg(() => {
      while pipe_reader.read_some() is Some(_) {
        ()
      }
    })
    // 从包装后的体源取出回调并装配（用户回调捕获计数 Writer）
    let counting : &@io.Writer = match wrapped.source {
      @core.BodySource::Stream(f) => {
        f(pipe_writer)
        holder[0]
      }
      _ => fail("应为 Stream 形态")
    }
    // 异步驱动写侧：累计回调 [5, 12]
    counting.write(b"hello")
    counting.write(b"world!!")
    pipe_writer.close()
    assert_eq(events, [5L, 12L])
    // 单调递增
    assert_true(events[1] > events[0])
  }
}

///|
// ① FR-009 累计不变式（经 Stream 形态驱动，1MB / 64KB 分块）：累计值
// 单调递增、终值 = content_length
async test "T015① FR-009 累计不变式：单调递增、终值 = content_length（1MB）" {
  @async.with_task_group() <| root => {
    let (pipe_reader, pipe_writer) = @io.pipe()
    // 读侧排空（模拟发送消费）；写端关闭后 EOF 结束
    root.spawn_bg(() => {
      while pipe_reader.read_some() is Some(_) {
        ()
      }
    })
    let holder : Array[&@io.Writer] = []
    let events : Array[Int64] = []
    let body = @core.RequestBody::stream(
      w => holder.push(w),
      content_length=Some(1048576L),
    )
    let wrapped = body.with_progress(total => events.push(total))
    let counting : &@io.Writer = match wrapped.source {
      @core.BodySource::Stream(f) => {
        f(pipe_writer)
        holder[0]
      }
      _ => fail("应为 Stream 形态")
    }
    // 64KB × 16 = 1MB 分块写
    let chunk = Bytes::make(65536, b'a')
    for _ in 0..<16 {
      counting.write(chunk)
    }
    pipe_writer.close()
    // FR-009：非空、单调递增、终值 = content_length
    assert_true(events.length() > 0)
    for i, v in events {
      if i > 0 {
        assert_true(v > events[i - 1])
      }
    }
    assert_eq(events[events.length() - 1], 1048576L)
  }
}

///|
// ③ 组合不变式（conversion-errors.md 条款 7）：with_progress 包装前后
// to_http_request 输出逐字节相同（content_length 元信息不被包装改变——
// 进度分块不降级 chunked）
test "T015③ 组合不变式：包装前后转换输出逐字节相同" {
  // Bytes 形态
  let bytes_body = @core.RequestBody::bytes(
    b"payload",
    7L,
    content_type=Some("text/plain"),
  )
  let plain_req = @core.RequestBuilder::new(sample_url())
    .method(@core.Method::Post)
    .body(bytes_body)
    .build()
  let wrapped_bytes = bytes_body.with_progress(_total => ())
  let wrapped_req = @core.RequestBuilder::new(sample_url())
    .method(@core.Method::Post)
    .body(wrapped_bytes)
    .build()
  assert_eq(conversion_snapshot(plain_req), conversion_snapshot(wrapped_req))
  // Stream 形态（Some(n) 定长）：包装不改元信息
  let stream_body = @core.RequestBody::stream(
    _w => (),
    content_length=Some(7L),
    content_type=Some("text/plain"),
  )
  let stream_req = @core.RequestBuilder::new(sample_url())
    .method(@core.Method::Post)
    .body(stream_body)
    .build()
  let wrapped_stream = stream_body.with_progress(_total => ())
  let wrapped_stream_req = @core.RequestBuilder::new(sample_url())
    .method(@core.Method::Post)
    .body(wrapped_stream)
    .build()
  assert_eq(
    conversion_snapshot(stream_req),
    conversion_snapshot(wrapped_stream_req),
  )
  // 元信息逐项核对（条款 7：content_type/content_length 不被包装改变）
  assert_eq(wrapped_stream.content_length, Some(7L))
  assert_eq(wrapped_stream.content_type, Some("text/plain"))
}

///|
// ④ 失败路径：写中途错误可判别传播且 on_bytes 不再回调（research R4：
// 错误沿 async 写调用原样传播，不并入 FR-012 封闭错误类型）
async test "T015④ 失败路径：错误可判别传播、on_bytes 不再回调" {
  let holder : Array[&@io.Writer] = []
  let events : Array[Int64] = []
  let body = @core.RequestBody::stream(w => holder.push(w))
  let wrapped = body.with_progress(total => events.push(total))
  let counting : &@io.Writer = match wrapped.source {
    @core.BodySource::Stream(f) => {
      let stub : OneShotWriter = { spent: false, }
      f(stub)
      holder[0]
    }
    _ => fail("应为 Stream 形态")
  }
  // 第一次写成功：累计回调一次
  counting.write(b"ok")
  assert_eq(events, [2L])
  // 第二次写：上游桩抛 SyntheticWriteError，经计数 Writer 原样传播（可判别）
  try {
    counting.write(b"boom")
    let _ : Unit = fail("应当 raise 上游写错误")
  } catch {
    e => assert_true(e is SyntheticWriteError::UpstreamWriteFailed)
  } noraise {
    _ => fail("应当 raise 上游写错误")
  }
  // 错误路径不回调 on_bytes
  assert_eq(events, [2L])
}

///|
// Bytes 形态的 with_progress：冻结契约语义核对——包装不得改变
// content_type/content_length 元信息（条款 7），转换输出不变
test "T015 补：Bytes 包装保元信息与转换恒等" {
  let body = @core.RequestBody::bytes(
    b"12345",
    5L,
    content_type=Some("application/json"),
  )
  let wrapped = body.with_progress(_total => ())
  assert_eq(wrapped.content_length, Some(5L))
  assert_eq(wrapped.content_type, Some("application/json"))
}
