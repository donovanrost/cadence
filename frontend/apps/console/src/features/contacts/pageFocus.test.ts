import { afterEach, describe, expect, it } from "vite-plus/test";
import { holdsFocus, landOnFirstNew } from "./pageFocus.ts";

/** a11y A5 / B4 (#243): Show earlier's last page lands focus only if the button had it. */
function list(rows: number) {
  const ul = document.createElement("ul");
  ul.innerHTML = Array.from({ length: rows }, (_, i) => `<li>row ${i}</li>`).join("");
  document.body.appendChild(ul);
  return ul;
}
afterEach(() => {
  document.body.innerHTML = "";
});

describe("Show earlier's focus on the last page", () => {
  it("lands on the first new row, made focusable, when the button had focus", async () => {
    const ul = list(5);
    await landOnFirstNew(ul, 3, true);
    expect(document.activeElement?.textContent).toBe("row 3");
    expect(document.activeElement?.getAttribute("tabindex")).toBe("-1");
  });

  it("leaves focus where the person put it otherwise", async () => {
    const ul = list(5);
    const elsewhere = document.createElement("button");
    document.body.appendChild(elsewhere);
    elsewhere.focus();
    await landOnFirstNew(ul, 3, false);
    expect(document.activeElement).toBe(elsewhere);
  });

  it("knows whether focus is inside a wrapper", () => {
    const wrap = document.createElement("div");
    const button = document.createElement("button");
    wrap.appendChild(button);
    document.body.appendChild(wrap);
    expect(holdsFocus(wrap)).toBe(false);
    button.focus();
    expect(holdsFocus(wrap)).toBe(true);
    expect(holdsFocus(null)).toBe(false);
  });
});
