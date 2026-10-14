# 契约：HeadersV 与 HeadersVBuilder（M1-P01 core 包公开 API）

**包**：`moonhttp/core`。底层存储 `Array[(CaseInsensitiveString, String)]`
（复用 `@http.CaseInsensitiveString`，research R2）；存储形态是实现细节，
契约以语义为准。错误变体清单见 [data-model.md §4.2](../data-model.md)。

## Builder（可变，构建期使用）

```moonbit
fn HeadersV::builder() -> HeadersVBuilder        // 空容器
/// 追加；名/值校验失败 raise HeadersError，容器不变。
fn HeadersVBuilder::add(self, name : String, value : String) -> Unit raise
/// 删全部同名后追加一条；校验同上。
fn HeadersVBuilder::set(self, name : String, value : String) -> Unit raise
/// 删全部同名；对非法名静默无操作（不 raise）。
fn HeadersVBuilder::remove(self, name : String) -> Unit
/// 产出不可变值
fn HeadersVBuilder::build(self) -> HeadersV
```

## 值（不可变）

```moonbit
fn HeadersV::get(self, name : String) -> String?       // 首个（大小写不敏感）
fn HeadersV::values(self, name : String) -> Iter[String]  // 保插入序全部（不折叠）
```

`values` 返回迭代器是接口形态（决策 M2-A）；**验收断言一律先收集为数组**
（`values("accept").to_array()` 之类）再 `assert_eq`，契约的语义承诺是
「按插入序给出该名字的全部值」，与具体迭代器类型无关。

## 边界折叠（进入 @http 执行管线）

```moonbit
/// 同名值以无空格逗号 "," 合并为单值（FR-005）。
/// 与 @http 响应侧 parser 的 "\{v0},\{v}" 逐字节对称。
fn HeadersV::to_http_map(self) -> @http.Headers
```

**折叠的两个不变量（SC-003，决策 H1-A——原「折叠后 `get` 首个语义不变」
在存在重复名时必然为假，已弃用）**：

1. **无重复名**：折叠对单值名是恒等映射，折叠后每个名字的 `get` 值与折叠前
   逐字节相等。属性测试按此生成**唯一名**列表。
2. **有重复名**：折叠值 = 按插入序以 `,` 无空格拼接；且该串经 @http 响应侧
   parser 拆分可**还原**原名值序列（进出互逆）。以确定性用例覆盖。

## 调试输出与脱敏（FR-013 / SC-005）

```moonbit
/// 手写 impl Debug（不 derive）：敏感头值脱敏后的调试形态。
impl Debug for HeadersV with to_repr(self, h) { ... }

/// 显式逃生口：输出未脱敏形态，仅供特殊排查。
/// 建议名 debug_unredacted；最终命名在 .mbti 冻结时定案。
fn HeadersV::debug_unredacted(self) -> String
```

1. `Authorization`、`Proxy-Authorization`、`Cookie`、`Set-Cookie`（名字
   大小写不敏感匹配）的值 MUST 输出脱敏占位；其余头名/值原样输出。
2. **必须手写 `impl Debug`**——`derive(Debug)` 读不到任何脱敏逻辑，会逐条
   原样打印名/值对（research R13；`@debug` 实测不可作用户工程依赖，无法借用）。
3. 脱敏只作用于**输出层**：判等与哈希仍看原值（契约条款 1、2 不受影响）。
4. 明文只可经**显式调用的逃生口方法**取得。本包 MUST NOT 提供包级可变的
   掩码开关（决策 N4-A）；运行期可配置掩码随 M3 的 Logger/EventListener
   设计，见欠账 **F12**（`docs/roadmap/deferred-items.md`）。
5. **测试与 `.snap` 快照 MUST NOT 使用逃生口**——明文头值不得进入版本库。
   URL 用户信息一侧由 FR-008 拒绝 userinfo 达成，本包不存在携带明文凭证的
   URL 值。

## 契约条款

1. **不可变性**：`build()` 后值永不变化 → 判等/哈希恒稳，可安全作 P04
   Address 池键（clarify 2026-10-13）。
2. **顺序语义**：插入序参与判等与哈希（「同 URL + 同头序」的 Vary 键与
   重放字节级一致前提）。
3. **大小写不敏感**：名字查找/删除/覆盖均按 ASCII 大小写不敏感；原名字符
   串原样保留（不强制小写化存储，to_string/折叠时按存储原样输出）。
4. **折叠语义**：`add("X-Multi","a")` + `add("X-Multi","b")` 折叠后单值
   `"a,b"`；空容器折叠为空 Map；值为空串的头合法保留。
5. **折叠例外（文档级承诺）**：值内 quoted-string 逗号不保证边界
   （`WWW-Authenticate: Basic realm="a, b"` 折叠后语义可能受损）；认证路径
   M2 绕过此转换（08-auth）。
6. **输入校验（FR-012）**：头名必须为非空 token（RFC 9110 token 字符）；
   头值不得含 CR/LF（防头注入）；违例 Builder 操作 raise `HeadersError`
   （`InvalidName`/`InvalidValue`，见
   [method-error.md](method-error.md)）。

## 验收锚点（对齐 spec US-3/US-4）

| 操作 | 结果 |
| --- | --- |
| Builder `add("Accept","a")`、`add("Accept","b")` → build | `values("accept")` 收集为数组 = `["a","b"]`，`get("ACCEPT")` = `"a"` |
| Builder `set("Accept","c")` → build | 同名仅剩 `"c"` |
| 两次相同顺序构造相同头列表 | 相等且哈希一致 |
| `X-Multi: a` + `X-Multi: b` → to_http_map | 单值 `"a,b"` |
| 空容器 → to_http_map | 空 Map |
| `add("Bad Name","v")` / `add("X","a\r\nY: 1")` | raise `InvalidName` / `InvalidValue`，容器不变 |
| `add("X","")` | 合法，值保留为空串 |
| `remove("Bad Name")` | 静默无操作，不 raise |
| `add("Authorization","Bearer secret")` → build → 调试输出 | 含头名与脱敏占位，**不含** `Bearer secret`；同一容器判等/哈希不受影响 |
