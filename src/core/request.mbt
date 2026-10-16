///|
// request：Request（不可变请求值，五要素）与 RequestBuilder（可变构造器 +
// 方法/体矩阵构造期校验）（spec US-1，FR-001/002；C2/C5 裁决）。
//
// 设计（data-model §1；research R2/R10）：
//   - Request 不可变值：构造只经 RequestBuilder，build() 成功即冻结；
//     跨重试/重定向复用内容恒定（FR-001）。
//   - 不实现 Eq/Hash（R10：body 含函数/引用字段，判等无语义；池键由 P01
//     HttpUrl+HeadersV 承担）——与 P01 FR-006 的有意差异。
//   - Request/RequestBuilder derive(Debug)（R10 三分法；headers 明文输出沿
//     P01 展示例外口径，F13/M3 收口；测试样例值用合成占位串，A9 纪律）。
//   - 方法/体矩阵（C5 裁决，佐证 research R2）：拒体仅 Get/Head；必体
//     Post/Put/Patch；可选 Delete/Options/Trace/Connect。违例 raise
//     MethodBodyMismatch（变体规范源 data-model §5）。
//   - 头操作 header 委托 P01 HeadersVBuilder 校验（raise HeadersError，
//     本包不重复/放宽，I12 消歧）；校验失败 Builder 状态不变（P01
//     「校验先于任何变更」纪律继承）。
//
// ⚠ method 为 MoonBit 保留字（[0035]，解析期警告）：它是 spec FR-002 冻结\r
// 契约的五要素字段/方法名（contracts/request.md），不可改名——包级\r
// options(warnings: ...) 已按有理由例外关闭该警告（见 moon.pkg，T020 门）。\r
pub struct Request {
  url : HttpUrl
  method : Method
  headers : HeadersV
  tag : Unit?
  body : RequestBody?
} derive(Debug)

///|
// 消除 implicit_impl_as_method [0079] 的配套写法（决策 N1-A，research R1）
pub extend Request with Debug::{to_repr}

///|
/// 可变构造器：链式设置五要素，`build()` 执行矩阵校验并产出不可变值。
pub struct RequestBuilder {
  url : HttpUrl
  method : Method
  headers : HeadersVBuilder
  tag : Unit?
  body : RequestBody?
} derive(Debug)

///|
pub extend RequestBuilder with Debug::{to_repr}

///|
/// 以必填 url 构造 Builder；method 缺省 `Get`、body 缺省 `None`、tag 缺省
/// `None`、headers 起始为空（FR-002）。
pub fn RequestBuilder::new(url : HttpUrl) -> RequestBuilder {
  {
    url,
    method: Method::Get,
    headers: HeadersVBuilder::new(),
    tag: None,
    body: None,
  }
}

///|
/// 设置方法（链式）。
pub fn RequestBuilder::method(
  self : RequestBuilder,
  method : Method,
) -> RequestBuilder {
  { ..self, method, }
}

///|
/// 整体替换 headers（链式）：接收 P01 已固化 HeadersV，经 `builder()` 防御性
/// 回转（P01 校验已发生，不重跑 FR-012）。
pub fn RequestBuilder::headers(
  self : RequestBuilder,
  headers : HeadersV,
) -> RequestBuilder {
  { ..self, headers: headers.builder(), }
}

///|
/// 追加一条头：委托 P01 `HeadersVBuilder::add` 校验（非法名/值 raise
/// `HeadersError`，P01 保证校验先于任何变更——失败时 Builder 状态不变）。
pub fn RequestBuilder::header(
  self : RequestBuilder,
  name : String,
  value : String,
) -> Unit raise HeadersError {
  self.headers.add(name, value)
}

///|
/// 设置 tag（链式；`Unit?` 占位——C2 裁决：只存取、无任何按 tag 定位/取消
/// 语义，升级评估挂欠账 F15）。
pub fn RequestBuilder::tag(
  self : RequestBuilder,
  tag : Unit?,
) -> RequestBuilder {
  { ..self, tag, }
}

///|
/// 设置请求体（链式）。
pub fn RequestBuilder::body(
  self : RequestBuilder,
  body : RequestBody,
) -> RequestBuilder {
  { ..self, body: Some(body), }
}

///|
/// 组装不可变 Request：执行方法/体矩阵双向校验（C5 裁决矩阵，变体触发点
/// 唯一规范源 data-model §5）；校验只读、失败 raise 且 Builder 状态不变，
/// 修正后可重入（FR-002）。
pub fn RequestBuilder::build(
  self : RequestBuilder,
) -> Request raise HttpMessageError {
  // 拒体组：Get/Head 带 body → MethodBodyMismatch
  // 必体组：Post/Put/Patch 缺 body → MethodBodyMismatch
  // 可选组：Delete/Options/Trace/Connect 不校验
  match self.method {
    Get | Head =>
      if self.body is Some(_) {
        raise HttpMessageError::MethodBodyMismatch
      }
    Post | Put | Patch =>
      if self.body is None {
        raise HttpMessageError::MethodBodyMismatch
      }
    Delete | Options | Trace | Connect => ()
  }
  {
    url: self.url,
    method: self.method,
    headers: self.headers.build(),
    tag: self.tag,
    body: self.body,
  }
}
