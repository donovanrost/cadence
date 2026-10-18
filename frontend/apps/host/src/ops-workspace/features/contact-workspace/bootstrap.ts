import { createApp } from "vue";
import { createWebHistory } from "vue-router";
import { VueQueryPlugin } from "@tanstack/vue-query";
import ContactWorkspaceApp from "./ContactWorkspaceApp.vue";
import { readWorkspaceBootstrap } from "./contracts";
import { createContactWorkspaceRouter } from "./router";
import { createWorkspaceClient, createWorkspaceQueryClient, workspaceClientKey } from "./client";

export async function mountContactWorkspace(root: HTMLElement) {
  const value: unknown = JSON.parse(root.dataset.bootstrap ?? "null");
  const bootstrap = readWorkspaceBootstrap(value);
  const router = createContactWorkspaceRouter(bootstrap.missionId, createWebHistory());
  const queries = createWorkspaceQueryClient();
  const client = createWorkspaceClient(bootstrap, queries);
  const app = createApp(ContactWorkspaceApp, { bootstrap });
  app.use(router);
  app.use(VueQueryPlugin, { queryClient: queries });
  app.provide(workspaceClientKey, client);
  await router.isReady();
  app.mount(root);
  window.addEventListener("pagehide", (event) => {
    if (event.persisted) return;
    app.unmount();
    queries.clear();
    router.options.history.destroy();
  });
}
