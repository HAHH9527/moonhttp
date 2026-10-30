///|
// recover_family.js：js 降级形态（R6；.js.mbt 后缀自动锁 js）。
//
// @os_error/@tls/@socket 上游无 js 支（三包在 js 上编译为空包），族检测
// 恒 Other ⇒ decide 恒 Fail ⇒ 重试路径不激活——js 语义＝浏览器管理连接、
// 无陈旧连接概念（spec Target 矩阵；宪法 V 未验证面，欠账随 M5 收口）。
// 与 recover_family.mbt 同签名（contracts §2 接缝契约）。
fn error_family(_stage : SendStage, _err : Error) -> ErrFamily {
  Other
}
