# Data Model: core 值对象——HttpUrl 与 HeadersV（M1-P01）

**日期**：2026-10-13 ｜ **依据**：[spec.md](spec.md)（FR-001–FR-013）、
[research.md](research.md) R2–R8、R11–R14。本文件描述语义与不变量，并是
**错误类型变体清单的唯一规范源**（决策 L4-A：spec/contracts/quickstart 只按名
引用、不重述）；公开签名见 [contracts/](contracts/)。

## 实体总览

```text
HttpUrl ──解析自──> URL 字符串（String）
HttpUrl ──resolve──> HttpUrl
HeadersV <──build()── HeadersVBuilder
HeadersV ──to_http_map()──> @http.Headers（Map[CaseInsensitiveString, String]）
HeadersV ──derive(Debug)──> 调试输出（FR-013：无其他输出面，R3-H1-A）
Method  ──映射──> @http.RequestMethod
HttpUrl.scheme() ──复用──> @http.Protocol（本包不自立 scheme 枚举，R12）
HttpUrlError：parse/resolve 的失败信号（四变体）
HeadersError：Builder 头校验的失败信号（两变体，FR-012）
```

下游组合关系（本包只交付零件，不组装）：P02 `Request = HttpUrl + Method +
HeadersV + body?`；P04 以 `HttpUrl`（scheme/host/port）与 `HeadersV` 判等/
哈希作 Address 键。

## 1. HttpUrl

| 字段 | 语义 | 不变量 |
| --- | --- | --- |
| scheme | 协议 | 类型复用上游 `@http.Protocol`（`Http`/`Https`）；仅 `http` / `https`（小写）；其余 → `UnsupportedScheme` |
| host | 主机 | 已 percent-decode、ASCII、小写；IPv6 literal 剥方括号存储（含 `:` 与可选 zone-id）；末尾点保留；非 ASCII → `InvalidHost` |
| port | 端口 | `1..=65535`；缺省时填充 `@http.Protocol` 的默认端口（80/443）；越界（含 `0` 与 `65536`）或非数字 → `InvalidPort`；`port == 默认端口` 时 to_string 省略 |
| path_segments | 路径段 | 已 percent-decode；不含 `.` / `..`（解析时消解）、不含空段（压缩）；空段序列表示根路径 `/`；to_string 重建以 `/` 起始 |
| query | 查询串 | 保留 encoded 形式；合法 `%XX` 不二次编码、裸非法字符按 query 编码集补编码（R8）；重复键原样保留；`None` 与空串可区分 |
| fragment | 片段 | 同 query 口径；`None`（无 `#`）与空串（`#` 后空）可区分 |

**验证规则（解析期，全部拒收为 raise，绝不 panic）**：

1. 空串 / 缺 scheme / 缺 host → `MalformedUrl`。
2. 含 userinfo（`user:pass@host`）→ `MalformedUrl`（显式拒绝，FR-008）。
3. host 含非法字符（空格等）或非 ASCII → `InvalidHost`。
4. 端口不在 `1..=65535`（含 `http://h:0/`）或非数字 → `InvalidPort`。
5. scheme 非 http/https → `UnsupportedScheme`。
6. IPv6 括号畸形（未闭合/多重）→ `InvalidHost`。

**核心操作语义**：

- `parse(s) -> HttpUrl raise HttpUrlError`：单遍 O(n)；输出必为规范化形态。
- `to_string() -> String`：规范化序列化；`parse(to_string(parse(s))) ==
  parse(s)`（FR-001 往返幂等，仅对被接受输入承诺）。
- `resolve(base, location) -> HttpUrl raise HttpUrlError`：RFC 3986 相对
  引用合并（复用已解析 base，O(增量)）；绝对 location 直接 parse；空 location
  返回 base 去 fragment（对齐 OkHttp）；网络路径参考 `//h/p` 的 scheme 自 base
  继承。
- 默认端口：直接用上游 `@http.Protocol` 的 `default_port`（http=80 /
  https=443），本包不重复定义（R12）；如需便捷入口，只保留 `HttpUrl` 上的
  实例转发。
- 判等/哈希：六字段全等（含 `None`/空串区分）；`derive(Eq, Hash, Debug)` +
  显式 `pub extend`（R4）。

**状态转换**：无（不可变值；「生命周期」= 构造即规范化）。

## 2. HeadersV（不可变）+ HeadersVBuilder（可变）

| 方面 | 语义 |
| --- | --- |
| 存储 | 名/值对的有序序列，名字为大小写不敏感类型（复用 `@http.CaseInsensitiveString`，R2） |
| 不变量 | 构造完成后不可变 → 判等/哈希恒稳（P04 池键安全）；顺序 = 插入序 |
| Builder 操作 | `add(name, value)` 追加；`set(name, value)` 删全部同名后追加一条；`remove(name)` 删全部同名。`add`/`set` 在**进入存储前**校验（见下方验证规则），校验失败即 raise 且容器不变；`remove` 对非法名静默无操作 |
| 值操作 | `get(name) -> String?` 首个；`values(name) -> Iter[String]` 保序全部（**不折叠**，决策 M2-A；同名值合并只发生在折叠转换） |
| 折叠 | `to_http_map() -> @http.Headers`：遍历序列，同名值以无空格 `","` 合并（FR-005，与 @http 响应侧 `parser.mbt` 的 `"\{v0},\{v}"` 逐字节对称）；空容器折叠为空 Map；值为空串的头合法保留 |
| 折叠不变量 | ① 无重复名时折叠对单值名是恒等映射；② 有重复名时折叠值 = 按插入序 `,` 无空格拼接，且该串经 @http 响应侧 parser 拆分可还原原名值序列（进出互逆）——SC-003 的两个可测命题（决策 H1-A） |
| 折叠例外声明 | 值内 quoted-string 逗号（如 `WWW-Authenticate` realm）不保证边界——文档显式声明，认证路径 M2 绕过（US-4 场景 2） |
| 调试输出 | `derive(Debug)` 默认实现（R3-H1-A，取代 R13 的手写脱敏方案）：明文输出面即 `Debug` 本身，无手写 impl、无逃生口方法；本包无日志/展示/序列化输出类 API（FR-013）。测试与 `.snap` 中的敏感头样例值必须为合成占位串（R3-M1 纪律）；脱敏专版与可配置开关归 M3（F13/F12），依据宪法 v1.2.0 :112-117 展示例外程序 |
| 判等/哈希 | 相同名值对序列（含顺序）相等且哈希一致——顺序参与判等（重放字节级一致的前提）；`derive(Eq, Hash)` + 显式 `pub extend`（R4） |

**验证规则（Builder 期，FR-012）**：

1. 头名 MUST 为非空 RFC 9110 token 字符序列（`!#$%&'*+-.^_`|~` 与数字、
   字母）；空名或含空格/`:`/CR/LF 等分隔符 → raise `HeadersError::InvalidName`。
2. 头值 MUST NOT 含 CR 或 LF（含 CRLF 折叠注入序列）→ 违例 raise
   `HeadersError::InvalidValue`（防头注入）。
3. 头值允许空串（合法保留）。校验失败的错误类型已定案为独立的
   `HeadersError`（决策 H2-A，不再在「并入 `HttpUrlError`」与「独立小枚举」
   之间二选一）。

## 3. Method

| 方面 | 语义 |
| --- | --- |
| 取值 | 九个标准方法：Get / Post / Put / Delete / Head / Options / Trace / Patch / Connect |
| 映射 | 与 `@http.RequestMethod` 一一对应的双向映射（封闭，无失败分支） |
| 判等/哈希 | `derive(Eq, Hash, Debug)` + 显式 `pub extend`（R4）；无参数化形态（`Custom` 已裁剪，spec FR-007） |

## 4. 错误模型（本文件为变体清单的唯一规范源）

两个错误枚举，都**只要求可调试输出**——不 `derive(Eq)`/`derive(Hash)`
（判别用 `is` 与模式匹配即够，错误对象也不参与池键），不 `derive(Show)`
（本工具链报弃用警告 [0027]，R4）。

### 4.1 HttpUrlError（parse/resolve 的失败信号）

| 变体 | 触发（见 HttpUrl 验证规则） | 下游用法 |
| --- | --- | --- |
| `InvalidHost` | host 非法/非 ASCII/IPv6 括号畸形 | P04 池键不可能出现；P06 降级判定 |
| `InvalidPort` | 端口不在 `1..=65535`（含 0）或非数字 | 同上 |
| `MalformedUrl` | 结构畸形（空串、缺段、userinfo 拒绝） | P06 非法 Location → 返回原响应 |
| `UnsupportedScheme` | 非 http/https | P06 降级判定 |

### 4.2 HeadersError（Builder 头校验的失败信号，FR-012）

| 变体 | 触发 | 下游用法 |
| --- | --- | --- |
| `InvalidName` | 头名为空或含非 RFC 9110 token 字符 | P02/P05 可直接透传给调用方；不得静默改名 |
| `InvalidValue` | 头值含 CR 或 LF（防头注入） | 同上——属安全类拒绝，下游不得放宽 |

**错误消息**：中文优先（宪法 VII），只携带定位片段、不回显完整原始输入
（SC-005 ② 判据，不因脱敏延后而撤销）。raise 源只有
`parse`/`resolve`/Builder 校验三处，本包其余 API 全是全函数（无 panic 路径）。

## 数据量假设

URL 与头列表尺寸按 HTTP 常规规模（URL < 8KB、头 < 100 条、单值 < 16KB）
设计；无持久化；**无包级可变状态**（脱敏不可全局配置，见 R14）——不可变值
天然线程/协程安全，四目标（native/wasm/wasm-gc/js）语义一致。
