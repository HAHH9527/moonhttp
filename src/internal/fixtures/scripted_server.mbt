///|
// scripted_server：P03 第 1 类夹具——@http 声明式编排服务端（B-01～B-06、B-08）。
//
// 设计锚点（specs/003-m1-p03-test-fixtures）：
//   - data-model.md 实体 1/2：ResponseScript 声明面与 ScriptedServer 状态机
//   - contracts/fixtures-api.md §1：公开面签名与行为子句
//   - research.md R2：自管 accept（不用 run_forever），每操作超时保护
//
// 上游公开 API 取证（moonbitlang/async@0.22.4，禁改、不 vendor；宪法 I）：
//   - src/http/pkg.generated.mbti — Server{addr 公开字段}/accept/
//     ServerConnection::send_response(code, reason, extra_headers?)/write/
//     flush/end_response/read_request
//   - src/http/parser.mbt:343-348 — read_request 对端 EOF（请求行读不到）时
//     raise @io.ReaderClosed——serve 循环以该错误为连接自然收尾点
//   - src/http/server.mbt:60-67 — ServerConnection::close 幂等（上游保证）
//   - src/http/send.mbt:85 — Sender 内部 1024B 发送缓冲；chunked 帧的线上
//     分块粒度由该缓冲与 write 粒度共同决定（B-05 断言以线上字节为准，
//     不按调用序手算线上字节）
//   - src/http/send.mbt:190-197 — extra_headers 带 Content-Length ⇒ 定长帧；
//     不带 ⇒ 首次写体转入 chunked（B-05 分派依据）
//
// 宪法 I：只用 @http/@socket/@io/@async 公开 API。宪法 IV：只听 127.0.0.1。
// 宪法 VII：注释中文。

///|
/// 响应编排声明（FR-012 声明式面；data-model 实体 1）。一次 mount 声明一个
/// 路由的完整响应编排；字段全部由测试编写者声明构造。
pub(all) struct ResponseScript {
  status : Int32 // 200/301/302/303/307/308/401/407…
  headers : Array[(String, String)] // Location / WWW-Authenticate / 等，原样下发
  framing : Framing // B-05：定长 / chunked
  body : BodyPlan
  head_delay_ms : Int32 // B-01：回响应头前的延迟
  close_after_response : Bool // B-06：Connection: close 头 + 应答后实际关闭
}

///|
/// 帧形态（B-05）：Fixed ⇒ 夹具经 extra_headers 携带 Content-Length；
/// Chunked ⇒ 不带 CL，块边界经 flush 保真。
pub(all) enum Framing {
  Fixed
  Chunked
}

///|
/// 体计划：Static 定长静态体；Echo（B-04）体 = "<id>:<请求体原样>"（FR-013）；
/// Drip（B-02）按块滴流，块间 sleep(interval_ms)。
pub(all) enum BodyPlan {
  Static(Bytes)
  Echo
  Drip(Int32, Int32, Int32) // block_bytes, blocks, interval_ms
}

///|
/// 只监听回环的声明式 HTTP 服务端句柄（data-model 实体 2）。
/// 状态机：start() 后 Listening；close() 后 Closed（幂等）。
pub struct ScriptedServer {
  priv server : @http.Server
  priv routes : Map[(String, String), ResponseScript]
  priv mut closed : Bool
}

///|
// RequestMethod → 路由键字符串（mount 声明用大写方法名）
fn method_name(m : @http.RequestMethod) -> String {
  match m {
    Get => "GET"
    Head => "HEAD"
    Post => "POST"
    Put => "PUT"
    Delete => "DELETE"
    Connect => "CONNECT"
    Options => "OPTIONS"
    Trace => "TRACE"
    Patch => "PATCH"
  }
}

///|
// 状态码 → reason 短语（编排常用集合；夹具面只需可辨认，无需穷尽 RFC）
fn reason_of(status : Int32) -> String {
  match status {
    200 => "OK"
    301 => "Moved Permanently"
    302 => "Found"
    303 => "See Other"
    307 => "Temporary Redirect"
    308 => "Permanent Redirect"
    400 => "Bad Request"
    401 => "Unauthorized"
    403 => "Forbidden"
    404 => "Not Found"
    407 => "Proxy Authentication Required"
    500 => "Internal Server Error"
    501 => "Not Implemented"
    _ => "Status \{status}"
  }
}

///|
// 组装 extra_headers：脚本声明头原样进入，framing 追加项由分派处负责
fn extra_headers_of(script_headers : Array[(String, String)]) -> @http.Headers {
  let extra : @http.Headers = Map([], capacity=4)
  for (name, value) in script_headers {
    extra[@http.CaseInsensitiveString(name)] = value
  }
  extra
}

///|
// 无体简单应答（404/501 等夹具自管收尾），带 CL:0，应答后由调用方决定连接去向
async fn send_simple(
  conn : @http.ServerConnection,
  code : Int32,
  reason : String,
) -> Unit {
  let extra : @http.Headers = Map([], capacity=4)
  extra[@http.CaseInsensitiveString("Content-Length")] = "0"
  conn.send_response(code, reason, extra_headers=extra)
  conn.end_response()
}

///|
/// 绑定 127.0.0.1:0 并监听；bind 冲突自动重试 ≤ bind_retry 次（FR-011/FR-003，
/// 复用 T004 的 raw_peer.mbt 同名常量——防御性分支未测口径同 T004 记录）。
pub async fn ScriptedServer::start() -> ScriptedServer {
  let mut last_error : Error? = None
  for _attempt in 0..<bind_retry {
    try {
      let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
      return { server, routes: Map([], capacity=8), closed: false, }
    } catch {
      err => last_error = Some(err)
    }
  }
  raise last_error.unwrap()
}

///|
/// OS 回填的实际监听端口（bind :0，恒 > 0；B-14 server 侧）。
pub fn ScriptedServer::port(self : ScriptedServer) -> Int32 {
  self.server.addr.port()
}

///|
/// 声明式路由（FR-012）：method+path 精确匹配；仅 start 之后、close 之前
/// 可调用（close 后为无害 no-op）。
pub fn ScriptedServer::mount(
  self : ScriptedServer,
  meth : String,
  path : String,
  script : ResponseScript,
) -> Unit {
  if self.closed {
    return
  }
  self.routes[(meth, path)] = script
}

///|
/// accept 一条连接并按脚本服务至对端关闭/EOF；整体受
/// @async.with_timeout_opt(timeout_ms) 保护（FR-004）：
/// 超时或出错均关闭连接收尾，不悬挂（SC-006）。
pub async fn ScriptedServer::serve_once(
  self : ScriptedServer,
  timeout_ms~ : Int32 = 5000,
) -> Unit {
  if self.closed {
    return
  }
  let mut conn_opt : @http.ServerConnection? = None
  let outcome : Result[Unit?, Error] = try {
    let served = @async.with_timeout_opt(timeout_ms) <| () => {
      let (conn, _peer_addr) = self.server.accept()
      conn_opt = Some(conn)
      self.serve_connection(conn)
    }
    Ok(served)
  } catch {
    e => Err(e)
  } noraise {
    r => r
  }
  // 收尾：无论正常 EOF/超时/出错，先关连接（幂等），错误如实上抛
  match conn_opt {
    Some(conn) => conn.close()
    None => ()
  }
  match outcome {
    Err(e) => raise e
    Ok(_) => ()
  }
}

///|
// 单连接服务循环：read_request 直到 EOF/错误；路由精确匹配后按脚本应答。
// 终止条件：对端关闭（@io.ReaderClosed，parser.mbt:346-348）/脚本声明关闭/
// 未声明路由（404 收尾）。
async fn ScriptedServer::serve_connection(
  self : ScriptedServer,
  conn : @http.ServerConnection,
) -> Unit {
  for ;; {
    let req = match
      (try conn.read_request() catch {
        e => Err(e)
      } noraise {
        r => Ok(r)
      }) {
      // EOF/连接级错误＝对端收尾，正常路径
      Err(_) => break
      Ok(req) => req
    }
    let script = self.routes.get((method_name(req.meth), req.path))
    let keep = match script {
      Some(script) => self.serve_script(conn, req, script)
      None => {
        // 未声明路由：404 收尾并关连接（防误用把夹具拖入无限循环）
        send_simple(conn, 404, "Not Found")
        false
      }
    }
    if !keep {
      break
    }
  }
}

///|
// 按脚本应答一次请求；返回是否继续在该连接上读下一个请求（keep-alive）。
// 分派按任务增量放开：未实现的编排一律 501「Not Implemented」+ 关连接收尾
// ——后续任务（T006～T010）的红阶段据此获得可归因失败（夹具还没有该行为）。
async fn ScriptedServer::serve_script(
  _self : ScriptedServer,
  conn : @http.ServerConnection,
  req : @http.Request,
  script : ResponseScript,
) -> Bool {
  // B-01：头延迟——send_response 前 sleep（T006 起；0 视为不延迟）
  if script.head_delay_ms > 0 {
    @async.sleep(script.head_delay_ms)
  }
  // T005 骨架路径（200 + Static + Fixed）；分派按任务增量放开：
  // 未实现的编排一律 501「Not Implemented」+ 关连接收尾——后续任务的红阶段
  // 据此获得可归因失败（夹具还没有该行为）。
  match (script.status, script.framing, script.body) {
    // B-03/B-08 编排面（T007 起）：status + headers（Location /
    // WWW-Authenticate 等）按声明原样下发，跟随/凭证语义归消费方测试
    (status, Fixed, Static(bytes)) => {
      let _ = req
      let extra = extra_headers_of(script.headers)
      extra[@http.CaseInsensitiveString("Content-Length")] = "\{bytes.length()}"
      conn.send_response(status, reason_of(status), extra_headers=extra)
      if bytes.length() > 0 {
        conn.write(bytes)
      }
      conn.end_response()
      // B-06 的「实际关闭」语义归 T010；骨架阶段靠对端 EOF/超时收尾
      true
    }
    // B-02 滴流（T006）：定长帧——CL 预先声明总量，体按块 write + flush，
    // 块间 sleep(interval_ms)；末块后不 sleep（间隔语义＝块与块之间）
    (200, Fixed, Drip(block_bytes, blocks, interval_ms)) => {
      let _ = req
      let total = block_bytes * blocks
      let extra = extra_headers_of(script.headers)
      extra[@http.CaseInsensitiveString("Content-Length")] = "\{total}"
      conn.send_response(200, "OK", extra_headers=extra)
      let block = drip_block(block_bytes)
      for i in 0..<blocks {
        conn.write(block)
        // R3：写有缓冲语义（server.mbt:128-129「MAY be buffered」），
        // flush 保证块准时上线，客户端侧才能观测到滴流节奏
        conn.flush()
        if i < blocks - 1 {
          @async.sleep(interval_ms)
        }
      }
      conn.end_response()
      true
    }
    _ => {
      send_simple(conn, 501, "Not Implemented")
      false
    }
  }
}

///|
// 滴流填充块：n 个 'x'（0x78）。内容确定性由元测试断言（B-02 总量/内容）。
// 返回视图即可——底层 FixedArray 由 GC 与视图共同保活（raw_peer.mbt 同款手法）。
fn drip_block(n : Int32) -> BytesView {
  FixedArray::make(n, b'x').unsafe_reinterpret_as_bytes()
}

///|
/// 幂等停止（B-15）：关监听不再 accept；在途连接由其操作超时上限收尾。
pub fn ScriptedServer::close(self : ScriptedServer) -> Unit {
  if self.closed {
    return
  }
  self.closed = true
  self.server.close()
}
