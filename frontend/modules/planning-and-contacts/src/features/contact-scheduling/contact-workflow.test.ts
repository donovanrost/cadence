import OpsContactSchedule from "./OpsContactSchedule.vue";
import { mount, flushPromises } from "@vue/test-utils";
import { expect, test, vi } from "vite-plus/test";
import {
  contactScheduleContribution,
  contactRecordContribution,
  reservationContribution,
} from "./contact.contributions";
import { contactPage, contactOperation, completedContact } from "./contact-workflow.test-support";
import {
  admitContactPage,
  admitContactOperation,
  type ContactPage,
  type ContactAction,
} from "./contact-workflow";
import type { ContactSchedule } from "./OpsContactSchedule.contracts";
import type { ReservationDetail } from "./OpsContactDetail.contracts";
import { searchFixture } from "./contact-schedule.test-support";
const contribution = (page: ContactPage) =>
  page.kind === "schedule"
    ? contactScheduleContribution
    : page.kind === "record"
      ? contactRecordContribution
      : reservationContribution;
function mountPage(page: ContactPage, execute = vi.fn(), read = vi.fn()) {
  let guard = () => true;
  const release = vi.fn();
  const c = contribution(page);
  const w = mount(c.component, {
    props: {
      page,
      port: {
        execute,
        navigate: vi.fn(),
        guardNavigation: (g: () => boolean) => {
          guard = g;
          return release;
        },
      },
      readPort: { read },
    },
  });
  return { w, guard: () => guard(), release };
}
async function submit(
  w: ReturnType<typeof mount>,
  page: ContactPage,
  action: ContactAction,
  reason = "Reviewed actual provider evidence",
) {
  if (action === "search") await w.get("#contact-search").trigger("submit");
  else if (action === "reserve")
    await w
      .get(`[id="reserve-${encodeURIComponent(page.search!.opportunities[0]!.id)}"]`)
      .trigger("click");
  else if (action === "cancel") {
    await w
      .get(
        `[id="cancel-review-${encodeURIComponent((page.model as ContactSchedule).reservations.entries[0]!.id)}"]`,
      )
      .trigger("click");
    await w.get("#contact-cancel-confirm").trigger("click");
  } else {
    await w.get("#" + action + "-reason").setValue(reason);
    await w.get("#" + action + "-form").trigger("submit");
  }
  await flushPromises();
}

test("search preserves UTC seconds and recovers a lost result without repeating provider traffic", async () => {
  const page = contactPage(),
    model = page.model as ContactSchedule;
  model.initial_window.starts_at = "2099-09-09T12:00:17Z";
  model.initial_window.ends_at = "2099-09-09T13:00:23Z";
  const read = vi.fn();
  const execute = vi.fn(async (action, input) => {
    read.mockResolvedValue(completedContact(page, contactOperation(page, action, input)));
    throw Error("response lost");
  });
  const { w } = mountPage(page, execute, read);
  try {
    await submit(w, page, "search");
    expect(execute.mock.calls[0]![1].payload.contact_search.starts_at).toBe(
      model.initial_window.starts_at,
    );
    expect(w.get("#contact-search fieldset").attributes("disabled")).toBeDefined();
    await w.get("#contact-schedule-refresh").trigger("click");
    await flushPromises();
    expect(w.get("#reserve-opportunity-one").attributes("disabled")).toBeUndefined();
    expect(execute).toHaveBeenCalledOnce();
  } finally {
    w.unmount();
  }
});

test("pending decisions survive bootstrap copies, block navigation and recover only matching receipts", async () => {
  const page = contactPage("reservation");
  let resolve!: (value: unknown) => void;
  const execute = vi.fn(
    () =>
      new Promise((r) => {
        resolve = r;
      }),
  );
  const read = vi.fn();
  const { w, guard, release } = mountPage(page, execute, read);
  try {
    await w.get("#reject-provider-change-reason").setValue("Separate draft");
    await submit(w, page, "approve-provider-change", "界".repeat(200));
    expect(guard()).toBe(false);
    await w.setProps({ page: structuredClone(page) });
    expect(guard()).toBe(false);
    const [action, input] = execute.mock.calls[0]! as any;
    const op = contactOperation(page, action, input);
    const fresh = completedContact(page, op);
    read.mockResolvedValue({ ...fresh, actor_id: "foreign" });
    resolve(op);
    await flushPromises();
    expect(w.get("#reservation-receipt").text()).toContain("approved");
    expect(w.get("#reject-provider-change-reason").element).toHaveProperty(
      "value",
      "Separate draft",
    );
    expect(w.get("#approve-provider-change").attributes("disabled")).toBeDefined();
    read.mockResolvedValue(fresh);
    await w.get("#reservation-refresh").trigger("click");
    await flushPromises();
    expect(w.get("#reservation-notice").text()).toContain("verified");
    expect(execute).toHaveBeenCalledOnce();
    expect(guard()).toBe(true);
  } finally {
    w.unmount();
  }
  expect(release).toHaveBeenCalledOnce();
});

test("record reads preserve pinned history and failed reads retain the previous record", async () => {
  const page = contactPage("record"),
    read = vi.fn().mockResolvedValue({ ...page, actor_id: "foreign" });
  const { w } = mountPage(page, vi.fn(), read);
  try {
    await w.get("#contact-record-refresh").trigger("click");
    await flushPromises();
    expect(w.find("#ops-contact-record-page").exists()).toBe(true);
    expect(w.get("#contact-record-notice").text()).toContain("retained");
    await w.setProps({ page: { ...page, model: {} } });
    expect(w.find("#ops-contact-record-page").exists()).toBe(true);
  } finally {
    w.unmount();
  }
});

test("uncertain attempts render while their results cannot unlock reservation mutations", async () => {
  const page = contactPage();
  page.search = searchFixture();
  const model = page.model as ContactSchedule;
  const row = model.reservations.entries[0]!;
  row.provider_revision = 1;
  row.provider_contact_ref = null;
  row.lifecycle_state = "unknown";
  expect(admitContactPage("schedule", page)).not.toBeNull();
  const input = { sequence: 1, payload: { token: page.search.opportunities[0]!.token } };
  const op = contactOperation(page, "reserve", input);
  op.status = "unconfirmed";
  op.receipt!.result.source = "recorded";
  op.receipt!.result.value.providerRevision = 1;
  op.receipt!.result.value.lifecycleState = "unknown";
  op.receipt!.result.value.scheduledContactId = null;
  expect(admitContactOperation(op, page)).not.toBeNull();
  const fresh = { ...page, operation: op, sequence: 1, consumed: [input.payload.token] };
  const read = vi.fn().mockResolvedValue(fresh);
  const execute = vi.fn().mockResolvedValue(op);
  const { w } = mountPage(page, execute, read);
  try {
    await submit(w, page, "reserve");
    expect(w.get("#contact-schedule-receipt").text()).toContain("unknown");
    expect(w.get("#contact-search fieldset").attributes("disabled")).toBeDefined();
    const observed = structuredClone(op);
    observed.status = "completed";
    observed.receipt!.result.source = "observed";
    observed.receipt!.result.value.providerRevision = 1;
    observed.receipt!.result.value.lifecycleState = "confirmed";
    const next = structuredClone(fresh);
    next.operation = observed;
    const nextRow = (next.model as ContactSchedule).reservations.entries[0]!;
    nextRow.provider_revision = 1;
    nextRow.provider_contact_ref = "provider-contact-one";
    nextRow.lifecycle_state = "confirmed";
    read.mockResolvedValue(next);
    await w.get("#contact-schedule-refresh").trigger("click");
    await flushPromises();
    expect(w.get("#contact-search fieldset").attributes("disabled")).toBeUndefined();
    expect(w.get("#reserve-opportunity-one").attributes("disabled")).toBeDefined();
    expect(execute).toHaveBeenCalledOnce();
  } finally {
    w.unmount();
  }
});

test("foreign, malformed and changed review receipts fail admission", () => {
  const page = contactPage("reservation"),
    d = page.model as ReservationDetail;
  const input = {
    sequence: 1,
    payload: {
      provider_reservation_id: d.reservation.id,
      reason: "Review",
      change_evidence: {
        contract_version: 1,
        ...d.context,
        reservation_id: d.reservation.id,
        change_id: d.selected!.id,
        provider_revision: d.selected!.provider_revision,
        proposal_hash: d.selected!.proposal_hash,
      },
    },
  };
  const op = contactOperation(page, "approve-provider-change", input);
  expect(admitContactOperation(op, page)).not.toBeNull();
  for (const field of ["actor_id", "organization_id", "mission_id", "action"]) {
    const bad = structuredClone(op);
    (bad.receipt!.result as any)[field] = "foreign";
    expect(admitContactOperation(bad, page)).toBeNull();
  }
  expect(admitContactPage("reservation", { ...page, sequence: 1 })).toBeNull();
});

test("a changed route can reject search without losing the reviewed draft", async () => {
  const page = contactPage();
  const read = vi.fn();
  const execute = vi.fn(async (action, input) => {
    const op = {
      ...contactOperation(page, action, input),
      status: "rejected" as const,
      receipt: null,
      feedback: ["review_changed" as const],
    };
    const fresh = structuredClone(page);
    fresh.sequence = 1;
    fresh.operation = op;
    (fresh.model as ContactSchedule).routes.entries = [];
    read.mockResolvedValue(fresh);
    return op;
  });
  const { w } = mountPage(page, execute, read);
  try {
    await submit(w, page, "search");
    expect(w.get("#contact-schedule-notice").text()).toContain("could not be applied");
    expect(w.find("#contact-schedule-uncertain").exists()).toBe(false);
    expect(execute).toHaveBeenCalledOnce();
  } finally {
    w.unmount();
  }
});

test("a lost reservation response cannot be unlocked by a read predating the attempted operation", async () => {
  const page = contactPage();
  page.search = searchFixture();
  const execute = vi.fn().mockRejectedValue(Error("lost")),
    read = vi.fn().mockResolvedValue(page);
  const { w } = mountPage(page, execute, read);
  try {
    await submit(w, page, "reserve");
    await w.get("#contact-schedule-refresh").trigger("click");
    await flushPromises();
    expect(w.get("#contact-search fieldset").attributes("disabled")).toBeDefined();
    expect(w.get("#reserve-opportunity-one").attributes("disabled")).toBeDefined();
    expect(execute).toHaveBeenCalledOnce();
  } finally {
    w.unmount();
  }
});

test("a returned booking can reconcile outside the current ledger page while a foreign reservation cannot", async () => {
  const page = contactPage();
  page.search = searchFixture();
  const model = page.model as ContactSchedule;
  model.query.reservations_page = 2;
  model.reservations.page = 2;
  model.reservations.entries = [];
  const outcome = contactPage("reservation").model as ReservationDetail;
  outcome.reservation.provider_revision = 5;
  const read = vi.fn();
  const execute = vi.fn(async (action, input) => {
    const op = contactOperation(page, action, input);
    const fresh = {
      ...page,
      sequence: 1,
      operation: op,
      consumed: [input.payload.token],
      operation_reservation: outcome,
    };
    read.mockResolvedValue(fresh);
    expect(
      admitContactPage("schedule", {
        ...fresh,
        operation_reservation: {
          ...outcome,
          context: { ...outcome.context, mission_id: "foreign" },
        },
      }),
    ).toBeNull();
    return op;
  });
  const { w } = mountPage(page, execute, read);
  try {
    await submit(w, page, "reserve");
    expect(w.get("#contact-search fieldset").attributes("disabled")).toBeUndefined();
    expect(w.get("#contact-schedule-notice").text()).toContain("verified");
    expect(w.get("#reserve-opportunity-one").attributes("disabled")).toBeDefined();
    expect(execute).toHaveBeenCalledOnce();
  } finally {
    w.unmount();
  }
});

test("the legacy scheduling adapter accepts seconds from the shared native control", async () => {
  const page = contactPage(),
    model = page.model as ContactSchedule;
  const execute = vi.fn().mockResolvedValue({});
  const w = mount(OpsContactSchedule, {
    props: { schedule: model, port: { context: model.context, execute, refresh: vi.fn() } },
  });
  try {
    await w.get("#search-start").setValue("2099-09-09T12:00:17");
    await w.get("#search-end").setValue("2099-09-09T13:00:23");
    await w.get("#contact-search").trigger("submit");
    await flushPromises();
    expect(execute).toHaveBeenCalledExactlyOnceWith(
      "search",
      expect.objectContaining({
        contact_search: expect.objectContaining({
          starts_at: "2099-09-09T12:00:17Z",
          ends_at: "2099-09-09T13:00:23Z",
        }),
      }),
    );
  } finally {
    w.unmount();
  }
});

test("producer supplied native contact contribution", async () => {
  if (!process.env.CADENCE_CONTACT_WORKFLOW) return;
  const supplied = JSON.parse(process.env.CADENCE_CONTACT_WORKFLOW),
    snapshot = supplied.snapshot;
  const page = snapshot.data as ContactPage,
    c = contribution(page);
  expect(c.read(page, snapshot.context)).toBeTruthy();
  const read = vi.fn().mockResolvedValue(supplied.refreshed?.data ?? page);
  const execute = vi.fn().mockResolvedValue(supplied.operation ?? {});
  const { w } = mountPage(page, execute, read);
  try {
    if (supplied.action) await submit(w, page, supplied.action, supplied.reason);
    if (supplied.reconciled) expect(w.get("#contact-schedule-notice").text()).toContain("verified");
    if (supplied.operation) {
      expect(admitContactOperation(supplied.operation, page)).not.toBeNull();
      if (page.kind === "reservation" && supplied.operation.status === "completed")
        expect(w.find("#reservation-receipt").exists()).toBe(true);
    }
    process.stdout.write("CONTACT_CONTRIBUTION_INPUT=" + JSON.stringify(execute.mock.calls) + "\n");
  } finally {
    w.unmount();
  }
});
