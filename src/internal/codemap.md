# src/internal/

## Responsibility

内部实现细节包的命名空间父目录：其下各包均为 moonhttp 的内部支撑设施，不对外发布为公共 API，
公共面只经 `src/core` / `src/client` 暴露。

## Integration

- `fixtures/`：回环测试夹具库（@http 声明式编排服务端 `ScriptedServer`、裸 TCP 程序化对端
  `ScriptedPeer`、线上帧判定 `FrameScanner`），仅供各包测试引用，详见其 `codemap.md`。
