# 契约：FR-015 关闭形态观测清单（B-10）

> 依据：spec Clarifications D2（2026-10-18）＋证据 E3/E5。
> 本清单是**元测试实测产出**，不允许手写断言代替（owner 验收口径）。

## 可观测集合（钉死）

客户端以裸 `@socket.Tcp` 读关闭后的对端，结局仅允许两类（E5 取证）：

| 结局 | 线上含义 | 客户端表现 |
| --- | --- | --- |
| `ReaderClosed` | 对端正常 FIN 收尾 | 读返回 0/EOF（`read_exactly` 抛 `@io.ReaderClosed`，reader.mbt:88-98） |
| `OSError` | 疑似 reset（不可归因承诺） | `@os_error.OSError`（context 形如 `@socket.Tcp::read()`；OSError 构造点＝`.mooncakes/moonbitlang/async/src/internal/event_loop/event_loop.mbt:541` 的 `raise @os_error.OSError(err, context~)`） |

**errno 数字不预先钉死**（2026-10-18 owner 复核裁定）：此前登记的「Windows
errno 10054」与锚点 `io_windows.mbt:136-144` 为未经复核的坏锚（`src/io/` 下
不存在 io_windows.mbt，该文件在 `src/internal/event_loop/` 且无 errno 常量），
已删除。实测字面错误文本以观测清单当次打点为准，例如 2026-10-18 本机
Windows 实测为 10053 族文案「`你的主机中的软件中止了一个已建立的连接。`」
（英文宿主为 `An established connection was aborted by the software in your
host machine.`）；不同宿主/场景的文案与数字可能不同，**如实并存记录，不作
跨场景归一**。

**不得**断言「close 必然表现为 FIN」或「必然表现为 RST」——实际表现依 OS 与
在途未读数据而变（D2/E3：公开 API 无 shutdown/SO_LINGER，close 为幂等全双工
单向关闭）。

## 观测记录行格式

```
[FR-015 观测] target=<native|wasm(moonrun)> pending_unread=<yes|no> outcome=<ReaderClosed|OSError>
```

- `pending_unread`：close 前**接收队列中存在未被读走的数据**，**双方向**
  （2026-10-18 owner 修正，把契约收窄错的措辞改回 spec.md:345 的方向中立
  原文——一致性修正，非改需求）：
  1. **客户端→夹具方向**：客户端已发请求、夹具未读走（未读请求即 close
     会在 Windows 等栈触发 RST——P03 T013 实测：PartialResponse/AcceptClose
     不 drain 即 close，四截断点 × 双 target 客户端全落 OSError）；
  2. **夹具→客户端方向**：夹具已写入响应字节、客户端未读走。
  两种前置条件都要覆盖——「带未读数据即 RST」的差异正是清单要暴露的。
- 测试内断言仅 `outcome ∈ {ReaderClosed, OSError}`；真实结局以 println 打点。

## 清单生成程序（验收流程）

1. `moon test -p hahh9527/moonhttp/internal/fixtures -f "P03-B10*" --target native --deny-warn`
   → 捕获 stdout 得 native 清单（≥2 行：pending=yes/no）。`-f` 为按测试名
   glob 过滤（2026-10-18 实测定谳），测试名遵循 P03-Bxxⓝ 约定。
2. 同命令 `--target wasm`（moonrun 宿主）→ wasm 清单（≥2 行）。
3. 两份清单随 P03 交付归档（测试日志），每行如实反映当次运行结局；
   跨机器/跨次运行结局可能不同——这正是清单的记录目的，不是失败。

## 失败口径

- 结局落在两类集合之外（如悬挂、抛出其他错误类型）⇒ 元测试失败。
- moonrun 宿主缺 socket 导入符号（宿主须同时提供 unix 与 windows 两套，
  E2）⇒ 环境问题，按夹具 wasm 口径记录，不判夹具失败。
