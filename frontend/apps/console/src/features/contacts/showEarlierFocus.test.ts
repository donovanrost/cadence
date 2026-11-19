import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { missionId } from "@/api/index.ts";
import ReservationRecord from "./ReservationRecord.vue";

/** a11y A5 / B4 (#243, ux #426): Show earlier's last page, by where focus is when it arrives. */
const entry = (id: string) => ({
  id,
  action: "confirm",
  outcome: "ok",
  recorded_at: "2026-11-16T02:11:04Z",
  change_id: null,
});
const reservation = (entries: unknown[], next: string | null) => ({
  reservation: {
    id: "res-1",
    provider_revision: 4,
    lifecycle_state: "confirmed",
    provider: { id: "nl", version: 4 },
    transport: null,
    plan: null,
    requirement: null,
    scheduled_contact_id: "sc-1",
    last_reconciled_at: null,
  },
  values: [],
  audit: { entries, next_cursor: next },
});
const reply = (body: unknown) =>
  new Response(JSON.stringify({ data: body }), {
    status: 200,
    headers: { "content-type": "application/json" },
  });

afterEach(() => {
  vi.unstubAllGlobals();
  document.body.innerHTML = "";
});

async function openRecord() {
  let release: (r: Response) => void = () => {};
  const lastPage = new Promise<Response>((resolve) => (release = resolve));
  vi.stubGlobal(
    "fetch",
    vi
      .fn()
      .mockResolvedValueOnce(reply(reservation([entry("a1")], "c1")))
      .mockReturnValueOnce(lastPage),
  );
  const w = mount(ReservationRecord, {
    props: { missionId: missionId("m"), passId: "res-1", providerName: "Northlight" },
    attachTo: document.body,
  });
  const details = w.get("details");
  details.element.setAttribute("open", "");
  await details.trigger("toggle");
  await flushPromises();
  const more = w.findAll("button").find((b) => b.text() === "Show earlier");
  if (!more) throw new Error("no Show earlier");
  if (more.element instanceof HTMLElement) more.element.focus();
  await more.trigger("click");
  return { w, finish: () => release(reply(reservation([entry("a2")], null))) };
}

describe("Show earlier's last page", () => {
  it("lands on the first new row when the button still has focus", async () => {
    const { w, finish } = await openRecord();
    finish();
    await flushPromises();
    expect(document.activeElement?.textContent).toContain("Confirm");
    expect(w.findAll("li").at(1)?.element).toBe(document.activeElement);
    w.unmount();
  });

  it("leaves focus alone when the person tabbed away while it loaded", async () => {
    const { w, finish } = await openRecord();
    const elsewhere = document.createElement("button");
    document.body.appendChild(elsewhere);
    elsewhere.focus();
    finish();
    await flushPromises();
    expect(document.activeElement).toBe(elsewhere);
    w.unmount();
  });
});
