import { describe, expect, it } from "vitest";
import { normalizeArticle } from "../src/pipeline/filter";
import { toNewsArticle } from "../src/domain/article";
import { bahamutAdapter } from "../src/sources/bahamut";
import { fourGamersAdapter } from "../src/sources/fourGamers";
import { gamebaseAdapter } from "../src/sources/gamebase";
import { gamerskyAdapter } from "../src/sources/gamersky";
import { gcoresAdapter } from "../src/sources/gcores";
import { ithomeAdapter } from "../src/sources/ithome";
import { mydriversAdapter } from "../src/sources/mydrivers";
import { rockstarAdapter } from "../src/sources/rockstar";
import { runSourceAdapters, type SourceAdapter } from "../src/sources/sourceAdapter";
import { threeDMAdapter } from "../src/sources/threeDM";
import { udnGameAdapter } from "../src/sources/udnGame";
import { vgtimeAdapter } from "../src/sources/vgtime";
import { PROVENANCE_SOURCE_IDENTITIES } from "../src/sources/provenanceRegistry";
import bahamutHTML from "./fixtures/bahamut.html?raw";
import fourGamersHTML from "./fixtures/fourgamers.html?raw";
import gamebaseHTML from "./fixtures/gamebase.html?raw";
import gamerskyHTML from "./fixtures/gamersky.html?raw";
import gcoresHTML from "./fixtures/gcores.html?raw";
import ithomeHTML from "./fixtures/ithome.html?raw";
import mydriversHTML from "./fixtures/mydrivers.html?raw";
import mydriversRepostHTML from "./fixtures/mydrivers-repost.html?raw";
import rockstarHTML from "./fixtures/rockstar.html?raw";
import threeDMHTML from "./fixtures/threedm.html?raw";
import udnGameHTML from "./fixtures/udn-game.html?raw";
import vgtimeHTML from "./fixtures/vgtime.html?raw";
import bahamutListHTML from "./fixtures/bahamut-list.html?raw";
import fourGamersListHTML from "./fixtures/fourgamers-list.html?raw";
import gamebaseListHTML from "./fixtures/gamebase-list.html?raw";
import gamerskyListHTML from "./fixtures/gamersky-list.html?raw";
import gcoresListHTML from "./fixtures/gcores-list.html?raw";
import ithomeListHTML from "./fixtures/ithome-list.html?raw";
import mydriversListHTML from "./fixtures/mydrivers-list.html?raw";
import rockstarListHTML from "./fixtures/rockstar-list.html?raw";
import threeDMListHTML from "./fixtures/threedm-list.html?raw";
import udnGameListHTML from "./fixtures/udn-game-list.html?raw";
import vgtimeListHTML from "./fixtures/vgtime-list.html?raw";
import { deduplicateArticles } from "../src/pipeline/dedupe";

const fixtureHTML: Readonly<Record<string, string>> = {
  bahamut: bahamutHTML, fourgamers: fourGamersHTML, gamebase: gamebaseHTML,
  gamersky: gamerskyHTML, gcores: gcoresHTML, ithome: ithomeHTML,
  mydrivers: mydriversHTML, rockstar: rockstarHTML, threedm: threeDMHTML,
  "udn-game": udnGameHTML, vgtime: vgtimeHTML
};
const html = (name: string) => fixtureHTML[name];
const withoutTitle = (value: string) => value
  .replace(/"headline":"[^"]+"/u, '"headline":""')
  .replace(/(<h1\b[^>]*>)[\s\S]*?(<\/h1>)/iu, "$1$2")
  .replace(/<meta\b[^>]*(?:property|name)=["'](?:og:title|twitter:title|title)["'][^>]*>/giu,
    (tag) => tag.replace(/content=["'][^"']*["']/iu, 'content=""'));
const listHTML: Readonly<Record<string, string>> = {
  bahamut: bahamutListHTML, fourgamers: fourGamersListHTML, gamebase: gamebaseListHTML,
  gamersky: gamerskyListHTML, gcores: gcoresListHTML, ithome: ithomeListHTML,
  mydrivers: mydriversListHTML, rockstar: rockstarListHTML, threedm: threeDMListHTML,
  "udn-game": udnGameListHTML, vgtime: vgtimeListHTML
};

const cases = [
  [rockstarAdapter, "rockstar", "rockstar-newswire", "officialCandidate", "2025-11-06T00:00:00.000Z"],
  [gamerskyAdapter, "gamersky", "gamersky", "media", "2026-06-29T09:40:39.000Z"],
  [threeDMAdapter, "threedm", "3dm", "media", "2025-11-06T22:34:56.000Z"],
  [gcoresAdapter, "gcores", "gcores", "media", "2026-06-25T04:00:00.000Z"],
  [bahamutAdapter, "bahamut", "bahamut-gnn", "media", "2026-06-18T02:30:00.000Z"],
  [fourGamersAdapter, "fourgamers", "4gamers", "media", "2026-06-24T11:36:59.000Z"],
  [udnGameAdapter, "udn-game", "udn-game", "media", "2026-06-29T07:32:00.000Z"],
  [ithomeAdapter, "ithome", "ithome", "media", "2026-06-24T10:32:56.000Z"],
  [mydriversAdapter, "mydrivers", "mydrivers", "media", "2026-07-16T16:46:07.000Z"],
  [vgtimeAdapter, "vgtime", "vgtime", "media", "2025-11-10T01:00:00.000Z"],
  [gamebaseAdapter, "gamebase", "gamebase", "media", "2025-11-07T03:00:00.000Z"]
] as const;

describe("Chinese source adapters", () => {
  it.each(cases)("parses %s safely", (adapter, fixture, id, kind, publishedAt) => {
    const result = adapter.parse(html(fixture));
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.articles).toHaveLength(1);
    expect(result.articles[0]).toMatchObject({ adapter: { id, kind }, publishedAt });
    expect(result.articles[0].id.length).toBeGreaterThan(0);
    expect(result.articles[0].id.length).toBeLessThanOrEqual(256);
    expect(new URL(result.articles[0].sourceURL).hostname).toMatch(adapter.trustedHosts[0]);
    expect(result.articles[0].claimedCredibility).toBeUndefined();
  });

  it.each(cases)("closes list-to-detail fetching for %s", async (adapter, fixture) => {
    const calls: string[] = [];
    const result = await runSourceAdapters([adapter], {
      fetcher: async (input) => {
        const url = String(input);
        calls.push(url);
        return new Response(url === adapter.url ? listHTML[fixture] : html(fixture));
      },
      maxArticlesPerSource: 1
    });
    expect(calls).toHaveLength(2);
    expect(result.failures).toHaveLength(0);
    expect(result.articles).toHaveLength(1);
  });

  it.each(cases)("rejects a malformed %s entry without throwing", (adapter, fixture) => {
    const valid = html(fixture);
    const malformed = withoutTitle(valid);
    expect(adapter.parse(malformed)).toMatchObject({ ok: false, failure: { stage: "parse" } });
  });

  it("rejects spoofed article and unsafe image hosts", () => {
    const spoofed = html("ithome").replaceAll("/0/968/138.htm", "https://www.ithome.com.evil.example/story");
    expect(ithomeAdapter.parse(spoofed)).toMatchObject({ ok: false, failure: { stage: "parse" } });
    const unsafeImage = html("ithome").replace("https://img.ithome.com/cover.jpg", "javascript:alert(1)");
    const result = ithomeAdapter.parse(unsafeImage);
    expect(result.ok && result.articles[0].imageURL).toBeNull();
  });

  it("rejects a same-host canonical URL outside the source article namespace", () => {
    const nonArticle = html("ithome").replaceAll("/0/968/138.htm", "/search?keyword=GTA6");
    expect(ithomeAdapter.parse(nonArticle)).toMatchObject({ ok: false, failure: { stage: "parse" } });
  });

  it("rejects an oversized raw URL identity instead of replacing it with a short hash", () => {
    const oversized = html("ithome").replaceAll("/0/968/138.htm", `/0/${"a".repeat(300)}.htm`);
    expect(ithomeAdapter.parse(oversized)).toMatchObject({ ok: false, failure: { stage: "parse" } });
  });

  it("bounds editorial text by Unicode code point and never forwards a body-sized description", () => {
    const longSummary = "简😀".repeat(300);
    const document = `<script type="application/ld+json">${JSON.stringify({
      "@type": "NewsArticle",
      headline: "《侠盗猎车手 6》最新消息",
      description: longSummary,
      url: "/0/968/139.htm",
      datePublished: "2026-06-24T18:32:56+08:00",
      identifier: "话题".repeat(100)
    })}</script>`;
    const result = ithomeAdapter.parse(document);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(Array.from(result.articles[0].summary)).toHaveLength(360);
    expect(result.articles[0].summary).not.toContain("�");
    expect(result.articles[0].upstreamTopicKey).toBeNull();

    const oversizedTitle = document.replace("《侠盗猎车手 6》最新消息", "题".repeat(181));
    expect(ithomeAdapter.parse(oversizedTitle)).toMatchObject({ ok: false, failure: { stage: "parse" } });
  });

  it("bounds nested image candidates and continues to a later valid article", () => {
    const malformedCandidate = {
      "@type": "NewsArticle",
      headline: "GTA VI 深层图片候选",
      description: "这条候选的图片结构异常，但不应影响后续文章。",
      image: "NESTED_IMAGE_PLACEHOLDER",
      url: "/0/968/140.htm",
      datePublished: "2026-06-24T18:32:56+08:00"
    };
    const validCandidate = {
      "@type": "NewsArticle",
      headline: "GTA VI 正常图片候选",
      description: "后续文章仍然能够被适配器正常解析。",
      image: "https://img.ithome.com/valid.jpg",
      url: "/0/968/141.htm",
      datePublished: "2026-06-24T18:33:56+08:00"
    };
    const deeplyNestedImage = `${"[".repeat(20_000)}"https://img.ithome.com/deep.jpg"${"]".repeat(20_000)}`;
    const candidateJSON = JSON.stringify([malformedCandidate, validCandidate])
      .replace('"NESTED_IMAGE_PLACEHOLDER"', deeplyNestedImage);
    const document = `<script type="application/ld+json">${candidateJSON}</script>`;
    const result = ithomeAdapter.parse(document);
    expect(result.ok).toBe(true);
    if (!result.ok) return;
    expect(result.articles).toHaveLength(2);
    expect(result.articles[0].imageURL).toBeNull();
    expect(result.articles[1].imageURL).toBe("https://img.ithome.com/valid.jpg");
  });

  it("treats malformed numeric HTML entities as text instead of throwing", () => {
    const malformedEntity = html("gamersky").replace("商店页面", "&#999999999;商店页面");
    expect(() => gamerskyAdapter.parse(malformedEntity)).not.toThrow();
    expect(gamerskyAdapter.parse(malformedEntity).ok).toBe(true);
  });

  it("emits records accepted by Task 10 without leaking adapter internals", () => {
    const result = rockstarAdapter.parse(html("rockstar"));
    if (!result.ok) throw new Error("fixture unexpectedly failed");
    const normalized = normalizeArticle(result.articles[0]);
    expect(normalized).not.toBeNull();
    expect(toNewsArticle(normalized!)).not.toHaveProperty("attributedAdapterID");
    expect(toNewsArticle(normalized!)).not.toHaveProperty("explicitTopicKey");
  });

  it("attributes a traceable repost to the exact registered original article", () => {
    const repost = mydriversAdapter.parse(mydriversRepostHTML);
    expect(repost.ok).toBe(true);
    if (!repost.ok) return;
    expect(repost.articles[0].originalSource).toEqual({
      sourceName: "游民星空",
      sourceURL: "https://www.gamersky.com/news/202606/2164170.shtml",
      adapter: { id: "gamersky", kind: "media" }
    });

    const directHTML = html("gamersky")
      .replace("《GTA6》单机模式有氪金内购？", "《GTA6》平台安排公布")
      .replace("商店页面标签引发玩家讨论。", "游民星空报道了 GTA6 的平台安排。");
    const direct = gamerskyAdapter.parse(directHTML);
    if (!direct.ok) throw new Error("direct fixture unexpectedly failed");
    const normalizedRepost = normalizeArticle(repost.articles[0]);
    const normalizedDirect = normalizeArticle(direct.articles[0]);
    expect(normalizedRepost).toMatchObject({
      sourceName: "游民星空",
      sourceURL: "https://www.gamersky.com/news/202606/2164170.shtml",
      credibility: "media",
      attributedAdapterID: "gamersky"
    });
    const deduped = deduplicateArticles([normalizedRepost!, normalizedDirect!]);
    expect(deduped).toHaveLength(1);
    expect(deduped[0].relatedSourceCount).toBe(0);
    const publicArticle = toNewsArticle(deduped[0]);
    expect(publicArticle).toMatchObject({
      sourceName: "游民星空",
      sourceURL: "https://www.gamersky.com/news/202606/2164170.shtml",
      credibility: "media"
    });
    expect(publicArticle).not.toHaveProperty("originalSource");
    expect(publicArticle).not.toHaveProperty("attributedAdapterID");
  });

  it("does not invent provenance from text-only, spoofed, invalid-path, or unknown sources", () => {
    const plain = mydriversAdapter.parse(html("mydrivers"));
    expect(plain.ok && plain.articles[0].originalSource).toBeUndefined();
    for (const link of [
      "https://evil.example/news/202606/2164170.shtml",
      "https://www.gamersky.com/privacy",
      "https://www.gamersky.com:8443/news/202606/2164170.shtml",
      "https://unknown.example/article/1"
    ]) {
      const spoofed = mydriversRepostHTML.replace("https://www.gamersky.com/news/202606/2164170.shtml", link);
      const result = mydriversAdapter.parse(spoofed);
      expect(result.ok).toBe(true);
      expect(result.ok && result.articles[0].originalSource).toBeUndefined();
      expect(result.ok && result.articles[0].sourceName).toBe("快科技");
    }
  });

  it.each(["citation", "isBasedOn", "isBasedOnUrl"] as const)("does not infer provenance from generic JSON-LD %s", (field) => {
    const cited = html("ithome").replace(
      '"image":"https://img.ithome.com/cover.jpg"',
      `"image":"https://img.ithome.com/cover.jpg","${field}":{"name":"任意显示名","url":"https://www.3dmgame.com/news/202511/3931272.html"}`
    );
    const result = ithomeAdapter.parse(cited);
    expect(result.ok).toBe(true);
    expect(result.ok && result.articles[0].originalSource).toBeUndefined();
  });

  it("does not treat a bibliography citation or related link as repost provenance", () => {
    const bibliography = html("ithome").replace(
      '"image":"https://img.ithome.com/cover.jpg"',
      '"image":"https://img.ithome.com/cover.jpg","citation":"https://www.gamersky.com/news/202606/2164170.shtml"'
    );
    const related = `${html("mydrivers")}<p>参考来源与延伸阅读</p><a href="https://www.gamersky.com/news/202606/2164170.shtml">相关报道</a>`;
    for (const [adapter, document] of [[ithomeAdapter, bibliography], [mydriversAdapter, related]] as const) {
      const result = adapter.parse(document);
      expect(result.ok).toBe(true);
      expect(result.ok && result.articles[0].originalSource).toBeUndefined();
    }
  });

  it("bounds deeply nested untrusted JSON-LD without throwing", () => {
    const probes = ["@graph", "headline", "citation"].map((field) =>
      `<script type="application/ld+json">{"${field}":${"[".repeat(20_000)}null${"]".repeat(20_000)}}</script>`
    );
    for (const document of probes) {
      expect(document.length).toBeGreaterThan(40_000);
      expect(() => ithomeAdapter.parse(document)).not.toThrow();
      expect(ithomeAdapter.parse(document)).toMatchObject({ ok: false, failure: { stage: "parse" } });
    }
  });

  it("keeps registry identities aligned with the 11 adapter descriptors", () => {
    const adapters = cases.map(([adapter]) => ({ id: adapter.id, kind: adapter.kind, sourceName: adapter.sourceName }));
    expect(PROVENANCE_SOURCE_IDENTITIES).toEqual(adapters);
  });

  it("represents a traceable Rockstar original without upgrading the repost to official", () => {
    const rockstarURL = "https://www.rockstargames.com/zh/newswire/article/ak3ak31a49a221/grand-theft-auto-vi-release";
    const cited = mydriversRepostHTML.replace(
      "https://www.gamersky.com/news/202606/2164170.shtml",
      rockstarURL
    );
    const result = mydriversAdapter.parse(cited);
    if (!result.ok) throw new Error("repost fixture unexpectedly failed");
    expect(result.articles[0].originalSource).toEqual({
      sourceName: "Rockstar Games",
      sourceURL: rockstarURL,
      adapter: { id: "rockstar-newswire", kind: "officialCandidate" }
    });
    expect(normalizeArticle(result.articles[0])).toMatchObject({
      sourceName: "Rockstar Games",
      sourceURL: rockstarURL,
      credibility: "media",
      isOfficial: false,
      attributedAdapterID: "rockstar-newswire"
    });
  });
});

describe("source runner", () => {
  function adapter(id: string, url: string): SourceAdapter {
    return { ...gamerskyAdapter, id, url };
  }

  it("isolates source failure and limits articles per source", async () => {
    const fetcher = async (input: RequestInfo | URL) => {
      const url = String(input);
      if (url.includes("broken")) throw new Error("offline");
      return new Response(url.includes("good") ? `${listHTML.gamersky}${listHTML.gamersky}` : html("gamersky"), { status: 200 });
    };
    const result = await runSourceAdapters([
      adapter("good", "https://www.gamersky.com/good"),
      adapter("broken", "https://www.gamersky.com/broken")
    ], { fetcher, maxArticlesPerSource: 1 });
    expect(result.articles).toHaveLength(1);
    expect(result.failures).toEqual([expect.objectContaining({ sourceID: "broken", stage: "fetch" })]);
  });

  it("keeps a valid detail when another detail from the same source is malformed", async () => {
    const listing = `${listHTML.gamersky}<a href="/news/202606/2164171.shtml">second</a>`;
    const result = await runSourceAdapters([gamerskyAdapter], {
      fetcher: async (input) => {
        const url = String(input);
        if (url === gamerskyAdapter.url) return new Response(listing);
        if (url.endsWith("2164170.shtml")) return new Response(withoutTitle(html("gamersky")));
        return new Response(html("gamersky").replaceAll("2164170.shtml", "2164171.shtml"));
      },
      maxArticlesPerSource: 2
    });
    expect(result.articles).toHaveLength(1);
    expect(result.failures).toEqual([expect.objectContaining({ sourceID: "gamersky", stage: "parse" })]);
  });

  it("classifies an unexpected adapter parser exception as parse, not fetch", async () => {
    const throwing: SourceAdapter = {
      ...gamerskyAdapter,
      parse: () => { throw new RangeError("untrusted parser depth"); }
    };
    const result = await runSourceAdapters([throwing], {
      fetcher: async (input) => new Response(String(input) === throwing.url ? listHTML.gamersky : html("gamersky"))
    });
    expect(result.failures).toEqual([expect.objectContaining({ sourceID: "gamersky", stage: "parse" })]);
  });

  it("enforces concurrency, timeout, response-size and cancellation bounds", async () => {
    let active = 0;
    let peak = 0;
    const fetcher = async (_input: RequestInfo | URL, init?: RequestInit) => {
      active += 1;
      peak = Math.max(peak, active);
      await new Promise<void>((resolve, reject) => {
        const timer = setTimeout(resolve, 10);
        init?.signal?.addEventListener("abort", () => { clearTimeout(timer); reject(init.signal?.reason); });
      });
      active -= 1;
      return new Response(String(_input).match(/\/\d$/u) ? listHTML.gamersky : html("gamersky"));
    };
    const sources = Array.from({ length: 5 }, (_, index) => adapter(`s${index}`, `https://www.gamersky.com/${index}`));
    const ok = await runSourceAdapters(sources, { fetcher, concurrency: 2, timeoutMs: 100, maxResponseBytes: 20_000 });
    expect(peak).toBeLessThanOrEqual(2);
    expect(ok.failures).toHaveLength(0);

    const oversized = await runSourceAdapters([adapter("large", "https://www.gamersky.com/large")], {
      fetcher: async () => new Response("x".repeat(101)), maxResponseBytes: 100
    });
    expect(oversized.failures[0]).toMatchObject({ stage: "size" });

    const timeout = await runSourceAdapters([adapter("slow", "https://www.gamersky.com/slow")], {
      fetcher: () => new Promise(() => {}), timeoutMs: 5
    });
    expect(timeout.failures[0]).toMatchObject({ stage: "timeout" });

    const controller = new AbortController();
    controller.abort("cancelled");
    const cancelled = await runSourceAdapters([adapter("cancel", "https://www.gamersky.com/cancel")], {
      fetcher, signal: controller.signal
    });
    expect(cancelled.failures[0]).toMatchObject({ stage: "cancelled" });
  });

  it("validates every redirect before following it", async () => {
    const redirected = (location: string) => async () => new Response(null, {
      status: 302, headers: { Location: location }
    });
    for (const location of [
      "https://evil.example/list",
      "http://www.gamersky.com/list",
      "https://user:secret@www.gamersky.com/list",
      "https://127.0.0.1/list",
      "https://www.gamersky.com:8443/list"
    ]) {
      const result = await runSourceAdapters([adapter("redirect", "https://www.gamersky.com/start")], {
        fetcher: redirected(location)
      });
      expect(result.failures[0]).toMatchObject({ stage: "fetch" });
    }

    const cycle = await runSourceAdapters([adapter("cycle", "https://www.gamersky.com/a")], {
      fetcher: async (input) => new Response(null, {
        status: 302, headers: { Location: String(input).endsWith("/a") ? "/b" : "/a" }
      })
    });
    expect(cycle.failures[0]).toMatchObject({ stage: "fetch", reason: "redirect cycle detected" });

    let redirectCount = 0;
    const tooMany = await runSourceAdapters([adapter("many", "https://www.gamersky.com/0")], {
      fetcher: async () => new Response(null, { status: 302, headers: { Location: `/${++redirectCount}` } })
    });
    expect(tooMany.failures[0]).toMatchObject({ stage: "fetch", reason: "too many redirects" });
  });

  it("fails closed on a declared legacy charset instead of emitting mojibake", async () => {
    const result = await runSourceAdapters([adapter("gb", "https://www.gamersky.com/gb")], {
      fetcher: async () => new Response(new Uint8Array([0xc4, 0xe3]), {
        headers: { "Content-Type": "text/html; charset=gb2312" }
      })
    });
    expect(result.failures[0]).toMatchObject({ stage: "decode", reason: "unsupported response charset: gb2312" });

    const metaOnly = await runSourceAdapters([adapter("gb-meta", "https://www.gamersky.com/gb-meta")], {
      fetcher: async () => new Response('<meta http-equiv="Content-Type" content="text/html; charset=gb2312">')
    });
    expect(metaOnly.failures[0]).toMatchObject({ stage: "decode", reason: "unsupported document charset: gb2312" });
  });
});
