///|
/// URL 解析失败的错误类型（parse/resolve 的 raise 信号）。
///
/// 变体清单的唯一规范源：specs/001-m1-p01-core-value-types/data-model.md §4.1
/// （决策 L4-A：本文件之外只按名引用、不重述分类细节）。
/// 仅 `derive(Debug)`：错误不参与判等/哈希（判别用 `is` 与模式匹配即够，
/// 决策 M5-A）；不使用 `derive(Show)`（弃用警告 [0027]，决策 N1-A）。
/// 错误输出只携带定位片段（变体名），不整体回显原始输入（SC-005 ②）。
pub(all) suberror HttpUrlError {
  InvalidHost
  InvalidPort
  MalformedUrl
  UnsupportedScheme
} derive(Debug)

///|
// 消除 implicit_impl_as_method [0079] 的配套写法（决策 N1-A）。工具链
// 0.1.20261012 比 research R4 基线（0.1.20260920）更严：错误类型的
// derive(Debug) impl 一经使用（debug_inspect/Repr，含同包测试）也会触发
// [0079]，故错误类型同样需要 Debug::{to_repr} 的显式 pub extend 才能
// 满足 SC-004 零警告。该 to_repr 方法并入 .mbti 冻结清单逐条审视
// （宪法 VI「接口变化必须是有意识的决定」；Eq/Hash 仍不提供，M5-A 不变）。
pub extend HttpUrlError with Debug::{to_repr}

///|
/// HeadersVBuilder 头校验失败的错误类型（FR-012，防头注入，决策 H2-A）。
///
/// 触发条件的唯一规范源：data-model.md §4.2。derive 口径与 HttpUrlError 一致。
pub(all) suberror HeadersError {
  InvalidName
  InvalidValue
} derive(Debug)

///|
pub extend HeadersError with Debug::{to_repr}
