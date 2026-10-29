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
/// 路由脚本（F-7，P04 T002/R5/R9）：Single 即既有 mount 的单脚本（覆盖式
/// 语义不变）；Sequence 按该路由的命中序取第 min(i, len-1) 个脚本（末位
/// 驻留）。不新增同名顶层 mount——顶层函数不可重载（E4051，R9），次序
/// 脚本经新入口 mount_sequence 挂载。
pub(all) enum RouteScript {
  Single(ResponseScript)
  Sequence(Array[ResponseScript])
  // F-8 最小扩展（P05 T002，归因 FR-010）：单请求内 1xx→200 组合响应——
  // 应答最终脚本前先裸写一条 1xx 状态线（interim_status ∈ 1xx 跳过集）。
  InterimThen(Int32, ResponseScript)
  // P05 T005/T010 体阶段断连注入（归因 FR-011/FR-005——US5③ skip 失败与
  // US5④ 非取消错误毒化的注入缝；P03 无「头完整+体截断」程序化形态）：
  // 按脚本声明下发完整响应头（含 CL；Connection: close 由第二字段声明——
  // review 修复批 FR-002 毒化判别需剥离 close-token 混淆）后**不发体、不
  // end_response**、立即关连接——客户端体读/skip 必然失败。
  Truncated(ResponseScript, Bool)
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
/// active/peak 为 serve_n 并发处理高水位观测位（B-04 交错自证的结构性
/// 证据）：每连接处理进入时 +1、退出时 -1；增减为纯同步代码、无 await
/// 中间态（协同式调度下跨任务可见且无竞态）。
pub struct ScriptedServer {
  priv server : @http.Server
  priv routes : Map[(String, String), RouteScript]
  priv route_hits : Map[(String, String), Int32] // F-7：Sequence 路由命中序
  priv mut closed : Bool
  priv mut next_id : Int32 // B-04 echo 单调 id（FR-013）
  priv mut active_conns : Int32 // 当前在途连接处理数
  priv mut peak_conns : Int32 // 在途高水位（≥2 即证并发处理）
  priv mut accepted_total : Int32 // F-5：累计接受连接数（accept 成功点 +1）
  priv conn_request_counts : Array[Int32] // F-6：按 accept 序号的每连接请求数
  priv captured_heads : Array[String] // T019：按请求到达序的「请求行+头」文本
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
      return {
        server,
        routes: Map([], capacity=8),
        route_hits: Map([], capacity=8),
        closed: false,
        next_id: 1,
        active_conns: 0,
        peak_conns: 0,
        accepted_total: 0,
        conn_request_counts: [],
        captured_heads: [],
      }
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
/// 可调用（close 后为无害 no-op）。覆盖式语义不变（内部包成
/// RouteScript::Single，既有调用点零破坏，R9）；同路由命中序随重声明
/// 复位（声明即重开，次序脚本确定性归 T011 桩消费方）。
pub fn ScriptedServer::mount(
  self : ScriptedServer,
  meth : String,
  path : String,
  script : ResponseScript,
) -> Unit {
  if self.closed {
    return
  }
  self.routes[(meth, path)] = Single(script)
  self.route_hits[(meth, path)] = 0
}

///|
/// interim 组合响应挂载（F-8 最小扩展，P05 T002，归因 FR-010）：同路由
/// 先裸写一条 1xx 状态线再按脚本应答最终响应；与 mount 同为覆盖式声明。
pub fn ScriptedServer::mount_interim(
  self : ScriptedServer,
  meth : String,
  path : String,
  interim_status : Int32,
  script : ResponseScript,
) -> Unit {
  if self.closed {
    return
  }
  self.routes[(meth, path)] = InterimThen(interim_status, script)
  self.route_hits[(meth, path)] = 0
}

///|
/// 断连注入挂载（P05 T005/T010，归因 FR-011/FR-005）：按脚本下发完整
/// 响应头后不发体、立即关连接；与 mount 同为覆盖式声明。
/// `derive_close~`（review 修复批，contracts §3 登记例外）：是否派生
/// `Connection: close` 头——缺省 true 保持既有语义；false 用于 FR-002
/// 排干失败毒化的单点判别（US6 补③：无 close-token，毒化只能来自
/// skip 失败路径）。
pub fn ScriptedServer::mount_truncated(
  self : ScriptedServer,
  meth : String,
  path : String,
  script : ResponseScript,
  derive_close~ : Bool = true,
) -> Unit {
  if self.closed {
    return
  }
  self.routes[(meth, path)] = Truncated(script, derive_close)
  self.route_hits[(meth, path)] = 0
}

///|
/// 次序脚本挂载（F-7，P04 T002）：同路由第 i 次命中取 scripts[min(i,
/// len-1)]（末位驻留）；与 mount 同为覆盖式声明，命中序随重声明复位。
pub fn ScriptedServer::mount_sequence(
  self : ScriptedServer,
  meth : String,
  path : String,
  scripts : Array[ResponseScript],
) -> Unit {
  if self.closed {
    return
  }
  self.routes[(meth, path)] = Sequence(scripts)
  self.route_hits[(meth, path)] = 0
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
      // F-5/F-6（P04 T002）：accept 成功点累计 +1，并按序号开请求记账位
      self.accepted_total = self.accepted_total + 1
      let conn_index = self.conn_request_counts.length()
      self.conn_request_counts.push(0)
      self.serve_connection(conn, conn_index)
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
// 未声明路由（404 收尾）。conn_index 为本连接的 accept 序号（F-6 记账位，
// 每完成一次请求 +1）。
async fn ScriptedServer::serve_connection(
  self : ScriptedServer,
  conn : @http.ServerConnection,
  conn_index : Int32,
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
    // F-6：本连接每完成一次请求 +1（read_request 成功即一次完整请求）
    self.conn_request_counts[conn_index] = self.conn_request_counts[conn_index] +
      1
    // T019（converge F1，owner 裁决① 2026-10-28）：与 F-6 计数同点捕获
    // 「请求行+头」渲染文本，按到达序 push——SC-004「同 host follow-up
    // 捕获字节完整保留 Authorization/Cookie」的黑盒观测面（原夹具丢弃头，
    // 无请求头观测能力）。最小扩展：一字段一捕获一访问器（tasks Path
    // Conventions「先红后绿最小扩展并逐处归因」授权口径）；头名以
    // CaseInsensitiveString::to_string 原样字符串化，不做归一化承诺。
    let mut head_text = "\{method_name(req.meth)} \{req.path}\r\n"
    for k, v in req.headers {
      head_text = head_text + "\{k.to_string()}: \{v}\r\n"
    }
    self.captured_heads.push(head_text)
    let key = (method_name(req.meth), req.path)
    let script_opt : ResponseScript? = match self.routes.get(key) {
      // F-7：Sequence 按命中序取 min(i, len-1)（末位驻留）；Single 原样
      Some(Sequence(scripts)) => {
        let i = self.route_hits.get(key).unwrap_or(0)
        self.route_hits[key] = i + 1
        let last = scripts.length() - 1
        Some(scripts[if i < last { i } else { last }])
      }
      Some(Single(script)) => Some(script)
      Some(InterimThen(interim, script)) => {
        // F-8（归因 FR-010）：最终应答前先发一条 1xx interim（经公开 API
        // send_response+end_response；1xx 无体，end_response 仅 flush 状态线
        // ——上游 utils_for_test.mbt:90 同款形态）。上游 end_request 按跳过
        // 集（100 | 102..<200）消费后继续读最终响应。
        conn.send_response(interim, "Continue")
        conn.end_response()
        Some(script)
      }
      Some(Truncated(script, derive_close)) => {
        // 体阶段断连注入（归因 FR-011/FR-005）：完整头（含 CL；close 头
        // 按 derive_close 声明）→ 不发体、不 end_response → 立即关连接。
        // 客户端体读/skip 必然以连接级错误收场。
        ScriptedServer::send_truncated_head(conn, script, derive_close~)
        None
      }
      None => None
    }
    // Truncated 已在本 arm 内自管收尾（关连接、不续循环）
    if self.routes.get(key) is Some(Truncated(_, _)) {
      break
    }
    let keep = match script_opt {
      Some(script) => {
        let served = self.serve_script(conn, req, script)
        if served && script.close_after_response {
          // B-06（T010）：应答后实际关闭——头已随响应下发，此处关连接
          // （ServerConnection::close 幂等，server.mbt:60-67），循环终止
          conn.close()
          false
        } else {
          served
        }
      }
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
// 断连注入的「完整头」下发（P05 T005/T010，归因 FR-011/FR-005）：按脚本
// 组头（Fixed 补 CL；Echo/Drip 声明大 CL 制造「体未发完即断」）、按
// derive_close 决定是否派生 Connection: close（review 修复批：false 供
// FR-002 毒化判别剥离 close-token 混淆），send_response 后不发体、不
// end_response、关连接。
async fn ScriptedServer::send_truncated_head(
  conn : @http.ServerConnection,
  script : ResponseScript,
  derive_close~ : Bool = true,
) -> Unit {
  let extra = extra_headers_of(script.headers)
  match script.body {
    Static(bytes) =>
      if script.framing is Fixed {
        extra[@http.CaseInsensitiveString("Content-Length")] = "\{bytes.length()}"
      }
    // Echo/Drip 声明量未知：声明大 CL 制造「体未发完即断」
    Drip(_, blocks, _) =>
      if script.framing is Fixed {
        extra[@http.CaseInsensitiveString("Content-Length")] = "\{blocks * 1024}"
      }
    Echo =>
      if script.framing is Fixed {
        extra[@http.CaseInsensitiveString("Content-Length")] = "1024"
      }
  }
  if derive_close {
    extra[@http.CaseInsensitiveString("Connection")] = "close"
  }
  conn.send_response(
    script.status,
    reason_of(script.status),
    extra_headers=extra,
  )
  // 头部经 Sender 缓冲——close 前必须 flush 保真上线（否则客户端在头段
  // 即见 EOF，注入语义退化为头截断）
  conn.flush()
  conn.close()
}

///|
/// 串行 accept、并发处理的多连接服务面（T008 owner 裁决 A，2026-10-18）。
///
/// 为什么 accept 必须串行：上游 `TcpServer::accept` 并发调用不安全——
/// 同一监听句柄挂两个 accept 等待时 native 直接 PanicError 崩溃
/// （0xc0000409）、wasm/moonrun 悬挂不醒（2026-10-18 双 target 实测，
/// 探针即用即删已复现；机制锚点 network_windows.mbt:194-213
/// `accept_windows` 经 `handle.wait_read_result` 在同一句柄挂等待）。
/// 上游唯一自证可行的形态即 `run_forever`（tcp.mbt:141-172）：循环内单次
/// 串行 `accept()`（三分支见 tcp.mbt:223/:231/:239），连接接受后经任务组
/// `spawn_bg` 并发处理——本原语照此收口（欠账 F18：上游缺口待回补，
/// 向 moonbitlang/async 提 issue/PR 须事先人工批准，宪法 I）。
///
/// FR-004/SC-006：accept 循环整体受 with_timeout_opt(timeout_ms) 保护；
/// 每条连接的处理亦受同额超时保护并在收尾时关闭连接；任务组在返回前
/// 等待全部在途连接处理完成。close() 幂等优雅停止：循环内发现 closed
/// 即停；accept 因监听句柄关闭而报错同样按停止收尾（不视为故障）。
pub async fn ScriptedServer::serve_n(
  self : ScriptedServer,
  n : Int32,
  timeout_ms~ : Int32 = 5000,
) -> Unit {
  if self.closed {
    return
  }
  @async.with_task_group() <| group => {
    let outcome : Result[Unit?, Error] = try {
      let r = @async.with_timeout_opt(timeout_ms) <| () => {
        for _i in 0..<n {
          if self.closed {
            break
          }
          // 串行 accept：同一时刻至多一个在途 accept（上游约束，见上）
          let (conn, _peer_addr) = self.server.accept()
          // F-5/F-6（P04 T002）：accept 成功点累计 +1，按序号开请求记账位
          self.accepted_total = self.accepted_total + 1
          let conn_index = self.conn_request_counts.length()
          self.conn_request_counts.push(0)
          group.spawn_bg(() => {
            // 高水位观测位：进入 +1 / 退出 -1，退出路径恒执行（含超时/错误）
            self.active_conns = self.active_conns + 1
            if self.active_conns > self.peak_conns {
              self.peak_conns = self.active_conns
            }
            let outcome : Result[Unit?, Error] = try {
              let r = @async.with_timeout_opt(timeout_ms) <| () => {
                self.serve_connection(conn, conn_index)
              }
              Ok(r)
            } catch {
              e => Err(e)
            } noraise {
              r => r
            }
            self.active_conns = self.active_conns - 1
            conn.close()
            match outcome {
              Err(e) => raise e
              Ok(_) => ()
            }
          })
        }
      }
      Ok(r)
    } catch {
      e => Err(e)
    } noraise {
      r => r
    }
    match outcome {
      Ok(_) => ()
      Err(err) =>
        // close 与 accept 的竞争窗口：句柄已关导致的报错＝优雅停止信号
        if self.closed {
          ()
        } else {
          raise err
        }
    }
  }
}

///|
// ASCII 串 → Bytes（逐码点取低 8 位；仅用于恒为 ASCII 的 id 前缀，
// 调用方须保证无多字节字符）
fn ascii_bytes(s : String) -> Bytes {
  let arr = FixedArray::make(s.length(), b'\x00')
  let mut i = 0
  for ch in s {
    arr[i] = ch.to_int().to_byte()
    i = i + 1
  }
  arr.unsafe_reinterpret_as_bytes()
}

///|
// 按脚本应答一次请求；返回是否继续在该连接上读下一个请求（keep-alive）。
// 分派按任务增量放开：未实现的编排一律 501「Not Implemented」+ 关连接收尾
// ——后续任务（T009/T010）的红阶段据此获得可归因失败（夹具还没有该行为）。
async fn ScriptedServer::serve_script(
  self : ScriptedServer,
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
  // 分派：按 body plan 为主线，framing 决定 CL 有无（send.mbt:190-197
  // 公开契约——extra_headers 带 CL ⇒ 定长帧；不带 ⇒ 首次写体转 chunked）。
  let extra = extra_headers_of(script.headers)
  if script.close_after_response {
    // B-06（T010）：夹具派生 Connection: close 头（与声明值覆盖语义一致，
    // close_after_response 是声明位，头由夹具统一落头）
    extra[@http.CaseInsensitiveString("Connection")] = "close"
  }
  match script.body {
    // B-05（T009）：定长/chunked 可选；chunked 路径块边界经 flush 保真（R3）
    Static(bytes) =>
      match script.framing {
        Fixed => {
          let _ = req
          extra[@http.CaseInsensitiveString("Content-Length")] = "\{bytes.length()}"
          conn.send_response(
            script.status,
            reason_of(script.status),
            extra_headers=extra,
          )
          if bytes.length() > 0 {
            conn.write(bytes)
          }
          conn.end_response()
          true
        }
        Chunked => {
          let _ = req
          conn.send_response(
            script.status,
            reason_of(script.status),
            extra_headers=extra,
          )
          if bytes.length() > 0 {
            conn.write(bytes)
            conn.flush()
          }
          conn.end_response()
          true
        }
      }
    // B-02 滴流（T006）：体按块 write + flush，块间 sleep(interval_ms)；
    // 末块后不 sleep（间隔语义＝块与块之间）。Fixed 预先声明 CL 总量；
    // Chunked 逐块自成帧（小写块经 flush 保块边界）
    Drip(block_bytes, blocks, interval_ms) => {
      let _ = req
      match script.framing {
        Fixed =>
          extra[@http.CaseInsensitiveString("Content-Length")] = "\{block_bytes * blocks}"
        Chunked => ()
      }
      conn.send_response(
        script.status,
        reason_of(script.status),
        extra_headers=extra,
      )
      let block = drip_block(block_bytes)
      for i in 0..<blocks {
        conn.write(block)
        // R3：写有缓冲语义（server.mbt:128-129「MAY be buffered」），
        // flush 保证块准时上线，客户端侧才能观测到滴流节奏/块边界
        conn.flush()
        if i < blocks - 1 {
          @async.sleep(interval_ms)
        }
      }
      conn.end_response()
      true
    }
    // B-04 echo 唯一 id（T008，FR-013）：体 = "<单调id>:<请求体原样>"。
    // 字节保真路径：id 段恒 ASCII，请求体字节原样拼接，多字节 UTF-8 不经
    // 字符串重编码（客户端以请求体逐字节回显为判据）
    Echo => {
      let req_body = conn.read_all().binary()
      let id = self.next_id
      self.next_id = id + 1
      let buf = Buffer()
      buf.write_bytes(ascii_bytes("\{id}:"))
      buf.write_bytes(req_body)
      let body = buf.to_bytes()
      match script.framing {
        Fixed =>
          extra[@http.CaseInsensitiveString("Content-Length")] = "\{body.length()}"
        Chunked => ()
      }
      conn.send_response(
        script.status,
        reason_of(script.status),
        extra_headers=extra,
      )
      conn.write(body)
      if script.framing is Chunked {
        conn.flush()
      }
      conn.end_response()
      true
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
/// serve_n 并发处理高水位（B-04 交错自证的结构性证据，owner 裁决 2026-10-18）：
/// serve 本轮处理中「同时在途连接数」的峰值；≥2 即直接证明连接处理真实
/// 并发交错（而非逐条串行）。须在 serve_n 返回后读取（此时全部连接已退出、
/// 峰值定格）。单连接 serve_once 不计入（观测位语义限 serve_n）。
pub fn ScriptedServer::peak_concurrent(self : ScriptedServer) -> Int32 {
  self.peak_conns
}

///|
/// 累计接受连接数（F-5，P04 T002/R5）：accept 成功点 +1 的累计值。
/// 归因：FR-009 外部证据 / US-2 场景 2（长跑无泄漏双证据服务侧证据面）。
pub fn ScriptedServer::accepted_total(self : ScriptedServer) -> Int32 {
  self.accepted_total
}

///|
/// 每连接请求数（F-6，P04 T002/R5）：按 accept 序号排列的请求记账拷贝。
/// 归因：长跑 keep-alive 复用自证 / US-2 场景 2；拷贝语义——改写返回值
/// 不影响夹具内部状态。
pub fn ScriptedServer::conn_request_counts(
  self : ScriptedServer,
) -> Array[Int32] {
  let out : Array[Int32] = []
  for count in self.conn_request_counts {
    out.push(count)
  }
  out
}

///|
/// 按请求到达序排列的「请求行+头文本」拷贝（T019/converge F1，owner 裁决①
/// 2026-10-28）：SC-004「同 host follow-up 捕获字节完整保留 Authorization/
/// Cookie」的黑盒观测面——原夹具无请求头观测能力（R7 口径），本访问器是
/// 夹具观测面、非库行为面。每条目首行为 `"<METHOD> <path>"`，其后逐头一行
/// `"<头名>: <值>"`；头名以 CaseInsensitiveString::to_string 原样字符串化，
/// 不做大小写归一化承诺。拷贝语义——改写返回值不影响夹具内部状态
/// （conn_request_counts 同款）。
pub fn ScriptedServer::captured_request_heads(
  self : ScriptedServer,
) -> Array[String] {
  let out : Array[String] = []
  for text in self.captured_heads {
    out.push(text)
  }
  out
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

///|
// P05 测试缝（US-1⑥/US-1④ 捕获断言用）：构造 RequestLineExpect。`method`
// 是 MoonBit 保留字（[0035]），客户端包未抑制该警告无法写字面量——本包
// 已有包级抑制（T003 口径），经此 helper 收口。
pub fn expect_request_line(
  meth~ : String,
  target~ : String,
) -> RequestLineExpect {
  { method: meth, target, }
}
