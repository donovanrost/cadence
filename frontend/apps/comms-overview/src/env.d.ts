/// <reference types="vite/client" />

declare module "*.vue" {
  import type { DefineComponent } from "vue";

  const component: DefineComponent;
  export default component;
}

declare module "@cadence/cadence-web-vue/CommsOverviewPage.vue" {
  import type { DefineComponent } from "vue";

  const component: DefineComponent;
  export default component;
}
