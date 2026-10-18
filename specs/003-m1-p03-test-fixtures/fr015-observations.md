# FR-015 关闭形态观测清单（B-10 实测归档）

- 生成方式：`fr015_observation_test.mbt` 实测产出（**禁止手写断言代替**），
  命令＝quickstart §3：`moon test -p hahh9527/moonhttp/internal/fixtures -f
  "P03-B10*" --target native|wasm`
- 生成日期：2026-10-18 ｜ moon 0.1.20261012 ｜ 宿主：Windows
  （wasm 由 moonrun 承载）
- 断言口径：仅「结局 ∈ {ReaderClosed, OSError}」（E5）；以下各行均为当次
  运行的真实打点。**结局依 OS 与在途未读数据而变，不构成行为承诺（D2）**。

## native 清单（2026-10-18 实测）

```
[FR-015 观测] target=native pending_unread=no outcome=ReaderClosed
[FR-015 观测] target=native pending_unread=yes direction=client->fixture outcome=OSError
[FR-015 观测] target=native pending_unread=yes direction=fixture->client outcome=ReaderClosed
```

## wasm(moonrun) 清单（2026-10-18 实测）

```
[FR-015 观测] target=wasm(moonrun) pending_unread=no outcome=ReaderClosed
[FR-015 观测] target=wasm(moonrun) pending_unread=yes direction=client->fixture outcome=OSError
[FR-015 观测] target=wasm(moonrun) pending_unread=yes direction=fixture->client outcome=ReaderClosed
```

## 形态判读（当次运行事实，非行为承诺）

- `pending_unread=no`（connect 即 close，接收队列空）→ **ReaderClosed**
  （FIN），双 target 一致。
- `pending_unread=yes direction=client->fixture`（客户端请求未被夹具读走）
  → **OSError**（RST 类），双 target 一致——夹具接收队列有未读数据时
  close 触发 RST；这正是 T013 踩响的集合外形态正源（drain 裁决 A 的依据）。
- `pending_unread=yes direction=fixture->client`（夹具写入 15B 未被客户端
  读走）→ **ReaderClosed**（FIN），双 target 一致——RST 由「发送方 close
  时**自身**接收队列有未读」触发，与对端接收缓冲的数据无关（双方向不对称，
  与 F16 登记的 Windows 行为一致）。
- 宿主差异提示：跨机器/跨次运行结局可能不同（尤其非 Windows 宿主），
  如实记录正是清单目的，不判失败。

## 遗留开口

- RST 的确定性构造仍属上游能力缺口（欠账 F16，需人工批准的上游 PR 候选）；
  本清单口径保留为跨平台事实记录。
