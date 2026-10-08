import { producerFixture } from "../../../../../test-support/producer-fixture";
import { required } from "../../../../../test-support/required";
import {
  fixtureRecord,
  fixtureString,
  fixtureContext,
  jsonFixture,
} from "../../../../../test-support/json-fixture";
import { oneOf } from "@cadence/plugin-sdk/admission";
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
  scheduleActions,
  reservationActions,
} from "./contact-workflow";
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
  else if (action === "reserve") await w.get('[id^="reserve-"]').trigger("click");
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

const producer = producerFixture("CADENCE_CONTACT_WORKFLOW", import.meta.url);
test.skipIf(!producer.available)("producer supplied native contact contribution", async () => {
  const supplied = jsonFixture(producer.read()),
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
    if (page.kind === "schedule" && supplied.search) {
      execute.mockResolvedValueOnce(supplied.search);
      await submit(w, page, "search");
      execute.mockClear();
    }
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

    if (supplied.operation) {
      if (page.kind !== "schedule")
        expect(admitContactOperation(supplied.operation, page)).not.toBeNull();
      if (page.kind === "reservation" && fixtureRecord(supplied.operation).status === "completed")
        expect(w.find("#reservation-receipt").exists()).toBe(true);
    }
    process.stdout.write("CONTACT_CONTRIBUTION_INPUT=" + JSON.stringify(execute.mock.calls) + "\n");
  } finally {
    w.unmount();
  }
});
