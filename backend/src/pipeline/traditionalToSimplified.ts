import { Converter } from "opencc-js/t2cn";
import type { SourceArticle } from "../domain/article";

const convert = Converter({ from: "tw", to: "cn" });

/** Only editorial text is converted. Attribution and URLs remain byte-for-byte intact. */
export function convertArticleTextToSimplified(article: SourceArticle): SourceArticle {
  return {
    ...article,
    title: convert(article.title),
    summary: convert(article.summary),
    adapter: { ...article.adapter },
    originalSource: article.originalSource
      ? { ...article.originalSource, adapter: { ...article.originalSource.adapter } }
      : article.originalSource
  };
}
