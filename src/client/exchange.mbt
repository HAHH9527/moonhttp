///|
// exchange：exchange_once 接缝 + 折叠缓存 + Address 推导（data-model
// 实体 3；research R5）。包内私有（FR-014 不进公开面）；execute 是其唯一
// 公开入口，只调一轮（FR-006 单轮，无 follow-up/重试循环——循环归 P06/P07）。
//
// 管线：pool.acquire(Address) → 折叠（I-2 恰一次）→ 发送头（extra_headers
// =folded）→ 发送体（Bytes 走 write_once / Stream 走填充器）→ end_request
// （不传 1xx 回调——C3 裁决，跳过语义照常）→ Response::from_http +
// ResponseBody::stream(bridge, on_event, on_dispose)。归还逻辑不在此步
// ——归还由体处置驱动（FR-005）。

///|
// Protocol → 串的包内私有 helper（不用弃用 Show——R1/plan；contracts §1
// 「Protocol→串匹配为包内私有 helper」）。
fn protocol_to_string(p : @http.Protocol) -> String {
  match p {
    Http => "http"
    Https => "https"
  }
}

///|
// Address 推导（FR-006）：Request.url → scheme/host/port 三元组池键。
fn address_of_request(request : @core.Request) -> Address {
  let url = request.url
  Address::new(
    scheme=protocol_to_string(url.scheme),
    host=url.host,
    port=url.port,
  )
}

///|
// origin-form 请求目标（conversion.mbt 同款封闭重组：path_segments 以 `/`
// 重组 + `?query`；fragment 剥除——不参与线上）。
fn origin_form(url : @core.HttpUrl) -> String {
  let sb = StringBuilder()
  sb.write_string("/")
  for i, seg in url.path_segments {
    if i > 0 {
      sb.write_string("/")
    }
    sb.write_string(seg)
  }
  match url.query {
    Some(q) => {
      sb.write_string("?")
      sb.write_string(q)
    }
    None => ()
  }
  sb.to_string()
}

///|
// 折叠缓存（I-2 恰一次）：首跑经 P02 `Request::to_http_request()`（内部
// 即 `HeadersV::to_http_map()` 基底 + body 元信息覆盖/删除规则）折叠并
// 缓存同一 Map 实例；此后每次发送读同一实例（fold_count 与重放次数解耦，
// US-4 白盒断言面）。
fn Call::folded_headers(
  self : Call,
) -> Map[@http.CaseInsensitiveString, String] {
  match self.folded {
    Some(m) => m
    None => {
      let m = self.request.to_http_request().headers
      self.folded = Some(m)
      self.fold_count = self.fold_count + 1
      m
    }
  }
}

///|
// exchange_once 接缝（FR-006）：租借→折叠→发送→收头→构建；单轮终止。
// exchange 内异常/取消：毒化收尾（图 2）后错误透传（取消错误沿 execute
// 的 handle_cancellation 外皮映射 CallCancelled）。
async fn Call::exchange_once(self : Call) -> @core.Response {
  let addr = address_of_request(self.request)
  let lease = self.client.pool.acquire(addr)
  self.lease = Some(lease)
  // exchange 内异常/取消：毒化收尾（图 2）后错误透传（取消错误沿 execute
  // 的 handle_cancellation 外皮映射 CallCancelled）
  errdefer self.poison_release()
  self.exchange_with_lease(lease)
}

///|
// 单轮管线本体（持租约段）：收头后构建挂 BodyBridge 的完整 Response
// （FR-009：code/headers/body 全量在场）。
async fn Call::exchange_with_lease(
  self : Call,
  lease : Lease,
) -> @core.Response {
  let folded = self.folded_headers()
  let meth = self.request.method.to_request_method()
  let path = origin_form(self.request.url)
  lease.conn.request(meth, path, extra_headers=folded)
  match self.request.body {
    Some(body) =>
      match body.source {
        @core.BodySource::Bytes(data) => {
          let _ = lease.conn.write_once(data, offset=0, len=data.length())
        }
        @core.BodySource::Stream(filler) => filler(lease.conn)
      }
    None => ()
  }
  // 收头：不传 on_informational_response（C3 裁决——1xx 自动跳过、回调
  // 不进本包公开面；101 原样返回归 M5，本包零特判，R2 锚点）
  let http_resp = lease.conn.end_request()
  // FR-007：响应声明 Connection: close ⇒ 旧连接不回池——先毒化标记，
  // 其后体处置的 release 走关闭分支（对端已关/将关，回池必得死连接）。
  // T022（FR-007/SC-002）：@http 头值不归一、重复头以 "," 拼接——精确
  // 小写比较漏判 `Close`（大小写）与 `keep-alive, close`（多值）两形态；
  // 改 token 解析：split(',') 后逐段 trim + 小写比较，任一命中即毒化。
  match http_resp.headers.get(@http.CaseInsensitiveString("Connection")) {
    Some(v) =>
      for token in v.split(",") {
        if token.trim().to_lower() == "close" {
          lease.poison()
          break
        }
      }
    None => ()
  }
  let bridge_struct : BodyBridge = { call: self, inner: lease.conn, }
  let body = self.make_response_body(bridge_struct)
  @core.Response::from_http(
    http_resp.code,
    http_resp.reason,
    http_resp.headers,
    http_resp.cookies,
    body=Some(body),
  )
}
