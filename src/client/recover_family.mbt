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
