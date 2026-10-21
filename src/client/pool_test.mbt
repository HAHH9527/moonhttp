///|
// pool_test：连接池 US 场景黑盒测试（P04 T005 起）。P03 夹具 +
// @http.Client 原语独立驱动，不经 P05（spec 独立测试口径）。
//
// 断言面仅公开计数器（per_host_total/stale_evictions）与行为观测——priv
// 状态黑盒不可读（E4091，research R9），三集合断言落同名白盒（pool_wbtest，
// -f 按测试名跨文件收集）。

///|
// P04-US1①（FR-008，T005）：空池 acquire → 新建连接，公开观测
// per_host_total(addr) 递增为 1。建连只经 Client::Client(uri)（D13），
// uri 形态 \{scheme}://\{host}:\{port}（实现结构审锚点：acquire 内单点）。
async test "P04-US1① 空池 acquire 新建连接且 per_host_total 记 1" {
  @async.with_task_group() <| _group => {
    let server = @fixtures.ScriptedServer::start()
    let pool = @client.ConnectionPool::new()
    let addr = @client.Address::new(
      scheme="http",
      host="127.0.0.1",
      port=server.port(),
    )
    assert_eq(
      pool.per_host_total(addr),
      0,
      msg="acquire 前观测计数应为 0",
    )
    let _lease = pool.acquire(addr)
    assert_eq(
      pool.per_host_total(addr),
      1,
      msg="空池 acquire 应新建连接并 +1（FR-008/不变量 6）",
    )
    server.close()
  }
}

///|
// P04-E⑥ 黑盒侧（FR-015，T005）：建连失败 → 错误原样透传（acquire 以
// raise 收场、不吞错），per_host_total 不虚增（失败侧 +0，不变量 6）。
// 注入形态＝port=0（连接期 OS 拒绝；2026-10-21 双 target 实测即时拒绝；
// close 后端口在本宿主悬挂不可用——P03⑩ 同款结论，故不用 close 形态；
// 错误类型不钉死，P03 口径「拒绝/悬挂形态不跨宿主断言」）。
async test "P04-E⑥ acquire 建连失败透传且计数不虚增" {
  @async.with_task_group() <| _group => {
    let server = @fixtures.ScriptedServer::start()
    let pool = @client.ConnectionPool::new()
    let addr = @client.Address::new(scheme="http", host="127.0.0.1", port=0)
    let raised = try {
      let _lease = pool.acquire(addr)
      false
    } catch {
      _ => true
    }
    assert_true(raised, msg="建连失败必须原样透传（FR-015）")
    assert_eq(
      pool.per_host_total(addr),
      0,
      msg="失败不得虚增计数（不变量 6：+1 只在建连成功后）",
    )
    server.close()
  }
}

///|
// P04-US1②③（FR-002/FR-004/SC-003，T006）：同 Address 串行
// acquire/release ≥100 次循环——② 循环结束 per_host_total(addr) == 1；
// ③ 循环全程零新建连接（首建之后计数恒 1）。黑盒可观测面仅公开计数器；
// LIFO 次序判据归白盒 P04-FR⑧（conn_id priv 黑盒不可读，research R9）。
async test "P04-US1② 串行 acquire/release 循环零新建" {
  @async.with_task_group() <| _group => {
    let server = @fixtures.ScriptedServer::start()
    let pool = @client.ConnectionPool::new()
    let addr = @client.Address::new(
      scheme="http",
      host="127.0.0.1",
      port=server.port(),
    )
    for i in 0..<100 {
      let lease = pool.acquire(addr)
      assert_eq(
        pool.per_host_total(addr),
        1,
        msg="第 \{i} 次循环出现新建——归池复用断裂（US1③/SC-003）",
      )
      lease.release()
    }
    assert_eq(
      pool.per_host_total(addr),
      1,
      msg="循环结束计数应为 1（US1②）",
    )
    server.close()
  }
}

///|
// P04-US1③（FR-003 栈满分支，T007）：max_idle=1 下两条连接先后 release →
// 第二条被 close、不入栈；复用不受影响。可观测推演：a.release() 后 idle=[A]，
// b.release() 触发栈满关闭（若 bug 回池则 idle=[A,B]）；此后两次 acquire
// 应为「得 A（命中，计数不动）→ 新建（计数 2→3）」——若 B 曾入栈则第二次
// acquire 复用 B、计数停在 2，即红。
// 【护栏/未红判据】栈满分支随 T006 归池谓词先行落地，本测试落笔即绿
// （003 T008/T016 先例口径，非静默）。
async test "P04-US1③ 栈满第二条 release 关闭不入栈且复用不受影响" {
  @async.with_task_group() <| _group => {
    let server = @fixtures.ScriptedServer::start()
    let pool = @client.ConnectionPool::new(max_idle=1, keep_alive_ms=300_000)
    let addr = @client.Address::new(
      scheme="http",
      host="127.0.0.1",
      port=server.port(),
    )
    let a = pool.acquire(addr)
    let b = pool.acquire(addr)
    assert_eq(pool.per_host_total(addr), 2, msg="两条连接均须新建")
    a.release()
    b.release()
    let again = pool.acquire(addr)
    assert_eq(
      pool.per_host_total(addr),
      2,
      msg="栈中唯一连接 A 须命中复用（计数不动）",
    )
    let more = pool.acquire(addr)
    assert_eq(
      pool.per_host_total(addr),
      3,
      msg="B 须已被关闭不入栈（若曾入栈则此处复用、计数停在 2）",
    )
    again.release()
    more.release()
    server.close()
  }
}
