///|
// recover_family：族检测层（data-model 实体 2；段相关归类）。
//
// 【targets 锁定】本文件由 src/client/moon.pkg options(targets) 显式锁
// [native, wasm]——普通命名文件默认全 target，不声明则 js 编译会碰到
// 锁定类型引用（@os_error/@tls/@socket 上游 js 为空包）；js 侧由
// recover_family.js.mbt 降级承载（.js.mbt 后缀自动锁 js）。上游
// http/moon.pkg client.mbt/client.js.mbt 成对声明先例（R6/qod-2 必修⑥）。
//
// 族检测（data-model 实体 2 矩阵；T007 展开，存根退役）。
fn error_family(stage : SendStage, err : Error) -> ErrFamily {
  // Protocol 首判（OkHttp :171-173 首行同构）：任意段 × 协议错误族
  // （BadRequest / HttpVersionNotSupported / IncorrectBodyLength）→
  // Protocol（不可重试、毒化照常、零计数）
  if err
    is (@http.BadRequest
    | @http.HttpVersionNotSupported(_)
    | @http.IncorrectBodyLength) {
    return Protocol
  }
  // P08 FR-008（T004，R5 判定器族落点三行）：超时变体按段分派——
  // Connect 变体 ∧ stage=Connect（连接伞注入点，FR-007）⇒
  // ConnectFailure（建连失败族，可重试：走既有
  // (Connect, ConnectFailure) => Retry 格，预算 ≤2 次尝试换新连接，
  // 耗尽透传原始变体——C3 对拍 5.5.0 recover InterruptedIOException
  // 分支形状）；Write/Read/Call ⇒ Other（decide 既有
  // `family is Other → Fail` 透传格——三变体不可重试原样透传，
  // decide 零改动）。插入位在 Protocol 首判之后、具体类型并集之前
  // （qod-2 零遮蔽：协议族优先级不变；变体与阶段一一对应，不可达格
  // 落 Other 由 P08-WB② 钉死）。本文件锁 [native, wasm]——HttpTimeout
  // 为本包自有类型，不引入锁定包类型（R12 moon.pkg 零改动）。
  if err
    is (HttpTimeout::Connect
    | HttpTimeout::Write
    | HttpTimeout::Read
    | HttpTimeout::Call) {
    if err is HttpTimeout::Connect && stage is SendStage::Connect {
      return ConnectFailure
    }
    return Other
  }
  match stage {
    Connect =>
      // 建连段：OSError（含 ECONNREFUSED 竞速全败）/ResolveHostnameError/
      // TLS 握手族 → ConnectFailure
      if err
        is (@os_error.OSError(_)
        | @socket.ResolveHostnameError(_)
        | @tls.TlsError(_)
        | @tls.ConnectionClosed) {
        return ConnectFailure
      }
    Send | ReadHead =>
      // 传输段：EOF 族（ReaderClosed）/RST 族（OSError——Windows EOF 折算
      // 并入）/TLS 传输族 → Stale
      if err
        is (@io.ReaderClosed
        | @os_error.OSError(_)
        | @tls.ConnectionClosed
        | @tls.TlsError(_)) {
        return Stale
      }
  }
  Other
}
