import { createJSONLDAdapter } from "./jsonLDAdapter";
export const ithomeAdapter = createJSONLDAdapter({ id: "ithome", kind: "media", sourceName: "IT之家", url: "https://www.ithome.com/search?keyword=GTA6", baseURL: "https://www.ithome.com/", trustedHosts: ["ithome.com"], imageHosts: ["ithome.com"], articlePathPattern: /^\/0\/\d+\/\d+\.htm$/u });
