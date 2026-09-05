/// <reference types="vite/client" />

declare module "*.vue" {
  import type { DefineComponent } from "vue";

  const component: DefineComponent;
  export default component;
}

declare module "*.js" {
  const moduleValue: any;
  export default moduleValue;
}
