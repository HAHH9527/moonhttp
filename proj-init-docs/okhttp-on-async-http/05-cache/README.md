# 05 缓存（HTTP Response Cache，RFC 7234）

> 结论：**非侵入可实现**，但为全项目工作量最大的单一特性。缓存天然盖在执行器之上、与底座解耦（既有对比研究 §3.4 同判断：底座差异为零）。

## 1. OkHttp 行为规格

- 可选磁盘缓存：目录 + 最大字节数；默认关闭。目录被单实例独占。
- 遵循 RFC + 对齐浏览器/服务器现实行为（OkHttp 为此维护大量特例，如无 `Cache-Control` 时按 `Last-Modified` 10% 启发式新鲜度）。
- 三种事件场景：**命中 / 未命中 / 条件命中**（304 后合并缓存与网络响应），经 EventListener 暴露（06）。
- `FORCE_NETWORK`（`Cache-Control: no-cache`）/ `FORCE_CACHE`（`only-if-cached`；无可用缓存返回 504）。
- **响应体必须被完整读取（或取消/停滞处理）才会写入缓存**。
- 管理 API：`delete()`、`evictAll()`、按 URL 迭代器精确移除。

## 2. async/http 现状（证据）

- 零缓存设施（全仓 grep；`@async/fs` 可用作落盘 IO）。
- 对缓存友好的既有行为：
  - 条件 GET 只是普通请求头注入（`extra_headers~` 任意头可用）；
  - **304 空 body 语义已正确**：`should_not_have_body(_, 304) = true`（`parser.mbt:379-386`）——条件命中不会误读连接残留；
  - 响应头已是 `Map[CaseInsensitiveString, String]`，日期/数字解析需自写（`Date`、`Age`、`Cache-Control` 令牌解析器）；
  - 响应体流挂在连接上（01 §3.6）——缓存写入需 tee（§3.4）。

## 3. 实现方案

### 3.1 位置与类型

```
CacheInterceptor（04 链中，RetryAndFollowUp 之后、Connect 之前）
  ├─ CacheStrategy：RFC 7234 §4 决策（freshness / revalidate / bypass）
  ├─ Store trait：抽象存储（native=磁盘 LRU；js=内存；测试=注入）
  └─ Entry：URL 键 + vary 键 + 响应头 + 请求头快照 + body
```

```moonbit
pub struct HttpCache {
  store : CacheStore            // trait：put/get/remove/urls/clear/size
  max_size : Int                // 字节
  directory : String?           // None = 内存
}
pub trait CacheStore { ... }    // 或函数字段 struct，风格与 04/08 一致
```

- **磁盘存储设计（简化版 DiskLruCache）**：键 = url 的 sha256 hex；两文件制（`<key>.meta` JSON：头/vary/请求快照/时间戳；`<key>.body` 原始字节）；journal.txt 记录 put/get/remove 追加日志，启动重放并按 LRU 淘汰到 max_size。目录锁：单实例独占（启动时创建 `.lock`，已存在则 raise `CacheDirInUse`——okhttp 同语义）。
- 淘汰精度：不做 okhttp 的严格 LRU 分代，采用 journal 重放频率近似——文档说明差异。

### 3.2 CacheStrategy（决策核心，对齐 okhttp CacheStrategy）

```
可缓存性（写入侧，RFC 7234 §3）：
  GET ∧ 200（或 410）∧ 无 no-store ∧ 无 Set-Cookie（okhttp 现实规则）
  ∧ (Authorization 头存在 → 必须有显式 fresheness 指令：s-maxage/public/must-revalidate)
  ∧ 完整响应（非 206/无 Content-Range）

新鲜度计算（读取侧）：
  response_age = max(apparent_age, corrected_age)   // Date 头 + Age 头 + 响应接收延迟
  freshness_lifetime = s-maxage? > max-age? > Expires-Date > (Last-Modified-Date)*10%（启发式）
  fresh ⇔ response_age < freshness_lifetime
  指令覆盖：请求 no-cache → 总是 revalidate；响应 no-cache → revalidate；
           only-if-cached(请求) → 仅缓存，miss 返回 504 GatewayTimeout（本地构造，okhttp 同款）
  min-fresh / max-stale 支持（RFC 指令，okhttp 实现）
```

- `Cache-Control` 令牌解析器（~100 行）：指令名、`=`、参数、引号值、大小写不敏感、未知指令容忍。
- HTTP 日期复用 11 §3.2 的解析器（同一组件）。

### 3.3 条件命中（Conditional Hit）

```
revalidate: 请求注入
  ETag 存在    → If-None-Match: <etag>          （强优先，okhttp 同）
  否则 Last-Modified → If-Modified-Since: <date>
304 到达 → 合并：以缓存头为基底，用 304 响应头覆盖可更新字段（Date/ETag/Cache-Control 等），
  body 用缓存副本 → 返回 200 语义响应（对应用户不可见合并，RFC 7234 §4.3.4）+ 事件 conditional_hit（06）
304 外的响应（200 新内容/410/…）→ 覆盖缓存条目
```

### 3.4 Body tee（流式响应的缓存写入）

- `CacheInterceptor` 命中"可缓存 + 可流式"时：不阻塞用户读——`ResponseBody.stream` 包装为计数+tee Reader：用户每读一块，同步写进 store 的写缓冲；**读完成**（EOF 或精确读完 Content-Length）→ 提交条目；中途放弃/取消 → 丢弃部分写入（okhttp "响应必须完整读取才缓存"同语义）。
- 已缓冲响应（`buffered`）：直接整体写入。
- 大 body 内存上界：tee 经 store 的分块写（如 32KB），磁盘 IO 在事件循环线程池侧（`@async/fs` 文件 IO 走 thread pool，AGENTS.md 注明）不阻塞用户读路径——但注意写放大：每块一次 `fs.write` 调用。

### 3.5 Vary 处理

- 响应带 `Vary` 时，条目键扩展：`url + hash(sorted(请求中 vary 头的值))`（okHttp `CacheStrategy` 的 varyKey 同构）。
- `Vary: *` → 不可缓存。
- 二次请求时按同键匹配，请求头值不同即 miss。

### 3.6 管理 API

- `HttpCache::{evict_all, remove(url), urls() -> Iter[String], delete_dir}`（对齐 okhttp Cache 同名 API；`remove` 走 `store.remove`，迭代器惰性列目录）。

## 4. 侵入性清单

| 项 | 级别 | 说明 |
| --- | --- | --- |
| 全部缓存逻辑 | **非侵入** | L1 拦截器 + fs + sha256（sha256 需自带或 core 提供，~100 行纯 MoonBit） |
| 304 语义 | 非侵入 | 底座已正确（`parser.mbt:379-386`） |

## 5. Target 支持矩阵

| target | 支持 | 说明 |
| --- | :-: | --- |
| native / wasm | ✅ | 磁盘 + 内存双模式（wasm 的 fs 依赖宿主注入，16） |
| js | ⭕ | 仅内存 store；可选进阶：映射到浏览器 **Cache API**（`caches.open/match/put`，经 `js_async` 桥）——能力对齐甚至更强，M3 扩展 |
| wasm-gc | ❌ | runtime 级缺口（16） |

## 6. 性能影响

- 命中：**省整整一次网络往返**（含 TLS 握手若连接已驱逐）+ 服务端处理——在池化收益（47–56×）之上再叠加，是延迟敏感场景的第二杠杆；量化基准进 `14-performance`（hit/miss/conditional 三态）。
- 代价：磁盘写放大（tee 每块一写）；命中率低的场景应在 HttpClient 配置中不装 CacheInterceptor（默认关闭，okhttp 同）。
- 元数据小（头 JSON <1KB），索引全内存 Map（启动 journal 重放构建，条目多时启动成本 O(n)——文档建议 max_size 上限）。

## 7. 工作量与依赖

- 依赖：01/04（拦截器挂点）、11 §3.2（日期解析器共享）、sha256 组件。
- 估计：Cache-Control/日期/策略 ~2.5 人日；Store 磁盘+journal+LRU ~2；tee/条件命中合并 ~1.5；Vary ~1；管理 API ~0.5；测试（移植 okhttp CacheTest 代表用例 + RFC 场景）~2.5。**~10 人日**——建议拆两期：内存缓存（4 天）先行，磁盘持久化后补。

## 8. 测试方案

- okhttp CacheTest 场景移植（其测试是公开的最完整 RFC 现实行为矩阵）：max-age/expires/启发式/no-cache/no-store/only-if-cached/max-stale/min-fresh/Vary/Age/Date 歪钟/304 合并/30x 不缓存/Set-Cookie 拒缓存。
- tee 中途取消 → 缓存无残留半条目；journal 重放后 LRU 正确。
- 双实例同目录 → 第二个 raise。
- 并发同 URL 命中/写入竞态（单线程事件循环下天然串行，断言无重复提交）。
