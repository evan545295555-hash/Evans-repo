# dsh-purge 全新安装指南

> 适用：从没装过 dsh，或已彻底清理干净
> 已装过 / 装坏了 → 看 [dsh-purge-修复指南.md](./dsh-purge-修复指南.md)

---

## 你需要什么

- Windows 10/11 或 macOS（Intel / Apple Silicon 都行）
- 能上网
- 约 1.5 GB 磁盘（宿主 830MB + 插件 2MB + 依赖）
- 15-25 分钟

---

## 第 0 步：打开终端

### Windows

```
Win 键 → 输入 powershell → 右键「Windows PowerShell」→「以管理员身份运行」→ 弹窗点「是」
```

窗口标题必须显示 **`管理员: Windows PowerShell`**。

### macOS

```
Command + 空格 → 输入「终端」→ 回车
```

---

## 第 1 步：检查 Node.js

```bash
node -v
```

### 结果判断

| 输出 | 下一步 |
|---|---|
| `v20.x` ~ `v26.x` | ✅ 跳到第 2 步 |
| `v18.x` 或更低 | 装新版（见下） |
| `'node' 不是内部或外部命令` / `command not found` | 装（见下） |

### 装 / 升级 Node

**Windows**
```powershell
winget install OpenJS.NodeJS.LTS
```

**macOS**
```bash
brew install node
```

### 装完必须做

```
1. 关掉所有终端窗口
2. 重新打开
3. node -v   ← 必须显示 v20 以上
```

---

## 第 2 步：Windows 额外一步（macOS 跳过）

```powershell
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

**会弹确认**：

```
是否要更改执行策略?
[Y] 是(Y)  [A] 全是(A)  [N] 否(N)  ...
```

**输入 `Y` 回车。**

**为什么要做**：Windows 的 `npm` 命令底层是 `npm.ps1`，被 PowerShell 默认策略拦住，不改的话后面每条 npm 命令都会报 `无法加载文件 ... 因为在此系统上禁止运行脚本`。

### 验证

```powershell
npm -v
```

出 `10.x` / `11.x` 版本号就好了。

---

## 第 3 步：安装

### Windows

```powershell
irm https://raw.githubusercontent.com/evan545295555-hash/Evans-repo/master/install.ps1 | iex
```

### macOS

```bash
curl -fsSL https://raw.githubusercontent.com/evan545295555-hash/Evans-repo/master/install.sh | bash
```

---

## 第 4 步：看懂安装输出

### 正常的输出长这样

**Windows**
```
==> dsh-purge 1.1.71-rc2.1 安装器（Windows）
OK  Node v24.16.0
OK  npm 策略 hoisted
OK  已装宿主 0.2.1-rc.2（兼容）        ← 已有宿主就跳过安装
OK  布局：嵌套（npm 全局默认，插件已兼容）
OK  原生模块已就绪                      ← 或「补跑原生模块构建…」后 OK
==> profile: C:\Users\xxx\.dsh\profiles\web
OK  已补齐缺失的 base / web-app
==> 下载插件 1.1.71-rc2.1
OK  已下载 2.1 MB
==> 安装插件到 profile
OK  插件已写入 node_modules
==> 登记到 profile bundles
OK  安装完成：dsh-purge 1.1.71-rc2.1

  ────────────────────────────────
   你给巴里啊啊点赞了吗？
  ────────────────────────────────
```

**macOS** 类似，只是 `OK  Node v26.13.0` 之类。

### 关键行对照

| 行 | 含义 |
|---|---|
| `OK Node v2x` | Node 合格 |
| `OK 已装宿主` | 复用现有宿主，没重装 |
| `==> 未检测到宿主，安装...` | 首次安装宿主，**要等 5-20 分钟** |
| `OK 原生模块已就绪` | node-pty 已编译，可直接用 |
| `==> 补跑原生模块构建` | 正在编译，**再等 30 秒 - 12 分钟** |
| `OK 安装完成` | **成功** |

### 出现这些就是失败

| 输出 | 怎么办 |
|---|---|
| `ERR 宿主安装失败` | 网络问题，重跑一次 |
| `ERR 下载失败` | 网络问题，重跑一次 |
| `ERR 版本不符` | 看修复指南 |
| `ERR node-pty 仍缺失` | 看修复指南的「原生模块」一节 |

---

## 第 5 步：启动

### Windows

```powershell
$env:REDTEAM_PRESET_REFRESH = "1"
dsh web
```

### macOS

```bash
export REDTEAM_PRESET_REFRESH=1
dsh web
```

**浏览器会自动打开 `http://127.0.0.1:3080/?token=...`**

### 如果浏览器没自动开

**复制终端里打印的 URL**（带 token 的那个）手动粘贴到浏览器。

### 如果报端口被占

```
Error: listen EADDRINUSE: address already in use 127.0.0.1:3080
```

说明有个旧的 `dsh web` 还在跑。换端口：

```bash
dsh web --port 3081
```

---

## 第 6 步：点「应用」（必须做）

**这是最后一步，也是最容易漏的一步。**

```
1. 界面上找到 dsh-purge（会话标题旁边，或左侧栏的 ＋ → Purge）
2. 点进去，停在「清洗」页
3. 点「应用」
4. 等它自动重启（约 10-30 秒）
```

### 为什么要手动点

**「应用」会改写宿主源码**（把破甲补丁写入 `dsh-system-prompt` 等文件），涉及文件写入 + 备份，必须由你确认。安装脚本不碰宿主源码。

---

## 第 7 步：验证

### Windows

```powershell
type $env:USERPROFILE\.dsh\redteam\preset-declare.json
```

### macOS

```bash
cat ~/.dsh/redteam/preset-declare.json
```

### 期望内容

```json
{
  "ok": true,
  "phase": "registered",
  "plugins": 19,
  "broken": null
}
```

| 字段 | 正确值 | 不对的含义 |
|---|---|---|
| `phase` | `registered` | `waiting-registry` = bundles 缺 base/web-app；`registered-broken` = 有组件崩了 |
| `plugins` | `19` | 少于 19 = 插件没完全加载 |
| `broken` | `null` | 有值 = 看那段文字说哪个组件没起来 |

---

## 安装完成后你能做什么

```
1. 会话模式下拉里出现「红队模式」
2. 左侧栏出现 Purge 面板（清洗 / 演练台 / 状态 / 维护）
3. 不同模型可以换不同提示词
```

---

## 常见问题

### Q1: `dsh web` 报 `Cannot find module ...node-pty...`

原生模块没编译。跑这个（30 秒 - 12 分钟）：

**Windows**
```powershell
npm i -g @deepseek-ai/dsh@0.2.1-rc.2 --allow-scripts=@deepseek-ai/dsh-subprocess-local,koffi,node-pty,@google/genai,protobufjs
```

**macOS**
```bash
npm i -g @deepseek-ai/dsh@0.2.1-rc.2 --allow-scripts=@deepseek-ai/dsh-subprocess-local,koffi,node-pty,@google/genai,protobufjs
```

### Q2: `irm` / `curl` 报连接失败

GitHub 网络问题，重跑一次。多次失败可以试镜像：

```powershell
irm https://ghfast.top/https://raw.githubusercontent.com/evan545295555-hash/Evans-repo/master/install.ps1 | iex
```

```bash
curl -fsSL https://ghfast.top/https://raw.githubusercontent.com/evan545295555-hash/Evans-repo/master/install.sh | bash
```

### Q3: 点「应用」报「清洗没有写进全部宿主」

插件版本不对（装了旧版 `1.1.71` 而不是 `1.1.71-rc2.1`）。

**查版本**
```bash
node -p "require(require('os').homedir()+'/.dsh/profiles/web/node_modules/dsh-purge/package.json').version"
```

**不是 `1.1.71-rc2.1` 就重跑第 3 步**（新版会自动清掉旧版再装）。

### Q4: dsh-purge 按钮完全不出现

| 原因 | 处理 |
|---|---|
| 用的是桌面版 App 而不是 `dsh web` | 改成命令行跑 `dsh web` |
| 装完没重启宿主 | `Ctrl+C` 停掉，重新 `dsh web` |
| 没设 `REDTEAM_PRESET_REFRESH=1` | 启动前先设 |

### Q5: 想先看看环境再装

有只读诊断脚本，不改任何东西：

**Windows**
```powershell
irm https://raw.githubusercontent.com/evan545295555-hash/Evans-repo/master/diagnose.ps1 | iex
```

**macOS**
```bash
curl -fsSL https://raw.githubusercontent.com/evan545295555-hash/Evans-repo/master/diagnose.sh | bash
```

输出 8 项检查（Node / 宿主 / 布局 / dsh 命令 / 插件 / profile 配置 / 红队模式 / 残留），每项标 `[OK]` / `[WARN]` / `[FAIL]`。

---

## 一页速查

```
第 0 步  管理员 PowerShell / 终端
第 1 步  node -v        → 必须 v20+
第 2 步  Set-ExecutionPolicy（仅 Windows）
第 3 步  irm / curl 安装脚本
第 4 步  看到 "OK 安装完成" = 成功
第 5 步  dsh web（带 REDTEAM_PRESET_REFRESH=1）
第 6 步  点 dsh-purge → 清洗 → 应用
第 7 步  查 preset-declare.json = registered / 19 / null
```

---

## 关键数字

| 项 | 正确值 |
|---|---|
| Node | `v20.x` 以上 |
| 宿主 | `@deepseek-ai/dsh@0.2.1-rc.2` |
| 插件 | `1.1.71-rc2.1` |
| 插件数 | `19` |
| phase | `registered` |
| broken | `null` |
| 端口 | `3080`（或自定义） |

---

**任何一步输出对不上，看 [dsh-purge-修复指南.md](./dsh-purge-修复指南.md)。**
