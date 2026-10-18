# Quickstart：P03 夹具库验证指南

> 前置：仓库根有 `moon.mod`（依赖 `moonbitlang/async@0.22.4`，钉 0.22.x）；
> moon ≥ 0.1.20261012（`--deny-warn`/`fmt --check` 存在性已核证；`-f` 过滤
> 语义＝按测试名 glob，2026-10-18 实测，research.md P-h + analyze V1）。
> 夹具宿主为 `src/internal/fixtures`（C1 裁决）。

## 1. 收口六门（合入前逐条跑，全部通过才算交付）

```powershell
# 缓存命中不算重跑：最终收口轮先 moon clean；日常轮可增量
moon clean
moon check --target native --deny-warn   # 门 1
moon check --target wasm   --deny-warn   # 门 2
moon test  --target native --deny-warn   # 门 3
moon test  --target wasm   --deny-warn   # 门 4
moon fmt --check                          # 门 5
moon info                                 # 门 6：审 .mbti diff——
# 期望：core 等既有公开包 .mbti 零 diff（夹具迁 internal 不改公开面）；
# internal/fixtures 的 .mbti 变化逐条审视（非对外承诺，但须有意识）
```

## 2. 分场景验证（对应 spec US-1～US-5）

```powershell
# 分场景元测试同包交付，按包运行即全部覆盖：
# US-1 脚本化 HTTP 场景（B-01～B-06、B-08）／US-2 裸 TCP 故障注入（B-09/B-11/B-12，
# 客户端错误落 {BadRequest, ReaderClosed}）／US-3、US-5 既有捕获自证与五缺陷回归
moon test -p hahh9527/moonhttp/internal/fixtures --target native
# core 侧断言辅助参数化回归（FR-009；002 tasks 的 T009 四条线上字节断言不回归）
moon test -p hahh9527/moonhttp/core --target native

# 需要按行为收窄时用「测试名 glob」——2026-10-18 本机实测（moon 0.1.20261012）：
# moon test 的 -f, --filter 按测试名 glob 过滤，不是按文件过滤（analyze V1 定谳）。
# 测试名遵循 P03-Bxxⓝ 约定（research.md R7），以实现期落定为准：
moon test -p hahh9527/moonhttp/internal/fixtures -f "P03-B05*" --target native
```

场景 ↔ 元测试对照：US-1 → `scripted_server_test.mbt`（B-01～B-06、B-08）；
US-2 → `scripted_peer_test.mbt`（B-09/B-11/B-12）；US-3/US-5 端到端 →
`raw_peer_test.mbt`；US-5 单元级（相位/溢出/重复头）→ `frames_scan_wbtest.mbt`；
FR-009 三形态 → `sc003_sc004_test.mbt`。

每个命令把 `--target native` 换成 `--target wasm` 再跑一轮（双绿门）。

## 3. FR-015 观测清单生成（实测产出，禁止手写）

```powershell
moon test -p hahh9527/moonhttp/internal/fixtures -f "P03-B10*" --target native 2>&1 | Select-String 'FR-015 观测'
moon test -p hahh9527/moonhttp/internal/fixtures -f "P03-B10*" --target wasm   2>&1 | Select-String 'FR-015 观测'
```

期望：各得 ≥2 行 `[FR-015 观测] target=… pending_unread=… outcome=…`，
outcome 仅取 ReaderClosed/OSError；两份清单随交付归档。行格式与失败口径见
contracts/wire-observations.md。

## 4. SC-003/SC-004 性能与确定性自证

```powershell
moon test -p hahh9527/moonhttp/internal/fixtures --target native
moon test -p hahh9527/moonhttp/internal/fixtures --target wasm
```

- SC-004：同一 >64KiB chunked 流 × ≥5 切分相位 → 判定/负载/raw 100% 一致
  （白盒矩阵 + 黑盒端到端，常驻默认套）。
- SC-003：2MB/8MB 捕获耗时（`@async.now()` 实测），断言 `t8 ≤ 5×t2` 且
  `t8 ≤ 2s`。该测试常驻默认套（修复后自缚上界，不拖门）；若 wasm 实测超
  2s：先查算法，确因 moonrun 吞吐则走 spec 变更流程附数据修订判据。

## 5. 行为清单 ↔ 元测试对账

见 plan.md「行为清单 ↔ 元测试映射表」（DoD-2 对账面：B-01～B-15，
B-07 为已裁 M1 缺口·推迟）。

## 6. 收尾（整包交付判定之后）

- 回勾 `specs/002-m1-p02-request-response/tasks.md:207-237` 的 T009
  （owner 2026-10-16 裁决：等 P03 整包交付后回勾；引用位置：002 tasks.md
  T009 条目 + 本 plan 收尾清单）。**owner 2026-10-18 常设授权：满足判据
  即可回勾、无需再次请示**——三条同时成立：① T026 六门全绿（含
  `moon clean` 后全量重跑）；② 包级 DoD 全通过（含映射表对账，B-07 按
  缺口显式标注口径满足）；③ FR/SC 覆盖核对表无缺项。**反例约束**：仅
  「002 T009 的技术内容已在 P02 交付并通过」（2026-10-16 native+wasm
  126/126）**不足以**触发回勾——勾与 P03 整包交付绑定，两者都要满足；
  判据不全时不得自主勾选。回勾时在本包留一行证据（六门结果 + 对账结论；
  与 tasks T028 同口径）。
- 汇报 `.mbti` diff 审视结论与六门输出摘要（宪法开发工作流节）。
