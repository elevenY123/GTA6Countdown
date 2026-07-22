# Task 13 资源与版权说明：Red / Green 记录

## Red

- 日期：2026-07-22
- 命令：`bash scripts/validate-assets.sh`
- 退出码：`1`
- 首个预期失败：`asset validation failed: missing AppIcon.appiconset/Contents.json`
- 结论：校验器在任何目标资源加入之前已能发现缺失的 App Icon catalog。

### About 与资源接入契约

- 命令：`node tests/task13_assets_about_contract_test.js`
- 退出码：`1`
- 首个预期失败：`Home must respond to light/dark appearance`
- 结论：现有主页尚未按外观选择 Hero，且 About 入口、占位图资源接入尚未实现。
- 可读性/工程接入扩展测试随后先失败于 `Hero top scrim must be at least 0.30 for white text contrast`；实现将顶部黑色遮罩提高至 `0.34`，并显式设置 `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`。

## Green

- 日期：2026-07-22
- `bash scripts/validate-assets.sh`：PASS
- `node tests/task13_assets_about_contract_test.js`：PASS
- `for test_file in tests/*.js; do node "$test_file"; done`：PASS
- `bash tests/project_structure_test.sh`：PASS
- `cd backend && npm test`：PASS（135 tests）
- `cd backend && npm run typecheck`：PASS
- 图像检查：App Icon 的 1024 px 和 60 px 成品均能清晰辨识原创“VI”几何字形；HeroLight、HeroDark 与 NewsPlaceholder 的裁切、对比度和构图已复核。
- 许可检查：发行声明中的 `opencc-js` MIT 文本与 `backend/node_modules/opencc-js/LICENSE` 逐字一致（SHA-256 `960f7fc16d8baa126802316a7df9078a383af4fb6bc60033adb28e85c08d5e5e`）。
- 环境边界：当前为 Linux 环境，没有 `xcodegen` / `xcodebuild`，Swift 编译和真实 iOS 16 外观仍需在 Task 14 的 macOS GitHub Actions 及 Task 15 真机验收中完成。

## 质量复审修复 Red

- 日期：2026-07-22
- 命令：`node tests/task13_assets_about_contract_test.js`
- 退出码：`1`
- 首个预期失败：`About must disclose third-party cover requests during list browsing`
- 后续契约同时禁止 Bash 4 才支持的 `declare -A`，并要求 `sha256sum` / `shasum -a 256` 回退及依赖检查。

## 质量复审修复 Green

- `bash -n scripts/validate-assets.sh`：PASS
- `node tests/task13_assets_about_contract_test.js`：PASS
- `bash scripts/validate-assets.sh`：PASS
- 校验器已改用 Bash 3.2 支持的 here-document 表格，启动时检查 `rg`、`identify`、`awk`、`cmp` 等依赖；Linux 优先使用 `sha256sum`，macOS 回退到 `shasum -a 256`。
- About 明确披露：浏览列表时即会直接向新闻来源站请求封面，可能传递 IP 地址和 User-Agent 等常规网络信息。
- 全部项目静态/结构契约：PASS；backend 135 tests：PASS；TypeScript typecheck：PASS。
