# T004 红绿记录（B-14 + B-15 驱动辅助）

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
