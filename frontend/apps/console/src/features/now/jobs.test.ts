import { flushPromises, mount } from "@vue/test-utils";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { missionId as missionIdReader } from "@/api/index.ts";
import JobSheets from "./JobSheets.vue";
import type { ResolutionAction } from "./attention.ts";
import { decode } from "@/api/index.ts";
import { actionQueueReader, presentQueue } from "./actionQueue.ts";
import { resolvedWords } from "./attention.ts";
import { CLOSE_BODY, jobTechnical, retryBody, retryCheck } from "./jobs.ts";
import { NO_ACCESS_JOB } from "./jobs.ts";

const NOW = new Date("2026-11-14T03:16:00Z");

/** The queue item as api serves it (domain + api shape 11-14). */
const item = (o: Record<string, unknown> = {}, priority = 1) => ({
  id: "attention:job_outcome_unknown:job-77:run-3",
  priority,
  kind: "attention",
  state: priority === 1 ? "critical" : "caution",
  source: "job_outcome_unknown",
  acknowledged: null,
  since: "2026-11-14T03:10:00Z",
  due_at: null,
  count: 1,
  spacecraft: [
    {
      id: "spacecraft-earendil-008",
      name: "EARENDIL-008",
      scid: 8,
      plane: 3,
      stale: false,
      last_received_at: null,
      violating_points: null,
      value: null,
      first_crossed_at: null,
      episode_id: null,
      status: null,
      assignee: null,
      acknowledged_by: null,
    },
  ],
  point: null,
  condition: null,
  plane: null,
  command: null,
  outcome: null,
  command_requests: [],
  finding: null,
  attention: {
    id: "job-77:run-3",
    source: "job_outcome_unknown",
    conflict: "outcome_unknown",
    state: "open",
    acknowledged_by: null,
    contact_id: "contact-8",
    reservation_id: "pass-8",
    station: { ref: "svb", id: "st-2", code: "SVB", name: "Svalbard B" },
    provider: { id: "p-1", name: "Northlight" },
    starts_at: "2026-11-14T03:10:00Z",
    ends_at: "2026-11-14T03:18:00Z",
    raised_at: "2026-11-14T03:09:00Z",
    provider_message: null,
    realized_contact_id: null,
    job: {
      id: "job-77",
      type_key: "contact_schedule_operation",
      run_id: "run-3",
      attempt: 1,
      node: "cadence@node-a",
      worker: "Cadence.Contacts.ScheduleOperations.Worker",
    },
    words: {
      noun: "Booking at Northlight",
      check_place: "with Northlight",
      consequence: "book the pass twice",
    },
    started_at: "2026-11-14T03:01:00Z",
    found_at: "2026-11-14T03:09:00Z",
    actions: ["retry", "close"],
    resolution: null,
    ...o,
  },
});

const rowOf = (o: Record<string, unknown> = {}, priority = 1) => {
  const r = decode(actionQueueReader, {
    observed_at: NOW.toISOString(),
    counts: { p1: 1, p2: 0, p3: 0, spacecraft_p1: 1 },
    items: [item(o, priority)],
  });
  if (!r.ok) throw new Error(r.error.message);
  return presentQueue(r.value, NOW, "EARENDIL")[0];
};

describe("job_outcome_unknown on Now (ux U54)", () => {
  it("names the pass and the job, says the outcome is unknown and what to do", () => {
    const row = rowOf();
    expect(row?.title).toBe(
      "EARENDIL-008 · SVB 03:10Z pass · Booking at Northlight: outcome unknown",
    );
    expect(row?.sentence).toBe(
      "Cadence stopped while this was running, so it doesn't know whether it finished. It won't run it again by itself: running it twice could book the pass twice. Check with Northlight, then retry it or close this.",
    );
    expect(row?.meta).toBe("STARTED 03:01Z · FOUND AT RESTART 03:09Z");
    expect(row?.job?.id).toBe("job-77:run-3");
    expect(row?.noAction).toBeUndefined();
    expect(row?.command).toBeUndefined();
    expect(row?.sentence).not.toMatch(/failed|interrupted/);
  });

  it("with no pass, the noun alone and nothing to open; an unknown type has fallback words", () => {
    const row = rowOf({
      reservation_id: null,
      contact_id: null,
      station: null,
      starts_at: null,
      ends_at: null,
      words: null,
    });
    expect(row?.title).toBe("EARENDIL-008 · A Cadence job: outcome unknown");
    expect(row?.noAction).toBe(true);
    expect(row?.sentence).toContain(
      "running it twice could repeat what it did. Check where it acts,",
    );
  });

  it("api's passless station and provider (objects of nulls) name nothing", () => {
    const row = rowOf({
      reservation_id: null,
      contact_id: null,
      station: { ref: null, id: null, code: null, name: null },
      provider: { id: null, name: null },
      starts_at: null,
      ends_at: null,
      words: {
        noun: "Catalog import",
        check_place: "in Setup › Catalog",
        consequence: "create a second revision",
      },
    });
    expect(row?.title).toBe("EARENDIL-008 · Catalog import: outcome unknown");
    expect(row?.noAction).toBe(true);
  });

  it("words the Retry sheet from the server's words", () => {
    const row = rowOf();
    if (!row?.job) throw new Error("no job");
    expect(retryBody(row.job)).toBe(
      "Retry only if you've checked with Northlight that it didn't happen. If it did, retrying could book the pass twice.",
    );
    expect(retryCheck(row.job)).toBe("I've checked with Northlight: it didn't happen.");
    expect(jobTechnical(row.job)).toEqual([
      "job: job-77",
      "type: contact_schedule_operation",
      "worker: Cadence.Contacts.ScheduleOperations.Worker",
      "attempt: 1",
      "node: cadence@node-a",
      "run: run-3",
      "id: job-77:run-3",
    ]);
    expect(NO_ACCESS_JOB).toBe("Operators decide what happens to jobs whose outcome is unknown.");
  });

  it("offers only the server's actions; a resolved item says how it closed", () => {
    expect(rowOf({ actions: [] })?.job).toBeUndefined();
    const closed = rowOf({
      state: "resolved",
      resolution: {
        action: "closed",
        actor: { kind: "user", id: "u-1", name: "Mira K." },
        at: "2026-11-14T03:22:00Z",
        note: "Northlight shows it booked.",
        provider_reference: null,
      },
    });
    expect(closed?.sentence).toBe(
      "Closed without retry by Mira K. at 03:22Z: “Northlight shows it booked.”",
    );
    expect(closed?.job).toBeUndefined();
  });

  it("says how it closed in the resolved list", () => {
    const said = (action: ResolutionAction, note: string | null) =>
      resolvedWords(
        {
          id: "attention:job_outcome_unknown:job-77:run-3",
          resolved_by: { kind: "user", id: "u-1", name: "Mira K." },
          action,
          resolved_at: "2026-11-14T03:20:00Z",
          note,
        },
        NOW,
      );
    expect(said("retried", null)).toBe("Retried by Mira K. at 03:20Z; it's queued.");
    expect(said("closed", "Northlight shows it booked.")).toBe(
      "Closed without retry by Mira K. at 03:20Z: “Northlight shows it booked.”",
    );
  });
});

// a11y A1/B6 (#243): a required field opens with focus on it, the sentence describes the sheet,
// and a refusal inside it is an alert.
describe("Close without retry sheet a11y (#243)", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    document.body.innerHTML = "";
  });
  it("opens on its field, described by its sentence; a 403 is an alert", async () => {
    const target = rowOf()?.job;
    if (!target) throw new Error("no job");
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(
        new Response(JSON.stringify({ error: { code: "forbidden", message: "No." } }), {
          status: 403,
          headers: { "content-type": "application/json" },
        }),
      ),
    );
    const w = mount(JobSheets, {
      props: { missionId: missionIdReader("m") },
      attachTo: document.body,
    });
    // oxlint-disable-next-line typescript/no-unsafe-call, typescript/no-unsafe-member-access -- vue-tsc checks the exposed open(); the lint type service can't resolve SFC instances.
    w.vm.openClose(target);
    await flushPromises();
    const dialog = w.get("dialog[open]");
    expect(document.activeElement?.tagName).toBe("TEXTAREA");
    const described = dialog.attributes("aria-describedby") ?? "";
    expect(document.getElementById(described)?.textContent).toBe(CLOSE_BODY);
    await dialog.get("textarea").setValue("checked the buffer");
    await dialog
      .findAll("button")
      .find((b) => b.text() === "Close")
      ?.trigger("click");
    await flushPromises();
    expect(dialog.get('[role="alert"]').text()).toBe(NO_ACCESS_JOB);
    w.unmount();
  });
});
