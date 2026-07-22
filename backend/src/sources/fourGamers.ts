import { createJSONLDAdapter } from "./jsonLDAdapter";
export const fourGamersAdapter = createJSONLDAdapter({ id: "4gamers", kind: "media", sourceName: "4Gamers", url: "https://www.4gamers.com.tw/site/search?keyword=GTA6", baseURL: "https://www.4gamers.com.tw/", trustedHosts: ["4gamers.com.tw"], imageHosts: ["4gamers.com.tw"], articlePathPattern: /^\/news\/detail\/\d+\/[a-z0-9-]+$/u });
