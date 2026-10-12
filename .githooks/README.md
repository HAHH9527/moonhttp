# Git Hooks

本目录的 hook 通过 `core.hooksPath` 注册，仅影响本仓库：

```bash
git config core.hooksPath .githooks
```

首次克隆后请务必执行上面这条命令——`core.hooksPath` 存在 `.git/config` 里，
不随克隆传播，新副本默认不会启用钩子。

## Pre-commit Hook

落实宪法第六条与"合入前质量门"，顺序如下：

1. 收集暂存区里的 `.mbt` 文件。若本次提交不含 MoonBit 源码，打印提示后放行
   （`moon info` / `moon fmt` 对无源码的提交是空操作，跑了也只拖慢速度）。
2. `moon info` —— 类型检查整个模块，并重新生成**所有包**的对外接口，失败即中止提交。
   全模块而非只改动包，是为了避免依赖方的接口留在过期状态。
   它已包含类型检查，所以不再单独跑 `moon check`。
3. `moon fmt -- <暂存的 .mbt>` —— 格式化改动所在包。
4. 只回暂存**本次涉及的文件**：暂存过的 `.mbt`，加上同包内新生成的 `.mbti`。
   绝不使用宽松的 `git add -u`——那会把工作区里未暂存的半成品改动一起提交进去。
5. 若有 `.mbti` 被重新生成但不属于本次改动的包，向 stderr 警告，供人工判断。

### 已知的取舍

- **同一文件内混有已暂存与未暂存改动时，无法完全隔离。** `moon fmt` 作用于整个文件，
  第 4 步回暂存会把你随后追加的内容一起带入提交。这是格式化钩子的固有代价：
  要么接受，要么改用"钩子只检查不修改，发现变动就中止"的严格模式。
- 生成的接口文件名固定为 `<pkg>.generated.mbti`（MoonBit 工具链决定，不是 `<包名>.mbti`）。
- 含空格或特殊字符的路径未做专门处理：`git status --porcelain` 会给这类路径加引号。
  MoonBit 源码路径实践上不含空格，故未额外转义。

### 注意

- `.mbti` 是生成物，不要手工编辑。
- 审视接口 diff 仍是人工责任：提交前 `git diff --cached` 确认对外接口的每个变化
  都是有意识的决定，而非意外泄漏。
- 可执行位：`pre-commit` 以 `100755` 入库。在 Windows 上重建首个提交时需显式设置，
  否则 Linux/macOS 队友克隆到的是不可执行的钩子：
  ```bash
  git add .githooks/pre-commit
  git update-index --chmod=+x .githooks/pre-commit
  ```
- 换行符：脚本必须是 LF。仓库根 `.gitattributes` 已声明 `.githooks/* text eol=lf`，
  因为 `core.autocrlf=true` 会把检出内容转成 CRLF，而 `#!/bin/sh\r` 会让 Git 报
  "bad interpreter"。
- 质量门里的 `moon test` 尚未接入：放进 pre-commit 代价过高，合适的位置是独立的
  `pre-push` 钩子或 CI。
