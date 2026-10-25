///|
// request_body：RequestBody（体元信息 + Bytes/Stream 两形态）与 BodySource
// （FR-003，C1/C3 裁决）。
//
// 设计（data-model §2；research R3/R4/R10）：
//   - BodySource::Bytes(Bytes)：可重放——Bytes 为不可变引用值，克隆 O(1)、
//     重放 N 次内容逐字节一致（SC-003）；构造期 O(1) 校验长度恒等（C3）。
//   - BodySource::Stream(async (&@io.Writer) -> Unit)：一次性回调消费、
//     不可重放；Writer 为 @http.Client 公开实现的底座 @io.Writer（C1 裁决
//     ——本包不自立 Writer trait、不暴露 @http.Client 具体类型）。
//     【P05 T006 修订 2026-10-25】回调形态由同步 async 化：底座写入面
//     （@io.Writer::write 等）为 async，同步回调在语言规则 [4149] 下不可
//     能执行任何写入（P02 T015 仅以「捕获 Writer」形态测试，未暴露该缝）；
//     async 化后既有同步闭包经 sync→async 子型继续可用（转换层/进度回调
//     测试零改动），真实流式发送（P05 US-1④）从此可表达。
//   - content_length : Int64?：None = 未知 → chunked（FR-004）；Some(n) =
//     定长帧（转换层注入 Content-Length 触发上游 SendingFixed，research R3）。
//   - 判等/哈希不承诺（R10：Stream 持函数，判等无语义；池键由 P01
//     HttpUrl+HeadersV 承担）。
//   - BodySource/RequestBody 手写 impl Debug（R10）：Bytes 印元信息（长度）、
//     Stream 印 <stream fn>——一律不印体字节（输出实用性：避免调试打印
//     转储大块字节，非脱敏/掩码措施，owner 2026-10-15 裁定；掩码与可配置
//     开关归 M3 F13/F12）。
pub(all) enum BodySource {
  Bytes(Bytes)
  Stream(async (&@io.Writer) -> Unit)
}

///|
// 体源 Debug 标签（BodySource/RequestBody 的手写 Debug 共用渲染口径，
// R10：Bytes 印长度元信息、Stream 印 <stream fn>，不印体字节）
fn body_source_debug_tag(source : BodySource) -> String {
  match source {
    Bytes(data) => "Bytes(len=\{data.length()})"
    Stream(_) => "Stream(<stream fn>)"
  }
}

///|
// 消除 implicit_impl_as_method [0079] 的配套写法（决策 N1-A，R1——手写
// pub impl 同样触发 [0079]，须显式 extend 暴露 to_repr；方法并入 .mbti
// 冻结清单逐条审视，T017）
pub extend BodySource with Debug::{to_repr}

///|
// 手写 Debug（R10）：不印体字节内容（pub：trait impl 需显式 pub 才跨包可见）
pub impl Debug for BodySource with fn to_repr(self) {
  Repr::Repr("BodySource::\{body_source_debug_tag(self)}")
}

///|
/// 请求体值：content_type / content_length 元信息 + 两形态体源（FR-003）。
///
/// 构造只经 `RequestBody::bytes` / `RequestBody::stream`（Bytes 构造期
/// 校验在 bytes 构造器内完成）；字段构造后不可变（FR-001）。
pub struct RequestBody {
  content_type : String?
  content_length : Int64?
  source : BodySource
}

///|
// 消除 implicit_impl_as_method [0079] 的配套写法（决策 N1-A，R1；T017）
pub extend RequestBody with Debug::{to_repr}

///|
// 手写 Debug（R10）：印元信息（content_type/content_length 与体源形态），
// 不印体字节（pub：trait impl 需显式 pub 才跨包可见）
pub impl Debug for RequestBody with fn to_repr(self) {
  let ct = match self.content_type {
    Some(v) => "\{v}"
    None => "None"
  }
  let cl = match self.content_length {
    Some(n) => "\{n}"
    None => "None"
  }
  Repr::Repr(
    "RequestBody(content_type=\{ct}, content_length=\{cl}, source=\{body_source_debug_tag(self.source)})",
  )
}

///|
/// Bytes 形态构造：构造期 O(1) 校验 `content_length == data.length()`，
/// 不符 raise `IncorrectBodyLength`（C3 裁决——Bytes 长度错在构造点暴露，
/// 发送期不再出现；发送期上游错误到同一变体的映射契约归 P05 执行）。
pub fn RequestBody::bytes(
  data : Bytes,
  content_length : Int64,
  content_type~ : String? = None,
) -> RequestBody raise HttpMessageError {
  if content_length != data.length().to_int64() {
    raise HttpMessageError::IncorrectBodyLength
  }
  {
    content_type,
    content_length: Some(content_length),
    source: BodySource::Bytes(data),
  }
}

///|
/// Stream 形态构造：回调一次性消费、不可重放；`content_length` 缺省 None
/// （→ chunked），显式 Some(n) 走定长帧、写超/欠写由发送期上游
/// `IncorrectBodyLength` 报错（P05 映射，research R3）。
pub fn RequestBody::stream(
  f : async (&@io.Writer) -> Unit,
  content_type~ : String? = None,
  content_length~ : Int64? = None,
) -> RequestBody {
  { content_type, content_length, source: BodySource::Stream(f), }
}

///|
// 计数 Writer（T016，R4）：委托底座 @io.Writer 并累计已写字节；每次成功
// 写入后以累计值回调 on_bytes。失败路径（委托写 raise）不经过回调语句——
// 「累计单调递增、终值 = content_length」仅在成功完成时成立（FR-009）。
priv struct CountingWriter {
  inner : &@io.Writer
  mut total : Int64
  on_bytes : (Int64) -> Unit
}

///|
// 只实现 write_once（抽象方法）：Writer 的 write/write_reader 默认实现
// 均最终经 write_once 落盘，计数在唯一落盘点收口
impl @io.Writer for CountingWriter with fn write_once(self, data, offset~, len~) {
  let n = self.inner.write_once(data, offset~, len~)
  if n > 0 {
    self.total = self.total + n.to_int64()
    (self.on_bytes)(self.total)
  }
  n
}

///|
/// 上传进度包装（FR-009；contracts/request.md 条款 3；**2026-10-16 owner
/// 裁决 C：进度承诺仅 Stream 形态**）：
/// - Stream 形态：以计数 `@io.Writer` 包装后传给用户回调——用户回调收到
///   的 Writer 每次成功落盘即以累计值回调 `on_bytes`（累计单调递增、
///   终值 = content_length）；失败路径不回调（错误沿 async 写调用原样
///   传播，research R4）；
/// - Bytes 形态：**spec FR-009 裁剪，不承诺回调**——Bytes 仅保证
///   content_type/content_length 元信息与 `to_http_request` 转换输出与
///   未包装逐字节恒等（T015③/T015 补用例锁定恒等语义）；
/// - 两种形态均不改变 content_type/content_length 元信息（条款 7：
///   进度分块不得降级 chunked）。
pub fn RequestBody::with_progress(
  self : RequestBody,
  on_bytes : (Int64) -> Unit,
) -> RequestBody {
  match self.source {
    Bytes(_) => self
    Stream(f) => {
      let source : BodySource = BodySource::Stream(async fn(writer) {
        let counting : CountingWriter = { inner: writer, total: 0L, on_bytes, }
        f(counting)
      })
      {
        content_type: self.content_type,
        content_length: self.content_length,
        source,
      }
    }
  }
}
