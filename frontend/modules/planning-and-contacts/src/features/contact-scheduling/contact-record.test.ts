import { flushPromises, mount } from "@vue/test-utils";
import { expect, test, vi } from "vite-plus/test";
import { OpsContactRecord, type ContactRecordPort } from "../../contact-scheduling";
import { admitContactRecord, recordHref } from "./contact-record";
import { contactRecordFixture } from "./contact-record.test-support";

test("historical schedule values and current or realized paths remain visibly distinct", () => {
  const record = contactRecordFixture();
  const wrapper = mount(OpsContactRecord, { props: { record } });
  expect(wrapper.get("#contact-record-reviewed-window").text()).toContain("12:00:00Z");
  expect(wrapper.get("#contact-record-schedule").text()).toContain("12:01:00Z");
  expect(wrapper.get("#contact-record-historical").text()).toContain(
    "Historical schedule evidence",
  );
  expect(wrapper.get("#contact-record-scheduled_paths").text()).toContain("scheduled-path");
  expect(wrapper.get("#contact-record-realized_paths").text()).toContain("actual-path");
  expect(wrapper.get("#contact-record-realized-link").attributes("href")).toBe(
    "/missions/mission-one/ops/contacts/records/realized-one",
  );
  expect(wrapper.get("#contact-record-current-revision").attributes("href")).toBe(
    "/missions/mission-one/ops/contacts/records/scheduled-one?revision=2",
  );
  wrapper.unmount();
});
test("a standalone realized record renders empty execution evidence without a fictional schedule", () => {
  const r = contactRecordFixture();
  r.subject = { id: "realized-one", kind: "realized" };
  r.query.contact_id = "realized-one";
  r.query.revision = null;
  r.scheduled = null;
  r.realized!.scheduled_id = null;
  r.review = null;
  r.revisions.entries = [];
  r.scheduled_paths.entries = [];
  r.realized_paths.entries = [];
  r.sources.entries = [];
  r.intents.entries = [];
  const wrapper = mount(OpsContactRecord, { props: { record: r } });
  expect(wrapper.find("#contact-record-no-schedule").exists()).toBe(true);
  expect(wrapper.find("#contact-record-realized_paths-empty").exists()).toBe(true);
  expect(wrapper.find("#contact-record-schedule").exists()).toBe(false);
  wrapper.unmount();
});
test("history and section navigation preserve the selected revision and independent page state", () => {
  const r = contactRecordFixture();
  r.query.realized_paths_page = 3;
  r.realized_paths.page = 3;
  expect(recordHref(r, { sources_page: 2 })).toBe(
    "/missions/mission-one/ops/contacts/records/scheduled-one?revision=1&realized_paths_page=3&sources_page=2",
  );
  r.origin = {
    change_id: "change-one",
    reservation_id: "reservation-one",
    provider_revision: 3,
    proposal_hash: "a".repeat(64),
  };
  r.review!.provider_change_id = "change-one";
  const wrapper = mount(OpsContactRecord, { props: { record: r } });
  expect(wrapper.get("#contact-record-reservation-link").attributes("href")).toBe(
    "/missions/mission-one/ops/contacts/reservation-one?change_id=change-one",
  );
  wrapper.unmount();
});
test("read recovery retains the previous record, rejects foreign refreshes and suppresses duplicate reads", async () => {
  const record = contactRecordFixture();
  let resolve!: (v: unknown) => void;
  const refresh = vi.fn<ContactRecordPort["refresh"]>().mockImplementation(
    () =>
      new Promise((done) => {
        resolve = done;
      }),
  );
  const wrapper = mount(OpsContactRecord, {
    props: { record, port: { context: record.context, refresh } },
  });
  await wrapper.get("#contact-record-refresh").trigger("click");
  await wrapper.get("#contact-record-refresh").trigger("click");
  expect(refresh).toHaveBeenCalledTimes(1);
  const foreign = structuredClone(record);
  foreign.context.organization_id = "foreign";
  resolve(foreign);
  await flushPromises();
  expect(wrapper.get("#contact-record-identity").text()).toBe("scheduled-one");
  expect(wrapper.get("#contact-record-notice").text()).toContain("previous record is retained");
  refresh.mockRejectedValue(new Error("private failure"));
  await wrapper.get("#contact-record-refresh").trigger("click");
  await flushPromises();
  expect(wrapper.get("#contact-record-identity").text()).toBe("scheduled-one");
  expect(wrapper.text()).not.toContain("private failure");
  refresh.mockResolvedValue(record);
  await wrapper.get("#contact-record-refresh").trigger("click");
  await flushPromises();
  expect(wrapper.get("#contact-record-notice").text()).toBe("Contact evidence refreshed.");
  wrapper.unmount();
});
test("a departed record ignores a late read and rejects replacement identity", async () => {
  const record = contactRecordFixture();
  let resolve!: (v: unknown) => void;
  const refresh = vi.fn<ContactRecordPort["refresh"]>().mockImplementation(
    () =>
      new Promise((done) => {
        resolve = done;
      }),
  );
  const wrapper = mount(OpsContactRecord, {
    props: { record, port: { context: record.context, refresh } },
  });
  await wrapper.get("#contact-record-refresh").trigger("click");
  const other = structuredClone(record);
  other.subject.id = "other";
  other.query.contact_id = "other";
  other.scheduled!.id = "other";
  other.realized!.scheduled_id = "other";
  await wrapper.setProps({ record: other });
  resolve(record);
  await flushPromises();
  expect(wrapper.find("#contact-record-unavailable").exists()).toBe(true);
  wrapper.unmount();
});
test("admission rejects unsupported, substituted, future, duplicate, and contradictory records", () => {
  expect(admitContactRecord(contactRecordFixture())).not.toBeNull();
  for (const mutate of [
    (r: any) => {
      r.contract_version = 2;
    },
    (r: any) => {
      r.subject.id = "foreign";
    },
    (r: any) => {
      r.realized.scheduled_id = "foreign";
    },
    (r: any) => {
      r.review.revision = 3;
      r.query.revision = 3;
    },
    (r: any) => {
      r.revisions.entries.push(r.revisions.entries[0]);
    },
    (r: any) => {
      r.scheduled_paths.entries.push(r.scheduled_paths.entries[0]);
    },
    (r: any) => {
      r.sources.entries[0].kind = "current_schedule";
    },
    (r: any) => {
      r.realized_paths.more = true;
    },
    (r: any) => {
      r.query.sources_page = 2;
    },
    (r: any) => {
      r.review.provider_change_id = "unverified-change";
    },
  ]) {
    const r = contactRecordFixture();
    mutate(r);
    expect(admitContactRecord(r)).toBeNull();
  }
  expect(
    admitContactRecord(contactRecordFixture(), {
      organization_id: "foreign",
      mission_id: "mission-one",
    }),
  ).toBeNull();
});
