# 契约：Method 与两个错误类型（M1-P01 core 包公开 API）

**包**：`moonhttp/core`。变体清单的**唯一规范源**是
[data-model.md §4](../data-model.md)，本文件只给签名形态与调用约定。

## Method（九值封闭枚举）

```moonbit
pub enum Method {
  Get; Post; Put; Delete; Head; Options; Trace; Patch; Connect
} derive(Eq, Hash, Debug)

// 消除 implicit_impl_as_method [0079] 的配套写法（research R4，决策 N1-A）：
pub extend Method with Eq::{not_equal, equal}
pub extend Method with Hash::{hash, hash_combine}
pub extend Method with Debug::{to_repr}

/// 与 @http.RequestMethod 一一对应（封闭映射，无失败分支）。
fn Method::to_request_method(self) -> @http.RequestMethod
fn Method::from_request_method(m : @http.RequestMethod) -> Method
```

**契约条款**：

1. 与 `@http.RequestMethod`（`types.mbt:16-26`）九值一一对应；双向映射
   全覆盖、无 `Custom`/失败分支（spec FR-007，用户裁决 Q2-B 裁剪）。
2. 无大小写规范化问题（枚举封闭，不接受字符串构造）；与 OkHttp「任意
   method token」的差异已在 spec A6 显式记录。
3. 判等/哈希 derive + 显式 `pub extend`，供 Request 值组合与测试断言。
4. **不使用 `derive(Show)`**——本工具链对 `derive(Show)` 报 deprecated_syntax
   警告 [0027]，与 SC-004「零错误零警告」互斥（决策 N1-A）。

## HttpUrlError（URL 解析失败，raise 专用）

```moonbit
pub enum HttpUrlError {
  InvalidHost       // host 非法 / 非 ASCII / IPv6 括号畸形
  InvalidPort       // 端口不在 1..=65535（含 0）或非数字
  MalformedUrl      // 结构畸形（空串、缺 scheme/host、userinfo 显式拒绝）
  UnsupportedScheme // 非 http/https
} derive(Debug)
```

**契约条款**：

1. 变体粒度为 clarify 2026-10-13 裁决（四变体）；下游 P06/P07 按变体判别
   降级策略（如非法 `Location` → `MalformedUrl`/`UnsupportedScheme` →
   返回原响应）。
2. **只 derive `Debug`**，不 derive `Eq`/`Hash`（错误不参与池键，判别用 `is`
   与模式匹配即够；`UnsupportedScheme` 若携带 payload，`Eq` 需递归 derive，
   属无收益公开面）；同样不使用 `Show`（决策 M5-A + N1-A）。
3. 错误消息中文优先（宪法 VII），只携带定位片段、不整体回显原始输入
   （敏感信息掩码在错误上下文一侧的最小适用面）。
4. `parse`/`resolve`/Builder 校验是唯一 raise 源；本包其余 API 全部全函数
   （无 panic 路径）。

## HeadersError（头校验失败，FR-012 引入）

```moonbit
pub enum HeadersError {
  InvalidName    // 头名为空或含非 RFC 9110 token 字符
  InvalidValue   // 头值含 CR 或 LF（防头注入）
} derive(Debug)
```

**契约条款**：

1. **已定案为独立小枚举**（决策 H2-A）：不再在「并入
   `HttpUrlError::MalformedUrl`」与「独立类型」之间二选一——URL 错误类型
   承载头错误语义错位，且下游无法只继承「校验」这一半义务。
2. `add`/`set` 校验失败即 raise 且**容器不变**；`remove` 对非法名静默
   无操作（不 raise）。
3. derive 组合与 `HttpUrlError` 一致：仅 `Debug`，无 `Eq`/`Hash`/`Show`。
4. 本条为安全类 MUST，P02/P05 按此继承，不得放宽为静默清洗或截断。

## derive 与公开面冻结的关联约定

本包全部值类型（`HttpUrl`/`HeadersV`/`HeadersVBuilder`/`Method`）
`derive(Eq, Hash, Debug)` 后**紧随**三行 `pub extend`，否则按契约写法调用
`equal`/`hash`/`debug_inspect` 会触发 `implicit_impl_as_method` 警告 [0079]。
由此进入 `.mbti` 的方法名一并计入 T018 的公开面冻结清单逐条核对
（宪法 VI）。`HeadersV` 的 `Debug` 属例外——手写 `impl Debug` 做脱敏，
见 [headers.md](headers.md)。
