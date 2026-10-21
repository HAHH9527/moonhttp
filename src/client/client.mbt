///|
pub fn placeholder() -> Bool {
  // 能力入口占位：客户端功能由 spec 驱动的垂直切片逐步替换
  true
}

///|
// 直连三元组池键（P04 data-model 实体 1，FR-014）：(scheme, host, port)
// 缺一不可；端口是键的一部分——上游 @http.Client 在构造期把 Host 头写进
// 持久头（R4.3），跨 host:port 复用同一连接会把请求发到错误源站。
// 键构造 noraise：不解析 URL、不做网络语义校验（窄语义，R4.3）。
// 字段恒为规范化形态（规范化在 new 内部单点收口），derive(Eq, Hash)
// 即键语义；equal/hash 显式方法面沿 P01 HttpUrl 先例（core mbti:76-79）。
pub struct Address {
  priv scheme : String // 小写化（"http"/"https"）
  priv host : String // 小写化；IPv6 字面量剥 [] 方括号
  priv port : Int32
} derive(Eq, Hash)

///|
// 消除 implicit_impl_as_method 警告 [0079] 的配套写法（决策 N1-A，
// core/http_url.mbt:29-32 先例）。
pub extend Address with Eq::{equal, not_equal}

///|
pub extend Address with Hash::{hash, hash_combine}

///|
// 键规范化单点收口（FR-014）：scheme/host 小写化、IPv6 字面量剥方括号。
pub fn Address::new(scheme~ : String, host~ : String, port~ : Int32) -> Address {
  {
    scheme: scheme.to_lower(),
    host: strip_ipv6_brackets(host.to_lower()),
    port,
  }
}

///|
// IPv6 字面量剥方括号："[" 前缀 + "]" 后缀形态剥离，其余原样（P01 HttpUrl
// 「剥方括号逐字存储」同款语义；host 已先小写化，IPv6 十六进制位一并归一）。
fn strip_ipv6_brackets(host : String) -> String {
  let len = host.length()
  if len >= 2 && host[0] == '[' && host[len - 1] == ']' {
    host[1:len - 1].to_owned()
  } else {
    host
  }
}

///|
pub fn Address::scheme(self : Address) -> String {
  self.scheme
}

///|
pub fn Address::host(self : Address) -> String {
  self.host
}

///|
pub fn Address::port(self : Address) -> Int32 {
  self.port
}
