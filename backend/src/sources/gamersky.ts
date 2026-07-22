import { createJSONLDAdapter } from "./jsonLDAdapter";
export const gamerskyAdapter = createJSONLDAdapter({ id: "gamersky", kind: "media", sourceName: "游民星空", url: "https://www.gamersky.com/z/gta6/news/", baseURL: "https://www.gamersky.com/", trustedHosts: ["gamersky.com"], imageHosts: ["gamersky.com"], articlePathPattern: /^\/news\/\d{6}\/\d+\.shtml$/u });
