///|
// timeout_writer：P08 写窗 @io.Writer trait 门面（contracts/timeout-api.md
// §2 priv 接缝；research R3）。职责：Stream 体经 filler(&@io.Writer) 驱动
// 时，每次用户写调用各享一个独立写窗（FR-003 按操作计时——OkHttp 逐 sink
// write 语义对齐）；trait 包装非侵入（P02 CountingWriter 同款先例，
// request_body.mbt:118-134）。
//
// 委托纪律（R3 注记，qod-2 S9）：三方法全部覆写（trait 缺省 write/
// write_reader 会经 self.write_once 递归回门面造成嵌套开窗）——委托
// 目标＝内层 conn 自身方法（`@io.Writer::write*(self.inner, ...)` 显式
// trait 调用，非门面自身方法）⇒ 单窗无嵌套。
//
// 上游适配（T008 同款取证，2026-10-30）：当前协程已处取消态时不再构造
// with_timeout 组（上游 with_task_group 在「已取消协程 + 子任务真实
// 错误」交叠下 PanicError）——此际直调内层，取消沿写调用原生传播。

///|
// 写窗门面（包内私有，不进公开面）：内层 conn + 写窗阈值。
priv struct TimeoutWriter {
  inner : @http.Client
  write_ms : Int32
}

///|
// 窗内直调 helper：write_ms>0 且协程非取消态 ⇒ 包窗后委托；否则直调
// （0=不限不建窗——INV-T1；取消态直调——T008 上游适配同款）。
async fn timeout_writer_write_once(
  inner : @http.Client,
  write_ms : Int32,
  buf : Bytes,
  offset~ : Int32,
  len~ : Int32,
) -> Int32 {
  if write_ms > 0 && !@async.is_being_cancelled() {
    @async.with_timeout(
      write_ms,
      () => @io.Writer::write_once(inner, buf, offset~, len~),
      error=HttpTimeout::Write,
    )
  } else {
    @io.Writer::write_once(inner, buf, offset~, len~)
  }
}

///|
// impl @io.Writer for TimeoutWriter with fn write_once（全覆写）：
// 单用户写调用单窗，委托内层 conn 自身 write_once。
impl @io.Writer for TimeoutWriter with fn write_once(self, buf, offset~, len~) -> Int32 raise {
  timeout_writer_write_once(self.inner, self.write_ms, buf, offset~, len~)
}

///|
// impl @io.Writer for TimeoutWriter with fn write（全覆写——阻断缺省
// 实现经门面 write_once 的递归嵌套）：单窗后委托内层 conn 自身 write
// （内层 write 的缺省实现调用的是内层自身 write_once——单窗）。
impl @io.Writer for TimeoutWriter with fn write(self, data) -> Unit raise {
  let inner = self.inner
  let write_ms = self.write_ms
  if write_ms > 0 && !@async.is_being_cancelled() {
    @async.with_timeout(
      write_ms,
      () => @io.Writer::write(inner, data),
      error=HttpTimeout::Write,
    )
  } else {
    @io.Writer::write(inner, data)
  }
}

///|
// impl @io.Writer for TimeoutWriter with fn write_reader（全覆写，同上
// 阻断递归）：单窗后委托内层 conn 自身 write_reader。
impl @io.Writer for TimeoutWriter with fn write_reader(self, reader) -> Unit raise {
  let inner = self.inner
  let write_ms = self.write_ms
  if write_ms > 0 && !@async.is_being_cancelled() {
    @async.with_timeout(
      write_ms,
      () => @io.Writer::write_reader(inner, reader),
      error=HttpTimeout::Write,
    )
  } else {
    @io.Writer::write_reader(inner, reader)
  }
}
