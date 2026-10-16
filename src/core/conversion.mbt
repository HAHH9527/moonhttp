///|
// conversion：Request → @http 调用参数的纯转换层（spec US-2，FR-004/005，
// SC-003；contracts/conversion-errors.md）。
//
// 设计（research R3/R5/R7；2026-10-16 owner 裁决 A：对齐 OkHttp body
// 覆盖语义，5.5.0 取证 = BridgeInterceptor.kt:42-54 + Request.kt:247-256
// `header()` 同名全部替换）：
//   - 产物复用上游 `pub(all) struct @http.Request`（meth/path/headers，
//     零新类型）；P05 直接以三元组喂 `Client::request(...) + write(...)`。
//   - meth：经 P01 `Method::to_request_method` 封闭映射（无失败分支）。
//   - path：origin-form 请求目标——path_segments 以 `/` 重组 + `?query`
//     （无 query 不追加）；fragment 剥除（不参与线上；上游把该串原样写入
//     请求行，send.mbt:322-335）。
//   - headers（folded）：基底 = P01 `HeadersV::to_http_map()`；随后按
//     FR-005 裁决 A 规则：
//       ① body.content_type = Some(v) → 覆盖用户同名 Content-Type（大小写
//          不敏感单键替换）；body = None 或 content_type = None → 不动；
//       ② body.content_length = Some(n) → 覆盖 Content-Length 为 n；
//       ③ body.content_length = None → 删除 Content-Length 键（等价 OkHttp
//          removeHeader；chunked 由上游在无 Content-Length 时自行写出）；
//       ④ body = None → 不注入也不删除（用户显式声明透传）。
//     **MUST NOT 注入 Transfer-Encoding**：上游 forbidden_headers 会丢弃
//     调用方 TE、chunked 由上游自管（send.mbt:37-39/:296-306/:103）——
//     机制差异（上游实现差异），非行为偏离。
//   - 纯函数（SC-003）：无状态、无 memoization——同 Request 重复转换输出
//     逐字节相同；L3「每 call 一次折叠、重放零折叠」缓存归 P05/P07 call
//     对象（research R7）。定长帧机制由上游在发送时从 extra_headers 提取
//     Content-Length 触发 SendingFixed（send.mbt:343-345），本层不触网络、
//     不写发送状态机（FR-010）。
//

///|
/// 纯转换：Request → `@http.Request`（meth/path/folded headers 三元组）。
pub fn Request::to_http_request(self : Request) -> @http.Request {
  // meth：封闭映射
  let meth = self.method.to_request_method()
  // path：origin-form 请求目标（fragment 剥除——仅 path_segments + query
  // 参与重组，fragment 不进入输出）
  let sb = StringBuilder()
  sb.write_string("/")
  for i, seg in self.url.path_segments {
    if i > 0 {
      sb.write_string("/")
    }
    sb.write_string(seg)
  }
  match self.url.query {
    Some(q) => {
      sb.write_string("?")
      sb.write_string(q)
    }
    None => ()
  }
  let path = sb.to_string()
  // headers：P01 折叠基底 + FR-005 裁决 A 覆盖/删除规则
  let map = self.headers.to_http_map()
  match self.body {
    Some(body) => {
      // Content-Type 覆盖：body 元信息有值即覆盖用户同名头（OkHttp
      // BridgeInterceptor:42-45 + Builder.header 替换语义）
      if body.content_type is Some(ct) {
        map[@http.CaseInsensitiveString("Content-Type")] = ct
      }
      // Content-Length：Some(n) 覆盖；None 删除（等价 OkHttp
      // removeHeader——chunked 由上游在无 Content-Length 时自行写出；
      // TE 由上游 forbidden_headers 自管，本层不注入）
      let cl_key = @http.CaseInsensitiveString("Content-Length")
      if body.content_length is Some(n) {
        map[cl_key] = "\{n}"
      } else {
        let _ = map.remove(cl_key)
      }
    }
    None => ()
  }
  { meth, path, headers: map, }
}
