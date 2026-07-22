import { createJSONLDAdapter } from "./jsonLDAdapter";
export const mydriversAdapter = createJSONLDAdapter({ id: "mydrivers", kind: "media", sourceName: "快科技", url: "https://news.mydrivers.com/tag/gta6.htm", baseURL: "https://news.mydrivers.com/", trustedHosts: ["mydrivers.com"], imageHosts: ["mydrivers.com"], articlePathPattern: /^\/1\/\d+\/\d+\.htm$/u });
