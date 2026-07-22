# Task 11 — Chinese source adapters TDD evidence

Checked: 2026-07-20 (UTC)

## RED

The first adapter contract test was written before `backend/src/sources` existed.

```text
FAIL test/sourceAdapters.test.ts
Error: Cannot find module '../src/sources/bahamut'
Test Files 1 failed
```

The suite then exposed four integration defects before turning green: a UTC+8 minute-only timestamp formatting bug, a UDN host fixture mismatch, a spoof test that only replaced a provenance comment, and Task 10 rejecting the real mixed Rockstar title `Grand Theft Auto VI将于…`.

The list/detail architecture was also tested red after review: parsing detail-only fixtures could not consume each adapter's configured list URL. The final contract explicitly exercises list discovery, bounded detail fetches, then detail parsing for all 11 sources.

Spec review added a second RED cycle for provenance. Traceable HTML and JSON-LD citation tests initially received `originalSource: undefined`; implementation followed only after those failures were recorded. The registry now requires an exact, HTTPS, default-port article URL from one of the 11 known sources. Text-only attribution never fabricates a URL.

Quality review added a third RED cycle. Generic JSON-LD references were shown to create false provenance, an intentionally throwing parser was classified as `fetch`, and the registry identity projection was missing. Tests also supplied roughly 40 KB / 20,000-level nested `@graph`, `headline`, and `citation` structures before bounded traversal and the outer parse guard were implemented.

## GREEN

Covered behaviors:

- every adapter resolves a relative list link only inside its trusted article path and host;
- every adapter parses a minimal detail fixture, normalizes China/Taiwan UTC+8 timestamps to strict ISO, bounds the raw ID, and emits no self-claimed credibility;
- only `rockstar-newswire` is `officialCandidate`; all ten publishers are `media`;
- a missing title rejects only that detail; another detail from the same source still succeeds;
- the runner bounds concurrency, source article count, timeout, response bytes and cancellation;
- redirects are manual and checked before every hop; cross-host, HTTP, credentialed, private-host, cyclic and excessive redirects fail closed;
- response header or HTML meta legacy charsets fail as structured `decode` errors rather than producing mojibake;
- source and image URL protocols/hosts are checked, and a same-host non-article canonical URL is rejected;
- generic JSON-LD `citation`, `isBasedOn`, and related links never create provenance; only an immediately adjacent linked “转载自 / 出处 / 原文 / 来源” label can enter the fixed source registry;
- all JSON-LD value/graph and provenance traversal is bounded to depth 16 and 256 nodes; the adapter parse boundary never throws, and the runner separately classifies an unexpected parser exception as `parse`;
- a media repost of a traceable Rockstar article remains `media`, while public attribution uses the exact Rockstar source URL;
- adapter output passes `normalizeArticle` / `toNewsArticle`, while pipeline-only fields do not enter the API shape.

Verification after implementation:

```text
npm test -- sourceAdapters pipeline
Test Files 2 passed
Tests 101 passed

npm run typecheck
tsc --noEmit (passed)
```

## Live research status

No robots bypass, browser automation, CAPTCHA handling or full article body storage was added. Temporary probes used a descriptive user agent and only public HTML. Committed fixtures retain only fields needed by the parser plus the source URL and check date.

| Source | Public page checked | Status for Task 11 |
|---|---|---|
| Rockstar 中文 Newswire | `https://www.rockstargames.com/zh/newswire?tag_id=666` and a `/zh/newswire/article/...` page | Both returned 200, but the list is a JS shell and the detail HTML has no reliable publish timestamp. Discovery/detail JSON-LD fixtures are contract-only; Task 12 must verify the public data endpoint. |
| 游民星空 | `https://www.gamersky.com/z/gta6/news/` and `/news/202606/2164170.shtml` | Live list returned 80 matching article paths; detail `h1`, description, image and source timestamp structure were checked. UTF-8 confirmed. |
| 3DM | `https://so.3dmgame.com/?keyword=GTA6` and `/news/202511/3931272.html` | Search and detail returned 200; detail JSON-LD/date structure checked. The exact `type=7` result list remains Task 12 smoke. UTF-8 confirmed. |
| 机核 | `https://www.gcores.com/search?keyword=GTA6` and `/articles/216392` | Search returned 200 and an `/articles/` path was observed; detail Open Graph metadata and timestamp attribute checked. Search result relevance remains Task 12 smoke. UTF-8 confirmed. |
| 巴哈姆特 GNN | `https://gnn.gamer.com.tw/search.php?keyword=GTA6` and `/detail.php?sn=306952` | Search/detail curl received 403; the public article was independently visible through search indexing. No bypass attempted. Fixture-only pending Task 12 smoke. |
| 4Gamers | `https://www.4gamers.com.tw/site/search?keyword=GTA6` and `/news/detail/80255/...` | Search returned a JS shell with no server-rendered matching link; public article was verified. Fixture-only pending Task 12 data-endpoint smoke. UTF-8 shell confirmed. |
| 联合新闻网游戏角落 | `https://game.udn.com/search/word/2/GTA6` and `/game/story/122089/9595469` | Search response was an empty/script shell; public article was verified. Fixture-only pending Task 12 smoke. |
| IT之家 | `https://www.ithome.com/search?keyword=GTA6` and `/0/968/138.htm` | Public article verified. Search response declared GB2312/interstitial; runner deliberately reports unsupported charset rather than guessing. Task 12 needs a documented UTF-8 endpoint or licensed Worker-compatible decoder. |
| 快科技 | `https://news.mydrivers.com/tag/gta6.htm` and `/1/1137/1137002.htm` | Live tag returned 10 matching article paths and the list card/title/summary/date structure was checked. UTF-8 confirmed. |
| 游戏时光 | `/news/U5iajYOBKLrTgG1AbPAnsQ%3D%3D` | Public article verified, but a reliable current list/search response was not. Fixture-only pending Task 12 smoke. |
| Gamebase | `https://news.gamebase.com.tw/news/detail/99437909` | Public article verified, but a reliable current list/search response was not. Fixture-only pending Task 12 smoke. |

## Dependency and copyright note

No HTML parser or runtime dependency was added. The adapters use Web Platform APIs and small bounded metadata/link extractors, so the existing third-party notice remains unchanged. Fixtures contain no article body or long quotation.
