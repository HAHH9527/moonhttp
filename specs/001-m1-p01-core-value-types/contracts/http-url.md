# 契约：HttpUrl（M1-P01 core 包公开 API）

**包**：`moonhttp/core`（MoonBit 包路径以 `.mbti` 冻结为准；本文件是语义
契约，签名写法为示意）。错误变体清单见 [data-model.md §4](../data-model.md)
（唯一规范源，本文件不重述）。

## 构造与序列化

```moonbit
/// 解析并规范化 URL；畸形输入 raise HttpUrlError，绝不 panic。
fn HttpUrl::parse(input : String) -> HttpUrl raise HttpUrlError

/// 规范化序列化；对 parse 产物满足 parse(to_string(u)) == u。
fn HttpUrl::to_string(self : HttpUrl) -> String
```

**契约条款**：

1. `parse` 单遍 O(n)；接受输入当且仅当通过 data-model §1 六条验证规则。
2. 往返幂等（FR-001）：仅对 parse 成功的输入承诺。
3. `to_string` 省略默认端口、小写 scheme/host、重建 path 以 `/` 起始、
   `query`/`fragment` 为 `None` 时不输出 `?`/`#`。

## 相对引用解析

```moonbit
/// RFC 3986 §5 相对引用解析；复用已解析 base。
/// - 绝对 location（含 scheme）：直接 parse。
/// - 网络路径 "//h/p"：scheme 自 base 继承。
/// - 空串：返回 base 去 fragment（对齐 OkHttp）。
fn HttpUrl::resolve(base : HttpUrl, location : String) -> HttpUrl raise HttpUrlError
```

## 访问器

```moonbit
/// scheme 复用上游 @http.Protocol（决策 N2-A）：本包不自立 Scheme 枚举。
fn HttpUrl::scheme(self) -> @http.Protocol     // Http | Https
fn HttpUrl::host(self) -> String               // 已剥 IPv6 方括号
fn HttpUrl::port(self) -> Int                  // 显式或默认，1..=65535
fn HttpUrl::path_segments(self) -> Array[String]  // 已 percent-decode
fn HttpUrl::query(self) -> String?             // encoded 原样（不二次编码）
fn HttpUrl::fragment(self) -> String?
```

**默认端口的真相源**：本包**不提供** `default_port(scheme)` 静态函数——
默认端口直接用上游 `@http.Protocol` 上的 `default_port`（http=80 /
https=443）。消费方写 `u.scheme().default_port()`。若实现期确需便捷入口，
至多加 `HttpUrl::default_port(self) -> Int` 的**实例转发**（非新真相），
最终取舍在 `.mbti` 冻结时定（决策 N2-A + L1-A）。

## 判等语义

六字段结构判等（`derive(Eq, Hash, Debug)` + 显式 `pub extend`，见
[research.md R4](../research.md)）：`query`/`fragment` 的 `None` 与空串
不相等；path 段序列以解码后形态参与判等。

## 验收锚点（对齐 spec US-1/US-2）

| 输入 | 输出 |
| --- | --- |
| `http://Example.COM:80/a/./b/../c?x=1#frag` → parse → to_string | `http://example.com/a/c?x=1#frag` |
| `http://[::1]:8080/x` → parse | host=`::1`, port=8080 |
| `http://h:0/` / `http://h:65536/` | `InvalidPort`（合法区间 `1..=65535`） |
| `http://bad host/` / `http://host:notaport/` | raise（类型可判别） |
| 非 ASCII host | `InvalidHost` |
| `user:pass@host` | `MalformedUrl`（显式拒绝） |
| `ftp://…` | `UnsupportedScheme` |
| base `http://a.com/dir/page` + `../up` | `http://a.com/up` |
| 同 base + `//b.com/x` | `http://b.com/x`（scheme 自 base 继承） |
| 同 base + `?x=1`（query-only 参考） | `http://a.com/dir/page?x=1`（fragment 丢弃） |
| 同 base + `#f`（仅 fragment 参考） | `http://a.com/dir/page#f`（path/query 保持） |
| base `http://a.com`（无 path）+ `../up` | `http://a.com/up`（base path 为空时的合并分支） |
