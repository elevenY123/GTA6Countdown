# GTA VI 倒计时

一款以 GTA VI 为主题、最低支持 iOS 16 的非官方 SwiftUI 应用。包含发售倒计时、
中文新闻、预测地图，以及倒计时和新闻桌面小组件。

> 本项目与 Rockstar Games、Take-Two Interactive 无隶属、授权或赞助关系。
> 商标和官方素材权利归各自权利人所有，素材来源见 `ASSET_SOURCES.md`。

## 只有 iPhone/iPad：从 GitHub Actions 下载 IPA

1. 打开仓库的 **Actions** 页面。
2. 选择 **Build, test, and package**，点击 **Run workflow**。
3. 等待 `backend-and-contracts` 和 `ios-build-test-package` 都变为绿色。
4. 在该次运行页面底部下载 `GTA6Countdown-TrollStore` artifact。
5. GitHub 下载的是 ZIP；解压后得到 `GTA6Countdown-TrollStore.ipa`。
6. 按 [TROLLSTORE_INSTALL.md](TROLLSTORE_INSTALL.md) 安装。

IPA 只面向用户已经安装好的 TrollStore 环境。它使用 ad-hoc 签名，不包含 Apple
开发者证书、描述文件或分发凭据，也不承诺能在普通 iOS 安装流程、所有系统版本或
所有 TrollStore 版本中工作。

## 新闻 API 配置

Release 构建读取 Info.plist 中的 `API_BASE_URL`，它必须是完整的 HTTPS feed 地址，
并以 `/v1/feed` 结尾，例如：

```text
https://your-worker.example.workers.dev/v1/feed
```

仓库管理员在 **Settings → Secrets and variables → Actions → Variables** 新建仓库变量
`API_BASE_URL`。这是公开请求地址，应使用 **Variable**，不需要放 API 密钥。不要把
Cloudflare 凭据写进仓库或应用。

未设置变量时，CI 会使用 `https://api.example.invalid/v1/feed`：工程仍能编译，测试
使用内置 fixture，但安装后的在线新闻不会更新；倒计时和地图仍可使用。正式发布前
必须部署 `backend/` Worker、配置 KV，并把变量改成真实 `/v1/feed` 地址。

本地 XcodeGen 的默认调试/发布占位地址分别位于 `Config/Debug.xcconfig` 和
`Config/Release.xcconfig`。

## 本地构建（需要 macOS 与 Xcode）

```bash
brew install xcodegen
xcodegen generate
xcodebuild test -project GTA6Countdown.xcodeproj -scheme GTA6Countdown \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

CI 使用 `CODE_SIGNING_ALLOWED=NO` 构建 Release iphoneos app，再由
`scripts/package-ipa.sh` 按“Widget 后、主应用”的顺序进行 ad-hoc 签名、封装 Payload，
最后由 `scripts/validate-ipa.sh` 校验 bundle ID、iOS 16.0、可执行文件、资源和 Widget。
工作流会在 `main` 分支 push、所有 pull request 或手动触发时运行；限制 push 分支可避免
同仓库 pull request 因分支 push 再重复运行一次。

Linux/macOS 都能运行 IPA 合同测试：

```bash
bash tests/task14_ipa_contract_test.sh
```
