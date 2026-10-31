# hahh9527/moonhttp — Repository Codemap

基于 `moonbitlang/async` 公开 API 构建的 OkHttp 对齐 HTTP 客户端（MoonBit，
`preferred_target = "native"`）。项目治理见 `AGENTS.md` 与
`.specify/memory/constitution.md`（宪法：仅经公开 API 使用 moonbitlang/async；
项目文档全部使用中文；验收场景与测试先行）。

## Root Assets

- `moon.mod` — 模块元数据：`source = "src"`（仅 src 参与构建），依赖
  `moonbitlang/async@0.22.4`。
- `AGENTS.md` — 代理工作约定（Spec Kit 流程、编码规范、工具链）与本仓库图入口。
- `README.md` — 项目简介。
- `.specify/` — Spec Kit 规格驱动开发配置与项目宪法。

## Repository Directory Map

| Directory | Responsibility | Link |
|-----------|----------------|------|
| `src/` | 源码根；三个构建内包的命名空间父级 | [View Map](src/codemap.md) |
| `src/core/` | 核心 HTTP 值模型层：`HttpUrl`、percent 编解码、`HeadersV`、`Method`、`Request`/`RequestBody`、`Response`/`ResponseBody`、错误模型、`Request::to_http_request` 纯转换；无网络 IO | [View Map](src/core/codemap.md) |
| `src/client/` | 用户客户端层：`HttpClient` 门面与 builder 派生面、`Call` 状态机、`ConnectionPool`（Address 分桶 LIFO + keep-alive）、四级超时伞（call/连接/写/读——看门者形态）、`exchange_once` 管线、recover 判定器、`BodyBridge` 体桥接与租约处置 | [View Map](src/client/codemap.md) |
| `src/internal/` | 内部支撑包命名空间，不对外发布为公共 API | [View Map](src/internal/codemap.md) |
| `src/internal/fixtures/` | 回环测试夹具：`ScriptedServer` 声明式编排服务端、`ScriptedPeer` 裸 TCP 程序化对端、私有 `FrameScanner` 帧边界判定 | [View Map](src/internal/fixtures/codemap.md) |
| `bench/` | T009 独立复核用一次性诊断/性能探针归档（独立 moon 模块：`bench/moon.mod`+`bench/moon.work`；根构建/门禁不感知） | [View Map](bench/codemap.md) |

## Architecture at a Glance

```
用户代码
   │  new_call(Request) → Call::execute()
   ▼
src/client  HttpClient → ConnectionPool.acquire(Address) → exchange_once
   │           │ folded headers / 发体 / 收头 / Connection: close 毒化
   ▼           ▼
src/core    Request::to_http_request → @http.Request；Response::from_http ← 上游响应
   │           ResponseBody 事件（Consumed/Dropped/Abandoned）驱动租约回池/毒化
   ▼
moonbitlang/async 公开 API（@http / @io / @async.Mutex / task group / cancellation）
```

- 依赖方向唯一：`client → core`；测试域经 `src/internal/fixtures` 回环夹具驱动。
- `bench/` 各探针独立成包、互不依赖，`cd bench && moon run <探针> --target native` 独立运行（夹具用 bench/fixtures 冻结快照）；根构建/门禁不感知。

## Codemap Scope

代码图覆盖实现源（`*.mbt`）与包配置（`moon.pkg`）及 `moon.mod`；黑盒/白盒测试
（`*_test.mbt`/`*_wbtest.mbt`）与生成接口（`*.mbti`）不入图。状态与变更检测存于
`.slim/codemap.json`（`codemap.mjs changes` 检测差异、`update` 固化）。
