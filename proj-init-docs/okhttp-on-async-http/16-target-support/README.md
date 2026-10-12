# 16 Target 支撑策略（native ≥ wasm > wasm-gc > js）

> 按用户给定的优先级 `native >= wasm > wasm-gc > js` 落到工程决策：native 与 wasm 共享同一代码路径且能力等价；wasm-gc 被上游 runtime 整体阻塞；js 是能力降级的独立适配层。

## 1. 底座 target 现状（证据）

| 层 | native | wasm | js | wasm-gc | 证据 |
| --- | :-: | :-: | :-: | :-: | --- |
| 事件循环/IOCP/epoll/kqueue | ✅ | ✅（宿主注入） | ✅（js_async 桥 Promise） | ❌（CI 仅 `moon check`，README.md:67） | AGENTS.md、check.yml:182 |
| socket | ✅ | ✅ moonrun 宿主 TCP 直通（**非** websocket 桥） | ❌ | ❌ | `ffi.wasm.mbt`、moon.pkg:22-43 |
| tls | ✅ OpenSSL(dlopen)/Schannel | ✅ moonrun 宿主 Rust TLS | ❌ | ❌ | 07 §2 |
| http 客户端 | ✅ | ✅ 同源 | ✅ **fetch 后端**（独立实现 `client.js.mbt`） | ❌ `unimplemented.mbt:17` | moon.pkg targets |
| http 服务端 | ✅ | ✅ | ❌ | ❌ | moon.pkg |
| fs | ✅ | ✅（宿主） | ❌ | ❌ | — |
| websocket | ✅ | ✅ | ❌（L1 桥补，12 §3.3） | ❌ | unimplemented |
| gzip / timer / semaphore / task_group | ✅ | ✅ | ✅ | ❌ | — |

## 2. L1（easyhttp）的 target 策略

### 2.1 native / wasm：同一路径（最高优先级）

- 所有特性（01–15 除 js 注记外）单一代码路径；`Client::connect` 的 native/wasm 实现同构（`client.mbt` targets）。
- wasm 验证环境：moonrun；`examples/curl` 等既有示例可作 smoke。差异点仅有：socket 错误分类（宿主映射）、TLS 后端（Rust TLS）——03 的 stale-retry 与 07 的 pinning 测试需在 wasm 单独跑一轮。
- **结论：native 与 wasm 并列 P0，无额外工作量**（只多一轮测试执行）。

### 2.2 wasm-gc：上游阻塞，明确不做（P2 观察）

- 阻塞链：async runtime 的 event_loop/socket/tls/io 均无 wasm-gc 实现（CI 只做编译检查防 API 腐化）。这不是 L1 能绕过的（fork 整个 runtime 不可取）。
- L1 处置：`moon.pkg` 不为 wasm-gc 编译核心包；提供一个 `#cfg(target="wasm-gc")` 的 stub 包，`HttpClient::new` 直接 `raise UnsupportedTarget("wasm-gc: blocked upstream (moonbitlang/async)")`——**明确报错优于静默缺席**。
- 跟进条件：上游 runtime 支持 wasm-gc（跟踪其 issue/路线图）；届时 L1 大概率免改或小改（adapter 与 native 同构）。
- 若业务强需 wasm-gc：替代路线是 js 桥（wasm-gc 可走 JS 互操作）→ 等价于 §2.3 的 js 适配层 + 互操作成本——列为咨询项而非承诺。

### 2.3 js：fetch 适配层（P1，能力降级清单）

设计：L1 核心（类型/配置/拦截器骨架/缓存策略/构造器）全 target 编译；**传输适配器**按 target 分：

```
native/wasm → @http.Client 路径（全能力）
js          → FetchTransport：包装 @http.Client（其 js 后端即 fetch，client.js.mbt）
              + 12 §3.3 的浏览器 WebSocket 桥
```

js 降级清单（写进用户文档的对照表，逐项已在各篇 §5 标注）：

| 特性 | js 表现 |
| --- | --- |
| 连接池/连接事件/DNS 事件 | 无意义（浏览器管理）；池层退化为直通 |
| 重定向 | 浏览器自动跟随（`client.js.mbt` 未设 redirect 选项）；`priorResponse` 不可用 |
| 超时 | 仅 callTimeout 生效（AbortController 已接，`client.js.mbt:195-202`）；connect/read/write 降级 |
| 代理 | 不支持（fetch 禁） |
| Cookies | 浏览器自管（`Response.cookies` 恒空）；L1 Jar 建议 off |
| TLS 控制/pinning | 不可用（浏览器策略） |
| 流式上传 | 需整块缓冲（`client.js.mbt:132-139` 本就缓冲）；大上传内存警示 |
| WebSocket | 浏览器原生桥（headers 受限） |
| 缓存 | 内存 store；可选映射浏览器 Cache API（05 §5） |
| 拦截器 | 应用层可用；网络层退化（无连接概念） |
| 每请求 Server | 不存在（js 无服务端）——L1 不受影响（我们只做客户端） |

- **适配层工作量**：~2 人日（FetchTransport 薄包装 + 降级语义的 cfg 分支 + 文档）。
- 优先级说明：用户排序 js 最低，但 fetch 适配"顺手可得"（@http 已做重活），故实际成本≈0，与 wasm-gc 的"硬阻塞"形成对照。

## 3. CI 与发布矩阵

| 维度 | 门禁 |
| --- | --- |
| native | `moon test --target native` 全量（含网络用例按 AGENTS.md 的 DNS 代理注意事项分流） |
| wasm | `moon check src --target wasm` + `moon test --target wasm`（moonrun）核心子集 |
| js | node + 浏览器双跑（enqueue/cancel/fetch 路径） |
| wasm-gc | `moon check --target wasm-gc` 仅编译通过（stub 包） |

发布：`moon.mod` `preferred_target = "native"`；README 的能力矩阵引用本篇 §2.3 对照表。

## 4. 工作量

- wasm 验证轮 ~1 人日；js 适配 ~2 人日；wasm-gc stub ~0.5 人日。**合计 ~3.5 人日**（不含上游 runtime 的 wasm-gc 工作）。
