# 素材来源与使用记录

访问日期统一为 **2026-07-22**。

| 应用资源 | 类型与用途 | 来源页面 | 精确原始文件 URL | 处理方式 |
|---|---|---|---|---|
| `HeroLight` / `HeroDark` | Rockstar Games 官方公开 GTA VI 美术；首页倒计时背景 | [GTA VI — Artwork & Wallpapers](https://www.rockstargames.com/VI/media/artwork-wallpapers) | [Jason and Lucia 03 — landscape JPEG](https://www.rockstargames.com/VI/_next/static/media/Jason_and_Lucia_03_landscape.0419q._86ukpt.jpg?akim=1&imdensity=1&imwidth=3840) | 从官方 3840×2160 JPEG（SHA-256 `0c5919c9253fedead3ed2dfa7df59129212234ca1cab41355446f23e8148eb90`）居中裁切为 3:4，并生成 1×/2×/3× JPEG；Dark 由同一原图降低亮度和饱和度后生成，并非另一幅官方图片。 |
| `AppIcon` | 应用图标 | 本项目原创，无第三方图片来源 | 不适用 | 以日落、海岸、棕榈树和抽象几何字形构成；没有复制或嵌入 Rockstar/GTA VI 官方 Logo。源文件为 `scripts/assets/AppIconSource.svg`。 |
| `NewsPlaceholder` | 新闻封面加载/失败占位图 | 本项目原创，无第三方图片来源 | 不适用 | 以日落、海岸、棕榈树和抽象报纸图形构成；没有使用官方人物、Logo 或第三方照片。源文件为 `scripts/assets/NewsPlaceholderSource.svg`。 |

## 权利与边界

本项目是非官方爱好者应用，与 Rockstar Games、Take-Two Interactive 或其关联公司没有从属、赞助或授权关系。Grand Theft Auto、GTA、GTA VI、Rockstar Games 及相关美术、标志和商标均归各自权利人所有。官方 Hero 仅用于介绍相关游戏与识别资讯来源；不得将本文件解释为 Rockstar 对本应用的认可或授权。

发布前应再次检查官方页面的现行使用条款，并在权利人提出要求时替换或移除官方 Hero。新闻文章封面来自各原文站点的远程 URL，不随 IPA 打包；应用只展示来源、短导语并链接原文。
