import { afterEach, describe, expect, it } from "vite-plus/test";
import { landFocus } from "./landFocus.ts";

/** a11y checklist C (Now): after acting, focus lands on the row's resolved line, never <body>. */
function panel(rows: string[]) {
  const section = document.createElement("section");
  section.innerHTML = `<h2>Action queue</h2><ul>${rows.map((k) => `<li data-key="${k}">${k}</li>`).join("")}</ul>`;
  document.body.appendChild(section);
  return section.querySelector("ul");
}
afterEach(() => {
  document.body.innerHTML = "";
});

describe("landing focus after a row resolves", () => {
  it("prefers the row's resolved line", async () => {
    const list = panel(["a", "a|resolved", "b"]);
    await landFocus(list, "a");
    expect(document.activeElement?.getAttribute("data-key")).toBe("a|resolved");
    expect(document.activeElement?.getAttribute("tabindex")).toBe("-1");
  });

  it("falls to the row while it's still open (retried)", async () => {
    const list = panel(["a", "b"]);
    await landFocus(list, "b");
    expect(document.activeElement?.getAttribute("data-key")).toBe("b");
  });

  it("falls to the queue's heading when the row is gone", async () => {
    const list = panel(["b"]);
    await landFocus(list, "a", 30);
    expect(document.activeElement?.textContent).toBe("Action queue");
  });

  it("leaves focus where it is when it already went somewhere real", async () => {
    const list = panel(["a|resolved"]);
    const kept = document.createElement("button");
    document.body.appendChild(kept);
    kept.focus();
    await landFocus(list, "a");
    expect(document.activeElement).toBe(kept);
  });
});
