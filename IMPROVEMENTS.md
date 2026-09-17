# 项目改进与优化清单

来源：2026-09-17 系统重装后的本地重建过程。以下是重建期间实际遇到、可复现的问题，
按影响面排序，供后续排期修复。

## 1. 依赖 / 构建

- **peer dependency 版本冲突**：安装后 `vite@8.0.1` 与多个包的 peer 依赖要求不一致——
  `electron-vite@5.0.0`（要 5/6/7.x）、`fumadocs-mdx@12.0.3`（要 6/7.x，且要
  next@15.x 但实际装的是 16.2.6）、`@vitejs/plugin-react@6.0.1`（要 vite@^8.0.0，
  当前满足）、`vitest@4.1.0`/`fumadocs-core@15.8.5` 同样有缺口。目前只是警告，还没
  炸，但升级/降级任一相关包时容易连锁出问题。建议：统一评估一次 vite/next 主版本，
  该升的包升，用 `pnpm.overrides` 锁死无法立即升级的部分。
- **`pnpm-lock.yaml` 与 `package.json` 的 `overrides` 不同步**：`pnpm install
  --frozen-lockfile`（CI 和 Docker 构建都用这个）直接报错
  `ERR_PNPM_LOCKFILE_CONFIG_MISMATCH`，本地和 Docker 构建各踩了一次。说明上一次改
  `overrides` 之后没有重新跑 `pnpm install` 并提交更新后的 lockfile。建议在 CI 里加一
  个"lockfile 与配置一致性"检查，改完 overrides 立刻起效，而不是等到下一次冻结安装才
  暴露。
- **重装系统后残留的 `node_modules` 导致 `pnpm install` 在非交互环境直接中止**
  （`ERR_PNPM_ABORTED_REMOVE_MODULES_DIR_NO_TTY`）。需要 `CI=true` 或 `--force` 才能
  非交互清理重装。文档里可以提一句给自动化/agent 使用。
- **Electron 二进制从 GitHub CDN 下载在国内网络下非常慢**（本次卡了近 10 分钟没有
  任何进度输出，换成 `ELECTRON_MIRROR=https://npmmirror.com/mirrors/electron/` 后
  17 秒装完）。建议把这个环境变量写进 `.npmrc` 或 onboarding 文档，作为国内贡献者的
  默认配置，而不是每次都要现查。
- **Node 26 不再自带 corepack**：`.nvmrc` 只写了 `22`，但新装的 Node 是 26.x（满足
  `engines.node >= 22`），此时 `corepack` 命令找不到，需要先
  `npm install -g corepack`。文档可以提醒一句，避免以为环境装坏了。

## 2. Windows 本地开发环境

- **WSL2/虚拟机平台功能"已启用"但实际无法启动**：`Get-WindowsOptionalFeature` 显示
  `Microsoft-Windows-Subsystem-Linux` 和 `VirtualMachinePlatform` 均为 `Enabled`，
  但 `wsl --status` 报"此计算机上未启用虚拟化"，直到**重启电脑**之后才真正生效。这个
  坑在全新装机/重装场景下必现，建议写进 SELF_HOSTING 文档的 Windows 章节：装完
  Docker Desktop 后无脑先重启一次。
- **Windows Defender 误杀本地未签名的 Go 构建产物**：`multica.exe`（daemon 二进制）
  曾被判定为 `Trojan:Win32/Bearfoos.A!ml` 并隔离（ThreatID 2147731250），因为所有
  智能体共享同一个 daemon 进程，一旦被隔离就是全部离线，排查成本高。建议：
  - 短期：文档里明确写"只排除这一个 exe 文件，不要放行整个安装目录"；
  - 长期：评估给本地开发构建做代码签名，从根上避免误报。

## 3. 数据 / 密钥管理

- `.env`（`JWT_SECRET` / `POSTGRES_PASSWORD` / `MULTICA_VCS_SECRET_KEY` 等）已经
  正确加入 `.gitignore`，没有泄露风险，但**唯一副本只存在于本机磁盘**——这次能恢复
  纯属运气好（文件恰好在 E 盘，系统重装时被保留）。建议把这些密钥额外存一份到密码
  管理器或加密备份，避免下次系统盘出问题时真的丢失。
- 系统重装前的数据库全量导出
  （`multica-local-before-sideeffect-cleanup-20260901-1608.dump`）和云端历史/附件
  导出（`multica-cloud-backup-*`、`multica-backups`）目前分散在
  `E:\APP\VSCODE-Project\Codex\` 下，没有固定的备份保留策略（比如保留几份、多久轮
  转一次）。建议定一个简单规则并写进 SYNC_POLICY 类文档。

## 4. 工作流程 / 协作

- **本次重建发现系统重装前有一批改动从未提交**（桌面端更新器、聊天视图/侧边栏、
  autopilot 消息投递迁移、codex agent 调整），只存在于工作区，差点随系统重装一起
  丢失。建议养成更高频率的小步提交习惯，或者在任何有风险的本机操作（重装系统、
  清盘、迁移硬盘）之前，先确认 `git status` 干净。
- 桌面端 Electron 应用的构建/打包/Defender 白名单流程目前完全靠人工记忆操作
  （见 HANDOFF.md 待办 2），没有一键脚本。建议后续把这一串步骤写成脚本或
  Makefile target，减少下次重建时的重复排错成本。
