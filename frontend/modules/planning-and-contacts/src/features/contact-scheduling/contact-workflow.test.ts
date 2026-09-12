import { required } from "../../../../../test-support/required";
import {
  fixtureRecord,
  fixtureString,
  fixtureContext,
  jsonFixture,
} from "../../../../../test-support/json-fixture";
import { oneOf } from "@cadence/plugin-sdk/admission";
import { containing } from "../../../../../test-support/matchers";
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
  type ContactPageRequest,
  type ContactOperation,
  scheduleActions,
  reservationActions,
} from "./contact-workflow";
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
  w: Pick<ReturnType<typeof mount>, "get">,
  page: ContactPage,
  action: ContactAction,
  reason = "Reviewed actual provider evidence",
) {
  if (action === "search") await w.get("#contact-search").trigger("submit");
  else if (action === "reserve")
    await w
      .get(
        `[id="reserve-${encodeURIComponent(required(required(page.search).opportunities[0]).id)}"]`,
      )
      .trigger("click");
  else if (action === "cancel") {
    if (page.kind !== "schedule") throw Error("Missing fixture schedule");
    await w
      .get(
        `[id="cancel-review-${encodeURIComponent(required(page.model.reservations.entries[0]).id)}"]`,
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
    model = page.model;
  model.initial_window.starts_at = "2099-09-09T12:00:17Z";
  model.initial_window.ends_at = "2099-09-09T13:00:23Z";
  const read = vi.fn();
  const execute = vi.fn(
    async (action: ContactAction, input: { sequence: number; payload: unknown }) => {
      read.mockResolvedValue(completedContact(page, contactOperation(page, action, input)));
      throw Error("response lost");
    },
  );
  const { w } = mountPage(page, execute, read);
  try {
    await submit(w, page, "search");
    expect(
      fixtureRecord(fixtureRecord(required(execute.mock.calls[0])[1].payload).contact_search)
        .starts_at,
    ).toBe(model.initial_window.starts_at);
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
  let resolve: ((value: unknown) => void) | undefined;
  const execute = vi.fn<(...request: ContactPageRequest) => Promise<unknown>>(
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
    const [action, input] = required(execute.mock.calls[0]);
    const op = contactOperation(page, action, input);
    const fresh = completedContact(page, op);
    read.mockResolvedValue({ ...fresh, actor_id: "foreign" });
    required(resolve)(op);
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
  const model = page.model;
  const row = required(model.reservations.entries[0]);
  row.provider_revision = 1;
  row.provider_contact_ref = null;
  row.lifecycle_state = "unknown";
  expect(admitContactPage("schedule", page)).not.toBeNull();
  const input = { sequence: 1, payload: { token: required(page.search.opportunities[0]).token } };
  const completed = contactOperation(page, "reserve", input);
  const op: Extract<ContactOperation, { action: "reserve"; status: "unconfirmed" }> = {
    ...completed,
    status: "unconfirmed",
    receipt: {
      ...completed.receipt,
      result: {
        ...completed.receipt.result,
        source: "recorded",
        value: {
          ...completed.receipt.result.value,
          providerRevision: 1,
          lifecycleState: "unknown",
          scheduledContactId: null,
        },
      },
    },
  };
  expect(admitContactOperation(op, page)).not.toBeNull();
  const fresh = {
    ...page,
    operation: op,
    sequence: 1,
    consumed: [fixtureString(fixtureRecord(input.payload).token)],
  };
  const read = vi.fn().mockResolvedValue(fresh);
  const execute = vi.fn().mockResolvedValue(op);
  const { w } = mountPage(page, execute, read);
  try {
    await submit(w, page, "reserve");
    expect(w.get("#contact-schedule-receipt").text()).toContain("unknown");
    expect(w.get("#contact-search fieldset").attributes("disabled")).toBeDefined();
    const observed = {
      ...completed,
      receipt: {
        ...completed.receipt,
        result: {
          ...completed.receipt.result,
          source: "observed" as const,
          value: {
            ...completed.receipt.result.value,
            providerRevision: 1,
            lifecycleState: "confirmed" as const,
            scheduledContactId: null,
          },
        },
      },
    };
    const next = { ...structuredClone(fresh), operation: observed };
    const nextRow = required(next.model.reservations.entries[0]);
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
    d = page.model;
  const input = {
    sequence: 1,
    payload: {
      provider_reservation_id: d.reservation.id,
      reason: "Review",
      change_evidence: {
        contract_version: 1,
        ...d.context,
        reservation_id: d.reservation.id,
        change_id: required(d.selected).id,
        provider_revision: required(d.selected).provider_revision,
        proposal_hash: required(d.selected).proposal_hash,
      },
    },
  };
  const op = contactOperation(page, "approve-provider-change", input);
  expect(admitContactOperation(op, page)).not.toBeNull();
  for (const field of ["actor_id", "organization_id", "mission_id", "action"]) {
    const bad = structuredClone(op);
    fixtureRecord(bad.receipt.result)[field] = "foreign";
    expect(admitContactOperation(bad, page)).toBeNull();
  }
  expect(admitContactPage("reservation", { ...page, sequence: 1 })).toBeNull();
});

test("a changed route can reject search without losing the reviewed draft", async () => {
  const page = contactPage();
  const read = vi.fn();
  const execute = vi.fn(
    async (action: ContactAction, input: { sequence: number; payload: unknown }) => {
      const op = {
        ...contactOperation(page, action, input),
        status: "rejected" as const,
        receipt: null,
        feedback: ["review_changed" as const],
      };
      const fresh = structuredClone(page);
      fresh.sequence = 1;
      fresh.operation = op;
      fresh.model.routes.entries = [];
      read.mockResolvedValue(fresh);
      return op;
    },
  );
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
  const model = page.model;
  model.query.reservations_page = 2;
  model.reservations.page = 2;
  model.reservations.entries = [];
  const outcome = contactPage("reservation").model;
  outcome.reservation.provider_revision = 5;
  const read = vi.fn();
  const execute = vi.fn(
    async (action: ContactAction, input: { sequence: number; payload: unknown }) => {
      const op = contactOperation(page, action, input);
      const fresh = {
        ...page,
        sequence: 1,
        operation: op,
        consumed: [fixtureString(fixtureRecord(input.payload).token)],
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
    },
  );
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

test("the remote scheduling adapter preserves initial UTC seconds through submission", async () => {
  const page = contactPage(),
    model = page.model;
  model.initial_window.starts_at = "2099-09-09T12:00:17Z";
  model.initial_window.ends_at = "2099-09-09T13:00:23Z";
  const execute = vi.fn().mockResolvedValue({});
  const w = mount(OpsContactSchedule, {
    props: {
      schedule: model,
      port: {
        protocol: "remote-query" as const,
        context: model.context,
        execute,
        refresh: vi.fn(),
      },
    },
  });
  try {
    expect(w.get<HTMLInputElement>("#search-start").element.value).toBe("2099-09-09T12:00:17");
    expect(w.get<HTMLInputElement>("#search-end").element.value).toBe("2099-09-09T13:00:23");
    await w.get("#contact-search").trigger("submit");
    await flushPromises();
    expect(execute).toHaveBeenCalledExactlyOnceWith(
      "search",
      containing({
        contact_search: containing({
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
  const supplied = jsonFixture(process.env.CADENCE_CONTACT_WORKFLOW),
    snapshot = fixtureRecord(supplied.snapshot);
  const raw = fixtureRecord(snapshot.data);
  if (!oneOf(["schedule", "record", "reservation"], raw.kind))
    throw Error("Invalid contact fixture kind");
  const page = required(admitContactPage(raw.kind, raw)),
    c = contribution(page);
  expect(c.read(page, fixtureContext(snapshot.context))).toBeTruthy();
  const read = vi
    .fn()
    .mockResolvedValue(supplied.refreshed ? fixtureRecord(supplied.refreshed).data : page);
  const execute = vi.fn().mockResolvedValue(supplied.operation ?? {});
  const { w } = mountPage(page, execute, read);
  try {
    if (supplied.action) {
      if (!oneOf([...scheduleActions, ...reservationActions], supplied.action))
        throw Error("Invalid fixture action");
      await submit(
        w,
        page,
        supplied.action,
        supplied.reason === undefined ? undefined : fixtureString(supplied.reason),
      );
    }
    if (supplied.reconciled) expect(w.get("#contact-schedule-notice").text()).toContain("verified");
    if (supplied.operation) {
      expect(admitContactOperation(supplied.operation, page)).not.toBeNull();
      if (page.kind === "reservation" && fixtureRecord(supplied.operation).status === "completed")
        expect(w.find("#reservation-receipt").exists()).toBe(true);
    }
    process.stdout.write("CONTACT_CONTRIBUTION_INPUT=" + JSON.stringify(execute.mock.calls) + "\n");
  } finally {
    w.unmount();
  }
});
