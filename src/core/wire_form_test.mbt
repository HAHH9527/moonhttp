///|
// wire_form_test：T009 线上字节断言（spec SC-002 四条锚点，
// specs/002-m1-p02-request-response/tasks.md:207-237、spec.md:383-387）。
//
// 驱动方式（工单「客户端驱动」条款）：`Request::to_http_request` 的输出
// 三元组直接喂上游 `@http.Client`（不经 P05），体经 Client 自身公开实现的
// `@io.Writer` 面写出；对端由 `@fixtures.RawPeer`（P03 裸 TCP 夹具）原样捕获
// 线上首帧。断言只针对帧头与块编码，不做整串字节相等比较——上游
// `send_request` 会自动补 `Accept-Encoding: gzip,identity`
// （.mooncakes/moonbitlang/async@0.22.4 src/http/send.mbt:338-342），
// 该头不在我们的 Map 里，整串比较必然假失败。
//
// 上游行为取证（同版本、本机 .mooncakes 解包；宪法 I：只经公开 API、不改上游）：
//   - src/http/pkg.generated.mbti:64/79/67/82/65 — `Client::Client(String,…)`、
//     `Client::request(Self, RequestMethod, StringView, extra_headers?)`、
//     `Client::end_request`、`Client::write(Self, &@io.Data)`、`Client::close`
//   - src/http/pkg.generated.mbti:86 — `pub impl @io.Writer for Client`
//     （体源回调收到 `&@io.Writer` 即 Client 本身，P02 C1 裁决）
//   - src/http/client.mbt:117-125 — `Client::Client(uri)` 且 `guard path is "/"`
//     （故 URI 路径必须是 `/`）
//   - src/http/client.mbt:252-282 — Host 与 Transfer-Encoding 不得出现在
//     extra_headers；Content-Length 若出现必须等于实际 body 总长
//   - src/http/send.mbt:37-39 + :292-311 — forbidden_headers 丢弃调用方 TE；
//     Content-Length 分支无 continue（透传上线并被解析为定长帧）
//   - src/http/send.mbt:343-345 — 有 Content-Length → `SendingFixed`；
//     无 → `WaitingRequestBody`
//   - src/http/send.mbt:103 + :134-146 — 首个体字节落地时才写
//     `Transfer-Encoding: chunked\r\n\r\n` 并转 `SendingBody`（故空体 POST
//     不落 chunked）
//   - src/http/send.mbt:253-254 — `SendingFixed(remaining=0)` 正常 flush、
//     非 0 剩余 raise IncorrectBodyLength（写欠即失败）
//
// Stream 形态的驱动口径：P02 的体源回调类型是同步签名
// `(&@io.Writer) -> Unit`（request_body.mbt:21），回调内不能发起异步写；
// 项目既有口径即 holder 模式（request_test.mbt:307-336 T015②）——回调取走
// Writer，真实写入在回调返回后由异步上下文完成。
//
// target 口径（tasks.md T009 注记①，converge 2026-10-16）：线上原始字节捕获
// 在 native 执行；wasm 若无法捕获则停下回报，不自立跳过机制、不改 spec 口径。
//
// 取证输出：core 测试无 stdout/stderr 捕获 API（~/.moon/lib/core/builtin 无
// 相应接口），故每条断言把捕获到的原始帧头以 `[T009 取证]` 行打印，作为回报
// 证据面；断言失败信息同样附带该文本。
//
// 宪法 IV：只连 127.0.0.1。宪法 VII：注释中文、标注取证行号。

///|
// 取证渲染：CRLF 转为可见转义（`String::replace` 只替换首个，须 replace_all——
// ~/.moon/lib/core/builtin/string_methods.mbt:2042 vs :2125）
fn wire_visible(s : String) -> String {
  s.replace_all(old="\r\n", new="\\r\\n")
}

///|
// note 的取证文本（`String?` 直接插值走已弃用的 Show，须显式展开）
fn note_text(note : String?) -> String {
  match note {
    Some(n) => n
    None => "（无）"
  }
}

///|
// 把转换层输出直接驱动到 @http.Client，返回对端捕获的线上首帧。
//
// Request 的 url 只贡献 origin-form 请求目标（conversion.mbt:39-54 只取
// path_segments + query），host/port 不上线；真实连接目标由对端实际端口经
// `Client::Client` 的 URI 给出（P05 才接管这一步，本测试不经 P05）。
//
// 写体口径：从 Request 自身的体源取值——Bytes 形态写其字节（长度 0 时不写，
// 空体定长帧由上游 `SendingFixed(remaining=0)` 收尾，send.mbt:253）；Stream
// 形态先以 Client 调用用户回调（它收到的 `&@io.Writer` 即 Client 本身，
// C1 裁决，收进调用方的 `writer_holder~`），再在异步上下文里经该 Writer
// 逐块写入 `chunks~`。
async fn wire_capture(
  req : @core.Request,
  chunks~ : Array[Bytes] = [],
  writer_holder~ : Array[&@io.Writer] = [],
) -> @fixtures.CapturedRequest {
  let peer = @fixtures.RawPeer::start()
  let port = peer.port()
  let out = req.to_http_request()
  // bg 任务在 group 退出前完成，故数组在 with_task_group 返回后已就位
  let slot : Array[@fixtures.CapturedRequest] = []
  let _ = @async.with_task_group() <| group => {
    group.spawn_bg(() => slot.push(peer.capture_one()))
    let client = @http.Client::Client("http://127.0.0.1:\{port}/")
    client.request(
      out.meth,
      out.path.to_string_view(),
      extra_headers=out.headers,
    )
    match req.body {
      Some(body) =>
        match body.source {
          @core.BodySource::Bytes(data) =>
            if data.length() > 0 {
              client.write(data)
            }
          @core.BodySource::Stream(f) => {
            f(client)
            if writer_holder.length() == 0 {
              fail("Stream 回调未收到 Writer（C1 承诺落空）")
            }
            let writer = writer_holder[0]
            for chunk in chunks {
              writer.write(chunk)
            }
          }
        }
      None => ()
    }
    // canned 200 回到客户端即证明对端写收尾后 end_request 正常返回（工单方案 6）
    let resp = client.end_request()
    assert_eq(resp.code, 200, msg="对端 canned 200 未回到客户端")
    client.close()
    slot
  }
  peer.close()
  if slot.length() == 0 {
    fail("对端未捕获到任何报文")
  }
  let cap = slot[0]
  println("[T009 取证] \{wire_visible(cap.head_text())}")
  cap
}

///|
// 断言面公共前提：帧收完、请求行为 `POST / HTTP/1.1`
fn assert_captured_frame(
  cap : @fixtures.CapturedRequest,
  tag : String,
) -> Unit raise {
  assert_true(
    cap.complete,
    msg="\{tag}：帧未收完（note=\{note_text(cap.note)}）",
  )
  assert_true(
    cap.head_text().has_prefix("POST / HTTP/1.1\r\n"),
    msg="\{tag}：请求行异常：\{wire_visible(cap.head_text())}",
  )
}

///|
// SC-002 锚点 a：Bytes 体（content_length=Some(n)）→ 线上含
// `Content-Length: n` 且不含 `Transfer-Encoding`
async test "T009a 线上：Bytes 体 Content-Length: 7、无 Transfer-Encoding" {
  let data = b"payload"
  let body = @core.RequestBody::bytes(data, 7L)
  let req = @core.RequestBuilder::new(
      @core.HttpUrl::parse("http://127.0.0.1:1/"),
    )
    .method(@core.Method::Post)
    .body(body)
    .build()
  let cap = wire_capture(req)
  assert_captured_frame(cap, "a")
  let head = cap.head_text()
  assert_true(
    head.contains("Content-Length: 7\r\n"),
    msg="a：线上缺 Content-Length: 7：\{wire_visible(head)}",
  )
  assert_false(
    head.contains("Transfer-Encoding"),
    msg="a：线上出现 Transfer-Encoding：\{wire_visible(head)}",
  )
  assert_eq(cap.chunked, false)
  // 体字节逐字节送达，未被改写
  assert_eq(cap.body, data)
}

///|
// SC-002 锚点 b：Stream 体（content_length=None）→ 线上含
// `Transfer-Encoding: chunked` 且块编码合法（合法性由夹具 walk_chunks 判停
// 校验后才交回 Complete：chunked=true、body 为剥壳拼接的负载）
async test "T009b 线上：Stream 体 Transfer-Encoding: chunked 与块编码" {
  // holder 模式（request_test.mbt:307-336 同口径）：同步回调只取走 Writer，
  // 真实异步写入由 wire_capture 在回调返回后经该 Writer 完成
  let holder : Array[&@io.Writer] = []
  let body = @core.RequestBody::stream(writer => holder.push(writer))
  let req = @core.RequestBuilder::new(
      @core.HttpUrl::parse("http://127.0.0.1:1/"),
    )
    .method(@core.Method::Post)
    .body(body)
    .build()
  let cap = wire_capture(
    req,
    chunks=[b"hello ", b"world"],
    writer_holder=holder,
  )
  // 回调确实收到 Client 的 Writer 面（C1 裁决的线上侧印证）
  assert_eq(holder.length(), 1)
  assert_captured_frame(cap, "b")
  let head = cap.head_text()
  assert_true(
    head.contains("Transfer-Encoding: chunked\r\n"),
    msg="b：线上缺 Transfer-Encoding: chunked：\{wire_visible(head)}",
  )
  assert_false(
    head.contains("Content-Length"),
    msg="b：chunked 与 Content-Length 并存：\{wire_visible(head)}",
  )
  assert_eq(cap.chunked, true)
  // 块编码合法：负载逐字节一致，末块为 0 长度 + CRLFCRLF
  assert_eq(cap.body, b"hello world")
  assert_true(
    wire_visible(cap.raw_text()).has_suffix("\\r\\n0\\r\\n\\r\\n"),
    msg="b：块终止符异常：\{wire_visible(cap.raw_text())}",
  )
}

///|
// SC-002 锚点 c：空体 Bytes(0) POST → 线上含 `Content-Length: 0`、
// 不落 chunked（U1 补锚 2026-10-15；机制取证 send.mbt:103/:134-146——
// 无体字节则永不进入 SendingBody，故不写 chunked 帧头）
async test "T009c 线上：空体 POST Content-Length: 0、不落 chunked" {
  let body = @core.RequestBody::bytes(b"", 0L)
  let req = @core.RequestBuilder::new(
      @core.HttpUrl::parse("http://127.0.0.1:1/"),
    )
    .method(@core.Method::Post)
    .body(body)
    .build()
  let cap = wire_capture(req)
  assert_captured_frame(cap, "c")
  let head = cap.head_text()
  assert_true(
    head.contains("Content-Length: 0\r\n"),
    msg="c：线上缺 Content-Length: 0：\{wire_visible(head)}",
  )
  assert_false(
    head.contains("Transfer-Encoding"),
    msg="c：空体落了 chunked：\{wire_visible(head)}",
  )
  assert_eq(cap.chunked, false)
  assert_eq(cap.body, b"")
  // 结构面：头部之后只剩空行 CRLF，线上无任何负载字节
  // （不断言 raw 不含子串 "0\r\n\r\n"——该串是 "Content-Length: 0\r\n\r\n" 的后缀）
  assert_eq(cap.raw.length(), cap.head.length() + 2)
}

///|
// SC-002 锚点 d：Bytes + with_progress 组合 → 线上仍是定长帧
// `Content-Length: 7` 且无 `Transfer-Encoding`（conversion-errors.md 条款 7：
// 进度包装不得把定长降级为 chunked）
async test "T009d 线上：Bytes+with_progress 组合不降级 chunked" {
  let events : Array[Int64] = []
  let body = @core.RequestBody::bytes(b"payload", 7L).with_progress(total => {
    events.push(total)
  })
  let req = @core.RequestBuilder::new(
      @core.HttpUrl::parse("http://127.0.0.1:1/"),
    )
    .method(@core.Method::Post)
    .body(body)
    .build()
  let cap = wire_capture(req)
  assert_captured_frame(cap, "d")
  let head = cap.head_text()
  assert_true(
    head.contains("Content-Length: 7\r\n"),
    msg="d：组合形态丢定义：\{wire_visible(head)}",
  )
  assert_false(
    head.contains("Transfer-Encoding"),
    msg="d：组合形态降级为 chunked：\{wire_visible(head)}",
  )
  assert_eq(cap.chunked, false)
  assert_eq(cap.body, b"payload")
  // Bytes 形态不承诺进度回调（FR-009 裁剪 + 2026-10-16 裁决 C）：
  // 定长帧线上形态不因包装而变，回调零触发是该裁剪的线上侧印证
  assert_eq(events.length(), 0)
}
