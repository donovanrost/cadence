/// <reference types="vite/client" />

declare const __CADENCE_REMOTE_RELEASE__: string;

declare module "*.vue" {
  import type { DefineComponent } from "vue";

  const component: DefineComponent;
  export default component;
}
