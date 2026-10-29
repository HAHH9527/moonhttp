///|
// follow_up_wbtest：P06 白盒测试（包内私有面直读——决策表纯函数、
// 代次折叠缓存、上限计数位置；005 call_wbtest 先例）。
// 红绿纪律（宪法 IV）：每测试先红后绿；首跑颜色实测记录，禁止事后
// 补造红灯。

///|
// 白盒辅助：按 code + headers 构造无体 Response（决策表纯函数输入面；
// 头经 HeadersVBuilder→to_http_map，与 R5 prior 构建同款互逆路径）。
// 返回（响应, 原始 @http.Headers）——WB⑧ 起 follow_up_request 的
// Location 读取走原始头 Map（H1 保真），用例须同时持有两态。
fn wb_resp(
  code : Int32,
  headers : Array[(String, String)],
) -> (@core.Response, @http.Headers) raise {
  let b = @core.HeadersVBuilder::new()
  for pair in headers {
    b.add(pair.0, pair.1)
  }
  let raw = b.build().to_http_map()
  (@core.Response::from_http(code, "", raw, []), raw)
}

///|
// 白盒辅助：构造指定方法/路径的 Request（决策表纯函数输入面）。
fn wb_req(
  port : Int32,
  path : String,
  meth : @core.Method,
) -> @core.Request raise {
  let url = @core.HttpUrl::parse("http://127.0.0.1:\{port}\{path}")
  @core.RequestBuilder::new(url).method(meth).build()
}

///|
// P06-WB①（FR-003 行 4/5 + FR-008 白盒半边，T002）：决策表 Terminal
// 恒判——304/305/306/401/407/408/200（含带 Location 形态，判码优先于
// Location）与 3xx 六码无 Location 一律 Terminal。纯函数无 IO（T016
// 穷举矩阵同口径，零夹具零网络）。
test "P06-WB① 决策表 Terminal 骨架：不跟随集合 + 3xx 无 Location" {
  // 不跟随集合与其余码：带 Location 也不跟随（行 4/5 判码优先）。
  // 方法取 Delete（非 GET/HEAD 且无体合法——P02 矩阵 Post/Put/Patch 必体）
  for code in [200, 304, 305, 306, 401, 407, 408] {
    let request = wb_req(1, "/a", @core.Method::Delete)
    let (response, raw) = wb_resp(code, [("Location", "/b")])
    assert_true(
      follow_up_request(response, request, raw) is Terminal,
      msg="code=\{code} 带 Location 应恒判 Terminal（FR-003 行 4/5）",
    )
  }
  // 3xx 无 Location：原响应终态（FR-008）
  for code in [300, 301, 302, 303, 307, 308] {
    let request = wb_req(1, "/a", @core.Method::Delete)
    let (response, raw) = wb_resp(code, [])
    assert_true(
      follow_up_request(response, request, raw) is Terminal,
      msg="code=\{code} 无 Location 应判 Terminal（FR-008）",
    )
  }
}

///|
// P06-WB①b（R9 两件套判别面，T002）：TooManyFollowUps derive(Debug)
// 且 `err is` 可判别、与既有两变体互不误判。
test "P06-WB①b TooManyFollowUps：Debug 可判别" {
  fn raise_too_many() -> Unit raise {
    raise TooManyFollowUps
  }

  let got = try {
    raise_too_many()
    false
  } catch {
    err => err is TooManyFollowUps
  }
  let not_cancelled = try {
    raise_too_many()
    false
  } catch {
    err => err is CallCancelled
  }
  let not_state = try {
    raise_too_many()
    false
  } catch {
    err => err is CallStateError
  }
  assert_true(got, msg="TooManyFollowUps 应可判别（FR-005）")
  assert_false(not_cancelled, msg="不得误判为 CallCancelled")
  assert_false(not_state, msg="不得误判为 CallStateError")
  // derive(@debug.Debug) + to_repr extend：可渲染不 panic（经 trait 面）
  let _ = @debug.Debug::to_repr(TooManyFollowUps)
}

///|
// ===== P06-WB③④（T004，循环直通 + 轮间取消 guard）=====

///|
// P06-WB③（T004，T007 后前提订正）：非跟随响应（200，FR-003 行 5）下
// 循环 = 单轮 exchange，与 P05 等价——终态原样返回、prior=None、夹具侧
// 恰 1 请求。（原场景用 301+Location 钉「骨架期 Terminal-only」，该
// 阶段性前提随 T005/T007 决策表展开而失效——301+Location 现按 FR-003
// 行 1 正确跟随，测试前提改用恒 Terminal 的 200，断言结构不变。）
async test "P06-WB③ 循环直通：非跟随响应单轮等价、prior None" {
  @async.with_task_group() <| group => {
    let server = @fixtures.ScriptedServer::start()
    server.mount("GET", "/hop", {
      status: 200,
      headers: [],
      framing: Fixed,
      body: Static(b"ok"),
      head_delay_ms: 0,
      close_after_response: false,
    })
    let s1 = group.spawn(
      () => server.serve_once(timeout_ms=3000),
      allow_failure=true,
    )
    let pool = ConnectionPool::new()
    let client = HttpClient::new(pool)
    let addr = Address::new(scheme="http", host="127.0.0.1", port=server.port())
    let call = get_call_wb(client, server.port(), "/hop")
    let resp = call.execute()
    assert_eq(
      resp.code(),
      200,
      msg="非跟随响应单轮直通（P05 等价）",
    )
    assert_true(
      resp.prior() is None,
      msg="单轮直通终态 prior=None（无跟随即无挂链）",
    )
    assert_eq(resp.body().unwrap().text(), "ok", msg="终态体可正常消费")
    assert_eq(
      pool.per_host_total(addr),
      1,
      msg="循环未产生 follow-up 请求（单轮）",
    )
    pool.evict_all()
    server.close()
    s1.wait() catch {
      _ => ()
    }
    assert_eq(server.conn_request_counts(), [1], msg="夹具侧恰 1 请求")
  }
}

///|
// P06-WB④b（FR-004 保留半边单元面，T011）：rewrite_headers 直驱——同
// host 双头原样保留、跨 host 双头剥除（黑盒捕获面不可达的保留半边由本
// 单元断言承载，tasks T011/R7 夹具口径）。纯函数无 IO。
test "P06-WB④b rewrite_headers 直驱：同 host 保留、跨 host 剥除" {
  let b = @core.HeadersVBuilder::new()
  b.add("Authorization", "Bearer x")
  b.add("Cookie", "a=1")
  b.add("X-Keep", "yes")
  let headers = b.build()
  // 同 host：双头与自定义头全保留
  let kept = rewrite_headers(headers, cross_host=false)
  assert_eq(
    kept.get("Authorization"),
    Some("Bearer x"),
    msg="同 host 保留 Authorization（FR-004 保留半边）",
  )
  assert_eq(kept.get("Cookie"), Some("a=1"), msg="同 host 保留 Cookie")
  assert_eq(
    kept.get("X-Keep"),
    Some("yes"),
    msg="同 host 自定义头不受影响",
  )
  // 跨 host：仅剥双头，自定义头保留
  let stripped = rewrite_headers(headers, cross_host=true)
  assert_true(
    stripped.get("Authorization") is None,
    msg="跨 host 剥 Authorization（FR-004）",
  )
  assert_true(stripped.get("Cookie") is None, msg="跨 host 剥 Cookie（C1）")
  assert_eq(
    stripped.get("X-Keep"),
    Some("yes"),
    msg="跨 host 仅剥两凭证头",
  )
}

///|
// P06-WB⑤（T012）：中间响应不交付不触发事件——两跳带体链（中间 1KB
// 体）执行后、终态体消费前：body_consumed/body_dropped 双 false（中间
// 响应不走 bridge 体路径，无 Consumed/Dropped 事件外泄——R6）；终态体
// 读毕 consumed 置位（终态事件语义 P05 不变）。
async test "P06-WB⑤ 中间响应零事件：带体排干不触发 Consumed/Dropped" {
  @async.with_task_group() <| group => {
    let server = @fixtures.ScriptedServer::start()
    let kb1 = Bytes::from_iter(Array::make(1024, b'a').iter())
    let kb2 = Bytes::from_iter(Array::make(1024, b'b').iter())
    server.mount("GET", "/w1", {
      status: 301,
      headers: [("Location", "/w2")],
      framing: Fixed,
      body: Static(kb1),
      head_delay_ms: 0,
      close_after_response: false,
    })
    server.mount("GET", "/w2", {
      status: 200,
      headers: [],
      framing: Fixed,
      body: Static(kb2),
      head_delay_ms: 0,
      close_after_response: false,
    })
    let serving = group.spawn(
      () => server.serve_n(1, timeout_ms=5000),
      allow_failure=true,
    )
    let pool = ConnectionPool::new()
    let client = HttpClient::new(pool)
    let call = get_call_wb(client, server.port(), "/w1")
    let resp = call.execute()
    assert_eq(resp.code(), 200, msg="带体两跳链终态 200")
    // 中间响应零事件外泄（排干走 conn skip，不经 bridge）
    assert_false(
      call.body_consumed,
      msg="中间响应不得触发 Consumed（R6 桥不涉中间响应）",
    )
    assert_false(
      call.body_dropped,
      msg="中间响应不得触发 Dropped（R6）",
    )
    // 终态体消费：事件语义 P05 不变
    assert_eq(resp.body().unwrap().bytes(), kb2, msg="终态体完整（1KB）")
    assert_true(
      call.body_consumed,
      msg="终态体读毕 Consumed 置位（P05）",
    )
    pool.evict_all()
    server.close()
    serving.wait()
    assert_eq(
      server.conn_request_counts(),
      [2],
      msg="带体两跳单连接（排干后复用）",
    )
  }
}

///|
// P06-WB④（FR-001，T004）：轮间取消 guard——取消标记置位后直调
// exchange_loop（白盒绕过 execute 前检，直击循环顶 guard），以裸
// `CallCancelled` 终止且零网络动作（guard 先于 ensure_lease/acquire）。
async test "P06-WB④ 循环顶取消 guard：裸 CallCancelled、零网络" {
  @async.with_task_group() <| _group => {
    let pool = ConnectionPool::new()
    let client = HttpClient::new(pool)
    let call = get_call_wb(client, 1, "/never")
    // 白盒直写取消标记（模拟第 k 轮边界前已取消；T005 起真实多轮链经
    // 同一循环顶 guard 复用本路径）
    call.cancelled = true
    let cancelled = try {
      let _ = call.exchange_loop()
      false
    } catch {
      err => err is CallCancelled
    }
    assert_true(
      cancelled,
      msg="轮间取消必须以裸 CallCancelled 终止（FR-001）",
    )
    assert_true(
      call.lease is None,
      msg="guard 先于租借——零网络零租约（FR-001 零动作面）",
    )
  }
}

///|
// P06-WB④c（FR-001，T022/converge F4，severity LOW）：真实轮间取消
// ——轮 k 真实完成（301 到达、决策表判跟随、中间体已排干、租约在场）
// 后经公开 cancel() 取消：循环顶 guard 以裸 CallCancelled 终止；毒化
// 连接不回池（探针新建连接、夹具侧两连接各 1 请求）。行为半边闭合
// baseline.md R9-3「FR-001 轮间取消租约处置」记录级义务（成文半边见
// follow_up.mbt 循环顶 guard 注释）。
// 构造等价性归约（确定性化，零 sleep 零竞态）：真实并发轮间取消的
// 落点任意，但其安全态恰为轮边界「cancelled=true 且租约在场」——本
// 用例白盒直构该状态（轮 k 三步 ensure_lease/exchange_with_lease/
// drain_intermediate 与 exchange_loop 轮体同一代码路径），cancel 落点
// 由此归约为确定位置，覆盖任意真实落点的共性安全面。
// errdefer 作用域实测注记（T022 探针实证）：MoonBit errdefer 作用域
// 仅当前轮循环体——轮间 raise 不触发上一轮 errdefer，租约毒化收尾由
// cancel() 的同步 poison_release 单点承担（I-3：处置完成即置 None），
// 轮级 errdefer 不代偿轮间 raise。
// 红绿归因（宪法 IV）：覆盖补齐/实现先行——converge F4 定性 partial
// 覆盖缺口而非缺陷，2026-10-28 首跑实测即绿（native 101/101 全过，
// 本文件 10/10），无倒装、无事后补造红灯。
async test "P06-WB④c 真实轮间取消：轮 k 完成租约在场、cancel 后 guard 裸 CallCancelled、连接毒化不回池" {
  @async.with_task_group() <| group => {
    let server = @fixtures.ScriptedServer::start()
    server.mount("GET", "/c1", {
      status: 301,
      headers: [("Location", "/c2")],
      framing: Fixed,
      body: Static(b""),
      head_delay_ms: 0,
      close_after_response: false,
    })
    server.mount("GET", "/probe", {
      status: 200,
      headers: [],
      framing: Fixed,
      body: Static(b"probe-ok"),
      head_delay_ms: 0,
      close_after_response: false,
    })
    let serving = group.spawn(
      () => server.serve_n(2, timeout_ms=8000),
      allow_failure=true,
    )
    let pool = ConnectionPool::new()
    let client = HttpClient::new(pool)
    let addr = Address::new(scheme="http", host="127.0.0.1", port=server.port())
    // 轮 k 真实完成：与 exchange_loop 轮体同一代码路径的三步（白盒直驱）
    let call = get_call_wb(client, server.port(), "/c1")
    let request = call.request
    let lease = call.ensure_lease(address_of_request(request))
    let (resp1, raw1) = call.exchange_with_lease(request, lease)
    assert_eq(resp1.code(), 301, msg="轮 k 响应到达")
    assert_true(
      follow_up_request(resp1, request, raw1) is Next(_),
      msg="决策表判跟随（轮边界态成立）",
    )
    drain_intermediate(lease)
    // 轮边界安全面前提：租约在场（同 host 零往返保持——INV-6）
    assert_true(
      call.lease is Some(_),
      msg="轮 k 完成后租约在场（取消前提）",
    )
    // 真实取消走公开 API：同步毒化收尾、处置完成即置 None（I-3 时序）
    call.cancel()
    assert_true(
      call.lease is None,
      msg="cancel 同步毒化收尾完成置 None（I-3）",
    )
    // 轮间 guard：循环顶以裸 CallCancelled 终止（FR-001）
    let cancelled = try {
      let _ = call.exchange_loop()
      false
    } catch {
      err => err is CallCancelled
    }
    assert_true(
      cancelled,
      msg="轮间取消必须以裸 CallCancelled 终止（FR-001）",
    )
    // 连接处置：毒化连接关闭不回池——探针必须新建连接（非复用）
    let probe = get_call_wb(client, server.port(), "/probe")
    let probed = probe.execute()
    assert_eq(probed.body().unwrap().text(), "probe-ok", msg="探针可达")
    assert_eq(
      pool.per_host_total(addr),
      2,
      msg="旧连接毒化关闭不回池——探针新建连接（非复用）",
    )
    pool.evict_all()
    server.close()
    serving.wait() catch {
      _ => ()
    }
    assert_eq(
      server.conn_request_counts(),
      [1, 1],
      msg="轮 k 与探针分属两连接（毒化连接未回池）",
    )
  }
}

///|
// P06-WB②（FR-010/C4 代次键化，T003）：折叠缓存按代次键化——同代次
// 重放复用同一 Map 实例（fold_count 不变）；换代后首次发送重折叠恰一次
// （fold_count +1），且新代次产物不含旧代次缺失头（不复用旧缓存产物）。
// 白盒直驱 folded_headers（无 IO），换代以直写 call.gen 模拟循环换代
// （T004 起 exchange_loop 驱动）。
test "P06-WB② 代次折叠缓存：同代次复用、换代重折叠恰一次" {
  let pool = ConnectionPool::new()
  let client = HttpClient::new(pool)
  let url = @core.HttpUrl::parse("http://127.0.0.1:1/a")
  let request = @core.RequestBuilder::new(url).method(@core.Method::Get).build()
  let call = client.new_call(request)
  assert_eq(call.gen, 0, msg="初代次 0（用户原请求）")
  assert_eq(call.folded_gen, 0, msg="初态折叠代次 0")
  // 首折叠（gen=0）：fold_count 0→1
  let f1 = call.folded_headers(request, call.gen)
  assert_eq(call.fold_count, 1, msg="首跑折叠恰一次（I-2）")
  assert_true(call.folded is Some(_), msg="缓存在场")
  // 同代次重放：复用同一实例、fold_count 不变（P05 SC-004 语义保持）
  let f2 = call.folded_headers(request, call.gen)
  assert_eq(call.fold_count, 1, msg="同代次重放零重折叠")
  assert_true(
    f1 == f2,
    msg="同代次复用同一 Map 实例（folded == 首.folded）",
  )
  // 换代（模拟循环 follow-up 换代：gen 0→1）后首次发送：重折叠恰一次
  let url2 = @core.HttpUrl::parse("http://127.0.0.1:1/b")
  let request2 = @core.RequestBuilder::new(url2)
    .method(@core.Method::Get)
    .build()
  call.advance_generation()
  let f3 = call.folded_headers(request2, call.gen)
  assert_eq(
    call.fold_count,
    2,
    msg="换代后首次发送重折叠恰一次（fold_count +1）",
  )
  assert_eq(
    call.folded_gen,
    1,
    msg="折叠缓存代次键随换代更新（INV-3）",
  )
  // FR-010 负向：新代次产物来自新请求，不复用旧代次缓存内容
  assert_true(
    f3.get(@http.CaseInsensitiveString("X-Gen")) is None &&
    f1.get(@http.CaseInsensitiveString("X-Gen")) is None,
    msg="前态确认：两请求均无 X-Gen（对照基准）",
  )
  let b2 = @core.HeadersVBuilder::new()
  b2.add("X-Gen", "1")
  let request3 = @core.RequestBuilder::new(url2)
    .method(@core.Method::Get)
    .headers(b2.build())
    .build()
  call.advance_generation()
  let f4 = call.folded_headers(request3, call.gen)
  assert_eq(call.fold_count, 3, msg="再换代重折叠恰一次")
  assert_eq(
    f4.get(@http.CaseInsensitiveString("X-Gen")),
    Some("1"),
    msg="新代次产物携带新请求头（FR-010 不复用旧缓存产物）",
  )
  // 新代次内重放：再次复用（fold_count 不再增长）
  let f5 = call.folded_headers(request3, call.gen)
  assert_eq(call.fold_count, 3, msg="新代次重放零重折叠")
  assert_true(f4 == f5, msg="新代次复用同一实例")
}

///|
// P06-WB⑥（FR-005 计数位置/FR-010，T014）：上限计数在「响应到达 +
// follow-up 已算出」后、发送前（R1 第 8 条）——白盒可观测面：20 个
// follow-up 实际发出（总请求 21，夹具计数）、代次推进恰 20（gen==20）、
// 折叠恰 21（1+跳数，INV-3/FR-010）；raise 后租约干净回池（复用零新建
// ——round3 D-2 排干先于计数的可观测承重面）。
async test "P06-WB⑥ 上限计数位置：20 follow-up、gen 20、fold 21、干净回池" {
  @async.with_task_group() <| group => {
    let server = @fixtures.ScriptedServer::start()
    let redirects : Array[@fixtures.ResponseScript] = []
    for _i in 0..<21 {
      redirects.push({
        status: 301,
        headers: [("Location", "/loop")],
        framing: Fixed,
        body: Static(b""),
        head_delay_ms: 0,
        close_after_response: false,
      })
    }
    redirects.push({
      status: 200,
      headers: [],
      framing: Fixed,
      body: Static(b"done"),
      head_delay_ms: 0,
      close_after_response: false,
    })
    server.mount_sequence("GET", "/loop", redirects)
    server.mount("GET", "/probe", {
      status: 200,
      headers: [],
      framing: Fixed,
      body: Static(b"probe-ok"),
      head_delay_ms: 0,
      close_after_response: false,
    })
    let serving = group.spawn(
      () => server.serve_n(1, timeout_ms=8000),
      allow_failure=true,
    )
    let pool = ConnectionPool::new()
    let client = HttpClient::new(pool)
    let addr = Address::new(scheme="http", host="127.0.0.1", port=server.port())
    let call = get_call_wb(client, server.port(), "/loop")
    let raised = try {
      let _ = call.execute()
      false
    } catch {
      err => err is TooManyFollowUps
    }
    assert_true(
      raised,
      msg="第 21 个仍需跟随的响应触发上限（INV-4）",
    )
    // 白盒直读：代次与折叠计数（FR-010：fold_count = 1 + 跳数）
    assert_eq(
      call.gen,
      20,
      msg="换代恰 20（20 个 follow-up 实际发出）",
    )
    assert_eq(call.fold_count, 21, msg="折叠恰 21 = 1 + 跳数（INV-3）")
    assert_true(
      call.lease is None,
      msg="raise 前租约已干净释放（INV-4：先 release 后 raise）",
    )
    // 排干先于计数的可观测面：第 21 响应已排干 ⇒ 连接干净回池可复用
    let probe = get_call_wb(client, server.port(), "/probe")
    let probed = probe.execute()
    assert_eq(probed.body().unwrap().text(), "probe-ok")
    assert_eq(
      pool.per_host_total(addr),
      1,
      msg="raise 后零新建（round3 D-2）",
    )
    pool.evict_all()
    server.close()
    serving.wait() catch {
      _ => ()
    }
    assert_eq(
      server.conn_request_counts(),
      [22],
      msg="总请求 21 + 探针 = 22",
    )
  }
}

///|
// P06-WB⑦（FR-003/R10，T016）：决策表穷举真值矩阵（白盒收口）——九标准
// 方法 × {300,301,302,303,307,308,304,401} × Location{有,无} ×
// body{Bytes,Stream,无}，纯函数无 IO 逐格 assert_true。构造不变量
// （P02 矩阵）：Get/Head 拒体、Post/Put/Patch 必体——不可构造格跳过
// （spec Edge Cases「构造面不可达」口径）。跨 host 剥头由 P06-WB④b
// rewrite_headers 直驱承载，本矩阵固定同 host Location。
// 每格断言行级语义：降级行（方法=GET/无体/三头去除/URL=resolve 目标）、
// 保持行（方法/体原样、同 host 头原样）、Terminal 行（304/401 判码
// 优先、3xx 无 Location、307/308+Stream）。
test "P06-WB⑦ 决策表穷举真值矩阵" {
  let methods = [
    @core.Method::Get,
    @core.Method::Post,
    @core.Method::Put,
    @core.Method::Delete,
    @core.Method::Head,
    @core.Method::Options,
    @core.Method::Trace,
    @core.Method::Patch,
    @core.Method::Connect,
  ]
  for meth in methods {
    for code in [300, 301, 302, 303, 307, 308, 304, 401] {
      for loc_present in [true, false] {
        for body_kind in [0, 1, 2] {
          // 构造不变量：0=无体 1=Bytes 2=Stream
          let rejects_body = meth is (@core.Method::Get | @core.Method::Head)
          let needs_body = meth
            is (@core.Method::Post | @core.Method::Put | @core.Method::Patch)
          let constructible = if rejects_body {
            body_kind == 0
          } else if needs_body {
            body_kind != 0
          } else {
            true
          }
          if !constructible {
            continue
          }
          let url = @core.HttpUrl::parse("http://127.0.0.1:1/a")
          let hb = @core.HeadersVBuilder::new()
          hb.add("Content-Type", "text/matrix")
          hb.add("Transfer-Encoding", "chunked")
          hb.add("Content-Length", "2")
          let builder = @core.RequestBuilder::new(url)
            .method(meth)
            .headers(hb.build())
          let request = match body_kind {
            1 => builder.body(@core.RequestBody::bytes(b"px", 2L)).build()
            2 =>
              builder
              .body(@core.RequestBody::stream(w => w.write(b"s")))
              .build()
            _ => builder.build()
          }
          let headers = if loc_present { [("Location", "/b")] } else { [] }
          let (response, raw) = wb_resp(code, headers)
          // 期望：Terminal ⇔ 304/401 判码优先 ∨ 无 Location ∨
          // (307/308 ∧ Stream 体)——data-model 实体 3 真值表
          let is_stream_body = body_kind == 2 && !rejects_body
          let terminal = (code == 304 || code == 401) ||
            !loc_present ||
            ((code == 307 || code == 308) && is_stream_body)
          let outcome = follow_up_request(response, request, raw)
          let cell = "method=\{meth.to_repr()} code=\{code} loc=\{loc_present} body=\{body_kind}"
          match outcome {
            Terminal =>
              assert_true(terminal, msg="应 Next 却 Terminal：\{cell}")
            Next(followup) => {
              assert_true(!terminal, msg="应 Terminal 却 Next：\{cell}")
              assert_eq(
                followup.url.to_string(),
                "http://127.0.0.1:1/b",
                msg="follow-up 目标 = resolve 产物：\{cell}",
              )
              if rejects_body {
                // 保持行（GET/HEAD 全状态码恒保持，R1 第 2 条）
                assert_true(
                  followup.method == meth,
                  msg="GET/HEAD 恒保持方法：\{cell}",
                )
                assert_eq(
                  followup.headers.get("Content-Type"),
                  Some("text/matrix"),
                  msg="同 host 保持行头原样（CT）：\{cell}",
                )
                assert_eq(
                  followup.headers.get("Transfer-Encoding"),
                  Some("chunked"),
                  msg="同 host 保持行头原样（TE）：\{cell}",
                )
              } else if code == 300 || code == 301 || code == 302 || code == 303 {
                // 降级行：GET、无体、三头去除（FR-003 行 1/2）
                assert_true(
                  followup.method == @core.Method::Get,
                  msg="降级为 GET：\{cell}",
                )
                assert_true(followup.body is None, msg="降级去体：\{cell}")
                assert_true(
                  followup.headers.get("Content-Length") is None &&
                  followup.headers.get("Content-Type") is None &&
                  followup.headers.get("Transfer-Encoding") is None,
                  msg="降级去三头：\{cell}",
                )
              } else {
                // 保持/重放行（307/308，Bytes/无体）
                assert_true(
                  followup.method == meth,
                  msg="307/308 保持方法：\{cell}",
                )
                match body_kind {
                  1 =>
                    assert_true(
                      followup.body is Some(_),
                      msg="307/308 Bytes 体随行：\{cell}",
                    )
                  _ =>
                    assert_true(
                      followup.body is None,
                      msg="307/308 无体保持：\{cell}",
                    )
                }
                assert_eq(
                  followup.headers.get("Content-Type"),
                  Some("text/matrix"),
                  msg="307/308 同 host 头原样：\{cell}",
                )
              }
            }
          }
        }
      }
    }
  }
}

///|
// P06-WB⑧（FR-008 Location 保真，review 修复批 H1）：Location 读取走
// 原始 @http.Headers 直读——P02 from_http 把头值按 "," 拆回多条、
// HeadersV::get 取首条，含逗号的 Location（"," 是 query 合法子分隔符）
// 会被截断成首段碎片并跟随到错误资源。修复前本用例红（follow-up 目标
// = /next?ids=1）。
test "P06-WB⑧ Location 含逗号保真：完整值参与 resolve、不退化首段碎片" {
  // 形态 1：单 Location 值含逗号（/next?ids=1,2）——修复前被
  // from_http 拆为 "/next?ids=1" + "2"，get 取首条即截断。
  let request = wb_req(1, "/a", @core.Method::Get)
  let (response, raw) = wb_resp(302, [("Location", "/next?ids=1,2")])
  match follow_up_request(response, request, raw) {
    Next(followup) =>
      assert_eq(
        followup.url.to_string(),
        "http://127.0.0.1:1/next?ids=1,2",
        msg="Location 值含逗号必须完整参与 resolve（H1 保真）",
      )
    Terminal =>
      assert_true(false, msg="302+合法 Location 应跟随（H1 回归）")
  }
  // 形态 2：上游 parser 对重复头以 "," 合并（parser.mbt:282）——合并值
  // 作为一个整体参与解析（合法则整体跟随；不可解析则 FR-008 终态），
  // 两种结局均不得退化为首段碎片 /x。
  let request2 = wb_req(1, "/a", @core.Method::Get)
  let (response2, raw2) = wb_resp(301, [("Location", "/x,/y")])
  match follow_up_request(response2, request2, raw2) {
    Next(followup) =>
      assert_eq(
        followup.url.to_string(),
        "http://127.0.0.1:1/x,/y",
        msg="合并头值整体解析（不得截断为首段 /x）",
      )
    // 合并值被 P01 resolve 拒绝 ⇒ 不跟随终态（FR-008 对齐，同样非碎片跟随）
    Terminal => ()
  }
}

///|
// P06-WB④d（FR-001 轮间 guard 位置 + FR-007 同 host 不归还判别面，
// review 修复批 M4）：真实循环内、第 1 轮完成后置取消，一次判别两件事：
// ① 循环顶 guard 在循环体内每轮求值——若 guard 被提到 while 之外，
//   第 2 轮会照常发送，夹具将看到 2 个请求 ⇒ 本用例红（修复前
//   WB④ 仅在入口前置取消，guard 提到函数外仍绿）；
// ② 同 host 保持分支真实「未归还」——若实现误归还（含 release+reacquire
//   命中同一 idle 连接、连接计数不变的混淆形态），guard raise 前租约
//   已被置 None ⇒ 本用例红。身份断言（lease is Some）承担连接计数无法
//   判别的半边。
// 确定性构造（零 sleep 零竞态）：取消标记由第 1 轮请求体 Stream 填充器
// 直写（填充器与循环体同任务同线程执行，无并发交错）；第 1 轮照常完成
// （POST 301 → 降级行 Next → 排干 → 同 host 不归还）→ 第 2 轮循环顶
// guard 命中 ⇒ 裸 CallCancelled、租约身份保持。
async test "P06-WB④d 循环内轮间取消 + 同 host 不归还判别：第 2 轮前取消、租约身份保持" {
  @async.with_task_group() <| group => {
    let server = @fixtures.ScriptedServer::start()
    server.mount("POST", "/h1", {
      status: 301,
      headers: [("Location", "/h2")],
      framing: Fixed,
      body: Static(b""),
      head_delay_ms: 0,
      close_after_response: false,
    })
    server.mount("GET", "/h2", {
      status: 200,
      headers: [],
      framing: Fixed,
      body: Static(b"unreachable-when-guard-in-loop"),
      head_delay_ms: 0,
      close_after_response: false,
    })
    let serving = group.spawn(
      () => server.serve_n(1, timeout_ms=5000),
      allow_failure=true,
    )
    let pool = ConnectionPool::new()
    let client = HttpClient::new(pool)
    let addr = Address::new(scheme="http", host="127.0.0.1", port=server.port())
    // 第 1 轮请求体 Stream 填充器：写体后直写取消标记（POST+Stream 合法
    // 构造面；301 + 非 GET/HEAD ⇒ 降级行 Next，循环进入轮间区）。经
    // holder 间接持有装箱 Call（结构体为引用类型，填充器内字段写对
    // call 可见）。
    let holder : Array[Call] = []
    let url = @core.HttpUrl::parse("http://127.0.0.1:\{server.port()}/h1")
    let request = @core.RequestBuilder::new(url)
      .method(@core.Method::Post)
      .body(
        @core.RequestBody::stream(w => {
          let _ = w.write(b"px")
          holder[0].cancelled = true
        }),
      )
      .build()
    let call = client.new_call(request)
    holder.push(call)
    let raised = try {
      let _ = call.execute()
      false
    } catch {
      err => err is CallCancelled
    }
    assert_true(
      raised,
      msg="轮间取消必须以裸 CallCancelled 终止（FR-001）",
    )
    assert_true(
      call.lease is Some(_),
      msg="同 host 保持分支未归还租约（FR-007 判别：guard raise 前零 release）",
    )
    assert_eq(
      pool.per_host_total(addr),
      1,
      msg="全程零新建（同 host 零往返保持）",
    )
    // 收尾：显式归还被判别面持有的健康租约，避免 serve_n 等满超时
    call.release_lease()
    pool.evict_all()
    server.close()
    serving.wait() catch {
      _ => ()
    }
    assert_eq(
      server.conn_request_counts(),
      [1],
      msg="第 2 轮未发送（guard 在循环体内每轮求值——提到 while 外则此数为 2）",
    )
  }
}
