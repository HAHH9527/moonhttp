# T004 红绿记录（B-14 + B-15 驱动辅助）

> 2026-10-18 起兼任 Phase 4 过程账目（未红判据、竞态事实、工具链异常观察
> 的集中留痕处，owner 要求不入静默）。

- 日期：2026-10-18 ｜ 任务：specs/003-m1-p03-test-fixtures/tasks.md T004
- 宪法 IV 红绿纪律产出：先落元测试（红）→ 最小实现转绿；未红判据与防御性
  分支按下文显式记录，无静默。

## 红绿过程（native + wasm 双 target 实测）

| 判据 | 测试 | 红阶段观测 | 绿阶段 |
| --- | --- | --- | --- |
| close 后新操作在超时上限内立即返回 | ⑨ | **红，原因符合预期**：close 后 `capture_one` 内 `accept()` 在已关闭句柄上 raise `OSError("@socket.TcpServer::accept(): An operation was attempted on something that is not a socket.")` 直接逃逸——夹具确缺优雅关闭语义 | `closed` 位短路：已关闭即返回 `complete=false` + note「夹具已关闭（stop 后不再接受新连接）」，实测 ~0ms（< 500ms 上限） |
| stop 后不再接受新连接 | ⑩ | **红，红因勘定见下节** | 钉死夹具可控不变量转绿 |
| `close()` 幂等 | ⑧ | **未红**：上游 `TcpServer::close()`（tcp.mbt:176-178）委托 `IoHandle::close()`，二次 close 天然无害——上游语义已满足 | 作为护栏测试保留 |
| `port()` 恒 > 0 | ⑧ | **未红**：① 连通性自证已覆盖同判据；bind :0 回填路径稳定 | 作为护栏测试保留 |

## ⑩ 红因勘定（宿主能力缺口，非夹具缺陷，D2 同族）

- 红阶段 ⑩ 原判据「close 后 connect 被拒且限时返回」失败形态＝connect
  **悬挂 ≥1s 无任何结局**（非快速 ECONNREFUSED）。
- 独立探针（即用即删，未入提交）在裸 `@socket.TcpServer/Tcp` 层复现同一悬挂
  ——与夹具无关，归因宿主/上游 connect 路径对「拒绝」结局的送达缺失。
- 处置（沿用本包 D2/E5/FR-015 既有口径）：判据重定为夹具可控不变量
  「**stop 后发起的连接绝不得到夹具的任何服务**」（读到任何应答字节＝集合外
  形态即 fail）；客户端 connect 的宿主形态（快速拒绝/悬挂/连接后无服务）以
  `println("[P03⑩ 观测] …")` 留痕，不作跨宿主断言。
- 双 target 实测留痕（2026-10-18 本机 Windows）：
  - native：`close 后 connect 悬挂（1514ms 内无结局；宿主形态，不判失败）`
  - wasm/moonrun：`close 后 connect 悬挂（1520ms 内无结局；宿主形态，不判失败）`
- 此事实供 T015（B-10/FR-015 观测清单）引用；不构成行为承诺。

## 防御性分支未测（显式记录，T026 对账点）

- **bind :0 冲突自动重试分支（`bind_retry = 3`，FR-011）未测**：bind :0 由 OS
  分配空闲端口，冲突几乎不可达，无构造性驱动手段（耗尽临时端口不可接受）。
  已实现防御性代码（重试 ≤3 次后原样上抛最后一次错误）与块注释标注
  （raw_peer.mbt `bind_retry` 处），未构造驱动用例——按 T004 要求显式登记，
  不静默。

## 绿阶段门禁（Phase 2 收口，moon clean 后全量实跑）

check native/wasm --deny-warn 通过；test native/wasm --deny-warn
**129/129**（基线 126 + 新增 ⑧⑨⑩）；`moon fmt --check` 通过；`moon info`
后 `.mbti` **零 diff**（`closed` 为 priv 字段，公开面零变化）。

---

# Phase 4 过程账目（2026-10-18 追记）

## T024 / R1 结论（owner 复核后定稿，2026-10-18）

**R1 不成立，无需走 spec 变更流程**——SC-003 的 2s 判据在 wasm/moonrun 上
以一个数量级的余量满足；「平方成本已消除」由双 target 墙钟独立佐证。

### 数值并列（三组来源，口径差异如实标注）

| 来源 | 轮次 | t2(2MB) | t8(8MB) | 比值 |
| --- | --- | --- | --- | --- |
| agent 全套件内单次 | 首测 | 49ms | 146ms | 297% |
| agent 全套件内单次 | 收口轮 | 62ms | 146ms | 235% |
| owner 全套件内单次 | 复跑 | 61/85ms | 143/160ms | 234%/188% |
| owner **隔离复跑** | native | 35–37ms | 137–140ms | **378–394%** |
| owner **隔离复跑** | wasm | 49–64ms | 168–175ms | **273–344%** |

### 诚实读法（防后人误判余量）

- **全套件内的单次比值（如 235%）是失真数**：t2 在全套件尾段被进程级固定
  开销（JIT/运行时已热但调度排队、缓冲池状态等）抬高，分母变大导致比值
  被压低——**不要拿它评估线性余量**。
- **隔离复跑才是诚实读数**：native 378–394%、wasm 273–344%——隔离态比值
  ≈3.9×，与「4 倍数据量下线性期望 ≈4×」精确吻合——**平方成本已消除**的
  佐证正是这个比值贴着线性期望，而非远低于它。
- 余量评估：隔离态 t8（137–175ms）对 2s 判据有 **11 倍以上余量**；
  双 target 形态一致。
- 处置：按 plan 风险表 R1 的处置顺序，「先查算法、确因宿主则走 spec 变更」
  ——实测落在第一格：算法线性成立、宿主未触限，**判据无需修订**。

## 未红判据（显式记录，无静默）

| 任务 | 测试/判据 | 未红原因 |
| --- | --- | --- |
| T012 | B-09 客户端结局 | T011 骨架的未实现收尾（accept→close）与 AcceptClose 语义同形——骨架吸收红 |
| T013 | ①字节计数之 Nothing 例 | Nothing 预期 0 字节，与骨架（0B close）同形 |
| T013 | ②客户端错误落集合（骨架期） | 骨架 0B close 时客户端已落 ReaderClosed（集合内）——该层的弱化防护由①字节计数承担 |
| T015 | CloseObservation 结局断言 | 骨架未实现分支的 close 收尾与 CloseObservation「accept 后 close」语义同形（同 T012） |

## B-11 竞态事实与 drain 裁决（owner 裁决 A，2026-10-18）

- **竞态实测**：骨架版 Nothing（不写直接 close）落 ReaderClosed；同路径
  转绿版 Nothing 落 OSError——同一 socket 行为两种结局＝判据踩在竞态上
  （close 时接收队列是否有未读数据依时序而定，结果依 OS 与在途数据而变）。
- **集合外实录**：未 drain 时四截断点 × 双 target 客户端错误全部落
  `OSError`（`@socket.Tcp::read()` 连接中止类）——未读请求即 close 在
  Windows 触发 RST，@http 错误面（D3/E4 推演的 BadRequest/ReaderClosed）
  根本未被触达。
- **裁决 A 落地**：drain 无条件内置（不加公开枚举字段）——read_frame 读尽
  请求后按 CutPoint 上线前缀再 close ⇒ close 走 FIN ⇒ 消除竞态。
- **修复后实测形态（四截断点 × 双 target 全绿 + 各连续 5 次零翻转）**：
  Nothing → ReaderClosed；MidStatusLine(15) → ReaderClosed；
  AfterStatusLine → ReaderClosed；MidHeaderLine(8) → **BadRequest**
  （F17 登记的 read_until 残余串下移形态的实证）。双 target 形态一致。

## 工具链异常观察（owner 指定复核，2026-10-18）

- **现象**：T012 期间 `scripted_peer_test.mbt` 被清空——提交 4cd3911 的
  `git show --stat` 显示该文件仅 1 行（`| 1 +`），`git show 4cd3911:<path>`
  内容 0 字节；发现于 T013 编辑时（edit oldString 失配 → 文件 1 字节）。
- **复核**：当前工具链（moon 0.1.20261012）对照实验——新写 73B 合法测试
  文件 → `moon fmt` → 内容保留，**不可复现**；无最小复现步骤可提供。
- **处置**：按 owner 要求如实登记「不可复现」；账目留痕（本文件）。
  建议后续对 fmt 前后的文件长度做廉价自检（如 CI diff 空文件告警）。

## 「unused_package 怪癖」证伪（owner 可逆探针复核，2026-10-18）

- **原登记（已证伪作废）**：此前记录「unused_package 检查不统计 error
  构造器（@io.ReaderClosed）在模式/is/表达式位置的引用」——**误判**，推测
  来自更早的某个中间态（当时 `_io_pkg_marker`/`ignore` 规避代码与真实
  引用并存，未做单变量对照）。
- **owner 证伪实验（可逆探针，双变体）**：
  - 变体1（只删 `_io_pkg_marker = @io.pipe()` 行）：
    `moon test --target native --deny-warn -p
    hahh9527/moonhttp/internal/fixtures` → 无 unused_package、27/27 绿；
  - 变体2（再加删 `ignore(@io.ReaderClosed)`）：同样无告警、27/27 绿。
- **结论**：`e is @io.ReaderClosed` 的引用**已正常计入**包使用，无需任何
  规避标记。两处标记已删除（`@io.pipe()` 在 native 上创建永不关闭的 OS
  管道句柄，属已知高危 API，无理由调用本身即风险面）。
- **真实存在的类型语义要点（保留，非怪癖）**：`try EXPR catch {...}
  noraise {...}` 的 noraise 分支拿**成功值**——try 块内手动再包 `Ok(...)`
  会产生双层 Result（T008/T013 各踩一次，with_timeout_opt 推导可证）。

## B-11 修复后形态的首个 BadRequest 实证（P07 判据证据，2026-10-18）

- **实测行**（drain 裁决 A 落地后，四截断点 × 双 target + 各连续 5 次
  零翻转中的稳定形态）：`MidHeaderLine(8) → BadRequest`——本套件**首次
  实测出 BadRequest**。
- **含义**：印证 spec E4/D3 的推演路径——服务端写入 25 字节（状态行 17 +
  头行前 8 字节「Content-」）后 close，客户端 `read_until` 在 EOF 时拿到
  Some(残余串)（reader.mbt:217-224），残串作头行无冒号 → parser.mbt:404
  抛 BadRequest。这是 **P07「不可重试」分支判据的直接证据**。
- **口径提示**：可观测集合 {BadRequest, ReaderClosed} ≠ 可重试集合（F17）；
  ReaderClosed（EOF 路径）可重试、BadRequest（协议错误族）不可重试但毒化
  ——分流判据归 P07，本夹具只钉可观测面。
- 同族实证：Nothing/MidStatusLine(15)/AfterStatusLine 三例 → ReaderClosed
  （EOF 路径），双 target 形态一致（B-11 竞态自证 10/10 零翻转）。

## 勾选态偏差（2026-10-18）

- **事实**：commit 01ff4d1 的 message 声称「勾选 Phase 6（T017–T022）」，
  实际仅勾选了 T018–T022 五项，**T017 漏勾**（tasks.md:103 保持 `- [ ]`）。
- **连带**：后续 Phase 7/8 的 T023/T024/T028 勾选与 002 T009 回勾
  （45ea3dd）都建立在 T017 已勾的错误认知上，且 T025/T026/T027 亦漏勾——
  形成「依赖项未勾而依赖项已勾」的顺序倒挂（host 独立复核发现）。
- **本次补齐口径（工单 L-1，commit 5ddc684）**：T017/T025/T026/T027 四项
  补勾，并在各条尾部就地补回补锚点（引用 host 实测行号/数字：frames.mbt
  :65/68/71 三常量、.mbti 归因两类与 core 零 diff（a05dd81）、六门
  160/160 双 target 与对账行号、frames.mbt:5–23 与 fr015-observations.md
  44 行）。`- [ ]` 计数自证为 0。
- **历史不改写**：01ff4d1 的 message 保持原样（如实反映当时的操作疏漏）；
  本节即为偏差记录与补齐凭据。