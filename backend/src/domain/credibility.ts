import type { Credibility, SourceArticle } from "./article";

const CHINESE_NEWSWIRE_PATH = /^\/(?:zh|zh-hans|zh-hant)\/newswire(?:\/|$)/i;

export function isTrustedChineseNewswireURL(value: string): boolean {
  try {
    const url = new URL(value);
    return url.protocol === "https:"
      && url.hostname.toLowerCase() === "www.rockstargames.com"
      && (url.port === "" || url.port === "443")
      && url.username === ""
      && url.password === ""
      && CHINESE_NEWSWIRE_PATH.test(url.pathname);
  } catch {
    return false;
  }
}

export function classifyCredibility(article: SourceArticle): Credibility {
  if (article.isLeak) {
    return "unverified";
  }

  if (
    article.adapter.id === "rockstar-newswire"
    && article.adapter.kind === "officialCandidate"
    && isTrustedChineseNewswireURL(article.sourceURL)
  ) {
    return "official";
  }

  if (article.adapter.kind === "community") {
    return "unverified";
  }

  return article.adapter.kind === "media" ? "media" : "unverified";
}
