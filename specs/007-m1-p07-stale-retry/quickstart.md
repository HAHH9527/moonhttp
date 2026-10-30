# Quickstart: 连接失败重试 stale-retry（M1-P07）验证指南

> 2026-10-30。前置：P01–P06 已交付（006 分支链）；本特性分支
> `007-m1-p07-stale-retry`。

## 六门跑法（合入前逐项）

```powershell
# 1) 编译零错误零警告（双 target）
moon check --target native
moon check --target wasm

# 2) 双 target 测试全绿
moon test --target native
moon test --target wasm

# 3) 接口与格式
moon info && moon fmt
git diff --stat            # .mbti 增量对账：仅 HttpClient::new 可选参数（contracts §1）

# 4) js 编译检查（非门禁，如实记录）
moon check --target js
```

## 分场景验证

| 场景 | 命令/用例组 | 预期 |
| --- | --- | --- |
| US-1 stale 闭环（SC-002） | `moon test --target native -p hahh9527/moonhttp/client -f call_test.mbt` 过滤 `P07-US1` | 静默关闭→自动换新连接→响应正确；`stale_evictions`==1；池计数守恒 |
| US-2 建连失败预算 | 过滤 `P07-US2` | 2 次尝试后透传原始错误；池状态零变化；拒绝形态观测清单双 target 记录 |
| US-3 不可重试分类 | 过滤 `P07-US3` | B-11 MidHeaderLine→BadRequest 透传+毒化+零计数；Nothing/15B/17B→重试成功；Stream 已发送→不重试；cancel→裸 CallCancelled |
| US-4 计数精度（SC-003） | 过滤 `P07-US4` | K 次独立 stale 注入计数恰 K；Protocol/Stream/耗尽路径零误计 |
| 判定器矩阵 | `moon test --target native -p hahh9527/moonhttp/client` 过滤 `P07-WB` | decide() 全分支 + 可构造族检测直测 |
| 重放保真（SC-004） | `P07-US1`/`P07-US3` 中 Bytes 重放用例 | 捕获对端字节逐字节一致；fold_count 不变 |
| 重试+301 叠加（SC-006） | 过滤 `P07-US6`（或编号就近） | stale 恢复后跟随 301；prior 链深 1；跳数语义与 P06 一致 |

## 端到端手动冒烟（可选）

`specs/007-m1-p07-stale-retry/` 无独立可执行入口；闭环行为由上述
测试组承载（宪法 IV：网络行为全部基于本地可控夹具，无外部网络）。

## 已知观测口径

- ReaderClosed 集成形态覆盖 0B/15B/17B 三截断点（F17 实测）；RST
  不可确定性注入（F16），OSError 形态以判定器单元级直测 + 拒绝
  形态元测试（R8）承载。
- wasm 断言强度按 specs/003 FR-015 观测清单（close 形态依 OS/在途
  数据而变）；若 wasm 侧形态翻转，按清单调整断言并在测试注释记录，
  行为不降级。
