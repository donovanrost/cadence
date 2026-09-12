import { flushPromises, mount } from "@vue/test-utils";
import { expect, test, vi } from "vite-plus/test";
import OpsContactDetail from "./OpsContactDetail.vue";
import type { ReservationAction, ReservationPort } from "./OpsContactDetail.contracts";
import {
  admitReservation,
  canDecide,
  reservationDecision,
  reservationHref,
} from "./reservation-detail";
import { reservationFixture } from "./reservation.test-support";
function harness() {
  const detail = reservationFixture(),
    execute = vi.fn<ReservationPort["execute"]>(),
    refresh = vi.fn<ReservationPort["refresh"]>();
  const port = { context: detail.context, execute, refresh };
  return {
    detail,
    execute,
    refresh,
    port,
    wrapper: mount(OpsContactDetail, { props: { detail, port } }),
  };
}
test("native approval sends exactly the reviewed proposal and reconciles its completed receipt", async () => {
  const h = harness();
  const updated = structuredClone(h.detail);
  updated.selected!.lifecycle_state = "approved";
  h.execute.mockResolvedValue({
    receiptId: "receipt-one",
    completedAt: "2026-09-08T12:00:00Z",
    result: {
      providerReservationId: h.detail.reservation.id,
      providerReservationChangeId: h.detail.selected!.id,
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
  await h.wrapper.get("#reservation-refresh").trigger("click");
  await flushPromises();
  await h.wrapper.get("#reject-provider-change-form").trigger("submit");
  await flushPromises();
  expect(h.execute).toHaveBeenCalledTimes(1);
  expect(h.refresh).toHaveBeenCalledTimes(1);
  h.wrapper.unmount();
});
test("departing a review ignores late mutations and a changed identity clears reasons", async () => {
  const h = harness();
  let done!: (v: unknown) => void;
  h.execute.mockImplementation(
    () =>
      new Promise((resolve) => {
        done = resolve;
      }),
  );
  await h.wrapper.get("#approve-provider-change-reason").setValue("First review");
  await h.wrapper.get("#approve-provider-change-form").trigger("submit");
  const next = structuredClone(h.detail);
  next.selected!.id = "change-other";
  next.query.change_id = "change-other";
  await h.wrapper.setProps({ detail: next });
  done({});
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
  d.selected!.review_complete = false;
  expect(canDecide(d, "approve-provider-change")).toBe(false);
  d.selected!.review_complete = true;
  d.selected!.deadline_at = "2020-01-01T00:00:00Z";
  expect(canDecide(d, "approve-provider-change")).toBe(false);
  d.selected!.deadline_at = null;
  d.permissions.decide = false;
  expect(canDecide(d, "approve-provider-change")).toBe(false);
});
test("admission rejects cross-reservation, future, duplicate, and incomplete evidence", () => {
  for (const mutate of [
    (d: any) => {
      d.query.change_id = "other";
    },
    (d: any) => {
      d.selected.provider_revision = 3;
    },
    (d: any) => {
      d.changes.entries.push(d.changes.entries[0]);
    },
    (d: any) => {
      d.selected.fields[0].visible = false;
    },
    (d: any) => {
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
test("producer-supplied reservation review", async () => {
  if (!process.env.CADENCE_RESERVATION_REVIEW_MODEL) return;
  const props = JSON.parse(process.env.CADENCE_RESERVATION_REVIEW_MODEL);
  const detail = admitReservation(props.detail);
  expect(detail).not.toBeNull();
  const execute = vi.fn<ReservationPort["execute"]>().mockRejectedValue(new Error("payload only"));
  const wrapper = mount(OpsContactDetail, {
    props: { ...props, port: { context: detail!.context, execute, refresh: vi.fn() } },
  });
  expect(wrapper.find("#ops-contact-detail-page").exists()).toBe(true);
  const action = process.env.CADENCE_RESERVATION_REVIEW_ACTION as ReservationAction;
  if (action) {
    await wrapper.get(`#${action}-reason`).setValue("Native producer review");
    await wrapper.get(`#${action}-form`).trigger("submit");
    await flushPromises();
    expect(execute).toHaveBeenCalledTimes(1);
    process.stdout.write(`RESERVATION_PAYLOAD=${JSON.stringify(execute.mock.calls[0]![1])}\n`);
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
  const wrapper = mount(OpsContactDetail, { props: { detail } });
  expect(wrapper.get("#reservation-plan").attributes("href")).toBe(
    "/missions/mission-one/ops/plans/plan-one?version=3",
  );
  expect(wrapper.get("#reservation-requirement").attributes("href")).toBe(
    "/missions/mission-one/ops/requirements/requirement-one?version=2",
  );
  wrapper.unmount();
});
