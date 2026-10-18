# T001 迁移前基线（对照物：T003/T025）

- 日期：2026-10-18 ｜ HEAD：e8f6963（git mv 前回滚点）｜ 分支：003-m1-p03-test-fixtures
- moon：0.1.20261012 ｜ 先 `moon clean` 后全量实跑，非缓存命中

## 六门结果（迁移前，src/fixtures 原位）

| # | 命令 | 结果 |
| --- | --- | --- |
| 1 | `moon check --target native --deny-warn` | 通过：`Finished. moon: ran 30 tasks, now up to date` |
| 2 | `moon check --target wasm --deny-warn` | 通过：`Finished. moon: ran 30 tasks, now up to date` |
| 3 | `moon test --target native --deny-warn` | 通过：`Total tests: 126, passed: 126, failed: 0.` |
| 4 | `moon test --target wasm --deny-warn` | 通过：`Total tests: 126, passed: 126, failed: 0.` |
| 5 | `moon fmt --check` | 通过：`Finished. moon: ran 32 tasks, now up to date`（exit 0） |
| 6 | `moon info` | 通过：`Finished. moon: ran 29 tasks, now up to date`；`git status` 零 diff（.mbti 无变化） |

## 快照 1：src/fixtures/pkg.generated.mbti（迁移前原样）

```mbti
// Generated using `moon info`, DON'T EDIT IT
package "hahh9527/moonhttp/fixtures"

// Values

// Errors

// Types and methods
pub(all) struct CapturedRequest {
  head : Bytes
  body : Bytes
  raw : Bytes
  chunked : Bool
  complete : Bool
  note : String?
}
pub fn CapturedRequest::head_text(Self) -> String
pub fn CapturedRequest::raw_text(Self) -> String

pub struct RawPeer {
  // private fields
}
pub async fn RawPeer::capture_one(Self, timeout_ms? : Int) -> CapturedRequest
pub fn RawPeer::close(Self) -> Unit
pub fn RawPeer::port(Self) -> Int
pub async fn RawPeer::start() -> Self

// Type aliases

// Traits
```

## 快照 2：src/core/pkg.generated.mbti（迁移前原样，187 行全文）

```mbti
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
