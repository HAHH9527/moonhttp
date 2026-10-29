# 最终复核（round9-qoder-final-verify）— 006-m1-p06-redirects

- **特性**：自动重定向 follow-up 循环（M1-P06）
- **执行日期**：2026-10-27 ｜ **执行者**：qoder（独立交叉复核方，工单⑪·analyze 环收口步）
- **输入**：`analyze/round8-opencode-fixes3.md`（履行 round7 判定）＋ `analyze/round7-opencode-verify.md`（判定原文）＋ 磁盘产物全量实测
- **只读声明**：除本文件外零写入、零 git 写操作（仅 `git status/log/diff` 只读查询与 `moon --version`）；未触碰 3 个 `pkg.generated.mbti`（只读 diff 观察）；未运行 `moon test/info/fmt` 等任何可写命令
- **取证限制（沿用申报）**：外部 OkHttp 取证仓不可达——5.5.0 行号断言（R1/spec 映射表/data-model:34-39 对应段/R6:202 closeQuietly 序）仍属「产物内部自洽」面，收口判按 owner 既定分工口径计（round7 双盲亦同此限），不阻塞放行

---

## A. 逐条对账表（round8 八条处置 → 实测 → 结论）

| # | round8 条目 | 实测磁盘锚点 | 落盘 | 与日志一致 | 新矛盾 |
|---|---|---|---|---|---|
| W1-改1 | spec US-6-2（日志:30-38） | spec.md:155-157 现文「旧租约干净归还回池（同址后续租借可复用）、新 host 新建连接（新建连接计数 +1；`Connection: close` 中间响应的关闭分支归 FR-009/Edge Cases，不在本场景）」——与日志「改后」逐字吻合 | ✅ | ✅ | 无 |
| W1-改2 | spec FR-007（日志:40-48） | spec.md:257-259 现文「跨 host 跳 MUST 干净归还旧租约（回池、同址后续租借可复用）……关闭处置是另一分支，见 FR-009」 | ✅ | ✅ | 无 |
| W1-改3 | spec SC-003（日志:50-60） | spec.md:299-302 现文「……旧连接干净回池、同址后续租借可复用（US-6-2，池/夹具计数双断言；语义收窄见 Assumptions W1 裁决）」 | ✅ | ✅ | 无 |
| W1-改4 | spec Assumptions W1 裁决（日志:62-69） | spec.md:342-345 新增条目在场（插于 C4 裁决 :334-341 之后，位置与日志声明一致） | ✅ | ✅ | 无 |
| W1 一致性 | 「应零改动项实测零改动」（日志:71-85） | tasks T013 :249-255（断言句 :251「旧 host 连接干净回池（后续同 Address 租借可复用）」）未动 ✅；data-model INV-6 :129-130、三态图 :153、伪码 :23「跨 host 干净回池」未动 ✅；research R6 :193「干净连接回池，P04 契约」未动 ✅；T017 :305 在场未动 ✅；US-6 导语 :141-142「旧连接被正确处置」伞形未动（与日志声明一致）✅；R6 备选② :215-216「跨 host 直接 poison——否决」在场，owner 方案 B 与设计面同向实核 ✅ | ✅ | ✅ | 无 |
| W2 | plan 新增「`.mbti` 对账基线口径」小节（日志:95-107） | plan.md:120-132 小节在场（Structure Decision :114-118 之后、四个决策节 :134 之前——与日志「插于 Structure Decision 之后」吻合）；四要点齐：①基线=git HEAD 提交态（§1/§2/§3 同理）②漂移=Int→Int32 工具链再生成（未提交/无 .mbt 伴随/非 P06 产物）③不随 P06 交付、T001 不入账、baseline.md 标注义务、T017 提交时门复验 ④仅登记不碰文件 | ✅ | ✅ | 无 |
| W2 归因复测 | 磁盘/git 可验部分（我方独立重跑） | `git status --porcelain` 仅 3 份 `.mbti` M + 未跟踪 specs/006，**无任何 `.mbt` 伴随** ✅；`git diff` client：`Address::hash/new(port~)/port`、`ConnectionPool::new/per_host_total/stale_evictions` 等全量 `Int→Int32` ✅（core 10 处/fixtures 16 处成对改写，--stat 26+/26-）；client `.mbti` 末次提交 = 309e890（P05 骨架）✅；本机工具链实测 `moon 0.1.20261023` > plan.md:29 所钉 0.1.20261012——「再生成显示差异」归因成立且有版本差佐证。**W2 三项事实主张全部磁盘复核** | ✅ | ✅ | 无 |
| I1 | plan 账目 2 处 + tasks 1 处（日志:116-133） | plan.md:56-60「改 5 文件（……call_wbtest.mbt 适配……后三者 P05 已在场非新建，round8 I1 补账）」；plan.md:108 文件树新增 `call_wbtest.mbt # 改（P05 已在场，增补）`；tasks.md:39-40 Path Conventions 补「`call_wbtest.mbt` 适配（T003，P05 已在场）」；「5 处=字样计数、实调用点 3 处」观察与 round2 我方实测（call_wbtest.mbt:366/:378/:633 直调 + :350/:353 引用）一致 | ✅ | ✅ | 无 |
| I2 | T010/T015 首跑即绿纪律注记 ×2（日志:147-155） | tasks.md:198-200、:284-286 两处注记在场，含「首跑颜色须实测记录」「不得事后补造红灯」——前提（T005 已落 resolve 主路径 :195-197；T002 Terminal 先行 :282-283 原文自述）实测成立 | ✅ | ✅ | 无 |
| I3 | 「剥两 头」笔误 ×3（日志:166-174） | data-model.md:71/:72 现文「跨 host 剥两头」；research.md:282「跨 host 字节不含两头」；:73 现文「（跨 host 剥）」确无笔误——**round7 锚点订正（:73 系误记）经磁盘复核成立**，opencode 如实采认 | ✅ | ✅ | 无 |
| I5 | Phase 9 INV-2 窗口分期注记（日志:183-187） | tasks.md:294-297 注记在场（Purpose :292 之后、T016 :299 之前）；前提复核：T005 :139-140「保留 T004 最小 advance」、T012 :246-247「替换 T005 的最小 advance」——窗口描述与任务文本一致 | ✅ | ✅ | 无 |
| Q-B3 | R3 记号口径注记（日志:204-210） | research.md:87-91 注记在场（「产物内 `exchange_*(request)` 为参数化后目标形态记号；P05 实况 `exchange_once(self)`/`exchange_with_lease(self, lease)` 读 `self.request`（exchange.mbt:78/:91）——实现以实况签名为准」）；源码复核 exchange.mbt:78/:91-94 实况签名精确 ✅；data-model.md:162「仅参数化（request 入参）」口径与之兼容 | ✅ | ✅ | 无 |
| N-1 | 读法约定成文（日志:229-232） | data-model.md:48-50 归属注记尾新增「红侧/断言文本中的 `poison_release` 字样均指**可观测结果**……不指调用位点——读法约定成文（round6 N-1，round8 落笔）」；与 tasks.md:238-240 红侧措辞、R6 :195-196「skip 失败路径已 poison」构成闭环 | ✅ | ✅ | 无 |
| 残留扫描 | 六组旧措辞活产物零残留（日志:263-265） | 我方独立 grep：`不再被后续租借复用/归还或关闭/归还/关闭/剥两 头/不含两 头/改 4 文件` 于 spec/plan/tasks/data-model/research/contracts/quickstart/checklists **零命中**（rc=1）✅；仅存 analyze/ 历史报告（按授权不回改） | ✅ | ✅ | 无 |
| 写范围 | 5 产物 + 本日志，其余零触碰（日志:13-15/:287-291） | mtime 实测：spec 14:22:49 / plan 14:22:49 / research·data-model 14:23:15 / tasks 14:23:33 / round8 日志 14:27:28；contracts 12:33:39、quickstart 11:42:20、checklists 11:25:38 未变；3 份 `.mbti` 未被本轮触碰（仍为 M 态）；`src/` 无写入痕迹（git status 无新增 M） | ✅ | ✅ | 无 |

**统计**：round8 八条处置（W1×4、W1 一致性面、W2、I1、I2、I3、I5、Q-B3、N-1、残留扫描、写范围共 **14 个对账面**）——**属实 14 / 不符 0 / 新矛盾 0**。

---

## B. 最终一致性结论

1. **W1 传导完整性：完全同向。** SC-003（spec:299-302）／US-6-2（:155-157）／FR-007（:257-259）三条新文与 T013 断言句（tasks:251）／INV-6（data-model:129-130）／三态图（:153）／伪码注释（:23）／R6（research:193）逐字同向；`Connection: close` 分支由 FR-009 显式互指、与 US-6-2 新文划界清晰；R6 备选② poison 否决（:215-216）证明方案 B 为设计面唯一自洽选择。**owner 裁决已完整落笔且无离群残留。**
2. **SC-003 取证路径可判定：是。** T013 = 双实例计数（新 host 新建 +1：`accepted_total` 增量按实例归属）+ 同址复用断言（对旧 host 地址再发请求，`conn_request_counts` 同连接 +1 且该实例 `accepted_total` 不增）——两断言均落 P03 夹具既有计数面（fixtures mbti:81/:83，round2/round7 双复核在场），P04 池契约保证复用语义确定性，无挂死/无歧义路径；T017（tasks:305）「SC-001～007 逐条记录证据测试名」在 SC-003 收窄后取证对象明确。**验收判据不可取证的问题已消除。**
3. **W2 口径与 contracts 自洽：是。** contracts §1/§2/§3（:4/:6/:15/:47/:55）原文只写「对账面/期望零 diff」**从未定义基线**——plan:120-132 的「基线 = git HEAD 提交态」是补定义而非改定义，无文本冲突、无外溢（contracts 零触碰实证）。T001「不入账 + baseline.md 标注」与 T017「提交时门复验」两头闭合；残留面仅剩「收口门 `moon info` 在新工具链（实测 0.1.20261023）下会整体重写 `.mbti` 为 Int32 形态」——该面已被「提交时门复验」口径覆盖并转成 owner 的有意识决定项，不构成规格矛盾。
4. **round7 判定闭环复核：** round7 D 节两项必修（W1/W2）均如实修复；16 项历史台账 round7 判 15/16 闭环 + N-1 本轮补落笔 = **16/16 全闭环**（N-1 磁盘实证见 A 表）。round7 I4（≈D1，记录性）/I6（≈Q-B5，六门双轨）不在工单⑩授权清单、round8 未处置——与授权范围一致，非遗漏。
5. **宪法 MUST 面（收口抽查）：** I（全公开 API，skip_response_body 上游 mbti:80 在场）／III（差异登记面自洽；5.5.0 行号未独立复核，边界已申报）／IV（FR-002 失败半边承载 + US-1-4/5 黑盒落点 + 首跑颜色纪律注记，三项测试先行缺口全闭）／V（target 矩阵显式）／VI（公开面增量=两件套、3 priv 字段、`.mbti` 基线口径钉死）／VII（全中文）——**无 MUST 级冲突。**

---

## C. 残留/新增问题清单

| ID | 级别 | 锚点 | 事实 |
|---|---|---|---|
| R9-1 | INFO（登记精度，非改动） | round8 日志:266-270 行号漂移登记表 | 该登记自身有 ±1 级偏差：spec Scale/Scope 实为改后 :56-60（登记「:56 后 +1」，插入点在 :57）；日志:217 称 N-1 注记「改后 :48-50」，实为新增文本居 **:48 尾句-:50**（:48 本身为原注记末行）；均属首/末行归属精度差，**内容改动本身全部实测在场**，不构成不符 |
| R9-2 | INFO（既有漂移，未修） | round7 日志:54（`HttpClient::new_call` 记 mbti:53）、:58（`Response::from_http` 记 :156）、:59（`Response::prior` 记 :158） | 我方 mbti 只读实测：new_call=:41、from_http=:158、prior=:160——round7 三处行号系自身 +4/+2 漂移（其 I3 勘误仅覆盖 research.md 侧，未回刷 B 节本表）；**结论均正确、仅引用位失准**。归档件不回改惯例下维持登记，供 implement 期引用换算（叠加 round5 §三、round8 日志:266-270 两张换算表使用） |
| R9-3 | INFO（存量 open，不阻塞） | round2 Q-B4/Q-B5(=round7 I6)/Q-B6/Q-B7/Q-B8(=I4 相关) | 五条 INFO 历史授权范围未覆盖、仍未落笔：六门成员双轨（quickstart:9-16 ↔ tasks T001）、FR-001 轮间取消租约处置未成文、「C1」编号双指、R7 21 跳链「+ 终态 mount」注记、checklists 勾选项口径。均记录级/口径级，**不构成 implement 阻塞**；建议 owner 视情况并入 implement 期或作废 |
| R9-4 | 记录（取证边界） | 本文件 B 段引言「取证限制」 | ①5.5.0 行号断言面未独立复核（外部仓不可达，round1/7/9 三轮同限）；②C-3 过程归因维持 round6「部分消解——不可判定证据边界项」判，owner 接受归因后该台账项即可视为处置完毕（本轮无新证据改变判法） |

**CRITICAL：0 ｜ WARNING：0 ｜ 新增 INFO：3（R9-1/R9-2/R9-3）+ 边界登记 1（R9-4）**

---

## D. 最终总结判

## **通过收口（放行 implement）**

一句话：round8 八条处置 14 个对账面全部属实、零不符、零新矛盾——W1 owner 方案 B 五文件传导完全同向、SC-003 取证路径经夹具计数面实证可判定；W2 基线口径（git HEAD）经我方 git/mtime 独立复测成立且与 contracts 零 diff 条款自洽互补；旧措辞六组活产物零残留、六项写入范围申报与 mtime 全表吻合；16 项历史台账全闭环。残留 R9-1/R9-2（引用行号精度）与 R9-3（五条授权外 INFO）均为记录级、不阻塞，随 implement 期按登记表换算处置即可。

*报告结束。生成：qoder 工单⑪ @ 2026-10-27 ｜ 唯一写入：本文件。*
