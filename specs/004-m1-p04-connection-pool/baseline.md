# Baseline：P04 动工前基线（T001）

> 记录时间：2026-10-21 ｜ 分支：`004-m1-p04-connection-pool`
> 用途：后续 diff 归因与回归对照（对照物：Phase 7 的 T024/T025 收口）。

## 静态测试计数

命令口径（工单给定）：

```sh
grep -rhP '^\s*(async\s+)?test\s' src --include='*_test.mbt' --include='*_wbtest.mbt' | wc -l
```

- 实测值：**160**（pwsh 等价实现：`Select-String '^\s*(async\s+)?test\s'`
  对 18 个 `_test.mbt`/`_wbtest.mbt` 文件逐行计数）
- 文件数：**18** —— 与工单锚点一致，无漂移

## 六门结果（全绿）

| # | 门 | 结果 |
| --- | --- | --- |
| 1 | `moon check --target native --deny-warn` | ✅ 通过（ran 31 tasks, up to date） |
| 2 | `moon check --target wasm --deny-warn` | ✅ 通过（no work to do） |
| 3 | `moon test --target native --deny-warn` | ✅ `Total tests: 160, passed: 160, failed: 0` |
| 4 | `moon test --target wasm --deny-warn` | ✅ `Total tests: 160, passed: 160, failed: 0` |
| 5 | `moon fmt --check` | ✅ 通过（no work to do） |
| 6 | `moon info` | ✅ 通过；`git status --porcelain` 零 diff（`.mbti` 全部与库内一致） |

## `.mbti` 快照（动工前）

### `src/client/pkg.generated.mbti`（仅 placeholder）

```text
// Generated using `moon info`, DON'T EDIT IT
package "hahh9527/moonhttp/client"

// Values
pub fn placeholder() -> Bool

// Errors

// Types and methods

// Type aliases

// Traits
```

### `src/core/pkg.generated.mbti`（187 行，P04 期望零 diff）

```text
// Generated using `moon info`, DON'T EDIT IT
package "hahh9527/moonhttp/core"

import {
  "moonbitlang/async/http",
  "moonbitlang/async/io",
  "moonbitlang/core/debug",
}

// Values

// Errors
pub(all) suberror HeadersError {
  InvalidName
  InvalidValue
} derive(@debug.Debug)
pub fn HeadersError::to_repr(Self) -> @debug.Repr

pub(all) suberror HttpMessageError {
  MethodBodyMismatch
  IncorrectBodyLength
} derive(@debug.Debug)
pub fn HttpMessageError::to_repr(Self) -> @debug.Repr

pub(all) suberror HttpUrlError {
  InvalidHost
  InvalidPort
  MalformedUrl
  UnsupportedScheme
} derive(@debug.Debug)
pub fn HttpUrlError::to_repr(Self) -> @debug.Repr

// Types and methods
pub(all) enum BodySource {
  Bytes(Bytes)
  Stream((&@io.Writer) -> Unit)
}
pub fn BodySource::to_repr(Self) -> @debug.Repr
pub impl @debug.Debug for BodySource

pub struct HeadersV {
  entries : Array[(@http.CaseInsensitiveString, String)]
} derive(Eq, Hash, @debug.Debug)
pub fn HeadersV::builder(Self) -> HeadersVBuilder
pub fn HeadersV::equal(Self, Self) -> Bool
pub fn HeadersV::get(Self, String) -> String?
pub fn HeadersV::hash(Self) -> Int
pub fn HeadersV::hash_combine(Self, Hasher) -> Unit
pub fn HeadersV::not_equal(Self, Self) -> Bool
pub fn HeadersV::to_http_map(Self) -> Map[@http.CaseInsensitiveString, String]
pub fn HeadersV::to_repr(Self) -> @debug.Repr
pub fn HeadersV::values(Self, String) -> Iter[String]

pub struct HeadersVBuilder {
  entries : Array[(@http.CaseInsensitiveString, String)]
} derive(Eq, Hash, @debug.Debug)
pub fn HeadersVBuilder::add(Self, String, String) -> Unit raise HeadersError
pub fn HeadersVBuilder::build(Self) -> HeadersV
pub fn HeadersVBuilder::equal(Self, Self) -> Bool
pub fn HeadersVBuilder::hash(Self) -> Int
pub fn HeadersVBuilder::hash_combine(Self, Hasher) -> Unit
pub fn HeadersVBuilder::new() -> Self
pub fn HeadersVBuilder::not_equal(Self, Self) -> Bool
pub fn HeadersVBuilder::remove(Self, String) -> Unit
pub fn HeadersVBuilder::set(Self, String, String) -> Unit raise HeadersError
pub fn HeadersVBuilder::to_repr(Self) -> @debug.Repr

pub struct HttpUrl {
  scheme : @http.Protocol
  host : String
  port : Int
  path_segments : Array[String]
  query : String?
  fragment : String?
} derive(Eq, Hash, @debug.Debug)
pub fn HttpUrl::equal(Self, Self) -> Bool
pub fn HttpUrl::fragment(Self) -> String?
pub fn HttpUrl::hash(Self) -> Int
pub fn HttpUrl::hash_combine(Self, Hasher) -> Unit
pub fn HttpUrl::host(Self) -> String
pub fn HttpUrl::not_equal(Self, Self) -> Bool
pub fn HttpUrl::parse(String) -> Self raise HttpUrlError
pub fn HttpUrl::path_segments(Self) -> Array[String]
pub fn HttpUrl::port(Self) -> Int
pub fn HttpUrl::query(Self) -> String?
pub fn HttpUrl::resolve(Self, String) -> Self raise HttpUrlError
pub fn HttpUrl::scheme(Self) -> @http.Protocol
pub fn HttpUrl::to_repr(Self) -> @debug.Repr
pub fn HttpUrl::to_string(Self) -> String

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
} derive(Eq, Hash, @debug.Debug)
pub fn Method::equal(Self, Self) -> Bool
pub fn Method::from_request_method(@http.RequestMethod) -> Self
pub fn Method::hash(Self) -> Int
pub fn Method::hash_combine(Self, Hasher) -> Unit
pub fn Method::not_equal(Self, Self) -> Bool
pub fn Method::to_repr(Self) -> @debug.Repr
pub fn Method::to_request_method(Self) -> @http.RequestMethod

pub struct Request {
  url : HttpUrl
  method : Method
  headers : HeadersV
  tag : Unit?
  body : RequestBody?
} derive(@debug.Debug)
pub fn Request::to_http_request(Self) -> @http.Request
pub fn Request::to_repr(Self) -> @debug.Repr

pub struct RequestBody {
  content_type : String?
  content_length : Int64?
  source : BodySource
}
pub fn RequestBody::bytes(Bytes, Int64, content_type? : String?) -> Self raise HttpMessageError
pub fn RequestBody::stream((&@io.Writer) -> Unit, content_length? : Int64?, content_type? : String?) -> Self
pub fn RequestBody::to_repr(Self) -> @debug.Repr
pub fn RequestBody::with_progress(Self, (Int64) -> Unit) -> Self
pub impl @debug.Debug for RequestBody

pub struct RequestBuilder {
  url : HttpUrl
  method : Method
  headers : HeadersVBuilder
  tag : Unit?
  body : RequestBody?
} derive(@debug.Debug)
pub fn RequestBuilder::body(Self, RequestBody) -> Self
pub fn RequestBuilder::build(Self) -> Request raise HttpMessageError
pub fn RequestBuilder::header(Self, String, String) -> Unit raise HeadersError
pub fn RequestBuilder::headers(Self, HeadersV) -> Self
pub fn RequestBuilder::method(Self, Method) -> Self
pub fn RequestBuilder::new(HttpUrl) -> Self
pub fn RequestBuilder::tag(Self, Unit?) -> Self
pub fn RequestBuilder::to_repr(Self) -> @debug.Repr

pub struct Response {
  code : Int
  reason : String
  headers : HeadersV
  cookies : Array[@http.Cookie]
  body : ResponseBody?
  prior : Response?
} derive(@debug.Debug)
pub fn Response::body(Self) -> ResponseBody?
pub fn Response::code(Self) -> Int
pub fn Response::cookies(Self) -> Array[@http.Cookie]
pub fn Response::from_http(Int, String, Map[@http.CaseInsensitiveString, String], Array[@http.Cookie], body? : ResponseBody?, prior? : Self?) -> Self
pub fn Response::headers(Self) -> HeadersV
pub fn Response::prior(Self) -> Self?
pub fn Response::reason(Self) -> String
pub fn Response::to_repr(Self) -> @debug.Repr

pub struct ResponseBody {
  // private fields
}
pub fn ResponseBody::buffered(Bytes) -> Self
pub async fn ResponseBody::bytes(Self) -> Bytes
pub fn ResponseBody::consumed(Self) -> Bool
pub fn ResponseBody::drop(Self) -> Unit
pub fn ResponseBody::dropped(Self) -> Bool
pub async fn ResponseBody::read_some(Self, max_len? : Int) -> Bytes?
pub fn ResponseBody::stream(&@io.Reader, on_event? : (ResponseBodyEvent) -> Unit) -> Self
pub async fn ResponseBody::text(Self) -> String
pub fn ResponseBody::to_repr(Self) -> @debug.Repr
pub impl @debug.Debug for ResponseBody

pub(all) enum ResponseBodyEvent {
  Consumed
  Dropped
  Abandoned
} derive(@debug.Debug)
pub fn ResponseBodyEvent::to_repr(Self) -> @debug.Repr

// Type aliases

// Traits
```

### `src/internal/fixtures/pkg.generated.mbti`（83 行，增量对照基线）

```text
// Generated using `moon info`, DON'T EDIT IT
package "hahh9527/moonhttp/internal/fixtures"

// Values

// Errors

// Types and methods
pub(all) enum BodyPlan {
  Static(Bytes)
  Echo
  Drip(Int, Int, Int)
}

pub(all) struct CapturedRequest {
  head : Bytes
  body : Bytes
  raw : Bytes
  chunked : Bool
  complete : Bool
  note : String?
}
pub fn CapturedRequest::assert_matches(Self, RequestLineExpect, String) -> Unit raise
pub fn CapturedRequest::head_text(Self) -> String
pub fn CapturedRequest::raw_text(Self) -> String

pub(all) enum CutPoint {
  Nothing
  MidStatusLine(Int)
  AfterStatusLine
  MidHeaderLine(Int)
}

pub(all) enum Framing {
  Fixed
  Chunked
}

pub(all) enum PeerProgram {
  AcceptClose
  CloseObservation
  PartialResponse(CutPoint, Bool)
  SlowReceive(Int, Int)
  Capture
}

pub(all) struct RequestLineExpect {
  method : String
  target : String
}

pub(all) struct ResponseScript {
  status : Int
  headers : Array[(String, String)]
  framing : Framing
  body : BodyPlan
  head_delay_ms : Int
  close_after_response : Bool
}

pub struct ScriptedPeer {
  // private fields
}
pub fn ScriptedPeer::close(Self) -> Unit
pub fn ScriptedPeer::mount(Self, PeerProgram) -> Unit
pub fn ScriptedPeer::port(Self) -> Int
pub async fn ScriptedPeer::run(Self, timeout_ms? : Int) -> CapturedRequest
pub async fn ScriptedPeer::start() -> Self

pub struct ScriptedServer {
  // private fields
}
pub fn ScriptedServer::close(Self) -> Unit
pub fn ScriptedServer::mount(Self, String, String, ResponseScript) -> Unit
pub fn ScriptedServer::peak_concurrent(Self) -> Int
pub fn ScriptedServer::port(Self) -> Int
pub async fn ScriptedServer::serve_n(Self, Int, timeout_ms? : Int) -> Unit
pub async fn ScriptedServer::serve_once(Self, timeout_ms? : Int) -> Unit
pub async fn ScriptedServer::start() -> Self

// Type aliases

// Traits
```

## 备注

- `git status --porcelain` 在六门后为空：`moon info` 未产生任何 `.mbti` diff，
  fmt 门零改动。
- 夹具 `moon.pkg` 已有 `import { … } for "test"` 语法先例
  （fixtures/moon.pkg:20-22，research R9）；`src/client/moon.pkg` 当前
  import 为空块——implement 期需要 `@fixtures`/`@async` 等依赖时按
  T002/T005 首个用例的红判验证可见性后再固化写法。
