# Quickstart: Call 执行骨架与取消（M1-P05）验证指南

**前置**：repo 根 `E:\Project\moonhttp`；moon 工具链；无外部网络依赖
（SC-006：全部测试仅访问 P03 本地夹具/loopback，断网可跑）。

## 0. ⚠️ `-p` 假验证警示（沿 004）

`moon test -p` 只认全包名（如 `hahh9527/moonhttp/client`）；写目录路径会
跑 0 个测试却 exit 0（假绿）。所有分包命令执行后检查 `Total tests:` 非 0。

## 1. 收口六门（合入门禁，命令逐条）

```sh
moon check --target native --deny-warn
moon check --target wasm --deny-warn
moon test  --target native --deny-warn
moon test  --target wasm --deny-warn
moon fmt --check
moon info   # 审 .mbti diff：core = contracts §2（且仅此）；client = contracts §1
```

`.mbti` 对账：`src/core` 增面必须恰好等于 `ResponseBody::stream` 增参 +
`dispose`（FR-015 裁决面）；`src/client` 等于 contracts §1；fixtures 零
diff（若 F-8 触发 1xx 夹具扩展，增面逐处归因 FR-010）。最终轮先
`moon clean`。

## 2. 分场景验证（黑盒 `P05-*`，`-p hahh9527/moonhttp/client`）

| 场景 | 过滤 | 期望 |
| --- | --- | --- |
| US-1 execute/复用/Connection:close/chunked | `-f "P05-US1*"` | code/headers/body 正确；连续 3 请求新建连接数=1；close 后 +1；未知长 Stream 以 chunked 发送（`CapturedRequest.chunked`） |
| US-2 一次性语义 | `-f "P05-US2*"` | 完成/失败/取消后二次 execute raise `CallStateError`（`err is` 判别） |
| US-3 取消三阶段 | `-f "P05-US3*"` | 预取消零网络（accepted_total==0）；慢收/滴流中 cancel→`CallCancelled`+毒化（池计数断言）；is_cancelled/重复 cancel 幂等 |
| US-4 重放零折叠 | `-f "P05-US4*"`（白盒） | 折叠计数==1；N 次捕获 raw 两两 `assert_eq` |
| US-5 体生命周期 | `-f "P05-US5*"` | 读到底回池；读半→`dispose()`→skip 回池+下个请求干净流；skip 失败（PartialResponse+断连）→毒化 |

## 3. 白盒与竞争专项

```sh
moon test -p hahh9527/moonhttp/client -f "P05-WB*"
```

覆盖：状态机迁移（I-1）、折叠缓存（I-2）、租约唯一处置与迟到 cancel
（I-3/FR-012：读到底→release→cancel→下个 execute 复用且新建不增）、
取消收尾仅同步（I-6）。

## 4. js 非门禁项（D14/F9）

```sh
moon check --target js   # 仅编译验证；不写 #cfg(js) 分支
```

可行时 node 冒烟（execute+cancel 直通）；失败不阻塞合入，登记欠账。

## 5. 完成判据对账

- 六门全绿 + `.mbti` 对账零计划外（SC-007）。
- SC-002/003/004/005 的池计数与字节级断言全部在 §2/§3 套件内
  （双证据：夹具 accepted_total + 池侧计数）。
- `moon info && moon fmt` 干净；宪法自查（I/III/IV/V/VI/VII）随 PR 记录。
