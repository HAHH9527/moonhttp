///|
// pool_wbtest：连接池白盒测试（P04 T004 起）。_wbtest.mbt 与本包同编译，
// priv 状态/私有构造入口可直读（research R9 盒型归属总依据）。
//
// FR② 判据形态裁决（2026-10-21 调查，opencode/DeepSeek V4.1 Flash Free
// 实测矩阵）：MoonBit 官方 "panic" 名称前缀测试在 native 被静默跳过且计
// passed（假绿）、try/catch 与 task group 均不可捕获 panic、上游 core 自身
// 将 panic 测试排除出 native（builtin/moon.pkg targets）、moonbitlang/async
// 全仓只测 raise。故校验逻辑落在可 raise 的私有纯函数 validate_pool_config
// （双 target 真断言，先红后绿不掺假）；new 公开面不变（noraise，校验失败
// 时 abort 构造期快速失败）——contracts/pool-api.md §2 契约零偏移。

///|
// P04-FR①（R2 注入式时钟）：with_clock 注入受控时钟序列，now_ms 逐点返回
// 受控值——虚拟时间推进零 sleep，全池时间语义单点（不变量 7）。
test "P04-FR① 注入时钟序列生效：now_ms 返回受控值" {
  let mut tick : Int64 = 100
  let pool = ConnectionPool::with_clock(max_idle=5, keep_alive_ms=1000, now_fn=() => {
    tick = tick + 1
    tick
  })
  assert_eq((pool.now_ms)(), 101L, msg="注入时钟应返回受控序列值")
  assert_eq((pool.now_ms)(), 102L, msg="推进后应取序列下一值")
}

///|
// P04-FR②（构造校验，FR-002/C4 前提）：max_idle=0 违反 max_idle > 0，
// 校验层拒绝且消息指认参数。
test "P04-FR② 构造校验：max_idle=0 即拒绝" {
  let err = @test.expect_error(fn() raise PoolConfigError {
    validate_pool_config(max_idle=0, keep_alive_ms=300_000)
  })
  let msg = match err {
    PoolConfigError(msg) => msg
  }
  assert_true(
    msg.contains("max_idle must be > 0"),
    msg="错误消息应指认 max_idle：\{msg}",
  )
}

///|
// P04-FR②（构造校验）：keep_alive_ms < 0 违反非负前提，校验层拒绝。
test "P04-FR② 构造校验：keep_alive_ms<0 即拒绝" {
  let rejected = try {
    validate_pool_config(max_idle=5, keep_alive_ms=-1)
    false
  } catch {
    PoolConfigError(_) => true
  }
  assert_true(rejected, msg="keep_alive_ms<0 必须被拒绝")
}

///|
// P04-FR②（构造校验镜像）：合法参数（含 keep_alive_ms=0 边界）零拒绝；
// new 全缺省形态可用且缺省时钟绑真实 @async.now（>0）。
test "P04-FR② 合法参数零拒绝且 new 缺省形态可用" {
  let pool = ConnectionPool::new()
  assert_true((pool.now_ms)() > 0L, msg="缺省时钟应绑真实 @async.now")
  let pool2 = ConnectionPool::new(max_idle=1, keep_alive_ms=0)
  let _ = pool2
  let pool3 = ConnectionPool::with_clock(max_idle=1, keep_alive_ms=0, now_fn=() => {
    0L
  })
  assert_eq((pool3.now_ms)(), 0L)
}

///|
// P04-E⑥ 白盒侧（FR-015，T005）：建连失败后 idle/borrowed/closed 三集合
// 零变化、发号器不动——无半租约（contracts §2 第 4 条）。与 pool_test 的
// 同名黑盒用例按 -f "P04-E*" 跨文件一并收集（research R9）。
async test "P04-E⑥ acquire 建连失败透传且计数不虚增" {
  let pool = ConnectionPool::with_clock(max_idle=5, keep_alive_ms=300_000, now_fn=() => {
    42L
  })
  let addr = Address::new(scheme="http", host="127.0.0.1", port=0)
  let raised = try {
    let _lease = pool.acquire(addr)
    false
  } catch {
    _ => true
  }
  assert_true(raised, msg="建连失败必须原样透传（FR-015）")
  // 三集合零变化（priv 状态白盒直读）：无半租约、无计数漂移
  assert_eq(pool.inner.borrowed.length(), 0, msg="borrowed 必须为空")
  assert_eq(pool.inner.closed.length(), 0, msg="closed 必须为空")
  let mut idle_total = 0
  for _key, bucket in pool.inner.idle {
    idle_total = idle_total + bucket.length()
  }
  assert_eq(idle_total, 0, msg="idle 必须为空")
  assert_eq(
    pool.inner.next_conn_id,
    1,
    msg="发号器不得在失败路径推进（守恒恒等式无隙）",
  )
}

///|
// P04-FR⑧（FR-004 真 LIFO 次序，T006 白盒）：造两条同 Address 空闲连接，
// release A → release B → acquire 断言得 B（栈尾=最热）；再次 acquire 得
// A；全程 per_host_total 不动（命中路径零新建，不变量 6）。conn_id 白盒
// 可读（R9）——黑盒不配当 LIFO 判据（串行单连接循环下恒真）。
async test "P04-FR⑧ LIFO 次序：release A→B 后 acquire 得 B" {
  @async.with_task_group() <| _group => {
    let server = @fixtures.ScriptedServer::start()
    let pool = ConnectionPool::new(max_idle=5, keep_alive_ms=300_000)
    let addr = Address::new(scheme="http", host="127.0.0.1", port=server.port())
    let a = pool.acquire(addr)
    let b = pool.acquire(addr)
    assert_true(a.conn_id != b.conn_id, msg="两条连接须互异")
    assert_eq(pool.per_host_total(addr), 2, msg="两条连接均须新建")
    a.release()
    b.release()
    // 栈态：[A, B]（尾=最热）——acquire 得 B
    let again = pool.acquire(addr)
    assert_eq(again.conn_id, b.conn_id, msg="LIFO：acquire 应得最热的 B")
    assert_eq(
      pool.per_host_total(addr),
      2,
      msg="命中路径不得新建（不变量 6）",
    )
    // 再取应得 A
    let third = pool.acquire(addr)
    assert_eq(third.conn_id, a.conn_id, msg="第二次 acquire 应得 A")
    assert_eq(pool.per_host_total(addr), 2, msg="全程零新建")
    server.close()
  }
}
