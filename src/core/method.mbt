///|
/// 请求方法值：九个标准方法（FR-007，用户裁决 Q2-B 裁剪 `Custom` 出 M1）。
/// 与 `@http.RequestMethod` 一一对应，经 `to_request_method`/
/// `from_request_method` 封闭双向映射（无失败分支）。
pub(all) enum Method {
  Get
  Post
  Put
  Delete
  Head
  Options
  Trace
  Patch
  Connect
} derive(Eq, Hash, Debug)

///|
// 消除 implicit_impl_as_method 警告 [0079] 的配套写法（决策 N1-A，
// research R4）：derive 生成 impl 后紧随三行 pub extend 把方法形态
// 暴露进公开面（方法名并入 .mbti 冻结清单逐条审视，宪法 VI）。
pub extend Method with Eq::{equal, not_equal}

///|
pub extend Method with Hash::{hash, hash_combine}

///|
pub extend Method with Debug::{to_repr}

///|
/// 映射到上游 `@http.RequestMethod`（封闭映射，无失败分支，FR-007）。
pub fn Method::to_request_method(self : Method) -> @http.RequestMethod {
  match self {
    Get => @http.RequestMethod::Get
    Post => @http.RequestMethod::Post
    Put => @http.RequestMethod::Put
    Delete => @http.RequestMethod::Delete
    Head => @http.RequestMethod::Head
    Options => @http.RequestMethod::Options
    Trace => @http.RequestMethod::Trace
    Patch => @http.RequestMethod::Patch
    Connect => @http.RequestMethod::Connect
  }
}

///|
/// 从上游 `@http.RequestMethod` 映射回本包 `Method`（双向封闭，FR-007）。
pub fn Method::from_request_method(m : @http.RequestMethod) -> Method {
  match m {
    @http.RequestMethod::Get => Method::Get
    @http.RequestMethod::Head => Method::Head
    @http.RequestMethod::Post => Method::Post
    @http.RequestMethod::Put => Method::Put
    @http.RequestMethod::Delete => Method::Delete
    @http.RequestMethod::Connect => Method::Connect
    @http.RequestMethod::Options => Method::Options
    @http.RequestMethod::Trace => Method::Trace
    @http.RequestMethod::Patch => Method::Patch
  }
}
