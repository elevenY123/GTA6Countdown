# Task 12 — Worker API、定时任务与远程配置 TDD 证据

检查日期：2026-07-22（UTC）

## RED

先创建 `backend/test/api.test.ts`，覆盖聚合、缓存回退、总批次截止时间、Swift payload 字段、ETag/304、健康检查和只读路由。实现文件尚不存在时，测试按预期失败：

```text
FAIL test/api.test.ts
Error: Cannot find module '../src/aggregate'
Test Files 1 failed
```

首轮实现后的测试已通过；随后 `tsc --noEmit` 找到远程配置过滤结果与测试 KV 具体类型的两处静态错误。收紧类型后，完整测试和类型检查均转绿。

两轮复审又开启了新的 RED 周期：损坏、过期、字段泄漏和超大 `feed:latest` 最初仍会被返回；KV 读取异常会穿透为未处理异常；`If-None-Match: *` 和弱 ETag 最初未命中；生产白名单也包含尚缺完整在线 smoke 证据的来源。新增 13 个失败用例固定这些边界后才实现修复。随后以恶意、旧版和损坏的私有 curated official 记录验证回退到已审计内置记录。

最终质量复审还发现首个 partial-success 用例使用固定聚合时间却通过实时时钟读取，超过 72 小时后会自然失效。测试现显式注入相邻读取时间；官方 date-only 中午锚点也先以失败断言固定，再同步实现。

## GREEN

最终契约包括：

- `GET /v1/feed` 只读取最近 72 小时内的最后成功 payload；读取前限制为 1 MB，并严格验证 Swift schema、字段集合、ISO 日期、URL、文章一致性和唯一置顶关系；损坏、过期或 KV 异常统一返回 `503`、`no-store` JSON；
- 提供稳定 SHA-256 ETag，支持精确、弱比较和 `If-None-Match: *`，命中时返回无响应体的 304；
- `GET /health` 只公开聚合结果与文章数量，不保存查询参数、User-Agent、用户或设备标识；
- 非 GET 方法返回 405，未知路径返回 404；
- 定时事件通过 `waitUntil` 启动聚合，`wrangler.jsonc` 使用 `0 * * * *` 每小时触发；
- 生产白名单暂时只启用具备完整列表/详情证据的游民星空与快科技；机核、3DM 在独立 live smoke 完成前保持禁用；
- 一个总批次 deadline 会中止并结束所有来源，而不是让各来源超时串行累积；
- 至少有一条 live 中文媒体文章时才合并经过审计的 curated Rockstar 官方记录并保存 fresh payload；全 live 来源无有效文章时只回退最近且有效的缓存，绝不会靠 curated 记录单独制造 fresh；
- 私有 `official:curated` 只接受标题、摘要、官方 URL、发布日期与图片五个字段；代码强制 Rockstar 身份，限制中文 Newswire 文章路径、大小和发布日期，并拒绝比内置当前公告更旧的覆盖；没有公共写 API；
- 可选远程配置读取失败会使用默认值，状态写入为最佳努力；关键 feed 写入失败会让聚合失败，不会虚报成功；
- 里程碑键和值会去除首尾空白、拒绝控制字符，并限制为 32 条、总计 4 KB；发布日期限制在 2025—2035 年的真实日历日期；
- 输出只能通过 `toNewsArticle` 投影，测试确认 `attributedAdapterID` 与 `explicitTopicKey` 不会进入 API；
- payload 字段逐项匹配 Swift `NewsPayload`、`RemoteConfig` 与 `NewsArticle`，默认日期为 `2026-11-19`，远程配置只能覆盖已验证的发布日期和里程碑文案。

验证：

```text
npm test
Test Files 3 passed
Tests 135 passed

npm run typecheck
tsc --noEmit (passed)

npm audit --omit=dev
found 0 vulnerabilities

npx esbuild src/index.ts --bundle --format=esm --platform=browser
bundle smoke passed

bash tests/project_structure_test.sh
PASS: parsed iOS project structure is valid
```

## Rockstar 人工维护流与在线 smoke

2026-07-22 通过公开 Rockstar 中文 Newswire 列表与详情页人工核验了当前最新公告：`6月25日Grand Theft Auto VI开启预购`，官方页面日期为 `2026年6月24日`，URL 为 `https://www.rockstargames.com/zh/newswire/article/5171972o3ak5oa/pre-order-grand-theft-auto-vi-on-june-25`。页面的本地化时间不用于推断时区；当来源只有日历日期而没有可信精确时刻时，内置记录使用 `2026-06-24T12:00:00Z` 的 UTC 中午锚点，以减少跨时区显示回退到前一天的风险，不把它表述为实际发布时间。摘要是本项目自行撰写的短概括，不复制长正文。

更新流程：维护者从公开中文列表打开最新详情，人工核对标题、日历日期、精确官方 URL 和封面；撰写简短中文概括；再通过经过认证的 Cloudflare 私有 KV 管理操作写入 `official:curated`。Worker 没有任何公共写路由。覆盖损坏、试图注入身份、使用仿冒域、早于内置公告或不符合中文 Newswire 路径时，系统继续使用内置已核验记录。运维上还应在写入前对照当前 KV，确保 `publishedAt` 相对上一次记录单调不减，避免误将旧公告重新置顶。

Rockstar 自动发现仍等待稳定、可审计的公开数据 API，不声称当前已自动抓取官方新闻。在线 smoke 不进入离线单元测试，避免网络波动导致 CI 失败；扩大媒体生产白名单前应单独验证每个来源至少能发现一条列表链接、读取 UTF-8 详情并产出合格中文记录。
