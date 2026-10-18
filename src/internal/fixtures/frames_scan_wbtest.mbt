///|
// frames_scan_wbtest：FrameScanner 判定内核的白盒元测试（FR-006/FR-007/
// FR-008 单元级；端到端见 sc003_sc004_test.mbt 与 raw_peer_test ①–⑦）。
//
// 相位矩阵（SC-004）：同一条 >64KiB chunked 流按 {1, 7, 100, 8191, 8192,
// 8193} 字节切分喂入（含劈中大小行的相位），判定/负载/原始字节必须逐相位
// 全同——判定确定性＝feed 纯推进、与读取分片相位无关（FR-006）。

///|
// 构造 >64KiB chunked 流：第一块 0x19000(=102400B)，使**第二块大小行**落在
// 流内绝对偏移 >64KiB 处——现行实现误用「流内绝对偏移」充当大小行上界，
// 在这些相位会假 Broken（缺陷 1 的直接实测点）。
fn big_chunked_stream() -> Bytes {
  let buf = Buffer()
  buf.write_bytes(
    b"POST /big HTTP/1.1\r\nHost: h\r\nTransfer-Encoding: chunked\r\n\r\n",
  )
  buf.write_bytes(b"19000\r\n")
  buf.write_bytes(FixedArray::make(102400, b'a').unsafe_reinterpret_as_bytes())
  buf.write_bytes(b"\r\n")
  buf.write_bytes(b"800\r\n")
  buf.write_bytes(FixedArray::make(2048, b'b').unsafe_reinterpret_as_bytes())
  buf.write_bytes(b"\r\n")
  buf.write_bytes(b"0\r\n\r\n")
  buf.to_bytes()
}

///|
let matrix_phases : Array[Int32] = [1, 7, 100, 8191, 8192, 8193]

///|
// 期望负载：102400 个 'a' + 2048 个 'b'（与 big_chunked_stream 对应）
fn expected_payload_len() -> Int32 {
  102400 + 2048
}

///|
// 相位矩阵：基准相位（一次性喂入）与六种切分相位的终态判定/负载全同；
// 且**任何相位、任何累计时刻都不得出现 Failed**（合法 chunked 流的中途
// 判死即缺陷 1 的假 Broken——T018 红阶段实测留痕：现行实现相位 1 在偏移
// 102467 处假 Broken「chunk 大小行超出上限仍未出现 CRLF」）。
async test "P03-WB① 相位矩阵：>64KiB chunked 流六相位判定全同" {
  let stream = big_chunked_stream()
  // 基准相位：一次性喂入
  let base = match FrameScanner::new().feed(stream) {
    Some(Done(head_end, payload, chunked)) => {
      assert_true(head_end > 0, msg="头部区长度非法")
      assert_true(chunked, msg="chunked 判定丢失")
      assert_eq(
        payload.length(),
        expected_payload_len(),
        msg="重组负载长度不符",
      )
      (head_end, payload, chunked)
    }
    Some(Failed(note)) =>
      fail(
        "基准相位假 Broken（缺陷 1：绝对偏移上界误用）：\{note}",
      )
    None => fail("完整流一次性喂入仍 NeedMore——判停回归")
  }
  // 相位矩阵：每相位独立扫描器逐片 feed
  for phase in matrix_phases {
    let scanner = FrameScanner::new()
    let mut offset : Int32 = 0
    let total = stream.length()
    for ;; {
      let end = if offset + phase < total { offset + phase } else { total }
      let sig = scanner.feed(stream[offset:end])
      match sig {
        Some(Failed(note)) =>
          fail(
            "相位 \{phase} 在偏移 \{offset} 处假 Broken（判停相位无关性被破坏）：\{note}",
          )
        _ => ()
      }
      offset = end
      if offset >= total {
        break
      }
    }
    // 终态必须与基准一致（判定/负载逐相位全同——FR-006）
    match scanner.feed(b"") {
      Some(Done(h1, p1, c1)) => {
        let (h2, p2, c2) = base
        assert_eq(
          h1,
          h2,
          msg="相位 \{phase} 头部区长度与基准不一致",
        )
        assert_eq(p1, p2, msg="相位 \{phase} 负载与基准不一致")
        assert_eq(
          c1,
          c2,
          msg="相位 \{phase} chunked 判定与基准不一致",
        )
      }
      Some(Failed(note)) =>
        fail("相位 \{phase} 终态假 Broken（不应发生）：\{note}")
      None =>
        fail("相位 \{phase} 全量喂入后仍 NeedMore——判停回归")
    }
  }
}

///|
// FR-007（T019 红阶段）：超大数值在未封顶累加下回绕——
//   - CL 4294967297（2^32+1）→ Int32 累加回绕为 1 → 放行 BodyFixed(1) →
//     等 1 字节不至 → **滞留到后续字节/超时**（三型之滞留型；99999999999 则回绕为大正数碰巧即时上限——回绕症状依输入而变，均不可依赖）
//   - chunk 大小行 FFFFFFFF → 同型
// 绿阶段判据：feed 头部后**同一次调用即时** Failed("…超出夹具上限")，
// 不出现空负载假收完、不滞留。
async test "P03-WB② FR-007：CL 4294967297（回绕为 1）即时超出夹具上限" {
  let s = b"POST /ovf HTTP/1.1\r\nHost: h\r\nContent-Length: 4294967297\r\n\r\n"
  match FrameScanner::new().feed(s) {
    Some(Failed(note)) =>
      assert_true(note.contains("上限"), msg="note 不如实：\{note}")
    Some(Done(_, payload, _)) =>
      fail(
        "空负载假收完——回绕症状（payload.len=\{payload.length()}）",
      )
    None =>
      fail(
        "超长 CL 未即时判停——滞留到后续字节（回绕滞留型症状）",
      )
  }
}

///|
async test "P03-WB③ FR-007：chunk 大小行 FFFFFFFF 即时超出夹具上限" {
  let s = b"POST /ovf HTTP/1.1\r\nHost: h\r\nTransfer-Encoding: chunked\r\n\r\nFFFFFFFF\r\n"
  match FrameScanner::new().feed(s) {
    Some(Failed(note)) =>
      assert_true(note.contains("上限"), msg="note 不如实：\{note}")
    Some(Done(_, payload, _)) =>
      fail(
        "空负载假收完——回绕症状（payload.len=\{payload.length()}）",
      )
    None =>
      fail(
        "超长大小行未即时判停——滞留到后续字节（回绕滞留型症状）",
      )
  }
}

///|
// FR-008（T020 红阶段）：重复 Content-Length 判畸形——走私向量防御，
// 与 TE 在场无关、在 TE 分派之前判定；同值/异值双头均畸形。
// 红阶段口径：现行头解析只取首个同名行——双 CL 正常收完（红因）。
async test "P03-WB④ FR-008：重复 Content-Length（同值）判畸形" {
  let s = b"POST /dup HTTP/1.1\r\nHost: h\r\nContent-Length: 5\r\nContent-Length: 5\r\n\r\nhello"
  match FrameScanner::new().feed(s) {
    Some(Failed(note)) =>
      assert_true(note.contains("重复"), msg="note 不如实：\{note}")
    Some(Done(_, _, _)) =>
      fail(
        "双 CL（同值）未判畸形——现行只取首个同名头（红因）",
      )
    None => fail("双 CL 未即时判停")
  }
}

///|
async test "P03-WB⑤ FR-008：重复 Content-Length（异值）判畸形" {
  let s = b"POST /dup HTTP/1.1\r\nHost: h\r\nContent-Length: 5\r\nContent-Length: 4\r\n\r\nhello"
  match FrameScanner::new().feed(s) {
    Some(Failed(note)) =>
      assert_true(note.contains("重复"), msg="note 不如实：\{note}")
    Some(Done(_, _, _)) =>
      fail("双 CL（异值）未判畸形——静默取其一即走私向量")
    None => fail("双 CL 未即时判停")
  }
}
