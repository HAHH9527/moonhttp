///|
// response：Response（不可变响应值，六要素）与 from_http 纯重建
// （spec US-3，FR-008/010；data-model §3；research R3/R7）。
//
// 设计：
//   - headers 由 @http 响应 Map 重建为 HeadersV：逐键把逗号合并值以无空格
//     `,` 拆回多条，条目序 = Map 遍历序——顺序不保真，验收 MUST NOT 断言
//     线上序（FR-008）；该拆分与 P01 折叠互逆（P01 SC-003 不变量②）。
//     quoted-string 逗号不做边界感知（与 P01 同一已记录限制，认证路径
//     M2 绕过）。
//   - cookies 仅透传（M1 不建 Jar；js 恒空，spec A8）。
//   - body/prior 为可选装配位：@http.Response 无 body 字段，body 由 P05
//     围绕 Client as @io.Reader 组装后传入；prior 由 P06 填充，本包不产链。
//   - charset 上下文：组装时按 research R5 从响应头 Map 提取 Content-Type
//     合并值注入 body（「取响应头 Map 中 Content-Type 的合并值」的天然
//     落点）；直构 ResponseBody（不经 from_http）text() 按缺省 UTF-8。
//   - 无 IO 无状态（纯函数，FR-008）。
//   - Request/Response 值类型不实现 Eq/Hash（R10：body/prior 含引用与
//     函数字段，判等无语义——有意口径，.mbti 冻结审视按此核对）。
//   - derive(Debug)（R10 三分法；headers/cookies 明文输出沿 P01 展示例外
//     口径，F13/M3 收口）。
pub struct Response {
  code : Int32
  reason : String
  headers : HeadersV
  cookies : Array[@http.Cookie]
  body : ResponseBody?
  prior : Response?
} derive(Debug)

///|
// 消除 implicit_impl_as_method [0079] 的配套写法（决策 N1-A，research R1）
pub extend Response with Debug::{to_repr}

///|
/// 纯重建：由上游 `@http` 响应面组装不可变 Response（FR-008）。
///
/// - headers：逐键拆分逗号合并值（无空格 `,`），条目序 = Map 遍历序；
/// - body?/prior?：可选装配位；
/// - charset 上下文按 research R5 从 headers 提取 Content-Type 合并值。
pub fn Response::from_http(
  code : Int32,
  reason : String,
  headers : @http.Headers,
  cookies : Array[@http.Cookie],
  body~ : ResponseBody? = None,
  prior~ : Response? = None,
) -> Response {
  // headers 重建：合并值拆回多条（与 P01 折叠互逆）
  let entries : Array[(@http.CaseInsensitiveString, String)] = []
  for name, value in headers {
    for piece in value.split(",") {
      entries.push((name, piece.to_owned()))
    }
  }
  // charset 上下文注入：Content-Type 合并值 → body（stream 态同享该声明）
  let content_type = headers.get(@http.CaseInsensitiveString("Content-Type"))
  match body {
    Some(b) => b.content_type = content_type
    None => ()
  }
  { code, reason, headers: { entries, }, cookies, body, prior, }
}

///|
/// 状态码访问器（FR-008 六要素访问器，contracts/response.md 条款 4）。
pub fn Response::code(self : Response) -> Int32 {
  self.code
}

///|
/// 原因短语访问器。
pub fn Response::reason(self : Response) -> String {
  self.reason
}

///|
/// 响应头访问器（HeadersV，遍历序重建）。
pub fn Response::headers(self : Response) -> HeadersV {
  self.headers
}

///|
/// cookies 访问器（透传，M1 不建 Jar）。
pub fn Response::cookies(self : Response) -> Array[@http.Cookie] {
  self.cookies
}

///|
/// 响应体访问器。
pub fn Response::body(self : Response) -> ResponseBody? {
  self.body
}

///|
/// 前置响应访问器（字段就位，P06 填充，本包不产链）。
pub fn Response::prior(self : Response) -> Response? {
  self.prior
}
