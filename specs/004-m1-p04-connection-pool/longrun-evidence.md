# Longrun 双证据记录（P04 T018，包级 DoD-1 归档）

> 执行时间：2026-10-21 ｜ 分支：`004-m1-p04-connection-pool`
> 机制：C5 主案——`#skip` 默认排除，显式执行经 `--include-skipped`
> （research R8）。执行命令（quickstart §3）：
>
> ```powershell
> moon test -p hahh9527/moonhttp/client -f "P04-LONGRUN*" `
>   --include-skipped --target native
> moon test -p hahh9527/moonhttp/client -f "P04-LONGRUN*" `
>   --include-skipped --target wasm
> ```

## 三连回归自检（T018 首步）

`-p` 全包名 + `-f` + `--include-skipped` 三连（R8 唯一未实测组合）实测：

```text
Total tests: 2, passed: 2, failed: 0.
```

`Total tests:` 非 0——非 `-p` 假绿；skip 条目真实执行（证据行见下）。

## 证据一：native（P04-LONGRUN①）

```text
[P04-LONGRUN① native] total=10000 池内新建=25 最大单连接请求数=400 stale=0
Total tests: 2, passed: 2, failed: 0.
```

- 规模：10 000 请求（40 波 × 25 任务 × 10 请求/租约），池 max_idle=32
- 外部证据：`accepted_total() == 25 == next_conn_id - 1`（无泄漏）
- 内部证据：`borrowed(0) + idle(25) + closed(0) == 25`（不变量 5）
- 复用度自证（F-6）：最大单连接请求数 400（≥2，keep-alive 复用真实发生）
- stale_evictions = 0（长跑零驱逐，符合 keep_alive 300s 场景设定）

## 证据二：wasm/moonrun（P04-LONGRUN②，分档降额 2000）

```text
[P04-LONGRUN② wasm] total=2000 池内新建=25 最大单连接请求数=80 stale=0
Total tests: 2, passed: 2, failed: 0.
```

- 规模：2 000 请求（8 波 × 25 任务 × 10 请求/租约）——wasm 分档数值为
  本任务校准定案（moonrun 吞吐约为 native 的 1/5～1/10，2000 请求单次
  显式运行秒级完成，满足「≤ 数分钟」上限；t004-record.md 的吞吐分档
  口径在此落为 10k:2k ≈ 5:1）
- 外部证据：`accepted_total() == 25 == next_conn_id - 1`
- 内部证据：`borrowed + idle + closed == 25`
- 复用度自证（F-6）：最大单连接请求数 80（≥2）

## skip 主案核证（默认套）

```text
moon test -p hahh9527/moonhttp/client --target native --deny-warn
Total tests: 29, passed: 29, failed: 0.   # 长跑条目不计数
moon test -p hahh9527/moonhttp/client --target wasm --deny-warn
Total tests: 29, passed: 29, failed: 0.
```

与 R8 核证一致：`#skip` 条目默认不计数；`--include-skipped` 时计数恢复
且真实执行。

## 备注

- 长跑池配置 max_idle=32 ≥ 波内并发 25：首波 25 条新建后全量复用，
  无连接churn——accept 预算（25）精确可判，dummy 兜底路径零触发。
- 时间推进零 sleep（R2）；判据只用双证据，禁 fd 计数（C-7/Q04）。
