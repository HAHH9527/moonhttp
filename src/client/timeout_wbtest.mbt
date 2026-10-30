///|
// timeout_wbtest：P08 配置面/接线白盒测试（contracts/timeout-api.md §2
// priv 接缝的断言面）。红绿纪律（宪法 IV）：每测试先红后绿；首跑颜色
// 实测记录，禁止事后补造。
//
// 覆盖面（按任务编号）：
//   - T018（US4 红）：build() 负值校验（C5/004 先例——纯校验函数可
//     raise 断言，abort 落点在 build()）、全缺省矩阵（FR-001）、
//     builder() 派生继承快照（标量=被派生方当前值）、new_builder(pool)
//     全缺省；
//   - T011（US1）：连接伞接线伴随 + R5 竞态收敛白盒；
//   - T013（US1 绿）：看门者三步序结构审判据（FR-002 有界例外①）。

///|
// 负值/定制探针构造辅助（四字段显式——Timeouts 无字段缺省语法，
// 单点缺省面由 Timeouts::default() 承载）。
fn probe_timeouts(
  connect_ms~ : Int32 = 10_000,
  write_ms~ : Int32 = 10_000,
  read_ms~ : Int32 = 10_000,
  call_ms~ : Int32 = 0,
) -> Timeouts {
  { connect_ms, write_ms, read_ms, call_ms, }
}

///|
// P08-WB③（FR-001 全缺省矩阵，T018 红）：Timeouts::default() 单点与
// HttpClient::new 缺省字面量一致——connect/write/read=10s、call=0
// （0=不限不建窗，OkHttp 对齐）；HttpClient::new 路径的缺省经 priv
// 直读核验。
test "P08-WB③ 全缺省矩阵：default() 与 HttpClient::new 缺省一致" {
  let d = Timeouts::default()
  assert_eq(d.connect_ms, 10_000, msg="connect_ms 缺省 10s（FR-001）")
  assert_eq(d.write_ms, 10_000, msg="write_ms 缺省 10s（FR-001）")
  assert_eq(d.read_ms, 10_000, msg="read_ms 缺省 10s（FR-001）")
  assert_eq(
    d.call_ms,
    0,
    msg="call_ms 缺省 0=不限不建窗（FR-001/INV-T1）",
  )
  let pool = ConnectionPool::new()
  let client = HttpClient::new(pool)
  assert_eq(
    client.timeouts.connect_ms,
    10_000,
    msg="HttpClient::new 缺省 connect_ms=10s",
  )
  assert_eq(client.timeouts.call_ms, 0, msg="HttpClient::new 缺省 call_ms=0")
  assert_true(client.follow_redirects, msg="缺省 true（P06 行为面）")
  assert_true(client.follow_ssl_redirects, msg="缺省 true（P06 行为面）")
}

///|
// P08-WB④（new_builder 全缺省 + build 校验单点，T018 红）：pool 根构造
// 全缺省；负值在 validate_timeouts 纯函数 raise（C5/004 D15 纯函数口径
// ——abort 不可断言，可 raise 纯校验为判据通道），build() 捕获后 abort。
test "P08-WB④ new_builder 全缺省 + 负值构建期快速失败" {
  let pool = ConnectionPool::new()
  let builder = HttpClient::new_builder(pool)
  let client = builder.build()
  // 全缺省矩阵（Timeouts 无 Eq——逐字段对账）
  assert_eq(client.timeouts.connect_ms, 10_000, msg="缺省 connect_ms=10s")
  assert_eq(client.timeouts.write_ms, 10_000, msg="缺省 write_ms=10s")
  assert_eq(client.timeouts.read_ms, 10_000, msg="缺省 read_ms=10s")
  assert_eq(client.timeouts.call_ms, 0, msg="缺省 call_ms=0")
  assert_true(client.retry_on_connection_failure, msg="重试开关缺省 true")
  // 负值四字段逐一快速失败（不静默钳制）
  try {
    let _ = validate_timeouts(probe_timeouts(connect_ms=-1))
    fail("connect_ms 负值应当 raise")
  } catch {
    e =>
      assert_true(e is TimeoutConfigError(_), msg="负 connect_ms 快速失败")
  }
  try {
    let _ = validate_timeouts(probe_timeouts(write_ms=-1))
    fail("write_ms 负值应当 raise")
  } catch {
    e =>
      assert_true(e is TimeoutConfigError(_), msg="负 write_ms 快速失败")
  }
  try {
    let _ = validate_timeouts(probe_timeouts(read_ms=-1))
    fail("read_ms 负值应当 raise")
  } catch {
    e => assert_true(e is TimeoutConfigError(_), msg="负 read_ms 快速失败")
  }
  try {
    let _ = validate_timeouts(probe_timeouts(call_ms=-1))
    fail("call_ms 负值应当 raise")
  } catch {
    e => assert_true(e is TimeoutConfigError(_), msg="负 call_ms 快速失败")
  }
  // 0 恒合法（=不限不建窗）
  validate_timeouts(
    probe_timeouts(connect_ms=0, write_ms=0, read_ms=0, call_ms=0),
  )
}

///|
// 池守恒核验（004 INV-5：借出+空闲+已关=累计新建；wbtest 同包 priv
// 直读三集合与发号器）。
fn pool_conservation_holds(pool : ConnectionPool) -> Bool {
  let mut idle_count = 0
  for _addr, bucket in pool.inner.idle {
    idle_count = idle_count + bucket.length()
  }
  let borrowed = pool.inner.borrowed.length()
  let closed = pool.inner.closed.length()
  let issued = pool.inner.next_conn_id - 1
  borrowed + idle_count + closed == issued
}

///|
// P08-WB⑥（T011②，US-1-1/US-3-3 载体；INV-T3/R5）：连接伞×建连竞速
// 收敛白盒——极小 connect_ms=1ms × 真实回环建连竞速 ×10 轮：
//   ① 终态有序（成功 ∨ HttpTimeout 变体之一——spec Edge Cases 退化
//     阈值口径「不赌计时赢家」；满载负载形态见下注）；
//   ② 池守恒每轮成立（004 INV-5：借出+空闲+已关=累计新建）；
//   ③ 无 borrowed 悬挂（R5 泄漏形态判别面——伞取消×记账完成的任何
//     交叠下，借出集合在体消费后必须清空；含锁等待支——S3：取消落
//     记账锁等待 ⇒ 取消安全 ⇒ 零记账，落建连 await ⇒ 构造器 errdefer
//     清理 ⇒ 零记账，两支皆过本断言）。
async test "P08-WB⑥ 连接伞×建连竞速收敛：终态有序 + 守恒每轮成立" {
  @async.with_task_group() <| group => {
    let server = @fixtures.ScriptedServer::start()
    server.mount("GET", "/fast", {
      status: 200,
      headers: [],
      framing: Fixed,
      body: Static(b"ok"),
      head_delay_ms: 0,
      close_after_response: false,
    })
    let serving = group.spawn(
      () => server.serve_n(1, timeout_ms=60_000),
      allow_failure=true,
    )
    let pool = ConnectionPool::new()
    // 【负载形态登记（2026-10-30 全量并发 run 实测）】满载下 1ms 伞可
    // 整轮 Connect（伞到期→重试→再到期→预算耗尽透传，~10-20ms/轮）
    // ——属二择一的合法支；夹具寿命 MUST 覆盖最坏轮程（serve 窗
    // 60s），否则夹具死亡后已交付连接的 end_request 挂至读窗（10s）
    // ⇒ Read 终态——客户端行为仍合规（窗口归属按逸出点），但不属
    // 本白盒二择一判据面。
    for round in 0..<10 {
      let client = HttpClient::new_builder(pool)
        .timeouts(probe_timeouts(connect_ms=1))
        .build()
      let url = @core.HttpUrl::parse("http://127.0.0.1:\{server.port()}/fast")
      let request = @core.RequestBuilder::new(url)
        .method(@core.Method::Get)
        .build()
      let call = client.new_call(request)
      let outcome = try {
        let resp = call.execute()
        // 体消费 ⇒ Consumed ⇒ 租约回池（借出清空的前提）
        let _ = resp.body().unwrap().text()
        "delivered"
      } catch {
        err => {
          // 终态有序判据（spec Edge Cases 退化阈值口径：connect_ms=1ms
          // 极小值下「不赌计时赢家」——满载下伞可整轮 Connect，已交付
          // 连接的后续段亦可被读窗收束；判据本体=终态有序（超时变体
          // 之一）+ 资源无泄漏 + 池守恒，端到端 Connect 无断言义务
          // ——R3 诚实边界）。
          assert_true(
            err
            is (HttpTimeout::Connect
            | HttpTimeout::Write
            | HttpTimeout::Read
            | HttpTimeout::Call),
            msg="第 \{round} 轮终态无序（非超时变体透传）：\{err}",
          )
          "timeout"
        }
      }
      assert_true(
        pool_conservation_holds(pool),
        msg="第 \{round} 轮池守恒破坏（004 INV-5；outcome=\{outcome}）",
      )
      assert_true(
        pool.inner.borrowed.length() == 0,
        msg="第 \{round} 轮 borrowed 悬挂（伞×建连竞态泄漏——R5/INV-T3）",
      )
    }
    pool.evict_all()
    server.close()
    serving.wait() catch {
      _ => ()
    }
  }
}

///|
// P08-WB⑦（T013，FR-002 有界例外①结构审判据；research R1）：看门者
// 三步序——正常交付路径看门者被组取消不算失败（execute 正常返回即证
// 据上游 task_group.mbt:116-119「取消不算失败」的结构依赖）、标记
// 不被置位（call_ms 远大于交付耗时 ⇒ sleep 未到期 ⇒ 标记恒 false——
// 若误置位，后续取消场景将误判 Call 变体）。call 伞到期路径的变体
// 选择由 US1④ 黑盒（T012/T013）覆盖。
async test "P08-WB⑦ 看门者三步序：正常交付路标记不被置位" {
  @async.with_task_group() <| group => {
    let server = @fixtures.ScriptedServer::start()
    server.mount("GET", "/fast-watchman", {
      status: 200,
      headers: [],
      framing: Fixed,
      body: Static(b"ok"),
      head_delay_ms: 0,
      close_after_response: false,
    })
    let serving = group.spawn(
      () => server.serve_once(timeout_ms=8000),
      allow_failure=true,
    )
    let pool = ConnectionPool::new()
    let client = HttpClient::new_builder(pool)
      .timeouts(probe_timeouts(call_ms=5000))
      .build()
    let url = @core.HttpUrl::parse(
      "http://127.0.0.1:\{server.port()}/fast-watchman",
    )
    let request = @core.RequestBuilder::new(url)
      .method(@core.Method::Get)
      .build()
    let call = client.new_call(request)
    let resp = call.execute()
    assert_eq(
      resp.code(),
      200,
      msg="call_ms 已配置的快请求应正常交付",
    )
    assert_false(
      call.call_timeout_fired,
      msg="正常交付路看门者标记不得置位（R1——置位仅发生于伞到期）",
    )
    pool.evict_all()
    server.close()
    serving.wait() catch {
      _ => ()
    }
  }
}

///|
// P08-WB⑤（builder() 派生继承快照，T018 红）：标量缺省=被派生方当前值
// （OkHttp newBuilder 同形——pool 引用共享、标量快照）；setter 覆盖链
// 仅影响 builder 终值，不回写被派生方（标量不可变快照）。
test "P08-WB⑤ builder() 派生继承快照与 setter 覆盖" {
  let pool = ConnectionPool::new()
  let base = HttpClient::new(pool)
  let derived = HttpClient::builder(base)
    .timeouts(
      probe_timeouts(
        connect_ms=1_000,
        write_ms=2_000,
        read_ms=3_000,
        call_ms=4_000,
      ),
    )
    .follow_redirects(false)
    .follow_ssl_redirects(false)
    .retry_on_connection_failure(false)
    .build()
  // 派生方拿到覆盖值
  assert_eq(derived.timeouts.connect_ms, 1_000, msg="覆盖生效 connect")
  assert_eq(derived.timeouts.call_ms, 4_000, msg="覆盖生效 call")
  assert_false(derived.follow_redirects, msg="覆盖生效 follow_redirects")
  assert_false(
    derived.follow_ssl_redirects,
    msg="覆盖生效 follow_ssl_redirects",
  )
  assert_false(
    derived.retry_on_connection_failure,
    msg="覆盖生效 retry 开关（P07 C4 承接）",
  )
  // 被派生方零串扰（US-4-1/3 前态）
  assert_eq(
    base.timeouts.connect_ms,
    10_000,
    msg="被派生方标量快照不被回写（connect）",
  )
  assert_eq(
    base.timeouts.call_ms,
    0,
    msg="被派生方标量快照不被回写（call）",
  )
  assert_true(base.follow_redirects, msg="被派生方开关不变")
  assert_true(
    base.retry_on_connection_failure,
    msg="被派生方重试开关不变",
  )
  // pool 引用共享的行为面对账归 US-4-1 黑盒（T020：A/B 顺序请求
  // per_host_total 单调共享、不重复建连）——ConnectionPool 无 Eq，
  // 白盒引用判等不可断言（诚实边界登记）。
}
