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

///|
// P04-FR③（FR-001 独占白盒 + 不变量 1/5，T008）：并发 acquire N → N 个
// 互异 conn_id 全员在 borrowed（两两不交＝Map 键唯一 + 全员在场）；交错
// release / 再 acquire 后守恒恒等式恒成立（borrowed+idle+closed ==
// next_conn_id-1），且命中路径不发新号（next_conn_id 冻结）。
// 【护栏备注】pop 移除与 borrowed 去重随 T006 接入路径在场，本测试为其
// 并发交错的回归护栏——若独占/守恒被破坏即红。
async test "P04-FR③ 并发 acquire 独占与守恒恒等式" {
  @async.with_task_group() <| group => {
    let server = @fixtures.ScriptedServer::start()
    let pool = ConnectionPool::new(max_idle=8, keep_alive_ms=300_000)
    let addr = Address::new(scheme="http", host="127.0.0.1", port=server.port())
    let n = 8
    // R2 对策：预启动 accept 循环再放行客户端——wasm 实测（2026-10-21）：
    // 不预启动时 8 并发 connect 打满监听 backlog 被拒（native 侧backlog
    // 较大未暴露）。被 accept 的连接处理阻塞在 read_request，由测试组
    // 退出时的结构化取消收尾（上游 task_group.mbt:116-119：被组取消的
    // 任务不算失败），无需 drain。
    let _serving = group.spawn(() => server.serve_n(n, timeout_ms=8000))
    let leases : Array[Lease?] = Array::make(n, None)
    let tasks = []
    for i in 0..<n {
      let k = i
      tasks.push(group.spawn(() => leases[k] = Some(pool.acquire(addr))))
    }
    for task in tasks {
      task.wait()
    }
    // 断言 1：N 个互异 conn_id
    let ids : Array[Int32] = []
    for i in 0..<n {
      let lease = match leases[i] {
        Some(l) => l
        None => fail("并发 acquire \{i} 未取得租约")
      }
      ids.push(lease.conn_id)
    }
    for i in 0..<n {
      for j in 0..<n {
        if i != j {
          assert_true(
            ids[i] != ids[j],
            msg="独占破坏：conn_id \{ids[i]} 重复出租（不变量 1）",
          )
        }
      }
    }
    // 断言 2：borrowed 恰含全部 N 个 id（两两不交 + 全员在场）
    assert_eq(
      pool.inner.borrowed.length(),
      n,
      msg="borrowed 基数应为 N（全员在租）",
    )
    for i in 0..<n {
      assert_true(
        pool.inner.borrowed.contains(ids[i]),
        msg="id \{ids[i]} 应在 borrowed 集合",
      )
    }
    // 断言 3：守恒恒等式（不变量 5）
    let mut idle_total = 0
    for _key, bucket in pool.inner.idle {
      idle_total = idle_total + bucket.length()
    }
    assert_eq(
      pool.inner.borrowed.length() + idle_total + pool.inner.closed.length(),
      pool.inner.next_conn_id - 1,
      msg="并发 acquire 后守恒恒等式破坏",
    )
    // 交错：前半 release（→idle），后半保持在租
    for i in 0..<4 {
      match leases[i] {
        Some(l) => l.release()
        None => ()
      }
    }
    // 再并发 acquire 4 个：全走 pop 命中，不得发新号
    let again : Array[Lease?] = Array::make(4, None)
    let tasks2 = []
    for i in 0..<4 {
      let k = i
      tasks2.push(group.spawn(() => again[k] = Some(pool.acquire(addr))))
    }
    for task in tasks2 {
      task.wait()
    }
    for i in 0..<4 {
      let lease = match again[i] {
        Some(l) => l
        None => fail("再 acquire \{i} 未取得租约")
      }
      assert_true(
        ids.contains(lease.conn_id),
        msg="命中路径发新号：\{lease.conn_id} 不在原 id 集（守恒破坏）",
      )
    }
    assert_eq(
      pool.inner.next_conn_id,
      n + 1,
      msg="全程不得有隐藏新建（发号器冻结于 N+1）",
    )
    // 收尾全量 release 后再验守恒（Borrowed→Idle 迁移不破坏恒等式）
    for i in 0..<4 {
      match again[i] {
        Some(l) => l.release()
        None => ()
      }
    }
    for i in 4..<n {
      match leases[i] {
        Some(l) => l.release()
        None => ()
      }
    }
    let mut idle_after = 0
    for _key, bucket in pool.inner.idle {
      idle_after = idle_after + bucket.length()
    }
    assert_eq(
      pool.inner.borrowed.length() + idle_after + pool.inner.closed.length(),
      pool.inner.next_conn_id - 1,
      msg="全量 release 后守恒恒等式破坏（不变量 5）",
    )
    assert_eq(idle_after, n, msg="max_idle=8 下 N 条应全部回池")
    server.close()
  }
}

///|
// P04-FR④（FR-018 终结幂等白盒，T012）：已 release 的 Lease 再次
// release / 释放后 poison → 均 no-op——不重复入栈、不二次关闭、标记不
// 生效；守恒恒等式在任意调用序下保持（不变量 5）。毒化正常路径（先
// poison 后 release）不受短路守卫影响，一并回归。
async test "P04-FR④ 终结幂等：重复终结 no-op 且守恒保持" {
  @async.with_task_group() <| _group => {
    let server = @fixtures.ScriptedServer::start()
    let pool = ConnectionPool::new(max_idle=5, keep_alive_ms=300_000)
    let addr = Address::new(scheme="http", host="127.0.0.1", port=server.port())
    let lease = pool.acquire(addr)
    lease.release()
    lease.release()
    lease.poison()
    // priv 直读：idle 恰 1 条、closed 空、终结标记不翻转
    assert_eq(
      pool.inner.idle.get(addr).unwrap_or([]).length(),
      1,
      msg="重复 release 不得重复入栈（不变量 5 前提）",
    )
    assert_eq(pool.inner.closed.length(), 0, msg="不得二次关闭")
    assert_false(lease.poisoned, msg="释放后 poison 须为 no-op")
    assert_eq(
      pool.inner.borrowed.length() + 1 + pool.inner.closed.length(),
      pool.inner.next_conn_id - 1,
      msg="终结幂等下守恒恒等式保持（不变量 5）",
    )
    // 毒化正常路径回归：先 poison 后 release → close（短路守卫不误伤），
    // 且不连带清掉其他空闲条目——先备两条连接：A 回池、B 毒化关闭
    let lease_a = pool.acquire(addr)
    let lease_b = pool.acquire(addr)
    lease_a.release()
    lease_b.poison()
    lease_b.release()
    assert_eq(
      pool.inner.closed.length(),
      1,
      msg="毒化路径关闭 B（conn2）",
    )
    assert_eq(
      pool.inner.idle.get(addr).unwrap_or([]).length(),
      1,
      msg="毒化关闭不得连带清掉空闲条目（A 应仍在栈）",
    )
    server.close()
  }
}

///|
// P04-FR⑤（FR-005 注入时钟超期剔除，R2 落地，T013）：with_clock
// (keep_alive_ms=1000) + 2 条空闲连接 → 虚拟时钟推进过阈 →
// evict_expired() 确定性剔除 2 条：stale_evictions +2、idle 清空、
// 未超期连接 0 误剔；连续调用幂等（第二次零剔除）。
async test "P04-FR⑤ 注入时钟超期剔除：确定性/计数口径/幂等/零误剔" {
  @async.with_task_group() <| _group => {
    let server = @fixtures.ScriptedServer::start()
    let mut now : Int64 = 10_000
    let pool = ConnectionPool::with_clock(max_idle=5, keep_alive_ms=1000, now_fn=() => {
      now,
    })
    let addr = Address::new(scheme="http", host="127.0.0.1", port=server.port())
    let a = pool.acquire(addr)
    let b = pool.acquire(addr)
    a.release()
    b.release()
    // 未过阈（500ms < 1000ms）：零剔除、零误伤
    now = 10_500
    pool.evict_expired()
    assert_eq(pool.stale_evictions(), 0, msg="未超期不得剔除")
    assert_eq(
      pool.inner.idle.get(addr).unwrap_or([]).length(),
      2,
      msg="未超期连接须原样在栈",
    )
    // 过阈（1500ms > 1000ms）：确定性剔除 2 条
    now = 11_500
    pool.evict_expired()
    assert_eq(
      pool.stale_evictions(),
      2,
      msg="2 条超期剔除 → stale_evictions +2（Q3 口径）",
    )
    assert_eq(
      pool.inner.idle.get(addr).unwrap_or([]).length(),
      0,
      msg="超期剔除后 idle 清空",
    )
    assert_eq(pool.inner.closed.length(), 2, msg="被剔连接迁移 Closed")
    // 幂等：连续调用第二次零剔除
    pool.evict_expired()
    assert_eq(pool.stale_evictions(), 2, msg="幂等：第二次零剔除")
    // 未超期连接 0 误剔：新入栈连接（idle_since=11500）推进 500ms 后不被剔
    let c = pool.acquire(addr)
    c.release()
    now = 12_000
    pool.evict_expired()
    assert_eq(pool.stale_evictions(), 2, msg="未超期连接 0 误剔")
    assert_eq(
      pool.inner.idle.get(addr).unwrap_or([]).length(),
      1,
      msg="未超期连接原样保留",
    )
    server.close()
  }
}
