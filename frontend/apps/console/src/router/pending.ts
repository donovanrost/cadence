import type { RouteComponent } from "vue-router";

/** Placeholder for a screen that isn't built yet. Replace with the feature's screen import. */
export const pending = (): Promise<RouteComponent> => import("@/shell/PendingScreen.vue");
