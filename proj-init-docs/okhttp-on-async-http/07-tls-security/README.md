# 07 HTTPS / TLS 安全（ConnectionSpec / 证书固定 / 自定义信任）

> 结论：**部分非侵入**：自定义信任（CA 替换）✅、证书固定 ✅（握手后验证路线）、明文开关 ✅。
> **ConnectionSpec（TLS 版本+密码套件清单）与客户端证书在现有 `@tls` 上无法表达——是全项目最硬的侵入项**（需动 OpenSSL/Schannel/moonrun 宿主三处后端）。

## 1. OkHttp 行为规格

- 4 种 ConnectionSpec 预设：`RESTRICTED_TLS`（最严合规）/ `MODERN_TLS`（默认）/ `COMPATIBLE_TLS`（旧服务器兼容）/ `CLEARTEXT`（http）；可配回退顺序、可自定义 TLS 版本 + 密码套件。
- **CertificatePinner**：限制受信证书/CA（SPKI sha256/sha1 pin）。
- **Custom Trust**：`sslSocketFactory + X509TrustManager` 替换平台 CA（企业内网自签等）。
- TLS 握手失败调试指引（版本协商失败 → 换 spec 重试）。

## 2. async/tls 现状（证据，探索代理核实）

| 能力 | 现状 | 证据 |
| --- | --- | --- |
| 后端 | 非 Windows native = **dlopen OpenSSL**（懒加载+版本检查）；Windows = **Schannel**；wasm = **moonrun 宿主 Rust TLS** | `tls/openssl_loader.mbt:37-58`、`schannel.c`、`tls.wasm.mbt:37-39` |
| 接口 | `Tls::client(Inner, verify?, host?, sni?, trust?)` | `tls/pkg.generated.mbti:28` |
| SNI | ✅ 默认随 host 开（Windows 不支持关） | `tls.mbt:87-89` |
| 自定义信任 | ✅ `TrustedRoot::{NoVerification; SystemRoot; CustomPemFile(String)}`（PEM 解析在内） | mbti:50、`tls.mbt:34-54` |
| 主机名校验 | ✅ 默认开 | — |
| 对端证书获取 | ✅ `get_peer_certificate() -> Bytes?`（DER） | mbti:33 |
| 通道绑定 | ✅ `unique_channel_binding() -> Bytes` | mbti:43 |
| **ALPN** | ❌（全仓 0 命中） | — |
| **TLS 版本/套件控制** | ❌（Schannel 硬编码 client 禁 TLS1.0/1.1；OpenSSL 用默认策略） | `schannel.c:146` |
| **证书固定 API** | ❌（无内建，但 DER 可取 → 可上层验证） | — |
| **客户端证书** | ❌（仅 server 侧有 key/cert） | — |
| **会话复用** | ❌ 显式 API（TLS1.3 ticket 仅连接内自然发生） | — |

## 3. 实现方案

### 3.1 L1 配置面（对齐 okhttp OkHttpClient 的 TLS 面）

```moonbit
pub struct TlsConfig {
  trust : TrustSpec                       // Default(=SystemRoot) | CustomCa(pem_path) | Insecure(=NoVerification, 仅测试)
  pinning : CertificatePinner?            // §3.3
  allow_cleartext : Bool = true           // okhttp: http:// 默认允许；false = 拒绝 http URL（RESTRICTED 部署）
}
```

### 3.2 自定义信任（Custom Trust）——非侵入 ✅

- 映射 `TrustSpec::CustomCa(path)` → `@tls.TrustedRoot::CustomPemFile(path)`，透传给 `Client::connect(trust~)`（`client.mbt:63-75` 每条 TLS 路径都接收）。
- 企业自签/中间盒场景完整覆盖；PEM 解析由 async 内建。
- `Insecure` 映射 `NoVerification`——**API 命名上刻意贬义**（对齐 reqbest `danger_accept_invalid_certs` 的处置：文档写明仅测试用），不进推荐配置面。

### 3.3 证书固定（CertificatePinner）——非侵入 ✅（握手后验证路线）

```moonbit
pub struct CertificatePinner {
  pins : Array[Pin]      // (host_pattern, algo, digest_hex)
}
priv enum PinAlgo { CertSha256 | SpkiSha256 | SpkiSha1 }
```

- 验证时机：**握手完成后**（okhttp 同款：pins 在 TLS 握手成功后、HTTP 数据前校验）——在 03 的 Connect 层拿到连接后调 `tls.get_peer_certificate()`（DER Bytes），逐 pin 校验；失败 → `raise CertificatePinningError{expected, actual}` + 连接毒化。
- 两种 pin：
  - `CertSha256`：整证书 DER 的 sha256——**零 ASN.1 依赖**，实现 ~30 行（sha256 见 §3.5）；缺点：服务端换同密钥新证书会误伤（okhttp 亦提示 cert-level pin 脆弱）。
  - `SpkiSha256/Sha1`：提取 SubjectPublicKeyInfo——需要 ~200 行 DER/ASN.1 遍历器（TLV 游标走到 Certificate→tbsCertificate→subjectPublicKeyInfo 的 OCTET STRING payload），输出 pins 与 `openssl x509 -pubkey` 工具链对齐（README 给生成命令）；稳健性最佳。
- pin 不匹配语义：无 pin 匹配且存在 pin 集 → 失败（okhttp：有 pin 列表的主机必须命中其一）；URL host 无 pin → 直通。
- 通配 host_pattern：`*.example.com` 后缀匹配（okhttp 同）。

### 3.4 ConnectionSpec（版本/套件）——【侵入 async/tls，深】

- 现实：三后端（OpenSSL dlopen / Schannel / moonrun 宿主 FFI）都未暴露版本与套件参数。
- **非侵入近似（M1 采纳）**：三个后端的默认策略本身已等价 "MODERN_TLS"：
  - OpenSSL ≥1.1 默认 TLS1.2+ 现代套件；
  - Schannel client 已禁 TLS1.0/1.1（`schannel.c:146`）；
  - moonrun Rust TLS（rustls 系）天然现代。
  → L1 只保留 `allow_cleartext` 开关 + 文档声明"当前 TLS 策略由平台默认（≈MODERN_TLS）"。
- **完整实现（侵入，建议上游 PR 路线）**：
  1. `Tls::client` 增加可选 `min_version?/max_version?/cipher_suites?` 参数；
  2. OpenSSL 路径：`SSL_CTX_set_min_proto_version` + `SSL_CTX_set_ciphersuites/cipher_list`（loader 需补两个符号绑定）；
  3. Schannel：`SEC_CHANNEL_BINDING` 前的 `SchannelCredentials` 套件 ALG_ID 配置（受 Windows 支持面限制，RESTRICTED 级别可能无法完整表达）；
  4. wasm：moonrun 宿主 `tls/connection/*` FFI 需扩协议参数（**依赖 moonrun 发版**，非我们可控）。
  → 工作量 ~2–3 人日（native 两处）+ moonrun 外部依赖；**列为 M4 可选，优先级低于 ALPN（13 依赖它）**。

### 3.5 密码学组件依赖清单

- sha256：缓存键（05）与 pinning（本篇）共用。优先 `moonbitlang/core` 若有；否则自带纯 MoonBit 实现（~120 行，含测试向量）。
- sha1：仅 SpkiSha1 兼容 pin（okhttp 遗留格式）——可先不支持（okhttp 自 5.x 已弱化）。
- base64：08 Basic 凭据共用。
- 无需引入外部 mooncake；若引 `bikallem/compress`（04 的 br/zstd）亦不冲突。

### 3.6 TLS 握手失败重试（okhttp 调试指引的对等物）

- 02 §3.3 的重试已覆盖"握手失败换路由"；spec 级回退（MODERN→COMPATIBLE）在无版本控制前无法表达——文档引用 3.4 的侵入项。

## 4. 侵入性清单

| 项 | 级别 | 说明 |
| --- | --- | --- |
| Custom Trust / pinning / cleartext 开关 | **非侵入** | — |
| ConnectionSpec（版本/套件控制） | 【侵入 async/tls：openssl_loader + schannel.c + moonrun 宿主 FFI 三处】 | §3.4；M4 可选 |
| 客户端证书（mTLS） | 【侵入 async/tls，同上三处】 | L1 无绕行（后端无 API）；列为上游 PR 候选 |
| TLS 会话复用（性能向） | 【侵入 async/tls，深】 | OpenSSL session cache / Schannel 会话缓存 / moonrun；见 14 §3.4 |
| pinning 时机前移（握手期内） | 侵入 | 平台无回调；okhttp 也是握手后校验，无功能损失 |

## 5. Target 支持矩阵

| target | 支持 | 说明 |
| --- | :-: | --- |
| native | ✅ CustomTrust + pinning（DER 可取）；spec 近似 | Windows(Schannel) 与 *nix(OpenSSL) 行为差异由 3.4 注明 |
| wasm | ✅ | moonrun Rust TLS；`get_peer_certificate` 经宿主 FFI 透传 DER（pinning 可用） |
| js | ⭕ | fetch/浏览器全接管 TLS：无 pinning/无自定义 CA（fetch 无法注入）；仅 `allow_cleartext` 语义可表达（拒绝 http URL）。文档明示 js 上安全策略=浏览器策略 |
| wasm-gc | ❌ | runtime 级缺口（16） |

## 6. 性能影响

- pinning 每连接一次 DER 哈希（典型 1–3KB 证书 → µs 级），仅新建连接时发生，池化后摊薄。
- CustomPemFile 信任库在每连接加载？——查证点：`tls.mbt:34-54` 若每次连接重读 PEM 文件则池化后可接受、高频新建连接下有放大——实现时验证并（若需要）【侵入 ~5 行】在 async 侧缓存已解析信任库（上游 PR）。
- 会话复用缺失的性能代价量化：见 `14-performance` §3.4（TLS 握手 ≈1–2 RTT + 非对称运算）。

## 7. 工作量与依赖

- 依赖：01/03（Connect 层挂 pinning）、sha256 组件（与 05 共享）。
- 估计：TlsConfig+trust 映射 ~0.5 人日；CertSha256 pin ~0.5；SPKI 提取（DER 遍历器）~1.5；测试（含 openssl 工具链对拍）~1。**~3.5 人日**（不含 3.4 侵入项）。

## 8. 测试方案

- pinning：本地自签服务端（仓库 `test_keys/` 已有测试证书基建）——命中/不命中/通配域/无 pin 直通/多 pin 备份证书轮换场景。
- SPkiSha256 与 `openssl x509 -in cert.pem -pubkey -noout | openssl pkey -pubin -outform DER | openssl dgst -sha256` 输出对拍。
- CustomCa：自签 CA 签发的服务端，CustomPemFile 信任后成功、SystemRoot 下失败。
- allow_cleartext=false 时 http URL 立即 raise（不发网络）。
