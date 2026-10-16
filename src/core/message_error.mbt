///|
/// HTTP 报文层错误类型（FR-012）。
///
/// 变体清单与触发点矩阵的**唯一规范源**：
/// specs/002-m1-p02-request-response/data-model.md §5（本文件与 contracts/
/// 只按名引用、不重述）。两类违例：
///   - MethodBodyMismatch：方法/体矩阵违例（RequestBuilder::build 构造期，
///     C5 裁决矩阵）；
///   - IncorrectBodyLength：声明长度 ≠ 实际字节（Bytes 构造期；Stream 发送
///     期经 P05 映射上游 @http.IncorrectBodyLength 为同一变体）。
///
/// **封闭二变体（2026-10-16 owner 裁决 B）**：原第三变体
/// `UnsupportedCharset(String)` 删除——FR-007 改为集外 charset 按 UTF-8
/// 降级解码（不 raise），该变体失去唯一触发点；保留永不触发的变体是
/// 错误面的虚假承诺（宪法 VI 最小接口），F14 回补时新增变体走 spec 变更。
///
/// 形态对齐 P01（research R1）：`pub(all) suberror` + 仅 `derive(Debug)`
/// ——错误不参与判等/哈希（判别用 `is` 与模式匹配即够）；不使用
/// `derive(Show)`（弃用警告 [0027]）。错误输出只携带定位片段（变体名/
/// 方法名/长度对），不回显头值/体内容/URL 全文（宪法敏感信息口径）。
pub(all) suberror HttpMessageError {
  MethodBodyMismatch
  IncorrectBodyLength
} derive(Debug)

///|
// 消除 implicit_impl_as_method [0079] 的配套写法（决策 N1-A，research R1）。
// 工具链 0.1.20261012 下 derive(Debug) 一经使用（含同包测试 debug_inspect）
// 即触发 [0079]，须显式 pub extend 暴露 to_repr；该方法并入 .mbti 冻结
// 清单逐条审视（宪法 VI）。
pub extend HttpMessageError with Debug::{to_repr}
