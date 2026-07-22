import type { Credibility, PipelineArticle } from "../domain/article";

const CREDIBILITY_PRIORITY: Record<Credibility, number> = {
  official: 2,
  media: 1,
  unverified: 0
};

function compareText(left: string, right: string): number {
  if (left === right) return 0;
  return left < right ? -1 : 1;
}

function stableArticleKey(article: PipelineArticle): string {
  return JSON.stringify([
    article.id,
    article.publishedAt,
    article.credibility,
    article.isOfficial,
    article.isPinned,
    article.sourceURL,
    article.sourceName,
    article.title,
    article.summary,
    article.imageURL,
    article.canonicalTopicKey,
    article.relatedSourceCount,
    article.attributedAdapterID,
    article.explicitTopicKey
  ]);
}

function preferredArticle(left: PipelineArticle, right: PipelineArticle): number {
  const credibility = CREDIBILITY_PRIORITY[right.credibility] - CREDIBILITY_PRIORITY[left.credibility];
  if (credibility !== 0) return credibility;
  if (left.isPinned !== right.isPinned) return left.isPinned ? -1 : 1;
  const published = Date.parse(right.publishedAt) - Date.parse(left.publishedAt);
  if (published !== 0) return published;
  const id = compareText(left.id, right.id);
  return id !== 0 ? id : compareText(stableArticleKey(left), stableArticleKey(right));
}

function outputOrder(left: PipelineArticle, right: PipelineArticle): number {
  if (left.isPinned !== right.isPinned) return left.isPinned ? -1 : 1;
  const official = Number(right.isOfficial) - Number(left.isOfficial);
  if (official !== 0) return official;
  const published = Date.parse(right.publishedAt) - Date.parse(left.publishedAt);
  if (published !== 0) return published;
  const id = compareText(left.id, right.id);
  return id !== 0 ? id : compareText(stableArticleKey(left), stableArticleKey(right));
}

function normalizedTitle(value: string): string {
  return value
    .normalize("NFKC")
    .toLocaleLowerCase("en-US")
    .replace(/\b(?:gta\s*(?:vi|6)|grand\s+theft\s+auto\s*(?:vi|6))\b/gi, "gtavi")
    .replace(/[《》「」『』【】()（）]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function chineseNumber(value: string | undefined): string | null {
  if (!value) return null;
  if (/^\d+$/.test(value)) return String(Number(value));
  const values: Record<string, string> = {
    一: "1", 二: "2", 两: "2", 三: "3", 四: "4", 五: "5",
    六: "6", 七: "7", 八: "8", 九: "9", 十: "10"
  };
  return values[value] ?? null;
}

function trailerNumber(title: string): string | null {
  const before = title.match(/第\s*([一二两三四五六七八九十\d]+)\s*支?\s*预告/);
  const after = title.match(/预告(?:片)?\s*([一二两三四五六七八九十\d]+)/);
  return chineseNumber(before?.[1] ?? after?.[1]);
}

function releaseDateSignature(title: string): string | null {
  if (!/(?:发售|发行|推出)/.test(title)) return null;
  const date = title.match(/(20\d{2})\s*年\s*(\d{1,2})\s*月(?:\s*(\d{1,2})\s*日)?/);
  return date ? `${date[1]}-${Number(date[2])}-${date[3] ? Number(date[3]) : "x"}` : null;
}

function eventFamily(title: string): "trailer" | "release" | "map" | "gameplay" | "characters" | null {
  if (/预告/.test(title)) return "trailer";
  if (/(?:发售|发行|推出)/.test(title)) return "release";
  if (/地图/.test(title)) return "map";
  if (/(?:实机|玩法|游戏演示)/.test(title)) return "gameplay";
  if (/(?:主角|角色)/.test(title)) return "characters";
  return null;
}

function titleTokens(title: string): Set<string> {
  const reduced = title
    .replace(/gtavi/g, " ")
    .replace(/(?:正式|最新|消息|媒体|转述|确认|宣布|公布|公开|发布|展示|带来)/g, " ");
  const tokens = new Set(reduced.match(/[a-z]+|\d+|[\u3400-\u9fff]{2}/gu) ?? []);
  for (const run of reduced.match(/[\u3400-\u9fff]{3,}/gu) ?? []) {
    for (let index = 0; index < run.length - 1; index += 1) {
      tokens.add(run.slice(index, index + 2));
    }
  }
  return tokens;
}

function jaccard(left: Set<string>, right: Set<string>): number {
  if (left.size === 0 || right.size === 0) return 0;
  let intersection = 0;
  for (const token of left) if (right.has(token)) intersection += 1;
  return intersection / (left.size + right.size - intersection);
}

interface PreparedArticle {
  readonly article: PipelineArticle;
  readonly normalizedTopic: string;
  readonly family: ReturnType<typeof eventFamily>;
  readonly trailerNumber: string | null;
  readonly releaseDate: string | null;
  readonly tokens: Set<string>;
}

function prepareArticle(article: PipelineArticle): PreparedArticle {
  const title = normalizedTitle(article.title);
  return {
    article,
    normalizedTopic: article.canonicalTopicKey.trim().toLocaleLowerCase("en-US"),
    family: eventFamily(title),
    trailerNumber: trailerNumber(title),
    releaseDate: releaseDateSignature(title),
    tokens: titleTokens(title)
  };
}

function areSimilarTopics(left: PreparedArticle, right: PreparedArticle): boolean {
  if (!left.family || left.family !== right.family) return false;

  if (left.family === "trailer") {
    if (left.trailerNumber && right.trailerNumber) return left.trailerNumber === right.trailerNumber;
    if (left.trailerNumber !== right.trailerNumber) return false;
  }

  if (left.family === "release") {
    if (left.releaseDate && right.releaseDate) return left.releaseDate === right.releaseDate;
    if (left.releaseDate !== right.releaseDate) return false;
  }

  return jaccard(left.tokens, right.tokens) >= 0.6;
}

function canShareGroup(left: PreparedArticle, right: PreparedArticle): boolean {
  if (left.normalizedTopic !== "" && left.normalizedTopic === right.normalizedTopic) return true;
  if (
    left.article.explicitTopicKey !== null
    && right.article.explicitTopicKey !== null
    && left.article.explicitTopicKey !== right.article.explicitTopicKey
  ) {
    return false;
  }
  return areSimilarTopics(left, right);
}

function sanitizeCount(value: number): number {
  return Number.isFinite(value) ? Math.min(99, Math.max(0, Math.trunc(value))) : 0;
}

/**
 * Collapses stable identities and adapter-assigned topics without mutating
 * articles. Fuzzy groups use complete-link membership to prevent bridge merges.
 */
export function deduplicateArticles(articles: readonly PipelineArticle[]): PipelineArticle[] {
  const prepared = articles.map(prepareArticle).sort((left, right) => {
    const explicit = Number(right.article.explicitTopicKey !== null)
      - Number(left.article.explicitTopicKey !== null);
    return explicit !== 0
      ? explicit
      : compareText(stableArticleKey(left.article), stableArticleKey(right.article));
  });
  const groups: PreparedArticle[][] = [];
  for (const candidate of prepared) {
    const identityGroup = groups.find((members) => (
      members.some((member) => member.article.id === candidate.article.id)
    ));
    const group = identityGroup
      ?? groups.find((members) => members.every((member) => canShareGroup(candidate, member)));
    if (group) group.push(candidate);
    else groups.push([candidate]);
  }

  const collapsed = groups.map((preparedGroup) => {
    const group = preparedGroup.map((item) => item.article);
    const sorted = [...group].sort(preferredArticle);
    const primary = sorted[0];
    const primaryTopic = primary.canonicalTopicKey.trim().toLocaleLowerCase("en-US");
    const groupKey = primaryTopic || `article-${primary.id}`;
    const distinctSources = new Set(group.map((item) => item.attributedAdapterID));
    const inheritedCount = Math.max(...group.map((item) => sanitizeCount(item.relatedSourceCount)));
    const relatedSourceCount = Math.min(99, inheritedCount + Math.max(0, distinctSources.size - 1));

    return {
      ...primary,
      canonicalTopicKey: groupKey,
      relatedSourceCount
    };
  });

  return collapsed.sort(outputOrder);
}
