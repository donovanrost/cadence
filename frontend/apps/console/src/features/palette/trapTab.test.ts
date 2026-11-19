import { afterEach, describe, expect, it } from "vite-plus/test";
import { trapTab } from "./trapTab.ts";

/** a11y A3 (#243): the phone Search sheet keeps Tab inside it. */
function sheet() {
  const outside = document.createElement("button");
  const root = document.createElement("div");
  root.innerHTML = `<input id="q" /><button id="cancel">Cancel</button><a id="r" href="#">Result</a>`;
  document.body.append(outside, root);
  const get = (id: string) => {
    const el = document.getElementById(id);
    if (!el) throw new Error(id);
    return el;
  };
  return { root, outside, q: get("q"), r: get("r") };
}
const tab = (shiftKey = false) =>
  new KeyboardEvent("keydown", { key: "Tab", shiftKey, cancelable: true });
afterEach(() => {
  document.body.innerHTML = "";
});

describe("trapTab", () => {
  it("wraps Tab from the last control to the first, and Shift+Tab from the first to the last", () => {
    const { root, q, r } = sheet();
    r.focus();
    const forward = tab();
    trapTab(root, forward);
    expect(forward.defaultPrevented).toBe(true);
    expect(document.activeElement).toBe(q);
    const back = tab(true);
    trapTab(root, back);
    expect(document.activeElement).toBe(r);
  });

  it("leaves Tab between inner controls to the browser", () => {
    const { root, q } = sheet();
    q.focus();
    const middle = tab();
    trapTab(root, middle);
    expect(middle.defaultPrevented).toBe(false);
  });

  it("brings focus that left the sheet back to its first control", () => {
    const { root, outside, q } = sheet();
    outside.focus();
    const stray = tab();
    trapTab(root, stray);
    expect(document.activeElement).toBe(q);
  });
});
