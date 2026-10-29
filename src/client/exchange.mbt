///|
// exchange：单轮收发管线 + 折叠缓存 + Address 推导（data-model 实体 3；
// research R5）。包内私有（FR-014 不进公开面）。生产路径归 follow_up.mbt
// 的 exchange_loop（P06 T004 spawn 换靶）：本文件提供其每轮复用的
// exchange_with_lease 持租管线（返回响应 + 原始 @http.Headers——Location
// 保真直读，WB⑧）与 spec 钦定的白盒直调接缝 exchange_once（单轮语义，
// #warnings 抑制登记见 plan 例外跟踪）。
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
// 折叠缓存（I-2 恰一次 + C4 代次键化/INV-3，P06 T003 参数化）：首跑经
// P02 `Request::to_http_request()`（内部即 `HeadersV::to_http_map()` 基底
// + body 元信息覆盖/删除规则）折叠并缓存同一 Map 实例；仅当
// `folded_gen == gen ∧ folded is Some` 复用（同代次重放零重折叠——P05
// SC-004 语义保持）；否则折叠一次并存 `{folded, folded_gen, fold_count+1}`
// （follow-up 头已改写，复用旧代次产物 = FR-010 正确性错误）。
fn Call::folded_headers(
  self : Call,
  request : @core.Request,
  gen : Int32,
) -> Map[@http.CaseInsensitiveString, String] {
  if self.folded_gen == gen {
    match self.folded {
      Some(m) => return m
      None => ()
    }
  }
  let m = request.to_http_request().headers
  self.folded = Some(m)
  self.folded_gen = gen
  self.fold_count = self.fold_count + 1
  m
}

///|
// exchange_once 接缝（FR-006；P06 T003 参数化——request 入参，单轮语义
// 不变，R3/Q-B3 实况口径）：租借→折叠→发送→收头→构建；单轮终止。
// exchange 内异常/取消：毒化收尾（图 2）后错误透传（取消错误沿 execute
// 的 handle_cancellation 外皮映射 CallCancelled）。
// 【T017 收口注】P06 起生产路径由 exchange_loop 承载（T004 spawn 换靶），
// 本函数降为 spec 钦定白盒直调接缝（P06-WB⑧/P06-US4① 桩接缝；plan
// Structure Decision「循环为 exchange 接缝的纯上层包裹」）——lib 构建
// 无生产调用点属预期形态，`#warnings` 定点抑制 unused_value（上游
// client.mbt #warnings 先例），语义与签名不变。
#warnings("-unused_value")
async fn Call::exchange_once(
  self : Call,
  request : @core.Request,
) -> @core.Response {
  let addr = address_of_request(request)
  let lease = self.client.pool.acquire(addr)
  self.lease = Some(lease)
  // exchange 内异常/取消：毒化收尾（图 2）后错误透传（取消错误沿 execute
  // 的 handle_cancellation 外皮映射 CallCancelled）
  errdefer self.poison_release()
  let (response, _raw_headers) = self.exchange_with_lease(request, lease)
  // 白盒直调面（WB⑧/US4①）不需要原始头——单轮语义下无 Location 读取
  response
}

///|
// 单轮管线本体（持租约段；P06 T003 参数化）：收头后构建挂 BodyBridge 的
// 完整 Response（FR-009：code/headers/body 全量在场）。返回二元组——
// 响应 + 原始 @http.Headers（review 修复批 H1：follow-up 的 Location
// 读取须绕开 from_http 的逗号拆分截断，直读原始头 Map；WB⑧ 钉死）。
async fn Call::exchange_with_lease(
  self : Call,
  request : @core.Request,
  lease : Lease,
) -> (@core.Response, @http.Headers) {
  let folded = self.folded_headers(request, self.gen)
  let meth = request.method.to_request_method()
  let path = origin_form(request.url)
  lease.conn.request(meth, path, extra_headers=folded)
  match request.body {
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
  // FR-009：响应声明 Connection: close ⇒ 该连接不回池——先毒化标记，
  // 其后体处置的 release 走关闭分支（对端已关/将关，回池必得死连接）。
  // T022（FR-007/SC-002）：@http 头值不归一、重复头以 "," 拼接——精确
  // 小写比较漏判 `Close`（大小写）与 `keep-alive, close`（多值）两形态；
  // 改 token 解析：split(',') 后逐段 trim + 小写比较，任一命中即毒化。
  match http_resp.headers.get(@http.CaseInsensitiveString("Connection")) {
    Some(v) =>
      for token in v.split(",") {
        if token.trim().to_lower() == "close" {
          lease.poison()
          // P06 INV-7 置位点（R6）：循环 advance 见标记即 release（关闭
          // 不回池）；标记由 ensure_lease 取新租复位（T012/T013 落地）。
          self.conn_close_seen = true
          break
        }
      }
    None => ()
  }
  let bridge_struct : BodyBridge = { call: self, inner: lease.conn, }
  let body = self.make_response_body(bridge_struct)
  let response = @core.Response::from_http(
    http_resp.code,
    http_resp.reason,
    http_resp.headers,
    http_resp.cookies,
    body=Some(body),
  )
  (response, http_resp.headers)
}
