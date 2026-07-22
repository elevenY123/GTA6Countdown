# 用 TrollStore 安装 GTA VI 倒计时

本文只说明如何在**已经可正常使用 TrollStore** 的 iPhone/iPad 上安装本项目 IPA，
不涉及获取 TrollStore，也不用于绕过其他平台或设备的安全机制。

## 下载 IPA

1. 用 Safari 打开本项目的 GitHub 仓库，进入 **Actions**。
2. 打开一次绿色的 **Build, test, and package** 运行记录。
3. 滑到 **Artifacts**，下载 `GTA6Countdown-TrollStore`。
4. 打开“文件”App 的“下载项”，轻点下载的 ZIP 将其解压。
5. 确认解压后的文件名是 `GTA6Countdown-TrollStore.ipa`，不是仍带 `.zip` 的文件。

如果你看不到 artifact，请先登录 GitHub；artifact 默认保留 30 天。过期后在 Actions
里手动运行一次工作流，等待新的绿色构建。

## 安装与首次打开

1. 打开 TrollStore，点右上角 **+**，选择 **Install IPA File**（不同版本措辞可能略有
   不同）。
2. 在文件选择器中选中 `GTA6Countdown-TrollStore.ipa`。
3. 安装完成后，从桌面打开“GTA VI 倒计时”。
4. 首次进入新闻页时允许联网并稍等片刻。若构建者没有配置真实 `API_BASE_URL`，在线
   新闻会显示不可用；这不是 TrollStore 安装失败。
5. “地图”会加载 `map.mygta.online`，需要网络；该站内容为社区预测，不是官方地图。

## 添加小组件

建议至少打开主应用一次，再添加小组件，以便系统识别扩展并建立共享缓存。

1. 长按主屏幕空白处，点左上角 **+**。
2. 搜索“GTA VI 倒计时”。
3. 选择倒计时小组件（2×2 或 2×4）或新闻小组件（2×4 或 4×4），点“添加小组件”。
4. 新闻小组件第一次可能先显示空状态；打开主应用新闻页刷新后，回到桌面等待系统
   刷新。iOS 决定小组件的实际刷新时机，不能保证立即更新。

## 更新应用

从新的绿色 Actions 运行记录下载并解压新 IPA，然后在 TrollStore 中安装。bundle ID
保持不变时，通常会覆盖更新并保留数据。为稳妥起见，不要先删除旧应用；删除会清除
本地缓存和主屏幕小组件配置。

## 常见问题

- **Actions 是红色**：不要安装该次产物。打开失败步骤查看错误，重新运行仍失败就把
  日志截图反馈给维护者。
- **提示 ZIP/IPA 无效**：确认下载的 artifact 已完整解压；不要把 GitHub 下载 ZIP
  直接改名为 IPA。CI 的 `validate-ipa.sh` 必须先通过才会上传产物。
- **没有小组件**：打开应用一次并重启桌面编辑界面；仍没有时，在 TrollStore 中用同一
  IPA 覆盖安装。确认构建日志包含 `valid TrollStore IPA contract`。
- **新闻不更新**：确认能访问构建时配置的 HTTPS `/v1/feed`；地图可用并不代表新闻
  Worker 可用。旧缓存可能暂时继续显示。
- **地图空白**：检查网络、内容拦截器和网站本身是否可访问，然后在地图页重试。
- **安装失败**：先确认你的设备、iOS 版本与 TrollStore 版本彼此兼容，并确认 TrollStore
  自身可安装其他已知正常的 IPA。本文不保证所有 iOS 或 TrollStore 组合均可用。

最低部署版本是 iOS 16.0；更高版本仍需以实际设备测试结果为准。
