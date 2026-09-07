import * as vue from "vue";
import { basename } from "node:path";

// Vite compiles the actual components through the same Vue plugin as production.
const modules = import.meta.glob(
  ["../packages/ui/src/**/*.vue", "../apps/host/src/shell/**/*.vue"],
  { eager: true, import: "default" },
);
const components = new Map(
  Object.entries(modules).map(([path, component]) => [basename(path), component]),
);
export async function loadSfc(path) {
  const component = components.get(basename(path));
  if (!component) throw new Error(`Unknown contract component: ${path}`);
  return { component };
}
export function integrationRequire(name) {
  if (name !== "vue") throw new Error(`Use an ordinary import for ${name}`);
  return vue;
}
export function installDom(markup = '<div id="app"></div>') {
  document.body.innerHTML = markup;
  return { window };
}
export async function flushVue(nextTick = vue.nextTick) {
  await nextTick();
  await new Promise((resolve) => setTimeout(resolve, 0));
  await nextTick();
}
export const elementAttributes = (element) =>
  Object.fromEntries(
    element
      .getAttributeNames()
      .sort()
      .map((name) => [name, element.getAttribute(name)]),
  );
