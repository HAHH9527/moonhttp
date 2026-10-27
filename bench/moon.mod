// bench/ 独立可运行模块（T009 一次性探针归档）。
//
// 本地依赖父目录主模块 hahh9527/moonhttp：新 moon.mod 格式的 import 只接受
// 字符串（path 依赖已废弃），须经同目录 moon.work（workspace）本地解析；
// import 中的 @version 仅占位，实际取本地源码而非 mooncakes.io。
//
// 隔离性：moon.work 位于 bench/ 内，仓库根目录的 moon check/test/fmt 不感知
// （根模块 source = "src" 也不扫描本目录），126 测试基线与门禁不受影响。
//
// 复跑：cd bench && moon run <探针目录名> --target native（如 diag_ovf）。
// 宪法 IV：全部连接仅 127.0.0.1；roadmap D8：代码自建。

name = "hahh9527/moonhttp-bench"

version = "0.1.0"

preferred_target = "native"

description = "T009 一次性探针归档：性能基准与诊断（独立模块，不进仓库门禁）"

import {
  "moonbitlang/async@0.22.4",
  "hahh9527/moonhttp@0.1.0",
}
