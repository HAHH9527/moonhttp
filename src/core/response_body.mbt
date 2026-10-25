///|
/// 流式体生命周期事件（data-model §6，spec FR-006）。
///
/// 触发点契约（唯一规范源 data-model §4 状态机 / research R9）：
///   - Consumed：读到 EOF（bytes() 读到底 / read_some 耗尽）——本包触发；
///   - Dropped：使用者显式 drop()（幂等；已 Consumed 则不再触发）——本包
///     触发；
///   - Abandoned：调用收尾发现既未 Consumed 也未 Dropped（毒化信号）——
///     触发权在 P04/P05 所有者（本包只提供状态查询）。
/// 互斥/时序不变量：Consumed 与 Dropped 至多其一（先到者赢，后到幂等无
/// 事件）；事件载荷为空（判别靠变体本身）。默认回调 no-op（FR-006）。
pub(all) enum ResponseBodyEvent {
  Consumed
  Dropped
  Abandoned
} derive(Debug)

///|
// 消除 implicit_impl_as_method [0079] 的配套写法（决策 N1-A，research R1）
pub extend ResponseBodyEvent with Debug::{to_repr}

///|
// response_body：ResponseBody 两态（buffered/stream）与生命周期事件契约
// （spec US-3/US-4，FR-006/007/010；data-model §4/§6）。
//
// 设计（data-model §4；research R5/R6/R9）：
//   - buffered 态：持有完整负载 Bytes（0 字节合法，bytes() 返回空不报错）。
//   - stream 态：持有 &@io.Reader（P05 传入 Client as @io.Reader；测试用
//     @io.MemoryReader/pipe 桩）+ 事件回调（默认 no-op）+ 只读状态标志
//     （consumed/dropped）。
//   - 读取 API 统一 async 签名（plan review 修订）：bytes()/text()/
//     read_some 均 pub async fn——stream 态走上游 async 读取面，buffered
//     态同签名对齐。
//   - charset（text()）：解码集 M1 仅 {UTF-8}（**2026-10-16 owner 裁决 B
//     覆写 C4**）；解析规则按 research R5——取 Content-Type 合并值中首个
//     charset= 参数（名值大小写不敏感、值可带引号）、缺省/utf-8 → UTF-8、
//     集外 → 按 UTF-8 降级解码 + stderr 告警（唯一出口
//     warn_charset_fallback），不 raise；解码用 @utf8.decode_lossy（畸形
//     序列替换 U+FFFD，对齐 OkHttp；BOM 不嗅探为已记录差异，R6）。
//   - 生命周期状态机（data-model §4）：Consumed/Dropped 至多其一（先到者
//     赢，后到幂等无事件）；Abandoned 仅由 P04/P05 所有者按 consumed()/
//     dropped() 查询结果触发——本包只提供状态查询与契约，默认回调 no-op。
//   - 判等/哈希不承诺（R10：stream 持 trait 对象，判等无语义）。
//   - 手写 impl Debug（R10）：印状态与长度元信息，不印体字节/reader 内部
//     （输出实用性：避免调试打印转储大块字节，非脱敏/掩码措施，owner
//     2026-10-15 裁定；掩码与可配置开关归 M3 F13/F12）。
//
// charset 上下文说明：ResponseBody 直构（buffered/stream 构造器）不携带
// Content-Type，text() 按缺省 UTF-8 解码（FR-007 缺省语义）；响应组装路径
// （Response::from_http）按 research R5 从响应头 Map 提取 Content-Type
// 合并值注入 body（见 response.mbt——「取响应头 Map 中 Content-Type 的
// 合并值」的天然落点）。
pub struct ResponseBody {
  priv buffered_data : Bytes?
  priv reader : &@io.Reader?
  priv mut consumed : Bool
  priv mut dropped : Bool
  priv mut content_type : String?
  priv on_event : (ResponseBodyEvent) -> Unit
  priv mut disposed : Bool // dispose 收尾唯一性标记（contracts §2 条款 6）
  priv on_dispose : (async () -> Unit)?
}

///|
// 消除 implicit_impl_as_method [0079] 的配套写法（决策 N1-A，R1；T017）
pub extend ResponseBody with Debug::{to_repr}

///|
// 手写 Debug（R10）：印状态与元信息，不印体字节/reader 内部
// （pub：trait impl 需显式 pub 才跨包可见）
pub impl Debug for ResponseBody with fn to_repr(self) {
  let state = if self.consumed {
    "consumed"
  } else if self.dropped {
    "dropped"
  } else if self.buffered_data is Some(_) {
    "buffered"
  } else {
    "stream"
  }
  let size = match self.buffered_data {
    Some(data) => "\{data.length()}"
    None => "unknown"
  }
  Repr::Repr("ResponseBody(state=\{state}, buffered_len=\{size})")
}

///|
/// buffered 态构造：持有完整负载（0 字节合法，FR-007/Edge Cases）。
pub fn ResponseBody::buffered(data : Bytes) -> ResponseBody {
  {
    buffered_data: Some(data),
    reader: None,
    consumed: false,
    dropped: false,
    content_type: None,
    on_event: ResponseBody::noop_event,
    disposed: false,
    on_dispose: None,
  }
}

///|
/// stream 态构造：持有 `&@io.Reader` 与事件回调（缺省 no-op——FR-006
/// 默认行为；真实归池/毒化接归 P04/P05）。`on_dispose?`（FR-015 裁决面，
/// contracts §2）：显式异步收尾钩子——`dispose()` 在置 dropped/触发
/// `Dropped` 后 await 它（注入方负责毒化在 raise 前完成）；缺省时
/// dispose 等价 `drop()` 纯状态标记。
pub fn ResponseBody::stream(
  reader : &@io.Reader,
  on_event? : (ResponseBodyEvent) -> Unit,
  on_dispose? : async () -> Unit,
) -> ResponseBody {
  let cb = match on_event {
    Some(f) => f
    None => ResponseBody::noop_event
  }
  {
    buffered_data: None,
    reader: Some(reader),
    consumed: false,
    dropped: false,
    content_type: None,
    on_event: cb,
    disposed: false,
    on_dispose,
  }
}

///|
// 默认 no-op 事件回调（FR-006 默认行为）
fn ResponseBody::noop_event(_event : ResponseBodyEvent) -> Unit {
  ()
}

///|
// 置 consumed 并触发 Consumed（互斥时序：先到者赢，幂等无二次事件）
fn ResponseBody::mark_consumed(self : ResponseBody) -> Unit {
  if !self.consumed {
    self.consumed = true
    (self.on_event)(ResponseBodyEvent::Consumed)
  }
}

///|
/// 完整负载读取：buffered 直取；stream 读到底（EOF 置 consumed/触发
/// `Consumed`，data-model §4 状态机）。IO 错误沿上游 raise 面透传
/// （contracts/response.md 条款 5）。
pub async fn ResponseBody::bytes(self : ResponseBody) -> Bytes {
  match self.buffered_data {
    Some(data) => data
    None => {
      // stream 态：读到底后拼接
      let acc : Array[Byte] = []
      if self.reader is Some(reader) {
        while reader.read_some() is Some(chunk) {
          for b in chunk {
            acc.push(b)
          }
        }
      }
      self.mark_consumed()
      Bytes::from_iter(acc.iter())
    }
  }
}

///|
/// 增量读取：`None` = EOF（EOF 同样置 consumed/触发 `Consumed`，contracts/
/// response.md 条款 2）。buffered 态为一次性给出：首次调用返回全部负载并
/// 置 consumed，其后返回 None。
pub async fn ResponseBody::read_some(
  self : ResponseBody,
  max_len? : Int32,
) -> Bytes? {
  match self.buffered_data {
    Some(data) =>
      if self.consumed {
        None
      } else {
        self.mark_consumed()
        match max_len {
          Some(n) =>
            if n < data.length() {
              Some(data[0:n].to_owned())
            } else {
              Some(data)
            }
          None => Some(data)
        }
      }
    None => {
      let chunk = match self.reader {
        Some(reader) => reader.read_some(max_len?)
        None => None
      }
      if chunk is None {
        self.mark_consumed()
      }
      chunk
    }
  }
}

///|
/// 文本解码：= bytes() + charset 解码（FR-007；stream 态先经 bytes() 读到
/// 底触发 `Consumed`）。charset 缺省/声明 UTF-8（任意大小写/带引号）→
/// UTF-8；**其余任何 charset 值 → 按 UTF-8 降级解码（`@utf8.decode_lossy`，
/// 畸形序列替换 U+FFFD）并经 `warn_charset_fallback` 输出一条 stderr 告警，
/// 不 raise**（**2026-10-16 owner 裁决 B**：降级语义对齐 OkHttp 5.5.0——
/// MediaType.kt:44-51 解析失败回退默认 + ResponseBody.string() 按 UTF_8；
/// stderr 告警为本地化增强、OkHttp 静默，登记为可观测面有意差异
/// （宪法 III），不改变返回值；每次调用都告警、不做进程内去重）。BOM 不
/// 嗅探（已记录差异，R6）。IO 错误沿上游 raise 面透传（contracts/
/// response.md 条款 5）。
pub async fn ResponseBody::text(self : ResponseBody) -> String {
  let data = self.bytes()
  let declared = match self.content_type {
    Some(ct) => parse_charset_param(ct)
    None => "utf-8"
  }
  // TODO(F14)：增加常用编码集支持（latin1 零码表成本低、gbk 需码表/第三方
  // 解码），扩展受支持集后按声明集解码，未知集仍降级 UTF-8。
  if declared.to_lower() != "utf-8" {
    warn_charset_fallback(declared)
  }
  @utf8.decode_lossy(data[0:data.length()])
}

///|
// charset 降级告警唯一出口（2026-10-16 owner 裁决 B）：text() 的集外
// charset 告警只经此函数——后续换 logger 或加可配置开关时一处改完。
// 消息只带 charset 名定位片段（不回显整条 Content-Type——沿用 P01/本包
// 「不回显头值/体内容/URL 全文」口径）；本包零掩码、零开关（脱敏统一
// 归 M3/F12/F13）。eprintln 为 core 跨 target 内建原语（native/wasm/js
// 同路径），与上游 async 运行期诊断惯例一致。每次调用都告警、不去重。
fn warn_charset_fallback(declared : String) -> Unit {
  eprintln(
    "moonhttp: charset \{declared} not supported (M1: UTF-8 only), falling back to UTF-8 lossy decoding",
  )
}

///|
/// 释放（幂等）：未 consumed 时置 dropped/触发 `Dropped`；已 Consumed 则
/// 静默无事件（data-model §4 互斥时序）。
pub fn ResponseBody::drop(self : ResponseBody) -> Unit {
  if !self.consumed && !self.dropped {
    self.dropped = true
    (self.on_event)(ResponseBodyEvent::Dropped)
  }
}

///|
/// 状态查询：是否已完整消费（`Consumed` 已触发）。
pub fn ResponseBody::consumed(self : ResponseBody) -> Bool {
  self.consumed
}

///|
/// 状态查询：是否已显式释放（`Dropped` 已触发）。
pub fn ResponseBody::dropped(self : ResponseBody) -> Bool {
  self.dropped
}

///|
/// 显式异步收尾（FR-015 裁决面，contracts/call-api.md §2；OkHttp
/// body.close() 的异步对应物）。契约逐条：
/// ① `consumed()` ⇒ no-op（处置已由 Consumed 通道完成）；
/// ② 否则未 dropped 则置 dropped/触发 `Dropped`（与 `drop()` 同一互斥
///    时序，先到者赢），随后 `await on_dispose()`；
/// ③ `on_dispose` 缺省 ⇒ 等价 `drop()` 纯状态标记（core 独立可用性）；
/// ④ `on_dispose` raise ⇒ 错误透传（毒化由注入方在 raise 前完成）；
/// ⑤ `drop()` 语义零变化——仅 drop 不 dispose ⇒ 租约滞留，调用方责任；
/// ⑥ 幂等与收尾唯一性：收尾动作（Dropped 触发 + await on_dispose）整体
///    至多一次有效；已收尾再 dispose ⇒ no-op；先 drop() 再 dispose() ⇒
///    Dropped 不重发、on_dispose 仍补执行一次；dispose 后 drop 亦 no-op。
pub async fn ResponseBody::dispose(self : ResponseBody) -> Unit {
  if self.consumed || self.disposed {
    return
  }
  // 先置收尾标记再推进（await 期间二次 dispose 即 no-op——收尾唯一性）
  self.disposed = true
  // 与 drop() 同一互斥时序：未 dropped 才置位/触发（drop-then-dispose 时
  // Dropped 先到者赢、此处静默不重发）
  self.drop()
  match self.on_dispose {
    Some(f) => f()
    None => ()
  }
}

///|
// charset 参数解析（research R5）：取 Content-Type 合并值中首个 `charset=`
// 参数——参数名与值大小写不敏感、值可带双引号；未找到 → "utf-8"。
// 病态场景（多 Content-Type 被上游逗号合并）按「首个参数」确定性取值。
fn parse_charset_param(content_type : String) -> String {
  for part in content_type.split(";") {
    let trimmed = part.trim().to_owned()
    // 前缀匹配 charset=（参数名大小写不敏感）
    if trimmed.length() >= 8 {
      let head = trimmed[0:8].to_owned().to_lower()
      if head == "charset=" {
        let mut value = trimmed[8:trimmed.length()].to_owned()
        // 引号值剥除（成对双引号，RFC 9110 quoted-string 参数形态）
        if value.length() >= 2 &&
          value.has_prefix("\"") &&
          value.has_suffix("\"") {
          value = value[1:value.length() - 1].to_owned()
        }
        return value.trim().to_owned()
      }
    }
  }
  "utf-8"
}
