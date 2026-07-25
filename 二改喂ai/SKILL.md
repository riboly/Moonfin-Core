---
name: moonfin-customization

description: Use when modifying the Moonfin-Core fork while preserving upstream sync and custom changes.
version: 1.0.0
author: riboly
license: GPL-2.0-or-later
metadata:
  hermes:
    tags: [moonfin, flutter, dart, fork, upstream-sync, customization]
    related_skills: []
---

# Moonfin-Core 二改技能

## 目的

本技能用于维护 `riboly/Moonfin-Core`：在跟随 `Moonfin-Client/Moonfin-Core` 上游更新的同时，安全保存和合并 riboly 的二改功能。

本项目是 Flutter/Dart 跨平台应用。任何 AI 开始工作前，都必须先读取本文件和同目录的 `二改说明.md`，再检查当前 Git 状态；不要根据旧对话猜测当前代码状态。

## 项目和 Git 基线

- 本地路径：`C:\Visual Studio Code\Moonfin-Core`
- GitHub Fork：`https://github.com/riboly/Moonfin-Core`
- 上游仓库：`https://github.com/Moonfin-Client/Moonfin-Core`
- `origin` 指向 riboly 的 Fork；`upstream` 指向官方仓库
- `main`：跟踪上游的同步基线；不要在此分支开发二改
- `custom`：二改集成分支；默认在此分支开发和测试
- 当前策略：上游更新先进入 `main`，再通过自动同步 PR 合并进 `custom`

先执行并记录：

```bash
git status --short --branch
git remote -v
git branch -vv
git log -5 --oneline --decorate
```

如果工作区有未提交改动，先报告具体文件和状态；未经用户明确同意，不要覆盖、清理、stash、reset 或删除这些改动。

## 二改工作原则

1. **先理解后修改**：先定位相关模块、调用链、状态管理、平台实现和测试；不要猜文件路径或接口。
2. **最小 diff**：只改用户要求和必要的关联文件；禁止顺手重构、格式化全仓库、升级无关依赖或修改版本号。
3. **保持上游可合并**：优先新增独立文件、局部组件、服务、配置和测试；减少对上游核心文件同一行的长期改写。
4. **平台边界清晰**：明确改动属于 Android、Android TV、iOS/tvOS、Windows、macOS、Linux、Web 或 Tizen；不要把某个平台的实现误用于其他平台。
5. **提交可追踪**：每个独立功能单独提交，使用清楚的提交信息，例如 `feat: ...`、`fix: ...`、`test: ...`。
6. **不伪造结果**：必须实际运行可用的检查；不能把“代码看起来正确”说成测试通过。
7. **先保护用户代码**：用户已有的二改、未提交文件和本地配置都视为不可丢失资产。

## 标准二改流程

### 1. 读取上下文

读取：

- `二改喂ai/SKILL.md`
- `二改喂ai/二改说明.md`
- 根目录 `pubspec.yaml`、`README.md`
- 与需求相关的 Dart、原生平台文件和已有测试

然后检查 Git 状态和当前分支。完成标准：能明确列出将修改的文件、不会修改的文件、目标平台和验证命令。

### 2. 设计改动

优先级：

1. 现有扩展点、配置、Provider、Repository、Service、ViewModel 或独立 Widget；
2. 新增局部文件并通过现有依赖注入/路由/状态管理接入；
3. 必要时修改核心文件，但要把改动限制在最小代码块并补测试。

不要为了“以后方便”提前建立大框架，也不要修改与需求无关的依赖锁文件。

### 3. 实现和验证

修改后至少执行与改动匹配的检查：

```bash
flutter pub get
flutter analyze
flutter test
```

若只改 Dart 局部逻辑，至少运行相关测试和 `flutter analyze`。若涉及 Windows 构建，使用：

```bash
flutter build windows --debug
```

若涉及其他平台，先用 `flutter devices` 确认本机工具链和设备，再选择真实可执行的命令。缺少 SDK、平台工具或凭据时，明确报告阻塞点，不要假装完成。

每次验证都要区分：

- **专项/ad-hoc 验证**：只验证本次功能或同步逻辑；
- **完整测试**：实际运行了完整命令并取得结果。

### 4. 提交二改

确认 diff 后只暂存相关文件：

```bash
git diff --check
git diff --stat
git diff -- <相关文件>
git add <相关文件>
git commit -m "feat: <二改功能>"
git push origin custom
```

提交前必须确认没有把密钥、签名文件、构建产物、用户数据或临时文件加入 Git。

## 上游同步流程

### 手动检查上游

```bash
git fetch upstream main
git log --oneline HEAD..upstream/main
git diff --stat HEAD..upstream/main
```

不要直接把上游分支强行覆盖 `custom`。正常结构是：

```text
upstream/main → 本地 main → origin/main
                              ↓
                         合并到 custom
```

### 本地手动同步

只有在工作区干净且用户确认需要同步时执行：

```bash
git fetch upstream main
git checkout main
git pull --ff-only upstream main
git push origin main
git checkout custom
git merge --no-edit main
```

如果冲突：

1. 立即停止继续提交或推送；
2. 列出冲突文件；
3. 分别阅读上游版本和二改版本；
4. 保留二改意图，同时适配上游的新接口；
5. 解决后运行 `git diff --check`、相关测试和分析；
6. 只有用户接受冲突解决结果后才提交。

### GitHub Actions 自动同步

仓库中的 `.github/workflows/sync-upstream.yml` 每天运行一次，也支持 `workflow_dispatch` 手动运行：

1. 将上游 `main` 合并到 Fork 的 `main`；
2. 从 `custom` 创建/更新 `sync/upstream-main`；
3. 将 `origin/main` 合并到该同步分支；
4. 自动创建目标为 `custom` 的 Pull Request。

无冲突时，用户应检查 PR diff、运行测试后再合并。若同步失败，通常是上游和二改修改了同一代码区域，需要手动解决，不能强制覆盖 `custom`。

## 代码区域提示

- 应用主代码在 `lib/`。
- 可复用的本地包在 `packages/`，包括 server、playback、design、preference 等。
- 平台原生代码位于 `android/`、`ios/`、`macos/`、`linux/`、`windows/`、`web/`、`tizen/`、`tvos/`。
- 测试位于 `test/`。
- 依赖和 Dart SDK 约束以根目录 `pubspec.yaml` 为准；当前项目要求 Dart `^3.11.0`，README 要求 Flutter stable `3.41+`、Dart `3.11+`。
- `pubspec.yaml` 中存在多个本地包、依赖覆盖和带特殊原因的精确版本；升级依赖前必须先读取相关注释并说明风险。

## 禁止事项

- 不要在 `custom` 之外凭空创建新的长期分支，除非用户要求。
- 不要在 `main` 上直接开发二改。
- 不要使用 `git reset --hard`、`git clean -fd`、强制覆盖 `main/custom`，除非用户明确指定并确认风险。
- 不要删除或重写用户已经做好的二改。
- 不要为了消除警告而进行全仓库无关重构。
- 不要把上游更新称为“已合并”而不提供真实 Git 输出。
- 不要把专项验证夸大为完整测试或成功构建。

## 完成检查清单

- [ ] 已读取本文件和 `二改说明.md`
- [ ] 已检查工作区、分支和两个 remote
- [ ] 已确认修改范围与用户需求一致
- [ ] 已保留用户现有改动
- [ ] 已运行适用的分析、测试或构建命令
- [ ] `git diff --check` 通过
- [ ] diff 中没有密钥、构建产物和无关修改
- [ ] 已提交并推送到正确分支，或明确说明尚未推送及原因
- [ ] 最终报告区分实际验证、未验证内容和阻塞原因
