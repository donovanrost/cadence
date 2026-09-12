import * as vue from "vue";
export function installDom(markup = '<div id="app"></div>') {
  document.body.innerHTML = markup;
  return { window };
}
export async function flushVue(nextTick = vue.nextTick) {
  await nextTick();
  await new Promise((resolve) => setTimeout(resolve, 0));
  await nextTick();
}
export const elementAttributes = (element: Element) =>
  Object.fromEntries(
    element
      .getAttributeNames()
      .sort()
      .map((name) => [name, element.getAttribute(name)]),
  );

export { required } from "./required.ts";
export function nativeElement(value: unknown): HTMLElement | null {
  if (value === null) return null;
  if (!(value instanceof HTMLElement)) throw new Error("Expected a native HTML element ref");
  return value;
}
export function nativeInput(value: unknown): HTMLInputElement | null {
  if (value === null) return null;
  if (!(value instanceof HTMLInputElement)) throw new Error("Expected a native input ref");
  return value;
}
