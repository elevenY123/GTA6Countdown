import { createJSONLDAdapter } from "./jsonLDAdapter";
export const gcoresAdapter = createJSONLDAdapter({ id: "gcores", kind: "media", sourceName: "机核", url: "https://www.gcores.com/search?keyword=GTA6", baseURL: "https://www.gcores.com/", trustedHosts: ["gcores.com"], imageHosts: ["gcores.com"], articlePathPattern: /^\/articles\/\d+$/u });
