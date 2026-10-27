# src/

## Responsibility

模块源码根目录（`moon.mod` 的 `source = "src"`）：承载 moonhttp 的全部构建内包，
按 MoonBit「一目录一包」组织。本目录自身无源文件，是三个包的命名空间父级。

| 子包 | 职责 | Codemap |
| --- | --- | --- |
| `core/` | 核心 HTTP 值模型层：URL/percent/headers/method/request/response/错误模型与出站纯转换，无网络 IO | [codemap.md](core/codemap.md) |
| `client/` | 用户客户端层：`HttpClient` 门面、`Call` 状态机、`ConnectionPool`、`exchange_once` 管线、`BodyBridge` 体桥接 | [codemap.md](client/codemap.md) |
| `internal/` | 内部支撑包命名空间（不对外发布） | [codemap.md](internal/codemap.md) |

## Integration

- 依赖方向唯一：`client → core`；`core`/`client` 的测试另引用 `internal/fixtures`，
  运行时依赖不经过该包。
- 全部经 moonbitlang/async 公开 API 使用上游（宪法不可妥协项）。
