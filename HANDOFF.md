# Multica 本地部署 — 交接卡

最后更新：2026-09-17（Windows 系统重装后的重建记录）

## 这是什么项目

Multica 是一个开源的"人类 + AI 智能体"项目管理平台（官方仓库
[multica-ai/multica](https://github.com/multica-ai/multica)）。本仓库是 `dddpxx` 的
本地定制 Fork（"Solo Mode"），针对个人/单人使用场景做了界面和自动更新方面的定制。

## 仓库地址

| 用途 | 地址 | 说明 |
|---|---|---|
| 日常开发 fork | https://github.com/dddpxx/multica | public，`origin` 远程 |
| 完整历史私有备份 | https://github.com/dddpxx/multica-pro | private，`pro` 远程，本次重建后新建，包含全部分支与 tags |
| 官方上游 | https://github.com/multica-ai/multica | `upstream` 远程，仅用于拉取官方更新，不直接推送 |

本地默认分支：`feat/solo-mode`（定制开发主分支），`main` 与官方 main 保持同步。

## 本次重建做了什么（系统重装后）

1. 在全新 Windows 环境安装了 Git、Node.js、Go、GitHub CLI、Docker Desktop + WSL2。
2. 恢复并同步了系统重装前遗留在工作区里的**未提交改动**（桌面端更新器、聊天视图、
   侧边栏、autopilot 消息投递迁移、codex agent 相关调整），提交为一个说明性 commit，
   避免丢失。
3. 用 `docker compose -f docker-compose.selfhost.yml -f docker-compose.selfhost.build.yml
   up -d --build` 从当前源码重新构建并启动了本地自托管栈（Postgres + Go 后端 + Next.js
   前端），验证 http://localhost:3000 可正常打开、`/health` 返回 `ok`。
4. 把本地代码同步/推送到了 `origin`（dddpxx/multica）和新建的 `pro`
   （dddpxx/multica-pro，private，完整历史）两个远程仓库。

## 怎么启动（本地自托管）

```bash
cd multica-project   # 或当前所在目录
docker compose -f docker-compose.selfhost.yml -f docker-compose.selfhost.build.yml up -d --build
```

- 前端：http://localhost:3000
- 后端：http://localhost:8080（`/health` 健康检查）
- `.env` 已经是重装前的可用配置（Solo Mode，`ALLOW_SIGNUP=true`，VCS 集成已开启），
  不需要重新生成 `JWT_SECRET` / `POSTGRES_PASSWORD`。**这个文件不在 git 里，是本机唯一
  副本，注意备份。**
- 首次登录：`.env` 里没配 `RESEND_API_KEY`，验证码要去 backend 容器日志里找
  （`docker logs multica-backend-1`）。

停止：`docker compose -f docker-compose.selfhost.yml down`（保留数据卷，不会丢数据）。

## 关键目录

- `server/` — Go 后端（`cmd/server` API、`cmd/multica` CLI/daemon、`cmd/migrate` 迁移）
- `apps/web/` — Next.js 前端
- `apps/desktop/` — Electron 桌面客户端（**本次重建未涉及**，见下方待办）
- `apps/docs/` — 官方文档站
- `packages/` — 前端共享包（ui/views/core 等）

## Solo Mode 本地定制内容

- Eric（内置智能体）只显示纯回复内容，隐藏思考过程/耗时/复制等额外 UI。
- 桌面端导航改为"聊天 → 收件箱 → 我的任务"。
- 桌面端关闭了官方自动更新检测/下载/安装（`apps/desktop/src/main/updater.ts`）。
- Autopilot 消息投递能力（迁移 `server/migrations/443_autopilot_chat_delivery.*`）。

## 待办 / 未完成事项

1. **目录迁移**：按计划应把整个项目移动到
   `E:\APP\VSCODE-Project\multica-project`，但 Claude Code 的安全策略把这个"移动/重命名
   大目录"的操作判定为不可逆的本地删除拦截了，需要你手动在资源管理器里剪切粘贴过去
   （同盘移动，几乎瞬间完成），或者调整 Claude Code 权限设置后重试。
2. **桌面端 Electron 应用未重建**：之前安装在
   `C:\Users\大鹏\AppData\Local\Programs\@multicadesktop\` 的定制版桌面客户端，重装系统
   后已经不存在了，本次只重建了 Web + 后端的自托管栈。如果还需要桌面端：
   - 在 `apps/desktop` 目录跑 `pnpm dev:desktop` 验证，再用 electron-builder 打包。
   - **重要**：本地未签名的 Go 构建产物 `multica.exe` 之前被 Windows Defender 误报
     为 `Trojan:Win32/Bearfoos.A!ml` 并隔离，导致所有智能体同时掉线（它们共享一个
     daemon 进程）。重新出现类似问题时，只对这一个 exe 文件加 Defender 排除，
     不要放行整个目录。
3. **旧数据是否恢复**：系统重装前的数据库快照
   `E:\APP\VSCODE-Project\Codex\multica-local-before-sideeffect-cleanup-20260901-1608.dump`
   （2026-09-01）以及 `multica-cloud-backup-*` / `multica-backups` 里的历史附件/工作区
   导出**没有**导入这次新建的空数据库，目前是全新空状态。如果需要找回旧的
   智能体/项目/任务数据，需要单独执行恢复。
4. `pnpm-lock.yaml` 在这次重建中被自动更新过（原文件与 `package.json` 的
   `overrides` 配置不匹配），提交前建议再看一眼这个 diff。

## 账号 / 凭据现状

- GitHub CLI (`gh`) 已登录 `dddpxx` 账号，token scope 含 `repo` + `workflow`，
  git 已配置为使用 `gh` 做凭据管理（`gh auth setup-git`）。
- `.env` 里的 `JWT_SECRET` / `POSTGRES_PASSWORD` / `MULTICA_VCS_SECRET_KEY` 只存在于
  本机这一份文件里，没有其他备份来源——建议存进密码管理器一份。

详细的问题清单和优化建议见 [IMPROVEMENTS.md](./IMPROVEMENTS.md)。
