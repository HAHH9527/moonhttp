///|
// pool_longrun_wbtest：US-2 场景 2 长跑双证据（P04 T018，白盒）。
//
// 隔离机制（裁决 C5 主案，research R8）：长跑条目声明 #skip——默认
// `moon test` 不计数、不执行；显式执行经 `--include-skipped`
// （quickstart §3）。禁止以 #cfg 充当跳过（R8 实测反例）。
//
// 判据（Q04 双证据，禁 fd 计数）：
// - 外部证据：夹具 accepted_total() == 池内累计新建（白盒 next_conn_id-1）
// - 内部证据：三集合基数守恒（不变量 5）
// - 复用度自证：F-6 每连接请求数存在 count ≥ 2（keep-alive 复用真实发生）
// 时间推进零 sleep；并发按波次屏障放行（accept 排水，同 US2① 实测对策）；
// accept 预算=首波新建数（确定性），由 dummy 连接兜底自然收口。

///|
// P04-LONGRUN①（native ≥10k 请求）：40 波 × 25 任务 × 10 请求/租约。
// max_idle=32 ≥ 波内并发 25——首波 25 条新建后全部复用（零churn），
// accept 预算 25 精确可判。
#skip("长跑（US-2 场景 2）：默认六门排除（C5）；显式执行见 quickstart §3")
async test "P04-LONGRUN① native 10k 请求双证据守恒与复用自证" {
  @async.with_task_group() <| group => {
    let server = @fixtures.ScriptedServer::start()
    server.mount("POST", "/echo", {
      status: 200,
      headers: [],
      framing: Fixed,
      body: Echo,
      head_delay_ms: 0,
      close_after_response: false,
    })
    let waves = 40
    let tasks_per_wave = 25
    let reqs_per_lease = 10
    let total = waves * tasks_per_wave * reqs_per_lease
    let budget = tasks_per_wave
    let _serving = group.spawn(() => server.serve_n(budget, timeout_ms=30000))
    let pool = ConnectionPool::new(max_idle=32, keep_alive_ms=300_000)
    let addr = Address::new(scheme="http", host="127.0.0.1", port=server.port())
    let failures : Array[Int32] = []
    for _w in 0..<waves {
      let wave_tasks = []
      for i in 0..<tasks_per_wave {
        let k = i
        wave_tasks.push(
          group.spawn(() => {
            let lease = pool.acquire(addr)
            let conn = lease.conn
            let mut r = 0
            while r < reqs_per_lease {
              conn.request(Post, "/echo")
              conn.write("lr-\{k}-\{r}")
              let resp = conn.end_request()
              let body = conn.read_all().text()
              let mismatch = match body.find(":") {
                Some(pos) => body[pos + 1:].to_owned() != "lr-\{k}-\{r}"
                None => true
              }
              if resp.code != 200 || mismatch {
                failures.push(k * 1000 + r)
              }
              r = r + 1
            }
            lease.release()
          }),
        )
      }
      for task in wave_tasks {
        task.wait()
      }
    }
    assert_eq(
      failures.length(),
      0,
      msg="长跑异常任务数 \{failures.length()}",
    )
    // 双证据（Q04）
    let pool_new = pool.inner.next_conn_id - 1
    assert_eq(
      server.accepted_total(),
      pool_new,
      msg="外部证据：accepted_total(\{server.accepted_total()}) == 池内新建(\{pool_new})——无泄漏",
    )
    let mut idle_total = 0
    for _key, bucket in pool.inner.idle {
      idle_total = idle_total + bucket.length()
    }
    assert_eq(
      pool.inner.borrowed.length() + idle_total + pool.inner.closed.length(),
      pool_new,
      msg="内部证据：三集合基数守恒（不变量 5）",
    )
    // 复用度自证（F-6）：存在承载 ≥2 请求的连接
    let counts = server.conn_request_counts()
    let mut max_per_conn = 0
    for count in counts {
      if count > max_per_conn {
        max_per_conn = count
      }
    }
    println(
      "[P04-LONGRUN① native] total=\{total} 池内新建=\{pool_new} 最大单连接请求数=\{max_per_conn} stale=\{pool.stale_evictions()}",
    )
    assert_true(
      max_per_conn >= 2,
      msg="复用度自证失败：无任何连接承载 ≥2 请求（keep-alive 复用未发生）",
    )
    // accept 预算兜底收口（同 US2①：取消不得命中 accept 等待）
    let consumed = pool.inner.next_conn_id - 1
    let mut filled = consumed
    while filled < budget {
      let dummy = @http.Client::Client("http://127.0.0.1:\{server.port()}/")
      dummy.close()
      filled = filled + 1
    }
    server.close()
  }
}

///|
// P04-LONGRUN②（wasm/moonrun 分档降额）：8 波 × 25 任务 × 10 请求/租约
// = 2000 请求（数值为本任务按 moonrun 实测吞吐校准并记录，上限「单次
// 显式运行 ≤ 数分钟」）。判据与 ① 同（双 target 同一套断言）。
#skip("长跑（US-2 场景 2）：默认六门排除（C5）；显式执行见 quickstart §3")
async test "P04-LONGRUN② wasm 2000 请求双证据守恒与复用自证" {
  @async.with_task_group() <| group => {
    let server = @fixtures.ScriptedServer::start()
    server.mount("POST", "/echo", {
      status: 200,
      headers: [],
      framing: Fixed,
      body: Echo,
      head_delay_ms: 0,
      close_after_response: false,
    })
    let waves = 8
    let tasks_per_wave = 25
    let reqs_per_lease = 10
    let total = waves * tasks_per_wave * reqs_per_lease
    let budget = tasks_per_wave
    let _serving = group.spawn(() => server.serve_n(budget, timeout_ms=60000))
    let pool = ConnectionPool::new(max_idle=32, keep_alive_ms=300_000)
    let addr = Address::new(scheme="http", host="127.0.0.1", port=server.port())
    let failures : Array[Int32] = []
    for _w in 0..<waves {
      let wave_tasks = []
      for i in 0..<tasks_per_wave {
        let k = i
        wave_tasks.push(
          group.spawn(() => {
            let lease = pool.acquire(addr)
            let conn = lease.conn
            let mut r = 0
            while r < reqs_per_lease {
              conn.request(Post, "/echo")
              conn.write("lr-\{k}-\{r}")
              let resp = conn.end_request()
              let body = conn.read_all().text()
              let mismatch = match body.find(":") {
                Some(pos) => body[pos + 1:].to_owned() != "lr-\{k}-\{r}"
                None => true
              }
              if resp.code != 200 || mismatch {
                failures.push(k * 1000 + r)
              }
              r = r + 1
            }
            lease.release()
          }),
        )
      }
      for task in wave_tasks {
        task.wait()
      }
    }
    assert_eq(
      failures.length(),
      0,
      msg="长跑异常任务数 \{failures.length()}",
    )
    let pool_new = pool.inner.next_conn_id - 1
    assert_eq(
      server.accepted_total(),
      pool_new,
      msg="外部证据：accepted_total(\{server.accepted_total()}) == 池内新建(\{pool_new})——无泄漏",
    )
    let mut idle_total = 0
    for _key, bucket in pool.inner.idle {
      idle_total = idle_total + bucket.length()
    }
    assert_eq(
      pool.inner.borrowed.length() + idle_total + pool.inner.closed.length(),
      pool_new,
      msg="内部证据：三集合基数守恒（不变量 5）",
    )
    let counts = server.conn_request_counts()
    let mut max_per_conn = 0
    for count in counts {
      if count > max_per_conn {
        max_per_conn = count
      }
    }
    println(
      "[P04-LONGRUN② wasm] total=\{total} 池内新建=\{pool_new} 最大单连接请求数=\{max_per_conn} stale=\{pool.stale_evictions()}",
    )
    assert_true(
      max_per_conn >= 2,
      msg="复用度自证失败：无任何连接承载 ≥2 请求（keep-alive 复用未发生）",
    )
    let consumed = pool.inner.next_conn_id - 1
    let mut filled = consumed
    while filled < budget {
      let dummy = @http.Client::Client("http://127.0.0.1:\{server.port()}/")
      dummy.close()
      filled = filled + 1
    }
    server.close()
  }
}
