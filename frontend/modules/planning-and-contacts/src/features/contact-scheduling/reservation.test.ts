import { producerFixture } from "../../../../../test-support/producer-fixture";
import { jsonFixture } from "../../../../../test-support/json-fixture";
import { oneOf } from "@cadence/plugin-sdk/admission";
import { reservationActions } from "./contact-workflow";
import { required } from "../../../../../test-support/required";
import { flushPromises, mount } from "@vue/test-utils";
import { pageHeaderHarness } from "@cadence/plugin-sdk/page-header-testing";
import { expect, test, vi } from "vite-plus/test";
import OpsContactDetail from "./OpsContactDetail.vue";
import type { ReservationPort } from "./OpsContactDetail.contracts";
import {
  admitReservation,
  canDecide,
  completedReceipt,
  reservationDecision,
  reservationHref,
} from "./reservation-detail";
import { reservationFixture } from "./reservation.test-support";
function harness() {
  const detail = reservationFixture(),
    execute = vi.fn<Extract<ReservationPort, { protocol: "remote-query" }>["execute"]>(),
    refresh = vi.fn<ReservationPort["refresh"]>();
  const port = { protocol: "remote-query" as const, context: detail.context, execute, refresh };
  return {
    detail,
    execute,
    refresh,
    port,
    wrapper: mount(
      pageHeaderHarness("/missions/:mission_id/ops/contacts/:provider_reservation_id").stage(
        OpsContactDetail,
      ),
      { props: { detail, port } },
    ),
  };
}
test("native approval sends exactly the reviewed proposal and reconciles its completed receipt", async () => {
  const h = harness();
  const updated = structuredClone(h.detail);
  required(updated.selected).lifecycle_state = "approved";
  h.execute.mockResolvedValue({
    receiptId: "receipt-one",
    completedAt: "2026-09-08T12:00:00Z",
    result: {
      providerReservationId: h.detail.reservation.id,
      providerReservationChangeId: required(h.detail.selected).id,
      providerRevision: 2,
      proposalHash: "a".repeat(64),
      lifecycleState: "approved",
    },
  });
  h.refresh.mockResolvedValue(updated);
  await h.wrapper.get("#approve-provider-change-reason").setValue("  Checked the pass shift  ");
  await h.wrapper.get("#approve-provider-change-form").trigger("submit");
  await flushPromises();
  expect(h.execute).toHaveBeenCalledExactlyOnceWith(
    "approve-provider-change",
    reservationDecision(h.detail, "Checked the pass shift"),
  );
  expect(h.refresh).toHaveBeenCalledTimes(1);
  expect(h.wrapper.find("#approve-provider-change-form").exists()).toBe(false);
  expect(h.wrapper.get("#reservation-notice").text()).toContain("Decision completed");
  h.wrapper.unmount();
});
test("unknown outcomes retain reasons and refresh never repeats the mutation", async () => {
  const h = harness();
  h.execute.mockRejectedValue(new Error("connection lost"));
  h.refresh.mockResolvedValue(h.detail);
  await h.wrapper.get("#reject-provider-change-reason").setValue("Conflicts with commanding");
  await h.wrapper.get("#reject-provider-change-form").trigger("submit");
  await flushPromises();
  expect(
    (h.wrapper.get("#reject-provider-change-reason").element as HTMLTextAreaElement).value,
  ).toBe("Conflicts with commanding");
  expect(h.wrapper.get("#reject-provider-change").attributes("disabled")).toBeDefined();
  await h.wrapper.get("#page-header-refresh").trigger("click");
  await flushPromises();
  await h.wrapper.get("#reject-provider-change-form").trigger("submit");
  await flushPromises();
  expect(h.execute).toHaveBeenCalledTimes(1);
  expect(h.refresh).toHaveBeenCalledTimes(1);
  h.wrapper.unmount();
});
test("departing a review ignores late mutations and a changed identity clears reasons", async () => {
  const h = harness();
  let done: ((v: unknown) => void) | undefined;
  h.execute.mockImplementation(
    () =>
      new Promise((resolve) => {
        done = resolve;
      }),
  );
  await h.wrapper.get("#approve-provider-change-reason").setValue("First review");
  await h.wrapper.get("#approve-provider-change-form").trigger("submit");
  const next = structuredClone(h.detail);
  required(next.selected).id = "change-other";
  next.query.change_id = "change-other";
  await h.wrapper.setProps({ detail: next });
  required(done)({});
  await flushPromises();
  expect(h.refresh).not.toHaveBeenCalled();
  expect(
    (h.wrapper.get("#approve-provider-change-reason").element as HTMLTextAreaElement).value,
  ).toBe("");
  h.wrapper.unmount();
});
test("historical, incomplete, expired, and unauthorized reviews do not enable approval", () => {
  const d = reservationFixture();
  expect(admitReservation(d)).not.toBeNull();
  expect(canDecide(d, "approve-provider-change")).toBe(true);
  d.reservation.provider_revision = 3;
  expect(canDecide(d, "approve-provider-change")).toBe(false);
  d.reservation.provider_revision = 2;
  required(d.selected).review_complete = false;
  expect(canDecide(d, "approve-provider-change")).toBe(false);
  required(d.selected).review_complete = true;
  required(d.selected).deadline_at = "2020-01-01T00:00:00Z";
  expect(canDecide(d, "approve-provider-change")).toBe(false);
  required(d.selected).deadline_at = null;
  d.permissions.decide = false;
  expect(canDecide(d, "approve-provider-change")).toBe(false);
});
test("admission rejects cross-reservation, future, duplicate, and incomplete evidence", () => {
  for (const mutate of [
    (d: ReturnType<typeof reservationFixture>) => {
      d.query.change_id = "other";
    },
    (d: ReturnType<typeof reservationFixture>) => {
      required(d.selected).provider_revision = 3;
    },
    (d: ReturnType<typeof reservationFixture>) => {
      d.changes.entries.push(required(d.changes.entries[0]));
    },
    (d: ReturnType<typeof reservationFixture>) => {
      required(required(d.selected).fields[0]).visible = false;
    },
    (d: ReturnType<typeof reservationFixture>) => {
      d.changes.next = 2;
    },
  ]) {
    const d = reservationFixture();
    mutate(d);
    expect(admitReservation(d)).toBeNull();
  }
  expect(
    admitReservation(reservationFixture(), {
      organization_id: "foreign",
      mission_id: "mission-one",
    }),
  ).toBeNull();
  expect(
    admitReservation(reservationFixture(), {
      ...reservationFixture().context,
      reservation_id: "foreign",
    }),
  ).toBeNull();
});
test("history links preserve the reviewed change and the independent audit cursor", () => {
  const d = reservationFixture();
  d.query.before_audit = "audit-20";
  expect(reservationHref(d, { before_revision: 5 })).toBe(
    "/missions/mission-one/ops/contacts/reservation-one?change_id=change-2&before_revision=5&before_audit=audit-20",
  );
});
const producer = producerFixture("CADENCE_RESERVATION_REVIEW_MODEL", import.meta.url);
test.skipIf(!producer.available)("producer-supplied reservation review", async () => {
  const props = jsonFixture(producer.read());
  const detail = admitReservation(props.detail);
  expect(detail).not.toBeNull();
  const execute = vi
    .fn<Extract<ReservationPort, { protocol: "remote-query" }>["execute"]>()
    .mockRejectedValue(new Error("payload only"));
  const wrapper = mount(
    pageHeaderHarness("/missions/:mission_id/ops/contacts/:provider_reservation_id").stage(
      OpsContactDetail,
    ),
    {
      props: {
        ...props,
        detail: props.detail,
        port: {
          protocol: "remote-query" as const,
          context: required(detail).context,
          execute,
          refresh: vi.fn(),
        },
      },
    },
  );
  expect(wrapper.find("#ops-contact-detail-page").exists()).toBe(true);
  const action = process.env.CADENCE_RESERVATION_REVIEW_ACTION;
  if (action) {
    if (!oneOf(reservationActions, action)) throw Error("Invalid fixture action");
    await wrapper.get(`#${action}-reason`).setValue("Native producer review");
    await wrapper.get(`#${action}-form`).trigger("submit");
    await flushPromises();
    expect(execute).toHaveBeenCalledTimes(1);
    process.stdout.write(
      `RESERVATION_PAYLOAD=${JSON.stringify(required(execute.mock.calls[0])[1])}\n`,
    );
  }
  wrapper.unmount();
});

test("reservation links retain the plan and requirement versions actually booked", () => {
  const detail = reservationFixture();
  Object.assign(detail.reservation, {
    plan_id: "plan-one",
    plan_version: 3,
    requirement_id: "requirement-one",
    requirement_version: 2,
  });
  const wrapper = mount(
    pageHeaderHarness("/missions/:mission_id/ops/contacts/:provider_reservation_id").stage(
      OpsContactDetail,
    ),
    { props: { detail } },
  );
  expect(wrapper.get("#reservation-plan").attributes("href")).toBe(
    "/missions/mission-one/ops/plans/plan-one?version=3",
  );
  expect(wrapper.get("#reservation-requirement").attributes("href")).toBe(
    "/missions/mission-one/ops/requirements/requirement-one?version=2",
  );
  wrapper.unmount();
});

test("a receipt cannot stand in for a missing reviewed provider change", () => {
  const detail = reservationFixture();
  detail.selected = null;
  detail.query.change_id = null;
  expect(
    completedReceipt(
      {
        receiptId: "receipt-one",
        completedAt: "2027-01-01T00:00:00Z",
        result: { providerReservationId: detail.reservation.id, lifecycleState: "approved" },
      },
      detail,
      "approve-provider-change",
    ),
  ).toBe(false);
});
