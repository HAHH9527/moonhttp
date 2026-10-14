///|
// headers：HeadersV（不可变有序多头容器）与 HeadersVBuilder（可变 Builder，
// FR-012 头校验在此发生）（spec US-3，FR-004/006/012/013）。
//
// 设计（research R2/R5，clarify 2026-10-13）：
//   - 底层存储 Array[(@http.CaseInsensitiveString, String)]，复用上游
//     CaseInsensitiveString 的大小写不敏感判等/哈希（零分配比较）
//   - 不可变值 + 可变 Builder：入池键后哈希恒稳（P04 Address 前提）；
//     build() 与 builder() 均做防御性复制，值与 Builder 互不串改
//   - 顺序 = 插入序，参与判等与哈希；名字大小写不敏感比较、原样保留
//   - derive(Eq, Hash, Debug) + 显式 pub extend（N1-A；R3-H1-A：Debug 为
//     默认明文实现，无手写 impl、无逃生口方法；输出面纪律见 FR-013）
//   - Builder 双入口（R2-C1）：HeadersVBuilder::new() 造空；
//     HeadersV::builder() 已固化值回转，不重跑 FR-012 校验
pub struct HeadersV {
  entries : Array[(@http.CaseInsensitiveString, String)]
} derive(Eq, Hash, Debug)

///|
// 消除 implicit_impl_as_method 警告 [0079] 的配套写法（决策 N1-A，research R4）
pub extend HeadersV with Eq::{equal, not_equal}

///|
pub extend HeadersV with Hash::{hash, hash_combine}

///|
pub extend HeadersV with Debug::{to_repr}

///|
// 可变配套容器：add/set/remove 与头名校验（FR-012）在此发生。
// entries 本身不可重绑定，变更经数组原地修改完成
pub struct HeadersVBuilder {
  entries : Array[(@http.CaseInsensitiveString, String)]
} derive(Eq, Hash, Debug)

///|
pub extend HeadersVBuilder with Eq::{equal, not_equal}

///|
pub extend HeadersVBuilder with Hash::{hash, hash_combine}

///|
pub extend HeadersVBuilder with Debug::{to_repr}

///|
// RFC 9110 token 字符：!#$%&'*+-.^_`|~ 与数字、字母
fn is_tchar(c : Char) -> Bool {
  if c.is_ascii_alphabetic() || c.is_ascii_digit() {
    true
  } else {
    c
    is ('!'
    | '#'
    | '$'
    | '%'
    | '&'
    | '\''
    | '*'
    | '+'
    | '-'
    | '.'
    | '^'
    | '_'
    | '`'
    | '|'
    | '~')
  }
}

///|
// 头名校验（FR-012）：非空且全为 RFC 9110 token 字符，违例 raise InvalidName
fn validate_header_name(name : String) -> Unit raise HeadersError {
  if name.length() == 0 {
    raise HeadersError::InvalidName
  }
  for c in name {
    if !is_tchar(c) {
      raise HeadersError::InvalidName
    }
  }
}

///|
// 头值校验（FR-012）：不得含 CR/LF（防头注入），违例 raise InvalidValue
fn validate_header_value(value : String) -> Unit raise HeadersError {
  for c in value {
    if c == '\r' || c == '\n' {
      raise HeadersError::InvalidValue
    }
  }
}

///|
// 原地删全部同名（大小写不敏感）
fn remove_all_entries(
  entries : Array[(@http.CaseInsensitiveString, String)],
  name : @http.CaseInsensitiveString,
) -> Unit {
  let kept : Array[(@http.CaseInsensitiveString, String)] = []
  for entry in entries {
    let (n, _) = entry
    if !(n == name) {
      kept.push(entry)
    }
  }
  entries.clear()
  for entry in kept {
    entries.push(entry)
  }
}

///|
// 复制条目数组（值与 Builder 的隔离保证）
fn copy_entries(
  from : Array[(@http.CaseInsensitiveString, String)],
) -> Array[(@http.CaseInsensitiveString, String)] {
  let copy : Array[(@http.CaseInsensitiveString, String)] = []
  for entry in from {
    copy.push(entry)
  }
  copy
}

///|
/// 空容器构造入口（R2-C1 双入口之一）。
pub fn HeadersVBuilder::new() -> HeadersVBuilder {
  { entries: [], }
}

///|
/// 已固化 HeadersV → 可变 Builder 的回转（R2-C1 双入口之二）：
/// 不重跑 FR-012 校验（源数据首次 build 前已校验）；防御性复制保原值不变。
pub fn HeadersV::builder(self : HeadersV) -> HeadersVBuilder {
  { entries: copy_entries(self.entries), }
}

///|
/// 追加一条头；名/值校验失败 raise HeadersError，容器不变（FR-012）。
pub fn HeadersVBuilder::add(
  self : HeadersVBuilder,
  name : String,
  value : String,
) -> Unit raise HeadersError {
  // 校验先于任何变更：违例时容器保持原状
  validate_header_name(name)
  validate_header_value(value)
  self.entries.push((@http.CaseInsensitiveString(name), value))
}

///|
/// 删全部同名后追加一条；校验同 add（FR-012）。
pub fn HeadersVBuilder::set(
  self : HeadersVBuilder,
  name : String,
  value : String,
) -> Unit raise HeadersError {
  validate_header_name(name)
  validate_header_value(value)
  let key = @http.CaseInsensitiveString(name)
  remove_all_entries(self.entries, key)
  self.entries.push((key, value))
}

///|
/// 删全部同名；对非法名静默无操作（不 raise，FR-012）。
pub fn HeadersVBuilder::remove(self : HeadersVBuilder, name : String) -> Unit {
  remove_all_entries(self.entries, @http.CaseInsensitiveString(name))
}

///|
/// 产出不可变值；防御性复制条目（Builder 可继续使用而不影响已产出值）。
pub fn HeadersVBuilder::build(self : HeadersVBuilder) -> HeadersV {
  { entries: copy_entries(self.entries), }
}

///|
/// 取首个同名头的值（大小写不敏感）；无则 None（FR-004）。
pub fn HeadersV::get(self : HeadersV, name : String) -> String? {
  let key = @http.CaseInsensitiveString(name)
  let mut result : String? = None
  for entry in self.entries {
    let (n, v) = entry
    if n == key {
      result = Some(v)
      break
    }
  }
  result
}

///|
/// 保插入序遍历该名字的全部值（不折叠同名值，决策 M2-A；同名值合并只发生
/// 在 to_http_map 边界折叠）。断言时先收集为数组（contracts/headers.md）。
pub fn HeadersV::values(self : HeadersV, name : String) -> Iter[String] {
  let key = @http.CaseInsensitiveString(name)
  let collected : Array[String] = []
  for entry in self.entries {
    let (n, v) = entry
    if n == key {
      collected.push(v)
    }
  }
  collected.iter()
}

///|
/// 折叠为 @http 请求侧头 Map（FR-005，spec US-4）：遍历序列、同名值以
/// 无空格逗号 "," 合并为单值——与 @http 响应侧 parser.mbt:282 的
/// `"\{v0},\{value}"` 合并逐字节对称（用户裁决 Q1-A：保证响应侧已合并的头
/// 再进请求侧折叠不变形）。
///
/// 不变量（SC-003，决策 H1-A）：① 无重复名 → 恒等映射；② 有重复名 →
/// 折叠值 = 按插入序 "," 拼接，且该串经响应侧拆分（按 ","）可还原原值序列。
///
/// ⚠ 折叠不保证 quoted-string 边界（US-4 场景 2 的文档承诺）：值内引号串
/// 逗号（如 WWW-Authenticate: Basic realm="a, b"）可能受损；认证路径 M2
/// 绕过此转换（08-auth）。
pub fn HeadersV::to_http_map(self : HeadersV) -> @http.Headers {
  let map : @http.Headers = Map([])
  for entry in self.entries {
    let (name, value) = entry
    match map.get(name) {
      Some(prev) => map[name] = "\{prev},\{value}"
      None => map[name] = value
    }
  }
  map
}
