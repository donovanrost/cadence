import { afterEach, describe, expect, it } from "vite-plus/test";
import { focusAfterRemove } from "./list-focus.ts";

function list(ids: readonly string[]) {
  document.body.innerHTML = `<main><h1>Page</h1><div id="box">${ids
    .map((id) => `<button data-x id="${id}">×</button>`)
    .join("")}<select id="add"></select></div></main>`;
  return document.querySelector<HTMLElement>("#box");
}
const add = () => document.querySelector<HTMLElement>("#add");

afterEach(() => {
  document.body.innerHTML = "";
});

describe("focusAfterRemove", () => {
  it("focuses the control now at the removed index (the next item)", async () => {
    const box = list(["a", "c"]);
    await focusAfterRemove(box, "[data-x]", 1, add);
    expect(document.activeElement?.id).toBe("c");
  });

  it("falls back to the item before when the last one went", async () => {
    const box = list(["a", "b"]);
    await focusAfterRemove(box, "[data-x]", 2, add);
    expect(document.activeElement?.id).toBe("b");
  });

  it("lands on the fallback when the list is empty", async () => {
    const box = list([]);
    await focusAfterRemove(box, "[data-x]", 0, add);
    expect(document.activeElement?.id).toBe("add");
  });

  it("leaves focus alone if the user has moved on", async () => {
    const box = list(["a", "b"]);
    add()?.focus();
    await focusAfterRemove(box, "[data-x]", 0);
    expect(document.activeElement?.id).toBe("add");
  });
});
