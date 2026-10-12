# 11 Cookies（CookieJar）

> 结论：**非侵入可实现**。底座已有完整的 Set-Cookie 解析（`Cookie` 结构），缺存储/匹配/回发三层——全部在上层。

## 1. OkHttp 行为规格

- `CookieJar` 接口：`load(url) -> List<Cookie>`（构造 Cookie 请求头）/ `saveFromResponse(url, cookies)`；无内置实现（okhttp-core 只给接口与解析，用户选 PersistentCookieJar 等生态实现）。
- Cookie 匹配（RFC 6265）：domain 后缀匹配（域 cookie vs host-only）、path 前缀匹配（最长）、secure（仅 https）、过期（Max-Age 优先于 Expires）、httpOnly。
- 跨 host 重定向时 Cookie 头由 Jar 按新 URL 重新计算（02 §1）。

## 2. async/http 现状（证据）

- **解析已有**：`Cookie::parse`（`cookie.mbt:43-105`）覆盖 name/value/path/expires_raw/max_age/domain/secure/http_only/extensions 属性——与 okhttp `Cookie.parse` 的字段面基本一致。
- `Response.cookies : Array[Cookie]` 收集所有 Set-Cookie（`parser.mbt:280-281`、`types.mbt:51-55`）。
- **无**：Jar、Cookie 请求头自动注入、Expires 日期解析（`expires_raw` 只存原串）、序列化回写（`Cookie::write_to` 是**服务端** Set-Cookie 方向，`cookie.mbt:109-132`；客户端 Cookie 头是 `name=value; ...` 平铺，方向不同）。
- js 后端：`Response.cookies` 恒空（浏览器禁读，`types.mbt:53-55` 注释）。

## 3. 实现方案

### 3.1 接口（函数字段，挂 HttpClient）

```moonbit
pub struct CookieJar {
  save_from_response : (HttpUrl, Array[Cookie]) -> Unit
  load_for_request   : (HttpUrl) -> Array[Cookie]
}
```

- Bridge 层（04）接线：请求前 `load_for_request(url)` 非空 → 注入/合并 `Cookie` 头（用户在 Request 显式设置的 Cookie 头优先级：okHttp 行为是 Jar 与手动头共存会发两行；我们选**Jar 注入仅当请求未显式设置 Cookie**，差异写入文档）；响应到 `save_from_response`（含 02 的中间响应——okhttp 对中间响应同样保存）。

### 3.2 内存 Jar（库内置 `InMemoryCookieJar`，对齐 okhttp-core 之外生态）

```
存储：Map[String /*domain key*/, Array[CookieEntry{cookie, host_only, creation}]>
  - 域规范化：去前导 '.'、小写；Set-Cookie 带 Domain 属性 → 域 cookie（host_only=false），否则 host-only
  - 匹配：url.host == cookie.domain 或 host.endswith("." + domain) 且 host 非全域后缀误匹配
    （如 ".com" 拒绝——最小公共后缀黑名单，内置 ~30 项（com/org/net/edu/gov/io/co/...），okhttp 无 PSL、我们同样以黑名单近似）
  - path 匹配：RFC 6265 §5.1.4（默认 = 设置路径的目录）
  - secure：url.scheme==https 才回发
  - 过期：expires_at() = max_age 优先（parse 已给出 Int64，`cookie.mbt:74-76`），否则解析 expires_raw
  - 逐条淘汰：同 (name,domain,path) 覆盖；总数上限（默认 500，超出按 LRU/最旧过期淘汰）
```

- **Expires 日期解析（必要新组件）**：`expires_raw` 是原串（如 `Wed, 21 Oct 2026 07:28:00 GMT`）。实现 RFC 1123 / RFC 850 / asctime 三格式宽容解析器（~120 行 + 用例）——okhttp 内部同样是三格式兼容（CookieJar 测试矩阵可移植）。解析失败 → 会话 cookie（不下盘）。

### 3.3 持久化 Jar（可选组件，对齐 PersistentCookieJar）

- `FileCookieJar(path)`：启动时全量载入（JSON Lines，`Cookie` 已 derive(ToJson)，`types.mbt:69`——补 FromJson 手写 ~30 行）；写策略：变更后异步落盘（防抖 1s）。
- 依赖 `@async/fs`（native/wasm）；js 无 fs → 仅内存（§5）。
- 序列化字段补 `host_only` 与 `expires_at` 计算值（避免启动时重复解析）。

### 3.4 客户端 Cookie 头序列化

```
Cookie: name1=value1; name2=value2      // 按 path 长度降序、同长按创建时间升序（RFC 6265 §5.4 顺序）
```

- ~20 行；值不再编码（RFC 6265 cookie-value 原样）。

## 4. 侵入性清单

| 项 | 级别 | 说明 |
| --- | --- | --- |
| Jar / 匹配 / 回发 / 持久化 | **非侵入** | 纯上层 |
| Expires 预解析 | 非侵入（可选小 PR） | 【侵入 async/http，~10 行】上游在 `Cookie::parse` 里直接把 expires_raw 解析成 Int64 存 max 字段，全生态受益；L1 先自带解析器 |

## 5. Target 支持矩阵

| target | 支持 | 说明 |
| --- | :-: | --- |
| native / wasm | ✅ | 全功能（含文件持久化） |
| js | ⭕ | fetch 下 `Response.cookies` 恒空（浏览器禁读）→ save 侧无数据，Jar 只能用于**主动 set**（load 侧注入 Cookie 头——fetch 允许自定义 Cookie 头仅在同源/特定场景，浏览器可能剥离）；**js 上推荐关闭 Jar、交给浏览器 document.cookie**，文档明示 |
| wasm-gc | ❌ | runtime 级缺口（16） |

## 6. 性能影响

- load/save 每 URL 一次 Map 查找 + 小数组扫描（cookie 数典型 <50）：µs 级以下。
- Cookie 头拼装每请求一次小 Bytes 分配（仅在存在 cookie 时）。

## 7. 工作量与依赖

- 依赖：01（HttpUrl/Bridge 挂点）、04（Bridge 接线）。
- 估计：接口+内存 Jar+匹配 ~1.5 人日；日期解析器 ~0.5；持久化 ~0.5；测试 ~1。**~3.5 人日**。

## 8. 测试方案

- 匹配矩阵（移植 okhttp CookieTest 的代表性用例）：host-only vs 域 cookie、前导点、子域、path 目录规则、secure、httpOnly（不回发给非 http API——我们无该区分，仅保留标记）。
- 过期：Max-Age 与 Expires 冲突优先级、负 Max-Age 立即失效、三格式日期、垃圾日期→会话 cookie。
- 覆盖：同名不同 path/domain 共存。
- Bridge 注入：与手动 Cookie 头的共存策略断言；中间响应（重定向）保存断言。
