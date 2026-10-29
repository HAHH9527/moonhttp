///|
// follow_up：P06 follow-up 循环层（data-model 实体 1 循环 / 实体 3
// 决策表）。职责：follow_up_request 纯函数决策表（FR-003 五行 + FR-008
// Location 门，5.5.0 对拍）+ exchange_loop 轮循环（FR-001 取消 guard /
// FR-002 排干 / FR-005 上限 / FR-006 prior 链 / FR-007 租约保持）。
// 包内私有（contracts §1 明确不进公开面）；行为锚点见 research R1
// （OkHttp tag parent-5.5.0 RetryAndFollowUpInterceptor 对拍真值）。
//
// js 形态（FR-011/R8，非门禁项——欠账随 M5 收口）：零 `#cfg(js)` 分支，
// 本层代码在 js 后端同形编译；js 上 @http 走 fetch 适配层
// （redirect:"follow" 默认），浏览器已自动跟随 ⇒ execute 首响应即终态、
// 循环首轮判定不跟随退出、prior 天然 None——js 直通语义由浏览器行为
// 保证，非代码分叉（宪法 V 未验证面）。

///|
// 决策表输出（data-model 实体 3）：Next(follow-up 请求) / Terminal
// （原响应终态返回，含 Stream 不可重放原样返回形态）。
priv enum FollowUp {
  Next(@core.Request)
  Terminal
}

///|
// 决策表（纯函数无 IO；FR-003 五行 + FR-008 Location 门）。Location
// 读取走 raw_headers 原始头 Map（H1 保真，WB⑧）；不跟随集合（304/305/
// 306/401/407/408 及其余非 3xx）+ 3xx 无 Location ⇒ Terminal。
fn follow_up_request(
  response : @core.Response,
  request : @core.Request,
  raw_headers : @http.Headers,
) -> FollowUp raise {
  let code = response.code()
  // FR-003 行 4/5：304/305/306 及其余一切非跟随码（200/401/407/408 等）
  // 一律终态。跟随集合为精确码集 {300,301,302,303,307,308}（5.5.0 RFU
  // L228 精确 switch——300 属跟随分支，C2/300 对拍修正；范围判定会把
  // 304/305/306 误纳，WB⑦ 矩阵红测钉死）。
  match code {
    300 | 301 | 302 | 303 | 307 | 308 => ()
    _ => return Terminal
  }
  // FR-008：Location 缺失 ⇒ 原响应终态（不跟随，5.5.0 L304-306 同构）。
  // 读取走 raw_headers 原始头 Map 直读（review 修复批 H1）：P02
  // from_http 把头值按 "," 拆回多条、HeadersV::get 取首条——含逗号的
  // Location（query 合法子分隔符）会被截断（WB⑧ 钉死）。
  guard raw_headers.get(@http.CaseInsensitiveString("Location")) is Some(_) else {
    return Terminal
  }
  // T002 骨架收尾 → T005 展开：Location 门 + 降级行（FR-003 行 1/2）；
  // GET/HEAD 保持行 T007、307/308 行 T008/T009 落地。
  let target = match resolve_location(raw_headers, request) {
    Some(t) => t
    None => return Terminal
  }
  // 跨 host 判定（R1 第 7 条）：Address 三元组不等 ⇒ 剥双头（FR-004）。
  let target_addr = Address::new(
    scheme=protocol_to_string(target.scheme),
    host=target.host,
    port=target.port,
  )
  let cross_host = address_of_request(request) != target_addr
  // FR-003 行 3 可重放判定先于方法分叉（spec Edge Cases 168-173）：307/
  // 308 下 Stream 不可盲目重放 ⇒ 原响应终态——GET/HEAD 保持行同样受此
  // 约束（公开构造面不可达——P02 拒体组保证 GET/HEAD 无体；防御性对齐，
  // review 修复批订正：原实现 GET/HEAD 跳过该判定）。
  if (code == 307 || code == 308) && request.body is Some(b) {
    if b.source is @core.BodySource::Stream(_) {
      return Terminal
    }
  }
  match request.method {
    // 保持行（FR-003 行 1/2 保持半边；R1 第 2 条 permitsRequestBody 门——
    // GET/HEAD 全状态码保持，方法/头原样；跨 host 剥 Authorization/Cookie
    // ——T011）
    Get | Head => Next(keep_request(request, target, cross_host))
    _ =>
      match code {
        // 降级行（FR-003 行 1/2；300 属跟随分支——C2/300 对拍修正）：
        // 非 GET/HEAD 一律降级 GET、去体与三头
        300 | 301 | 302 | 303 =>
          Next(degrade_to_get(request, target, cross_host))
        // 保持/重放行（FR-003 行 3；R1 第 5 条）：307/308 方法/头/体原样
        // （RequestBody 不可变值搬移；跨 host 剥离——T011）。Stream 不可
        // 重放已在上方拦截 ⇒ 此处 Bytes/无体恒可随行
        307 | 308 => Next(keep_request(request, target, cross_host))
        // 304-306 不跟随（FR-003 行 4）
        _ => Terminal
      }
  }
}

///|
// 保持重组（R4/T007+T008+T011）：方法/头（跨 host 剥双头后）原样；体
// 原值搬移（GET/HEAD 构造面无体——P02 拒体组保证，307/308 的 Bytes 体
// 按原值随行）。build 错误理论不可达，透传不吞。
fn keep_request(
  request : @core.Request,
  target : @core.HttpUrl,
  cross_host : Bool,
) -> @core.Request raise {
  let builder = @core.RequestBuilder::new(target)
    .method(request.method)
    .headers(rewrite_headers(request.headers, cross_host~))
  match request.body {
    Some(body) => builder.body(body).build()
    None => builder.build()
  }
}

///|
// 降级重组（R4/T005+T011）：`RequestBuilder::new(target)` → GET → 降级
// 头改写（跨 host 剥双头 + 去三头）→ 无体。build 错误理论不可达（GET
// 无体恒合法），透传不吞（防御性，R4）。
fn degrade_to_get(
  request : @core.Request,
  target : @core.HttpUrl,
  cross_host : Bool,
) -> @core.Request raise {
  @core.RequestBuilder::new(target)
  .method(@core.Method::Get)
  .headers(rewrite_headers_degrade(request.headers, cross_host~))
  .build()
}

///|
// Location 门（FR-008，R4；review 修复批 H1 订正）：从原始 @http.Headers
// 直读（大小写不敏感——@http.CaseInsensitiveString 判等；P02 from_http 的
// 逗号拆分 + HeadersV::get 取首条会截断含逗号的 Location 值，WB⑧ 钉死）
// → `HttpUrl::resolve`（相对/绝对/网络路径三形态，P01 契约）；缺失或
// resolve raise（含非 http(s) scheme 绝对引用）⇒ None（不跟随终态）。
fn resolve_location(
  raw_headers : @http.Headers,
  request : @core.Request,
) -> @core.HttpUrl? {
  let loc = match raw_headers.get(@http.CaseInsensitiveString("Location")) {
    Some(loc) => loc
    None => return None
  }
  Some(request.url.resolve(loc) catch { _ => return None })
}

///|
// 头改写（R4；T011 启用跨 host 分支）：跨 host（Address 判定，scheme/
// host/port 任一不同）剥 `Authorization` + `Cookie`（C1 有意差异——M1
// 无 CookieJar 的等价保守化，M2/11-cookies 回改）；remove 与 get 同为
// 大小写不敏感（P02 契约，US4① 大小写变体注入钉死）。
fn rewrite_headers(
  headers : @core.HeadersV,
  cross_host~ : Bool,
) -> @core.HeadersV {
  let b = headers.builder()
  if cross_host {
    b.remove("Authorization")
    b.remove("Cookie")
  }
  b.build()
}

///|
// 降级头改写（FR-003 行 1/2，R4）：跨 host 剥双头（T011）+ 去 Content-
// Length/Content-Type/Transfer-Encoding（存在才移）。
fn rewrite_headers_degrade(
  headers : @core.HeadersV,
  cross_host~ : Bool,
) -> @core.HeadersV {
  let stripped = rewrite_headers(headers, cross_host~)
  let b = stripped.builder()
  b.remove("Content-Length")
  b.remove("Content-Type")
  b.remove("Transfer-Encoding")
  b.build()
}

///|
// prior 条目构建（R5/INV-5）：`HeadersV::to_http_map` → `from_http` 互逆
// 路径装配；条目恒 body=None（对齐 OkHttp priorResponse——中间体已排干
// 关闭，无体可读）。
fn prior_entry(resp : @core.Response, prev : @core.Response?) -> @core.Response {
  @core.Response::from_http(
    resp.code(),
    resp.reason(),
    resp.headers().to_http_map(),
    resp.cookies(),
    body=None,
    prior=prev,
  )
}

///|
// 终态挂链（R5）：同上装配但活体透传（body 原样随租约，P05 语义不变），
// prior=链头（FR-006 保序）。
fn attach_prior(
  resp : @core.Response,
  prev : @core.Response?,
) -> @core.Response {
  @core.Response::from_http(
    resp.code(),
    resp.reason(),
    resp.headers().to_http_map(),
    resp.cookies(),
    body=resp.body(),
    prior=prev,
  )
}

///|
// ensure_lease（data-model 实体 1/INV-1/INV-6，R6）：缺失 ⇒ acquire；
// 同 host（`lease.addr` 同包直读比对——round3 D-4 订正不设镜像字段）⇒
// 零往返复用；跨 host ⇒ 先干净释放旧租再取新租（INV-6）。取新租时复位
// `conn_close_seen`（INV-7/I-7：标记仅由此复位）。
async fn Call::ensure_lease(self : Call, addr : Address) -> Lease {
  match self.lease {
    Some(lease) => {
      if lease.addr == addr {
        return lease
      }
      self.release_lease()
    }
    None => ()
  }
  let lease = self.client.pool.acquire(addr)
  self.lease = Some(lease)
  self.conn_close_seen = false
  lease
}

///|
// 排干中间响应体（FR-002/INV-2，R6）：中间响应不走 bridge 体读路径
// （不交付、不触发 Consumed/Dropped 事件），直接 `conn.skip_response_
// body()`。失败纯透传——drain 内不写 catch/毒化，毒化由轮级 errdefer
// 单点归属（round3 D-2）。
async fn drain_intermediate(lease : Lease) -> Unit {
  lease.conn.skip_response_body()
}

///|
// follow-up 主循环（data-model 实体 1；P06 T004 直通版）：循环顶取消
// guard（FR-001）→ ensure_lease → 轮级 errdefer 毒化（轮内失败唯一毒化
// 归属点，round3 D-2）→ 单轮 exchange → 决策表；Terminal 即终态返回，
// Next 走 advance 最小路径（换请求 + 换代；排干/换租/上限随 T005/T012/
// T013/T014 深化——round8 I5 分期口径）。
async fn Call::exchange_loop(self : Call) -> @core.Response {
  let mut request = self.request
  let mut prior : @core.Response? = None // prior 链（实体 4/INV-5）
  let mut follow_ups = 0 // 已判定跟随数（INV-4，R1 第 8 条）
  while true {
    // FR-001：每轮循环顶 guard 取消（轮间取消 ⇒ 裸 CallCancelled）。
    // 轮间取消租约处置（T022/converge F4 实证成文，闭合 baseline.md
    // R9-3 记录级义务）：轮 k 完成租约在场后取消时，租约收尾由
    // Call::cancel 的同步 poison_release 单点承担（毒化+关连+置 None，
    // I-3 时序：处置完成即置 None，迟到 cancel 只见 None）；MoonBit
    // errdefer 作用域实测仅当前轮循环体——轮间 raise 不触发上一轮
    // errdefer，轮级 errdefer 不代偿轮间 raise。行为锚点 P06-WB④c。
    guard !self.cancelled else { raise CallCancelled }
    let lease = self.ensure_lease(address_of_request(request))
    // 轮内失败毒化：exchange/决策表 raise 沿此收尾（与 P05 exchange 段
    // 既有 errdefer 幂等叠合，无害）
    errdefer self.poison_release()
    let (response, raw_headers) = self.exchange_with_lease(request, lease)
    // raw_headers = 原始 @http.Headers（H1 保真）：Location 直读不走
    // from_http 拆分产物（WB⑧）
    match follow_up_request(response, request, raw_headers) {
      // 终态返回：活体透传 + prior 挂链（FR-006）
      Terminal => return attach_prior(response, prior)
      Next(followup) => {
        // INV-2：排干先于换代——skip 直调（不走 bridge 体路径，不交付
        // 不触发事件；失败纯透传，毒化由轮级 errdefer 单点归属——D-2）。
        drain_intermediate(lease)
        // INV-7/INV-6（T013）：中间 close（token 毒化已置位 ⇒ release 走
        // 关闭不回池）或跨 host（干净回池，W1 方案 B）⇒ advance 显式释放
        // 旧租；同 host 零往返保持。标记由 ensure_lease 取新租复位。
        if self.conn_close_seen || lease.addr != address_of_request(followup) {
          self.release_lease()
        }
        // INV-4（T014）：计数在「响应到达 + follow-up 已算出」后、发送前
        // 推进；超限路径先 release（此时 lease 已 None ⇒ errdefer no-op，
        // 连接保持干净回池）再 raise——顺序是 INV-4 成立条件（反序将使
        // errdefer 毒化已排干连接，round3 D-2）。
        follow_ups = follow_ups + 1
        guard follow_ups <= 20 else {
          self.release_lease()
          raise TooManyFollowUps
        }
        prior = Some(prior_entry(response, prior))
        request = followup
        self.advance_generation()
      }
    }
  }
  // 不可达：循环仅经 return（Terminal）/raise（取消/失败）退出
  abort("unreachable: follow-up loop exited without terminal")
}
