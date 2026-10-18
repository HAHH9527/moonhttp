///|
// T009 独立复核性能探针（B2/B3，owner 2026-10-16 授权工单；独立复核方产物，
// 非 T009 交付物）。
//
// 测什么（roadmap L2 杠杆的机制面）：
//   1. 同一份体数据经「Bytes 定长帧」与「Stream chunked 帧」两条发送路径
//      的每请求墙钟成本与线上字节数——经 @core 转换层输出驱动真实
//      @http.Client，对端为 src/fixtures 裸 TCP 夹具（逐请求捕获 raw 长度）。
//   2. `Request::to_http_request` 纯函数的单位成本（10^6 次循环）。
//
// 口径护栏（B4）：本数字仅指示性；正式基准门归 P10。机器未做隔离
// （桌面 Windows、共享资源）、时钟为 @async.now() 毫秒精度、夹具
// capture_one 的帧扫描成本两臂共有（chunked 臂的扫描略多，见报告）。
// 无对照组与方差依据时不得外推为「性能提升 X%」。
//
// 宪法 IV：全部连接仅 127.0.0.1。D8：代码自建，未搬运上游资产。

///|
// 构造确定性负载块（FixedArray 填充后转 Bytes，同 raw_peer 夹具手法）
fn make_block(n : Int32) -> Bytes {
  let arr : FixedArray[Byte] = FixedArray::make(n, b'\x00')
  for i = 0; i < n; i = i + 1 {
    arr[i] = (i % 251).to_byte()
  }
  arr.unsafe_reinterpret_as_bytes()
}

///|
// 8×8KiB 分块（chunked 臂的流式写入单位）
fn make_chunks(count : Int32, size : Int32) -> Array[Bytes] {
  let out : Array[Bytes] = []
  for i = 0; i < count; i = i + 1 {
    out.push(make_block(size))
  }
  out
}

///|
// 定长臂的转换层输出：Bytes 体（content_length=Some(n)），带 Content-Type
// 覆盖路径，与 T009a 同构；Request URL 的 host:port 不上线（夹具实际端口
// 经 Client URI 给出），与 src/core/wire_form_test.mbt 同口径。
// 返回值已是 to_http_request 产物（转换成本单独测，不进发送回路）
fn fixed_out(payload : Bytes) -> @http.Request raise {
  let body = @core.RequestBody::bytes(
    payload,
    payload.length().to_int64(),
    content_type=Some("application/octet-stream"),
  )
  let builder = @core.RequestBuilder::new(
    @core.HttpUrl::parse("http://127.0.0.1:1/"),
  ).method(@core.Method::Post)
  builder.header("X-Probe", "perf")
  let builder = builder.body(body)
  builder.build().to_http_request()
}

///|
// chunked 臂的转换层输出：Stream 体（content_length=None → 转换层删除
// Content-Length，上游落 Transfer-Encoding: chunked），带 Content-Type
fn chunked_out() -> @http.Request raise {
  let body = @core.RequestBody::stream(
    _writer => (),
    content_type=Some("application/octet-stream"),
  )
  let builder = @core.RequestBuilder::new(
    @core.HttpUrl::parse("http://127.0.0.1:1/"),
  ).method(@core.Method::Post)
  builder.header("X-Probe", "perf")
  let builder = builder.body(body)
  builder.build().to_http_request()
}

///|
// 单次发送：转换层输出（预构造）驱动真实 @http.Client，经夹具捕获线上
// 首帧，返回线上 raw 字节数。writes：定长臂 = 单元素（整体一次 write）；
// chunked 臂 = 逐块多次 write（体回调不经此路径——chunked 帧由
// extra_headers 无 Content-Length 触发（send.mbt:343-347），Writer 即
// Client 本身（C1 裁决））
async fn send_once(out : @http.Request, writes : Array[Bytes]) -> Int32 {
  let peer = @fixtures.RawPeer::start()
  let port = peer.port()
  let slot : Array[@fixtures.CapturedRequest] = []
  let _ = @async.with_task_group() <| group => {
    group.spawn_bg(() => slot.push(peer.capture_one()))
    let client = @http.Client::Client("http://127.0.0.1:\{port}/")
    client.request(
      out.meth,
      out.path.to_string_view(),
      extra_headers=out.headers,
    )
    for data in writes {
      client.write(data)
    }
    let _resp = client.end_request()
    client.close()
    slot
  }
  peer.close()
  guard! slot.length() == 1
  slot[0].raw.length()
}

///|
// 预热 20 次 + 试点 30 次定 N：目标每轮 ≥500ms 墙钟（时钟 1ms 精度下
// 量化误差 ≤0.2%），同时钳位 [30, 400] 控制总时长与 TIME_WAIT 占用
async fn calibrate(
  tag : String,
  out : @http.Request,
  writes : Array[Bytes],
) -> Int32 {
  for i = 0; i < 20; i = i + 1 {
    let _ = send_once(out, writes)
  }
  let t0 = @async.now()
  for i = 0; i < 30; i = i + 1 {
    let _ = send_once(out, writes)
  }
  let pilot_ms = (@async.now() - t0).to_int()
  let n = if pilot_ms < 1 {
    400
  } else {
    let est = 500 * 30 / pilot_ms
    if est < 30 {
      30
    } else if est > 400 {
      400
    } else {
      est
    }
  }
  println("[probe] calibrate arm=\{tag} pilot30_ms=\{pilot_ms} n=\{n}")
  n
}

///|
// 单轮计时：墙钟、每请求微秒、平均线上字节数
async fn bench_round(
  tag : String,
  out : @http.Request,
  writes : Array[Bytes],
  n : Int32,
) -> Unit {
  let mut total_bytes = 0
  let t0 = @async.now()
  for i = 0; i < n; i = i + 1 {
    total_bytes = total_bytes + send_once(out, writes)
  }
  let ms = @async.now() - t0
  let us = ms.to_double() * 1000.0 / n.to_double()
  println(
    "[probe] arm=\{tag} n=\{n} total_ms=\{ms} us_per_req=\{us} bytes_per_req=\{total_bytes / n}",
  )
}

///|
// to_http_request 纯函数：10^6 次循环（ns/op 数值上恰等于 total_ms×1000，
// 因 1ms = 1e6ns 且恰好 1e6 次）
fn bench_conversion(req : @core.Request) -> Unit {
  for round = 1; round <= 3; round = round + 1 {
    let t0 = @async.now()
    for i = 0; i < 1_000_000; i = i + 1 {
      let _ = req.to_http_request()
    }
    let ms = @async.now() - t0
    let ns_per_op = ms * 1000L
    println(
      "[probe] to_http_request round=\{round} iters=1000000 total_ms=\{ms} ns_per_op=\{ns_per_op}",
    )
  }
}

///|
// to_http_request 基准输入：带 3 个自定义头 + path 重组（多段 + query）+
// Bytes 体（含 Content-Type / Content-Length 覆盖路径），构造一次、循环内
// 只测纯函数
fn conversion_req() -> @core.Request raise {
  let payload = make_block(1024)
  let body = @core.RequestBody::bytes(
    payload,
    payload.length().to_int64(),
    content_type=Some("application/octet-stream"),
  )
  let builder = @core.RequestBuilder::new(
    @core.HttpUrl::parse("http://127.0.0.1:1/a/b/c?k=v"),
  ).method(@core.Method::Post)
  builder.header("X-Probe-A", "aaa")
  builder.header("X-Probe-B", "bbb")
  builder.header("X-Probe-C", "ccc")
  let builder = builder.body(body)
  builder.build()
}

///|
async fn main {
  println(
    "[probe] 说明：T009 独立复核指示性 microbenchmark（B3），非 P10 正式基准",
  )
  // 同份体数据：64KiB 负载 = 8 个相同 8KiB 块顺序拼接（两臂字节内容一致）
  let blocks = make_chunks(8, 8192)
  let buf = Buffer()
  for blk in blocks {
    buf.write_bytes(blk)
  }
  let payload_64k = buf.to_bytes()
  let payload_1k = make_block(1024)
  let chunks_64k : Array[Bytes] = []
  for blk in blocks {
    chunks_64k.push(blk)
  }
  let arms : Array[(String, @http.Request, Array[Bytes])] = [
    ("fixed-1KiB", fixed_out(payload_1k), [payload_1k]),
    ("chunked-1KiB", chunked_out(), [payload_1k]),
    ("fixed-64KiB", fixed_out(payload_64k), [payload_64k]),
    ("chunked-64KiB-1x64KiB", chunked_out(), [payload_64k]),
    ("fixed-64KiB-8x8KiB", fixed_out(payload_64k), chunks_64k),
    ("chunked-64KiB-8x8KiB", chunked_out(), chunks_64k),
  ]
  // 先全部标定 N，再轮转 3 轮计时（轮转顺序降低慢漂移单臂偏置）
  let ns : Array[Int32] = []
  for arm in arms {
    ns.push(calibrate(arm.0, arm.1, arm.2))
  }
  for round = 1; round <= 3; round = round + 1 {
    for i, arm in arms {
      bench_round("\{arm.0} r\{round}", arm.1, arm.2, ns[i])
    }
  }
  bench_conversion(conversion_req())
  println("[probe] done")
}
