import { createWebHistory } from "vue-router";

// Register Vue Router's history listener before LiveSocket connects. Only the
// mounted browser host claims history; native Phoenix pages keep their lifecycle.
export const hostBrowserHistory = createWebHistory();
let active = false;
window.addEventListener("popstate", (event) => {
  if (active) event.stopImmediatePropagation();
});
export function ownBrowserHistory(value: boolean) {
  active = value;
}
