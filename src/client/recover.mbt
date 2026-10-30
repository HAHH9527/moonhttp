///|
// recover：P07 判定器——决策层（data-model 实体 3；全 target 共享纯函数）。
// 六条件合取的机械形态（FR-001）：取消优先 → 开关 → 预算 → 族（Protocol/
// Other 不可重试）→ 体可重放门 → 段×族主矩阵 → 收尾兜底行。族检测
// （段相关）归 recover_family.mbt（research R4 两层切分）；接线归
// follow_up.mbt 轮内尝试子循环（T011）。判定器仅在错误路径执行
// （宪法 II：快乐路径零新增分支/分配）。
//
// 公开面纪律（FR-011/INV-R5）：三枚举与判定函数全 priv，不进 .mbti。

///|
// 阶段标记（data-model 实体 1）：L1 自有调用点边界——Connect=建连段
// （ensure_lease）、Send=发头/写体段（request/write_once/filler）、
// ReadHead=收头段（end_request）。置位点＝exchange.mbt 四调用点前置赋值
// （T009 插桩）；子循环体首行复位 Connect（qod-2 必修④，防跨 attempt
// 残留误计数）。
priv enum SendStage {
  Connect
  Send
  ReadHead
}

///|
// 错误族（data-model 实体 2）：族检测结果（段相关，error_family 按
// stage 归类）——Stale=EOF/RST 传输族（可重试、ReadHead 段判 stale）、
// Protocol=协议错误族（不可重试、毒化照常）、ConnectFailure=建连失败族
// （可重试、无租约无毒化义务）、Other=未知（不可重试透传；js 降级恒值）。
priv enum ErrFamily {
  Stale
  Protocol
  ConnectFailure
  Other
}

///|
// 判定输出（FR-001）：Retry=捕获分支内重试（先毒化后 continue，INV-R1）；
// Fail=原始错误透传（逸出路径毒化归属＝轮级 errdefer 单点，FR-008）。
priv enum RetryDecision {
  Retry
  Fail
}

///|
// 体可重放门（FR-003，qod-2 必修①前置格）：None/Bytes 恒可重放（C2——
// Bytes 部分写出后仍整体重发，entered 置位不影响）；Stream 保守封锁
// （R3：filler 调用即置位 ⇒ entered=true 封锁）。判据方向＝宁可漏重试
// 不可误重试。
fn replayable(body : @core.BodySource?, stream_body_entered : Bool) -> Bool {
  match body {
    None => true
    Some(@core.BodySource::Bytes(_)) => true
    Some(@core.BodySource::Stream(_)) => !stream_body_entered
  }
}

///|
// 判定器（FR-001 六条件合取的机械形态；T005 按 data-model 实体 3 矩阵
// 展开）。纯函数无 IO，输入全部可构造——全分支白盒可测（宪法 IV，T004
// 矩阵 WB①..⑧）。合取式判定可交换、重排无损（data-model 注记）；此处
// 排序＝取消/开关/预算先行（廉价格短路），族与重放门次之，主矩阵收尾。
fn decide(
  stage : SendStage,
  family : ErrFamily,
  body : @core.BodySource?,
  stream_body_entered : Bool,
  attempts : Int32,
  enabled : Bool,
  cancelled : Bool,
) -> RetryDecision {
  if cancelled {
    return Fail // FR-006 取消优先（外层轮顶/attempt 级 guard 亦兜底）
  }
  if !enabled {
    return Fail // FR-010 开关（false ⇒ 任何失败不重试）
  }
  if attempts >= 2 {
    return Fail // FR-005 预算（按请求代次，每代次 ≤2 次尝试）
  }
  if family is Protocol {
    return Fail // FR-002 协议族不可重试（毒化照常，经捕获/逸出分支）
  }
  if family is Other {
    return Fail // 未知错误透传（FR-008；js 降级恒值在此格汇流）
  }
  if !replayable(body, stream_body_entered) {
    return Fail // FR-003 体可重放门（ReadHead∧Stream∧entered 必经此格）
  }
  match (stage, family) {
    (Connect, Stale) | (Connect, ConnectFailure) => Retry // FR-001 建连失败族
    (Send, Stale) => Retry // 已过体可重放门
    (ReadHead, Stale) => Retry // stale 判定主路径（计数判据格）
    _ => Fail // 收尾兜底行（qod-2 必修①，全域定义）
  }
}
