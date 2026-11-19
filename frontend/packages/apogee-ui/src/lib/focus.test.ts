import { afterEach, describe, expect, it } from "vite-plus/test";
import { focusLost, refocusFirst } from "./focus.ts";

function page(html: string) {
  document.body.innerHTML = `<main><h1>Page</h1>${html}</main>`;
}
const el = (sel: string) => document.querySelector<HTMLElement>(sel);

afterEach(() => {
  document.body.innerHTML = "";
});

describe("focusLost", () => {
  it("is true on <body> and false on a real control", () => {
    page(`<button id="b">B</button>`);
    expect(focusLost()).toBe(true);
    el("#b")?.focus();
    expect(focusLost()).toBe(false);
  });

  it("is true once the focused control leaves the page", () => {
    page(`<button id="b">B</button>`);
    el("#b")?.focus();
    el("#b")?.remove();
    expect(focusLost()).toBe(true);
  });
});

describe("refocusFirst", () => {
  it("focuses the first connected candidate, making a line focusable", () => {
    page(`<p id="line">Done.</p>`);
    const gone = document.createElement("button");
    refocusFirst(gone, el("#line"));
    expect(document.activeElement).toBe(el("#line"));
    expect(el("#line")?.getAttribute("tabindex")).toBe("-1");
  });

  it("falls back to the page h1, never <body>", () => {
    page("");
    refocusFirst(null, undefined);
    expect(document.activeElement).toBe(el("main h1"));
  });

  it("leaves focus alone when the user has already moved on", () => {
    page(`<button id="b">B</button><p id="line">Done.</p>`);
    el("#b")?.focus();
    refocusFirst(el("#line"));
    expect(document.activeElement).toBe(el("#b"));
    expect(el("#line")?.hasAttribute("tabindex")).toBe(false);
  });
});
