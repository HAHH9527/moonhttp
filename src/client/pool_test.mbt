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
