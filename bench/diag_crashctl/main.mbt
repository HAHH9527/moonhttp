///|
// 栈对照控制组（D3b 佐证）：
//   非尾自递归 1_000_000 层 —— 每层需保留栈帧（结果参与后续加法），
//   栈不足则进程 abort（预期不打印其后输出）。
//   （尾递归对照已单独运行取证：tail_loop(1_000_000) 正常返回，见报告。）

///|
// 非尾自递归：递归结果参与加法，调用点之后仍有工作
fn nontail_sum(n : Int32) -> Int32 {
  if n == 0 {
    0
  } else {
    1 + nontail_sum(n - 1)
  }
}

///|
fn main {
  println("[ctl] nontail(1_000_000) 开始")
  let b = nontail_sum(1_000_000)
  println("[ctl] nontail 返回：\{b}（若栈不足则到不了本行）")
  println("[ctl] done-nontail")
}
