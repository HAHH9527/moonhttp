///|
// recover_wbtest：P07 白盒测试（判定器两层——decide 决策矩阵全分支 +
// error_family 可构造族直测；R4 两层切分的宪法 IV 对账面）。
// 红绿纪律（宪法 IV）：每测试先红后绿；首跑颜色实测记录，禁止事后补造。
//
// 诚实边界（research R4）：TLS 族（@tls.TlsError/ConnectionClosed）与
// @socket.ResolveHostnameError 为 pub 非 pub(all)——跨包不可构造，本文件
// 不覆盖其族归类；decide 层以 ErrFamily::Stale/ConnectFailure 直测兜底
// （T004 WB⑦/R10 映射行），M2 TLS 场景扩展时接管。

///|
// 白盒辅助：Stream 体源构造（filler 零动作——decide 纯函数输入面不执行体）。
fn wb_stream_body() -> @core.BodySource {
  @core.BodySource::Stream(_w => ())
}

///|
// P07-WB①（FR-006 取消优先，T004）：cancelled=true 恒 Fail——其余入参全取
// 可重试形态（ReadHead∧Stale∧预算内∧开关开∧可重放体）仍不重试；外层轮顶
// guard 与 attempt 级 guard 为第一道防线，decide 首条件兜底（R1）。
test "P07-WB① decide 取消优先：cancelled 恒 Fail" {
  let d = decide(ReadHead, Stale, None, false, 1, true, true)
  assert_true(d is Fail, msg="cancelled=true 必须恒 Fail（FR-006）")
}

///|
// P07-WB②（FR-010 开关，T004）：enabled=false 恒 Fail——可重试形态全就位
// 仍不重试（retry_on_connection_failure=false ⇒ 判定器恒 Fail，js 语义
// 同构；毒化等既有语义在捕获分支侧不受影响）。
test "P07-WB② decide 开关关闭：enabled=false 恒 Fail" {
  let d = decide(ReadHead, Stale, None, false, 1, false, false)
  assert_true(d is Fail, msg="开关关闭必须恒 Fail（FR-010）")
}

///|
// P07-WB③（FR-005 预算，T004）：attempts 边界——1=原始尝试可过预算门
// （可重试形态下 Retry）；2=预算耗尽恒 Fail（每代次 ≤2 次尝试，C3）。
test "P07-WB③ decide 预算边界：attempts=1 放行、attempts=2 Fail" {
  let within = decide(ReadHead, Stale, None, false, 1, true, false)
  assert_true(
    within is Retry,
    msg="attempts=1 边界内（重试形态基准）",
  )
  let exhausted = decide(ReadHead, Stale, None, false, 2, true, false)
  assert_true(
    exhausted is Fail,
    msg="attempts=2 预算耗尽恒 Fail（FR-005）",
  )
}

///|
// P07-WB④（FR-002 协议族不可重试，T004）：family==Protocol 恒 Fail——
// BadRequest/HttpVersionNotSupported/IncorrectBodyLength 同族（族检测
// 归一，WB⑩ 诚实边界外的集成面 B-11 承载）；毒化照常在捕获/逸出分支，
// 不进判定器。
test "P07-WB④ decide Protocol 族：恒 Fail" {
  let send = decide(Send, Protocol, None, false, 1, true, false)
  assert_true(send is Fail, msg="Send∧Protocol 不可重试（FR-002）")
  let read_head = decide(ReadHead, Protocol, None, true, 1, true, false)
  assert_true(
    read_head is Fail,
    msg="ReadHead∧Protocol 不可重试（畸形字节已到达=协议错误优先于重放门）",
  )
}

///|
// P07-WB⑤（未知错误透传，T004）：family==Other 恒 Fail——未知错误原样
// 透传（FR-008）；js 降级（error_family 恒 Other）在此格汇流（R6 同构）。
test "P07-WB⑤ decide Other 族：恒 Fail" {
  let connect = decide(Connect, Other, None, false, 1, true, false)
  assert_true(
    connect is Fail,
    msg="Connect∧Other 透传（未知建连错误）",
  )
  let read_head = decide(ReadHead, Other, None, false, 1, true, false)
  assert_true(
    read_head is Fail,
    msg="ReadHead∧Other 透传（js 降级同构）",
  )
}

///|
// P07-WB⑥（FR-003 体可重放门，T004）：replayable 前置格——None/Bytes 恒
// 可重放（C2：Bytes 部分写出后仍整体重发，entered 置位不影响）；Stream
// 保守封锁（R3：filler 调用即置位）——entered=true ⇒ Fail、entered=false
// ⇒ 放行；qod-2 必修①行：ReadHead∧Stream∧entered 必经此格 Fail。
test "P07-WB⑥ decide 体可重放门：None/Bytes 恒真、Stream 按 entered" {
  // None 体恒可重放：ReadHead∧Stale∧entered=true 仍放行（空体 GET canonical）
  let none_body = decide(ReadHead, Stale, None, true, 1, true, false)
  assert_true(
    none_body is Retry,
    msg="None 体恒可重放（entered 不影响）",
  )
  // Bytes 恒可重放：部分写出（entered=true）后仍整体重发（C2）
  let bytes_body = decide(
    Send,
    Stale,
    Some(@core.BodySource::Bytes(b"px")),
    true,
    1,
    true,
    false,
  )
  assert_true(
    bytes_body is Retry,
    msg="Bytes 体恒可重放（C2 对拍精化）",
  )
  // Stream∧entered=true：保守封锁（宁可漏重试不可误重试）
  let stream_entered = decide(
    Send,
    Stale,
    Some(wb_stream_body()),
    true,
    1,
    true,
    false,
  )
  assert_true(
    stream_entered is Fail,
    msg="Stream 已进入体发送 ⇒ Fail（FR-003）",
  )
  // Stream∧entered=false：发头失败形态，可重放门放行（主矩阵可达 Retry）
  let stream_fresh = decide(
    Send,
    Stale,
    Some(wb_stream_body()),
    false,
    1,
    true,
    false,
  )
  assert_true(stream_fresh is Retry, msg="Stream 未进入体发送 ⇒ 放行")
  // qod-2 必修①行：ReadHead∧Stream∧entered 必经重放门 Fail
  let read_head_stream = decide(
    ReadHead,
    Stale,
    Some(wb_stream_body()),
    true,
    1,
    true,
    false,
  )
  assert_true(
    read_head_stream is Fail,
    msg="ReadHead∧Stream∧entered 必经此格 Fail（qod-2 必修①）",
  )
}

///|
// P07-WB⑦（FR-001 可重试主矩阵，T004）：段×族可重试格——Connect∧Stale
// /Connect∧ConnectFailure（建连失败族）、Send∧Stale（已过重放门）、
// ReadHead∧Stale（stale 判定主路径）全部 Retry。TLS 族/ResolveHostname
// 分支以 ErrFamily 直测兜底（诚实边界，R4/R10）。
test "P07-WB⑦ decide 可重试主矩阵：四格 Retry" {
  let connect_stale = decide(Connect, Stale, None, false, 1, true, false)
  assert_true(
    connect_stale is Retry,
    msg="Connect∧Stale → Retry（FR-001）",
  )
  let connect_failure = decide(
    Connect,
    ConnectFailure,
    None,
    false,
    1,
    true,
    false,
  )
  assert_true(
    connect_failure is Retry,
    msg="Connect∧ConnectFailure → Retry（建连失败族，无毒化义务）",
  )
  let send_stale = decide(Send, Stale, None, false, 1, true, false)
  assert_true(
    send_stale is Retry,
    msg="Send∧Stale → Retry（已过重放门）",
  )
  let read_head_stale = decide(ReadHead, Stale, None, false, 1, true, false)
  assert_true(
    read_head_stale is Retry,
    msg="ReadHead∧Stale → Retry（stale 判定主路径，计数判据格）",
  )
}

///|
// P07-WB⑧（收尾兜底行，T004）：全域定义兜底——非可重试格一律 Fail
// （Send/ReadHead ∧ ConnectFailure：建连族错误出现在传输段=未知形态，
// 透传不误重试；qod-2 必修①兜底行）。
test "P07-WB⑧ decide 收尾兜底行：非可重试格恒 Fail" {
  let send_connect_failure = decide(
    Send,
    ConnectFailure,
    None,
    false,
    1,
    true,
    false,
  )
  assert_true(
    send_connect_failure is Fail,
    msg="Send∧ConnectFailure → Fail（兜底行）",
  )
  let read_head_connect_failure = decide(
    ReadHead,
    ConnectFailure,
    None,
    false,
    1,
    true,
    false,
  )
  assert_true(
    read_head_connect_failure is Fail,
    msg="ReadHead∧ConnectFailure → Fail（兜底行）",
  )
}

///|
// P07-WB⑩（T006）：族检测可构造面——@io.ReaderClosed/@os_error.OSError
// 均为 pub(all) 可跨包构造（R2 锚点表）；段相关归类（qod-2 必修②）：
// OSError 在 Connect → ConnectFailure、在 Send/ReadHead → Stale（RST 读头
// 形态可重试的必要条件）；ReaderClosed 在 Send/ReadHead → Stale、在
// Connect → Other（矩阵兜底——建连段无读面，未知形态透传）。
test "P07-WB⑩ 族检测可构造面：OSError/ReaderClosed 段相关归类" {
  let probe_os = @os_error.OSError(
    111,
    context="可构造探针（ECONNREFUSED 量级）",
  )
  assert_true(
    error_family(Connect, probe_os) is ConnectFailure,
    msg="Connect∧OSError → ConnectFailure（建连失败族）",
  )
  assert_true(
    error_family(Send, probe_os) is Stale,
    msg="Send∧OSError → Stale（RST 族并入，Windows EOF 折算同入）",
  )
  assert_true(
    error_family(ReadHead, probe_os) is Stale,
    msg="ReadHead∧OSError → Stale（stale 判定主路径族）",
  )
  assert_true(
    error_family(Send, @io.ReaderClosed) is Stale,
    msg="Send∧ReaderClosed → Stale（EOF 族）",
  )
  assert_true(
    error_family(ReadHead, @io.ReaderClosed) is Stale,
    msg="ReadHead∧ReaderClosed → Stale（F17 三形态同判）",
  )
  assert_true(
    error_family(Connect, @io.ReaderClosed) is Other,
    msg="Connect∧ReaderClosed → Other（建连段无读面，矩阵兜底）",
  )
}

///|
// P07-WB⑪（T006）：未知错误 → Other——以包内可构造的 CallCancelled 作
// 未知错误探针（取消不属任何失败族；decide 首条件另行兜底，族层如实归
// Other 透传）。
test "P07-WB⑪ 族检测未知错误：CallCancelled → Other" {
  assert_true(
    error_family(Connect, CallCancelled) is Other,
    msg="Connect∧未知错误 → Other",
  )
  assert_true(
    error_family(ReadHead, CallCancelled) is Other,
    msg="ReadHead∧未知错误 → Other",
  )
}

///|
// P07-WB⑭（T017，2026-10-30）：HttpClient::new 开关参数传递链断言——
// 尾随可选参缺省 true（FR-010＝OkHttp 默认行为面）、显式 false 如实落
// 字段（判定处经 client 同包 priv 直读，qod-2 点 4-5）；构造面字段值
// 直读（priv 白盒）。
test "P07-WB⑭ 开关参数传递链：缺省 true、显式 false 落字段" {
  let pool = ConnectionPool::new()
  let default_client = HttpClient::new(pool)
  assert_true(
    default_client.retry_on_connection_failure,
    msg="缺省 true（FR-010/C4：OkHttp 默认行为面）",
  )
  let off_client = HttpClient::new(pool, retry_on_connection_failure=false)
  assert_false(
    off_client.retry_on_connection_failure,
    msg="显式 false 如实落字段（FR-010）",
  )
}

///|
// P08-WB①（P08 FR-008 判定器族落点矩阵·可达格，T003 红；S6 收敛口径）：
// HttpTimeout 四变体 × 可达段——变体与注入伞一一对应（data-model 实体 2）：
//   - Connect 变体 ∧ stage=Connect（连接伞注入点）→ ConnectFailure
//     （建连失败族，可重试——走既有 (Connect, ConnectFailure) => Retry 格）；
//   - Write 变体 ∧ stage=Send（写窗注入点）→ Other（decide 既有
//     family is Other → Fail 透传格，零 decide 改动）；
//   - Read 变体 ∧ stage=ReadHead（读窗注入点）→ Other（同上）；
//   - Call 变体 × 任意段 → Other（call 伞取消不经 catch——R4 结构保证，
//     结构上不可能作为错误进入判定器；族层如实归 Other 钉死防御格）。
// 预期红：error_family 无 HttpTimeout 分支 ⇒ Connect∧Connect 格落
// Other，红恰 1 格（T004 转绿）。
test "P08-WB① 判定器族落点矩阵·可达格：Connect→建连族、余→Other" {
  // 可达格 1：连接伞注入点（红因格——无分支时落 Other）
  assert_true(
    error_family(Connect, HttpTimeout::Connect) is ConnectFailure,
    msg="Connect∧HttpTimeout::Connect → ConnectFailure（建连失败族可重试，FR-008/C3）",
  )
  // 可达格 2：写窗注入点 → Other（不可重试透传）
  assert_true(
    error_family(Send, HttpTimeout::Write) is Other,
    msg="Send∧HttpTimeout::Write → Other（Write 不可重试，FR-008）",
  )
  // 可达格 3：读窗注入点 → Other（不可重试透传）
  assert_true(
    error_family(ReadHead, HttpTimeout::Read) is Other,
    msg="ReadHead∧HttpTimeout::Read → Other（Read 不可重试，FR-008）",
  )
  // Call 变体 × 任意段 → Other（R4：取消不可被 catch 捕获，结构上
  // 不可达；三段如实归 Other 钉死）
  for stage in [SendStage::Connect, Send, ReadHead] {
    assert_true(
      error_family(stage, HttpTimeout::Call) is Other,
      msg="HttpTimeout::Call×任意段 → Other（R4 结构不可达防御格）",
    )
  }
}

///|
// P08-WB②（族落点矩阵·不可达格钉不回归，T003）：变体与阶段一一对应
// （伞注入点决定）——Connect 变体出现在 {Write(=Send), Read(=ReadHead),
// Call} 段、Send/ReadHead 段目睹 Connect 变体均为不可达格；断言族
// 落点 = Other（钉不回归——未来分支改动不得把不可达格误归可重试族）。
test "P08-WB② 族落点矩阵·不可达格：恒 Other（钉不回归）" {
  // Connect 变体出现在传输/收头段（不可达——连接伞只在建连段注入）
  assert_true(
    error_family(Send, HttpTimeout::Connect) is Other,
    msg="Send∧HttpTimeout::Connect 不可达格 → Other",
  )
  assert_true(
    error_family(ReadHead, HttpTimeout::Connect) is Other,
    msg="ReadHead∧HttpTimeout::Connect 不可达格 → Other",
  )
  // 传输/收头段目睹 Write/Call 变体（不可达——写窗只在 Send、call 伞
  // 沿取消链逸出）
  assert_true(
    error_family(Connect, HttpTimeout::Write) is Other,
    msg="Connect∧HttpTimeout::Write 不可达格 → Other",
  )
  assert_true(
    error_family(ReadHead, HttpTimeout::Write) is Other,
    msg="ReadHead∧HttpTimeout::Write 不可达格 → Other",
  )
  assert_true(
    error_family(Connect, HttpTimeout::Call) is Other,
    msg="Connect∧HttpTimeout::Call 不可达格 → Other",
  )
  assert_true(
    error_family(Send, HttpTimeout::Call) is Other,
    msg="Send∧HttpTimeout::Call 不可达格 → Other",
  )
  assert_true(
    error_family(ReadHead, HttpTimeout::Call) is Other,
    msg="ReadHead∧HttpTimeout::Call 不可达格 → Other",
  )
}
