import { describe, expect, it } from "vitest";
import { toNewsArticle, type SourceArticle } from "../src/domain/article";
import { classifyCredibility } from "../src/domain/credibility";
import { deduplicateArticles } from "../src/pipeline/dedupe";
import { isGTAVIRelevant, normalizeArticle } from "../src/pipeline/filter";
import { convertArticleTextToSimplified } from "../src/pipeline/traditionalToSimplified";

const mediaAdapter = { id: "gnn", kind: "media" as const };
const officialAdapter = { id: "rockstar-newswire", kind: "officialCandidate" as const };

function article(overrides: Partial<SourceArticle> = {}): SourceArticle {
  return {
    id: "article-1",
    title: "GTA VI 第二支预告片公布",
    summary: "Rockstar 公布了游戏的新消息。",
    sourceName: "巴哈姆特 GNN",
    sourceURL: "https://gnn.gamer.com.tw/detail.php?sn=1",
    publishedAt: "2026-07-20T12:00:00Z",
    adapter: mediaAdapter,
    ...overrides
  };
}

describe("GTA VI relevance", () => {
  it.each([
    "GTA VI 第二支预告片公布",
    "侠盗猎车手6确认发售日",
    "俠盜獵車手 VI 預告公開",
    "Grand Theft Auto 6 最新消息"
  ])("accepts GTA VI aliases: %s", (title) => {
    expect(isGTAVIRelevant(article({ title }))).toBe(true);
  });

  it("accepts an official Chinese headline immediately after the Roman numeral", () => {
    expect(isGTAVIRelevant(article({
      title: "Grand Theft Auto VI将于2026年11月19日发售",
      summary: "官方确认了游戏的最新发售安排。"
    }))).toBe(true);
  });

  it.each([
    "GTA Online 夏季更新现已推出",
    "GTA V 次世代版促销",
    "Grand Theft Auto Online 新载具上线"
  ])("rejects GTA Online or GTA V without a VI link: %s", (title) => {
    expect(isGTAVIRelevant(article({ title, summary: "洛圣都本周活动奖励翻倍。" }))).toBe(false);
  });

  it("does not mistake the vi letters inside unrelated words for a Roman numeral", () => {
    expect(isGTAVIRelevant(article({ title: "GTA Online VIP 奖励", summary: "VIP 活动开启" }))).toBe(false);
  });

  it("rejects English-only stories while retaining genuinely mixed Chinese coverage", () => {
    expect(isGTAVIRelevant(article({
      title: "Grand Theft Auto VI trailer details",
      summary: "Rockstar shares new characters, locations and gameplay details."
    }))).toBe(false);
    expect(isGTAVIRelevant(article({
      title: "Grand Theft Auto 6 最新消息",
      summary: "新预告展示了罪恶城与两位主角。"
    }))).toBe(true);
  });

  it("requires substantive Chinese in the title independently of a long Chinese summary", () => {
    expect(isGTAVIRelevant(article({
      title: "Grand Theft Auto VI trailer details",
      summary: "这是一篇很长的中文摘要，详细介绍了预告片中的角色、地点、车辆以及故事线索。"
    }))).toBe(false);
    expect(isGTAVIRelevant(article({
      title: "Rockstar Games 公布 GTA VI 发售日",
      summary: "官方消息确认游戏将在明年正式推出。"
    }))).toBe(true);
  });

  it("requires Chinese content in the required summary field", () => {
    expect(isGTAVIRelevant(article({
      title: "GTA VI 第二支预告片公布",
      summary: "New trailer."
    }))).toBe(false);
  });
});

describe("credibility", () => {
  it.each([
    "https://www.rockstargames.com/zh/newswire/article/1",
    "https://www.rockstargames.com/zh-hans/newswire/article/1",
    "https://www.rockstargames.com/zh-hant/newswire/article/1"
  ])("allows a trusted Rockstar Newswire adapter and URL: %s", (sourceURL) => {
    expect(classifyCredibility(article({ sourceURL, adapter: officialAdapter }))).toBe("official");
  });

  it.each([
    "http://www.rockstargames.com/zh/newswire/article/1",
    "https://rockstargames.com.evil.example/zh/newswire/article/1",
    "https://news.rockstargames.com/zh/newswire/article/1",
    "https://www.rockstargames.com/zh/games/article/1",
    "https://www.rockstargames.com/newswire/article/1"
  ])("rejects spoofed or non-Newswire official URLs: %s", (sourceURL) => {
    expect(classifyCredibility(article({ sourceURL, adapter: officialAdapter }))).not.toBe("official");
  });

  it("does not trust an article's self-reported official flags", () => {
    expect(classifyCredibility(article({ claimedCredibility: "official" }))).toBe("media");
  });

  it("never grants official status through repost provenance", () => {
    const rockstarOriginal = {
      sourceName: "Rockstar Games",
      sourceURL: "https://www.rockstargames.com/zh/newswire/article/1",
      adapter: officialAdapter
    };
    expect(classifyCredibility(article({ originalSource: rockstarOriginal }))).toBe("media");
    expect(classifyCredibility(article({
      adapter: { id: "untrusted-feed", kind: "officialCandidate" },
      originalSource: rockstarOriginal
    }))).toBe("unverified");
    expect(classifyCredibility(article({
      adapter: officialAdapter,
      sourceURL: "https://www.rockstargames.com/zh/newswire/article/own",
      originalSource: {
        sourceName: "媒体归因",
        sourceURL: "https://media.example/story",
        adapter: mediaAdapter
      }
    }))).toBe("official");
  });

  it("keeps a traceable leak unverified even when its original URL is Rockstar", () => {
    expect(classifyCredibility(article({
      isLeak: true,
      adapter: officialAdapter,
      sourceURL: "https://www.rockstargames.com/zh/newswire/article/leak",
      originalSource: {
        sourceName: "Rockstar Games",
        sourceURL: "https://www.rockstargames.com/zh/newswire/article/original",
        adapter: officialAdapter
      }
    }))).toBe("unverified");
  });

  it("downgrades forums, leaks, and untraceable tips", () => {
    expect(classifyCredibility(article({
      adapter: { id: "forum", kind: "community" },
      isLeak: true
    }))).toBe("unverified");
  });
});

describe("Traditional Chinese conversion", () => {
  it("converts title and summary but preserves proper terms, punctuation, source, and URLs", () => {
    const input = article({
      title: "《GTA VI》第二支預告片正式公開！",
      summary: "遊戲將帶玩家回到罪惡城，Rockstar Games 帶來全新畫面。",
      sourceName: "巴哈姆特電玩資訊站",
      sourceURL: "https://example.com/傳統中文",
      imageURL: "https://img.example.com/遊戲.jpg"
    });

    const converted = convertArticleTextToSimplified(input);

    expect(converted.title).toBe("《GTA VI》第二支预告片正式公开！");
    expect(converted.summary).toContain("游戏将带玩家回到罪恶城");
    expect(converted.summary).toContain("Rockstar Games");
    expect(converted.sourceName).toBe(input.sourceName);
    expect(converted.sourceURL).toBe(input.sourceURL);
    expect(converted.imageURL).toBe(input.imageURL);
    expect(input.title).toContain("預告片");
  });
});

describe("normalization and deduplication", () => {
  it("drops missing or malformed required fields and safely drops a malformed image URL", () => {
    expect(normalizeArticle(article({ title: "   " }))).toBeNull();
    expect(normalizeArticle(article({ sourceURL: "not a url" }))).toBeNull();
    expect(normalizeArticle(article({ publishedAt: "yesterday" }))).toBeNull();
    expect(normalizeArticle(article({ imageURL: "javascript:alert(1)" }))?.imageURL).toBeNull();
  });

  it("sanitizes related source counts to a finite bounded integer", () => {
    const values = [Number.NaN, Number.POSITIVE_INFINITY, -12, 4.9, 10_000];
    const normalized = values.map((relatedSourceCount) => normalizeArticle(article({ relatedSourceCount }))!);
    expect(normalized.map((item) => item.relatedSourceCount)).toEqual([0, 0, 0, 4, 99]);
    expect(JSON.stringify(normalized)).not.toContain('"relatedSourceCount":null');
  });

  it("constructs globally namespaced stable IDs without a short hash", () => {
    const first = normalizeArticle(article({ id: "shared", upstreamTopicKey: "first" }))!;
    const repeated = normalizeArticle(article({ id: "shared", upstreamTopicKey: "first" }))!;
    const otherAdapter = normalizeArticle(article({
      id: "shared",
      adapter: { id: "ithome", kind: "media" },
      sourceURL: "https://www.ithome.com/0/001/001.htm",
      title: "GTA VI 发售平台消息",
      upstreamTopicKey: "platforms"
    }))!;
    const sameAdapterOtherURL = normalizeArticle(article({
      id: "shared",
      sourceURL: "https://gnn.gamer.com.tw/detail.php?sn=2",
      title: "GTA VI 地图消息",
      upstreamTopicKey: "map"
    }))!;

    expect(first.id).toBe(repeated.id);
    expect(new Set([first.id, otherAdapter.id, sameAdapterOtherURL.id]).size).toBe(3);
    expect(first.id).toContain("gnn");
    expect(first.id.length).toBeLessThanOrEqual(2_500);
    expect(normalizeArticle(article({ id: "x".repeat(257) }))).toBeNull();
  });

  it("strictly validates timestamp shape, calendar values, timezone, and range", () => {
    expect(normalizeArticle(article({ publishedAt: "2026-07-20" }))).toBeNull();
    expect(normalizeArticle(article({ publishedAt: "2026-07-20T12:00:00" }))).toBeNull();
    expect(normalizeArticle(article({ publishedAt: "2026-02-30T12:00:00Z" }))).toBeNull();
    expect(normalizeArticle(article({ publishedAt: "9999-01-01T00:00:00Z" }))).toBeNull();
    expect(normalizeArticle(article({ publishedAt: "2026-07-20T20:00:00+08:00" }))?.publishedAt)
      .toBe("2026-07-20T12:00:00.000Z");
  });

  it("rejects credentialed or oversized sources and unsafe image hosts", () => {
    expect(normalizeArticle(article({ sourceURL: "https://user:secret@gnn.gamer.com.tw/story" }))).toBeNull();
    expect(normalizeArticle(article({ sourceURL: `https://example.com/${"a".repeat(2_100)}` }))).toBeNull();

    const unsafeImages = [
      "http://images.example.com/cover.jpg",
      "https://user:secret@images.example.com/cover.jpg",
      "https://localhost/cover.jpg",
      "https://localhost./cover.jpg",
      "https://cdn.local/cover.jpg",
      "https://cdn.local./cover.jpg",
      "https://127.0.0.1/cover.jpg",
      "https://10.0.0.1/cover.jpg",
      "https://169.254.1.1/cover.jpg",
      "https://172.16.0.1/cover.jpg",
      "https://192.168.1.1/cover.jpg",
      "https://[::1]/cover.jpg",
      "https://[fe80::1]/cover.jpg",
      "https://[fc00::1]/cover.jpg",
      `https://images.example.com/${"a".repeat(2_100)}`
    ];
    for (const imageURL of unsafeImages) {
      expect(normalizeArticle(article({ imageURL }))?.imageURL, imageURL).toBeNull();
    }
    expect(normalizeArticle(article({ imageURL: "https://images.example.com/cover.jpg" }))?.imageURL)
      .toBe("https://images.example.com/cover.jpg");
  });

  it("drops untraceable leaks but retains a leak with valid original provenance as unverified", () => {
    expect(normalizeArticle(article({ isLeak: true }))).toBeNull();

    const traceable = normalizeArticle(article({
      isLeak: true,
      originalSource: {
        sourceName: "具名爆料者",
        sourceURL: "https://community.example/post/42",
        adapter: { id: "named-leaker", kind: "community" }
      }
    }));
    expect(traceable).toMatchObject({
      sourceName: "具名爆料者",
      sourceURL: "https://community.example/post/42",
      credibility: "unverified"
    });
  });

  it("keeps display attribution separate from normalized credibility", () => {
    const rockstarOriginal = {
      sourceName: "Rockstar Games",
      sourceURL: "https://www.rockstargames.com/zh/newswire/article/original",
      adapter: officialAdapter
    };
    expect(normalizeArticle(article({ originalSource: rockstarOriginal }))).toMatchObject({
      sourceName: "Rockstar Games",
      sourceURL: rockstarOriginal.sourceURL,
      credibility: "media",
      isOfficial: false
    });
    expect(normalizeArticle(article({
      isLeak: true,
      adapter: officialAdapter,
      sourceURL: "https://www.rockstargames.com/zh/newswire/article/leak",
      originalSource: rockstarOriginal
    }))).toMatchObject({ credibility: "unverified", isOfficial: false });
    expect(normalizeArticle(article({
      sourceName: "Rockstar Games",
      sourceURL: "https://www.rockstargames.com/zh/newswire/article/direct",
      adapter: officialAdapter,
      originalSource: {
        sourceName: "错误转载归因",
        sourceURL: "https://media.example/repost",
        adapter: mediaAdapter
      }
    }))).toMatchObject({
      sourceName: "Rockstar Games",
      sourceURL: "https://www.rockstargames.com/zh/newswire/article/direct",
      credibility: "official",
      isOfficial: true
    });
  });

  it("never merges unrelated articles whose upstream topic keys are empty", () => {
    const first = normalizeArticle(article({ id: "a", title: "GTA VI 地图细节", upstreamTopicKey: " " }));
    const second = normalizeArticle(article({ id: "b", title: "GTA VI 配乐消息", upstreamTopicKey: "" }));
    expect(deduplicateArticles([first!, second!])).toHaveLength(2);
    expect(first?.canonicalTopicKey).not.toBe(second?.canonicalTopicKey);
  });

  it("groups the same event and lets Rockstar official copy replace media retellings", () => {
    const media = normalizeArticle(article({
      id: "media",
      title: "媒体转述：GTA 6 第二支预告发布",
      upstreamTopicKey: " Trailer TWO ",
      publishedAt: "2026-07-20T12:00:00Z"
    }))!;
    const official = normalizeArticle(article({
      id: "official",
      title: "《Grand Theft Auto VI》预告片 2",
      summary: "官方发布第二支预告片，介绍两位主角。",
      sourceName: "Rockstar Games",
      sourceURL: "https://www.rockstargames.com/zh/newswire/article/trailer-2",
      upstreamTopicKey: "trailer-two",
      publishedAt: "2026-07-19T12:00:00Z",
      adapter: officialAdapter
    }))!;

    const result = deduplicateArticles([media, official]);

    expect(result).toHaveLength(1);
    expect(result[0]).toMatchObject({
      id: official.id,
      credibility: "official",
      isOfficial: true,
      canonicalTopicKey: "trailer-two",
      relatedSourceCount: 1
    });
  });

  it("keeps an older pinned official item over a newer official item", () => {
    const pinned = normalizeArticle(article({
      id: "pinned",
      sourceName: "Rockstar Games",
      sourceURL: "https://www.rockstargames.com/zh/newswire/article/pinned",
      adapter: officialAdapter,
      upstreamTopicKey: "official-event",
      publishedAt: "2026-07-19T12:00:00Z",
      isPinned: true
    }))!;
    const newer = normalizeArticle(article({
      id: "newer-official",
      sourceName: "Rockstar Games",
      sourceURL: "https://www.rockstargames.com/zh/newswire/article/newer",
      adapter: officialAdapter,
      upstreamTopicKey: "official-event",
      publishedAt: "2026-07-20T12:00:00Z"
    }))!;

    expect(deduplicateArticles([newer, pinned])[0]).toMatchObject({
      sourceURL: "https://www.rockstargames.com/zh/newswire/article/pinned",
      isPinned: true
    });
  });

  it("does not fuzzy-merge records with different explicit upstream topics", () => {
    const first = normalizeArticle(article({
      id: "explicit-one",
      title: "GTA VI 第二支预告片公开",
      upstreamTopicKey: "trailer-event-one"
    }))!;
    const second = normalizeArticle(article({
      id: "explicit-two",
      title: "GTA VI 第二支预告片正式公开",
      upstreamTopicKey: "trailer-event-two"
    }))!;
    expect(deduplicateArticles([first, second])).toHaveLength(2);
  });

  it("collapses a repeated stable ID even when upstream topic metadata conflicts", () => {
    const first = normalizeArticle(article({ upstreamTopicKey: "first-topic" }))!;
    const duplicate = normalizeArticle(article({
      title: "GTA VI 地图消息与地点分析",
      upstreamTopicKey: "conflicting-topic"
    }))!;
    expect(first.id).toBe(duplicate.id);
    expect(deduplicateArticles([first, duplicate])).toHaveLength(1);
  });

  it("prevents transitive fuzzy-title bridges with complete-link grouping", () => {
    const first = normalizeArticle(article({
      id: "bridge-a",
      title: "GTA VI 地图 罪恶 海滩 港口 城市",
      upstreamTopicKey: undefined
    }))!;
    const bridge = normalizeArticle(article({
      id: "bridge-b",
      title: "GTA VI 地图 罪恶 海滩 港口 城市 沼泽 山区",
      upstreamTopicKey: undefined
    }))!;
    const third = normalizeArticle(article({
      id: "bridge-c",
      title: "GTA VI 地图 港口 城市 沼泽 山区",
      upstreamTopicKey: undefined
    }))!;

    expect(deduplicateArticles([first, bridge])).toHaveLength(1);
    expect(deduplicateArticles([bridge, third])).toHaveLength(1);
    expect(deduplicateArticles([first, bridge, third])).toHaveLength(2);
  });

  it("conservatively groups similar trailer-event titles without an upstream topic key", () => {
    const media = normalizeArticle(article({
      id: "media-similar",
      title: "《GTA 6》预告 2 发布，展示罪恶城",
      upstreamTopicKey: undefined
    }))!;
    const official = normalizeArticle(article({
      id: "official-similar",
      title: "GTA VI 第二支预告片正式公开",
      summary: "官方发布第二支中文预告片。",
      sourceName: "Rockstar Games",
      sourceURL: "https://www.rockstargames.com/zh/newswire/article/trailer-2",
      adapter: officialAdapter,
      upstreamTopicKey: undefined
    }))!;
    const map = normalizeArticle(article({
      id: "map",
      title: "GTA VI 地图分析与罪恶城地点",
      upstreamTopicKey: undefined
    }))!;

    const result = deduplicateArticles([map, media, official]);
    expect(result).toHaveLength(2);
    expect(result.find((item) => item.isOfficial)?.relatedSourceCount).toBe(1);
    expect(result.some((item) => item.title.includes("地图分析"))).toBe(true);
  });

  it("does not merge different numbered trailers through title similarity", () => {
    const first = normalizeArticle(article({
      id: "trailer-1",
      title: "GTA VI 第一支预告片公开",
      upstreamTopicKey: undefined
    }))!;
    const second = normalizeArticle(article({
      id: "trailer-2",
      title: "GTA VI 第二支预告片公开",
      upstreamTopicKey: undefined
    }))!;
    expect(deduplicateArticles([first, second])).toHaveLength(2);
  });

  it("recognizes repost provenance and does not count repeated copies as independent sources", () => {
    const original = {
      sourceName: "游戏时光",
      sourceURL: "https://www.vgtime.com/topic/1",
      adapter: { id: "vgtime", kind: "media" as const }
    };
    const direct = normalizeArticle(article({
      id: "direct",
      sourceName: original.sourceName,
      sourceURL: original.sourceURL,
      adapter: original.adapter,
      upstreamTopicKey: "release-date"
    }))!;
    const repost = normalizeArticle(article({
      id: "repost",
      sourceName: "转载站",
      sourceURL: "https://repost.example/a",
      upstreamTopicKey: "release-date",
      originalSource: original
    }))!;

    const result = deduplicateArticles([repost, direct]);
    expect(result).toHaveLength(1);
    expect(result[0].sourceName).toBe("游戏时光");
    expect(result[0].sourceURL).toBe("https://www.vgtime.com/topic/1");
    expect(result[0].relatedSourceCount).toBe(0);
  });

  it("counts related media outlets, not multiple URLs from the same outlet", () => {
    const first = normalizeArticle(article({
      id: "same-outlet-a",
      sourceURL: "https://gnn.gamer.com.tw/detail.php?sn=1",
      upstreamTopicKey: "event"
    }))!;
    const second = normalizeArticle(article({
      id: "same-outlet-b",
      sourceURL: "https://gnn.gamer.com.tw/detail.php?sn=2",
      upstreamTopicKey: "event"
    }))!;
    expect(deduplicateArticles([first, second])[0].relatedSourceCount).toBe(0);
  });

  it("counts attributed adapter identities rather than display names", () => {
    const renamed = normalizeArticle(article({
      id: "renamed-a",
      sourceName: "巴哈姆特",
      sourceURL: "https://gnn.gamer.com.tw/a",
      upstreamTopicKey: "identity-event"
    }))!;
    const sameAdapter = normalizeArticle(article({
      id: "renamed-b",
      sourceName: "巴哈姆特 GNN 新闻",
      sourceURL: "https://gnn.gamer.com.tw/b",
      upstreamTopicKey: "identity-event"
    }))!;
    expect(deduplicateArticles([renamed, sameAdapter])[0].relatedSourceCount).toBe(0);

    const differentAdapter = normalizeArticle(article({
      id: "different-adapter",
      adapter: { id: "other-media", kind: "media" },
      sourceName: "巴哈姆特",
      sourceURL: "https://other.example/story",
      upstreamTopicKey: "identity-event"
    }))!;
    expect(deduplicateArticles([renamed, differentAdapter])[0].relatedSourceCount).toBe(1);
  });

  it("is deterministic and never mutates inputs", () => {
    const older = normalizeArticle(article({ id: "older", upstreamTopicKey: "event", publishedAt: "2026-07-19T00:00:00Z" }))!;
    const newer = normalizeArticle(article({ id: "newer", upstreamTopicKey: "event", publishedAt: "2026-07-20T00:00:00Z" }))!;
    const unrelated = normalizeArticle(article({ id: "other", title: "GTA VI 地图分析", upstreamTopicKey: "map" }))!;
    const snapshot = JSON.stringify([older, newer, unrelated]);

    const forward = deduplicateArticles([older, unrelated, newer]);
    const reverse = deduplicateArticles([newer, unrelated, older]);

    expect(forward).toEqual(reverse);
    expect(forward.map((item) => item.id)).toEqual([unrelated.id, newer.id]);
    expect(JSON.stringify([older, newer, unrelated])).toBe(snapshot);
  });

  it("uses stable fields when credibility, time, and id are all tied", () => {
    const left = normalizeArticle(article({
      id: "same-id",
      title: "GTA VI 预告片 2：A 版本报道",
      summary: "中文摘要包含来源甲的补充内容。",
      sourceName: "来源甲",
      sourceURL: "https://a.example/story",
      upstreamTopicKey: "same-event"
    }))!;
    const right = normalizeArticle(article({
      id: "same-id",
      title: "GTA VI 预告片 2：B 版本报道",
      summary: "中文摘要包含来源乙的补充内容。",
      sourceName: "来源乙",
      sourceURL: "https://b.example/story",
      upstreamTopicKey: "same-event"
    }))!;

    expect(deduplicateArticles([left, right])).toEqual(deduplicateArticles([right, left]));
  });

  it("keeps deterministic raw output when normalized tie-break fields collide", () => {
    const uppercase = normalizeArticle(article({
      id: "same-id-and-source",
      title: "GTA VI 预告片 A版报道",
      summary: "这是同一篇中文摘要内容。",
      sourceName: "同一来源",
      sourceURL: "https://same.example/story",
      upstreamTopicKey: "case-event"
    }))!;
    const lowercase = normalizeArticle(article({
      id: "same-id-and-source",
      title: "GTA VI 预告片 a版报道",
      summary: "这是同一篇中文摘要内容。",
      sourceName: "同一来源",
      sourceURL: "https://same.example/story",
      upstreamTopicKey: "case-event"
    }))!;

    const forward = deduplicateArticles([uppercase, lowercase]);
    const reverse = deduplicateArticles([lowercase, uppercase]);
    expect(forward).toEqual(reverse);
    expect(forward[0].title).toBe("GTA VI 预告片 A版报道");
  });

  it("strips internal aggregation metadata from the Swift API article", () => {
    const internal = normalizeArticle(article())!;
    const output = toNewsArticle(internal);
    expect(output).not.toHaveProperty("attributedAdapterID");
    expect(output).not.toHaveProperty("explicitTopicKey");
    expect(Object.keys(output).sort()).toEqual([
      "canonicalTopicKey", "credibility", "id", "imageURL", "isOfficial", "isPinned",
      "publishedAt", "relatedSourceCount", "sourceName", "sourceURL", "summary", "title"
    ]);
  });
});
