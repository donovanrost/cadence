import { createRouter, type RouterHistory } from "vue-router";
import type { InjectionKey } from "vue";
import { workspaceBase, type WorkspaceBootstrap } from "./contracts";
import ContactWorkspacePage from "./ContactWorkspacePage.vue";
export const workspaceBootstrapKey: InjectionKey<WorkspaceBootstrap> =
  Symbol("workspace-bootstrap");
export function createContactWorkspaceRouter(mission: string, history: RouterHistory) {
  const base = workspaceBase(mission);
  return createRouter({
    history,
    routes: [
      { path: base, name: "contact-schedule", component: ContactWorkspacePage },
      {
        path: `${base}/records/:contactId`,
        name: "contact-record",
        component: ContactWorkspacePage,
      },
    ],
  });
}
