import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { missionId } from "@/api";
import EditCallouts from "./editor/EditCallouts.vue";
import { focusedControlOwns } from "./focus-fallback.ts";
import RetireSheet from "./library/RetireSheet.vue";

/** #245 A5: a button that leaves with its own action hands focus somewhere stated, never <body>. */
vi.mock("./library/api.ts", async (original) => ({
  ...(await original<typeof import("./library/api.ts")>()),
  retireItem: () =>
    Promise.resolve({ ok: false, error: { kind: "http", status: 409, message: "in use" } }),
  usedByOf: () => [{ id: "d1", name: "Ops wall", placements: 1 }],
}));
vi.mock("vue-router", async (original) => ({
  ...(await original<typeof import("vue-router")>()),
  RouterLink: { template: "<a><slot /></a>" },
}));

afterEach(() => {
  document.body.innerHTML = "";
});
const button = (name: string) =>
  Array.from(document.querySelectorAll("button")).find((b) => b.textContent?.trim() === name);

describe("edit conflict callout", () => {
  it("sends focus to the page heading once Continue editing resolves it", async () => {
    document.body.innerHTML = "<main><h1>Bus overview</h1><div id='app'></div></main>";
    const w = mount(EditCallouts, {
      props: {
        conflict: { currentVersion: 8, savedBy: "Mira K.", savedAt: null },
        notice: null,
        busy: false,
        resumed: false,
        retiredLibrary: false,
      },
      attachTo: "#app",
    });
    button("Continue editing")?.focus();
    button("Continue editing")?.click();
    expect(w.emitted("continue")).toHaveLength(1);
    await w.setProps({ conflict: null });
    await flushPromises();
    expect(document.activeElement).toBe(document.querySelector("h1"));
  });
});

describe("Library Delete refused as in use", () => {
  it("takes Delete away and focuses the line that says where it's used", async () => {
    const w = mount(RetireSheet, {
      props: { missionId: missionId("m1") },
      attachTo: document.body,
    });
    // oxlint-disable-next-line typescript/no-unsafe-call, typescript/no-unsafe-member-access -- vue-tsc checks the exposed open(); the lint type service can't resolve SFC instances.
    w.vm.open({ id: "i1", name: "Battery", latest_version: 2, updated_at: null });
    await flushPromises();
    button("Delete")?.focus();
    button("Delete")?.click();
    await flushPromises();
    expect(button("Delete")).toBeUndefined();
    const line = document.querySelector("[data-retire-used]");
    expect(line?.textContent).toContain("Used in 1 dashboard: Ops wall.");
    expect(line?.getAttribute("role")).toBe("alert");
    expect(document.activeElement).toBe(line);
  });
});

describe("screen-wide keys vs a focused control (B8)", () => {
  const press = (key: string, html: string) => {
    document.body.innerHTML = html;
    const event = new KeyboardEvent("keydown", { key });
    Object.defineProperty(event, "target", { value: document.querySelector("#t") });
    return focusedControlOwns(event);
  };
  it("leaves Space to a button or checkbox, and arrows to a field or radio group", () => {
    expect(press(" ", "<button id='t'>Exit</button>")).toBe(true);
    expect(press(" ", "<button><span id='t'>Exit</span></button>")).toBe(true);
    expect(press(" ", "<input id='t' type='checkbox' />")).toBe(true);
    expect(press("ArrowRight", "<input id='t' />")).toBe(true);
    expect(
      press("ArrowLeft", "<div role='radiogroup'><button id='t' role='radio'>A</button></div>"),
    ).toBe(true);
  });
  it("lets the screen have its keys elsewhere: Space on a heading, arrows on a button", () => {
    expect(press(" ", "<h2 id='t' tabindex='-1'>Power</h2>")).toBe(false);
    expect(press("ArrowRight", "<button id='t'>Exit</button>")).toBe(false);
    expect(press("Escape", "<input id='t' />")).toBe(false);
  });
});
