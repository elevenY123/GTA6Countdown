declare module "opencc-js/t2cn" {
  export function Converter(options: {
    readonly from: "hk" | "tw";
    readonly to: "cn";
  }): (text: string) => string;
}
