///|
// resolve：RFC 3986 §5 相对引用解析（spec US-2，FR-002）。
//
// 实现复用 http_url.mbt 的统一解析核心 parse_with_base（对齐 OkHttp 的
// parse(base, input) 单算法结构）：
//   - 绝对 location（含 scheme，且 scheme 与 base 不同或后随 ≥2 个斜杠）：
//     直接按绝对 URL 解析；
//   - 同 scheme 且斜杠数 < 2：按相对引用处理（继承 base 的 authority，
//     "http:g" 形式等价于相对路径 "g"，OkHttp/WHATWG 口径）；
//   - 网络路径参考 "//h/p"：scheme 自 base 继承；
//   - 空串 location：返回 base 去 fragment（对齐 OkHttp）；
//   - query-only（"?x=1"）丢弃 fragment；仅 fragment（"#f"）保持 path/query；
//   - base 无 path（根路径）时 "../up" 钳制到根（L6-A 锚点 3）。
// 复杂度：复用已解析 base，仅对 location 增量解析（O(增量)，宪法 II）。

///|
/// RFC 3986 §5 相对引用解析；复用已解析 base、O(增量)（FR-002）。
/// 绝对 location（含 scheme）直接解析；网络路径参考 "//h/p" 的 scheme 自
/// base 继承；空 location 返回 base 去 fragment（对齐 OkHttp）。
pub fn HttpUrl::resolve(
  base : HttpUrl,
  location : String,
) -> HttpUrl raise HttpUrlError {
  parse_with_base(Some(base), location)
}
