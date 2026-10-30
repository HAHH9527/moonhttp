# Quickstart: M1-P08 四类超时与 per-call 配置

**Branch**: `008-m1-p08-timeouts` | 前置：P03–P07 已交付（007 tip）

## 六门（质量门，全部通过为合入判据）

```powershell
moon info && moon fmt          # 门 1：接口/格式干净，.mbti diff 恰 contracts §1 四项
moon test --target native      # 门 2：native 全绿（含既有全量回归）
moon test --target wasm        # 门 3：wasm 全绿
moon check --target js         # 门 4：错误数 = 13（基线持平零新增）
moon test --target native      # 门 5：断网环境复跑门 2（SC-009 零外部网络）
# 门 6：grep 审计——无外部地址（仅 127.0.0.1/localhost），无敏感信息输出
```

## 分场景跑法（验收场景 → 定位）

| 场景 | 命令片段（`-p <pkg> -f <file>` 过滤） | 期望 |
| --- | --- | --- |
| US-1-2/1-3/1-4 四类触发 | `moon test --target native -p hahh9527/moonhttp/client` | `HttpTimeout::{Read,Write,Call}` 各判别命中，C1 带内 |
| US-2 读按操作重置 | 同上（Drip/DripHang 场景） | 滴流完整读零超时；滴后静默一窗触发 |
| US-3 毒化守恒 | 同上（池计数断言场景） | idle 不含、INV-5 守恒、R5 竞态收敛 |
| US-4 派生隔离/共享 | 同上（builder 场景） | B 超时 A 正常；连接计数共享 |
| US-5 call 伞×重试/取消 | 同上（ServeSequence 组合场景） | `stale_evictions` 恰 1；反向隔离裸 `CallCancelled` |
| US-6 跟随开关 | 同上（301 两态矩阵） | 关闭 ⇒ 3xx 终态 + `prior() is None` |
| 判定器矩阵（FR-008） | `moon test --target native -p hahh9527/moonhttp/client`（wbtest） | 四变体族落点断言（R5 口径） |
| 决策表两门（FR-010） | 同上（follow_up wbtest） | 门序 5.5.0 对拍断言 |

## 端到端手动冒烟（可选）

无外部可执行入口（library 包）；手动冒烟经 `moon test` 场景集即等价
（全部行为级场景有黑盒载体，见上表）。js 侧无冒烟义务（宪法 V 未验
证面，仅门 4 对账）。

## 落地物索引

- 公开面用法：[contracts/timeout-api.md](contracts/timeout-api.md) §1
- 接线点位/状态机：[data-model.md](data-model.md) 实体 4/5
- 设计决策与取证：[research.md](research.md) R1–R12
- 验收语义：[spec.md](spec.md) US-1–US-6 / SC-001–SC-010
