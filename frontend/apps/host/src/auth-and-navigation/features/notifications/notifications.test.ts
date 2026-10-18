import { producerFixture } from "../../../../../../test-support/producer-fixture";
import { jsonFixture } from "../../../../../../test-support/json-fixture";
import { required } from "../../../../../../test-support/required";
import { flushPromises, mount } from "@vue/test-utils";
import { expect, test, vi } from "vite-plus/test";
import { inboxHref, readInbox, type Inbox } from "./contracts";
import NotificationsPage from "./NotificationsPage.vue";
import NotificationsPanel from "./NotificationsPanel.vue";
const fixture = (): Inbox => ({
  version: 1,
  user_id: "user-1",
  observed_at: "2026-09-01T00:00:00Z",
  limit: 50,
  query: { unread: "", before_at: "", before_id: "" },
  next_cursor: null,
  notifications: [
    {
      id: "notif-1",
      kind: "organization_invitation",
      title: "Join Flight",
      body: "Organization invitation",
      created_at: "2026-08-31T00:00:00Z",
      read_at: "2026-08-31T01:00:00Z",
      invitation_status: "pending",
    },
  ],
});
const props = (model = fixture()) => ({
  model,
  act: vi.fn().mockResolvedValue({ status: "ok", data: { status: "accepted" } }),
  refresh: vi.fn().mockResolvedValue(undefined),
});

test("reading an invitation does not claim acceptance or remove its pending action", async () => {
  const input = props(),
    wrapper = mount(NotificationsPanel, { props: input });
  expect(wrapper.get("#notification-state-notif-1").text()).toBe("Invitation pending");
  expect(wrapper.find("#notification-mark-read-notif-1").exists()).toBe(false);
  await wrapper.get("#notification-accept-notif-1").trigger("click");
  await flushPromises();
  expect(input.act).toHaveBeenCalledWith("accept_invitation", { notification_id: "notif-1" });
  expect(wrapper.get("#notification-action-message").text()).toBe("Invitation accepted.");
  wrapper.unmount();
});
test("terminal and unavailable invitations expose their actual state and only the read action", () => {
  for (const state of ["accepted", "expired", "revoked", "unavailable"] as const) {
    const model = fixture();
    required(model.notifications[0]).invitation_status = state;
    required(model.notifications[0]).read_at = null;
    const wrapper = mount(NotificationsPanel, { props: props(model) });
    expect(wrapper.get("#notification-state-notif-1").text().toLowerCase()).toContain(state);
    expect(wrapper.find("#notification-accept-notif-1").exists()).toBe(false);
    expect(wrapper.find("#notification-mark-read-notif-1").exists()).toBe(true);
    wrapper.unmount();
  }
});
test("one pending request and an uncertain outcome require fresh evidence before another action", async () => {
  let reject!: (e: Error) => void;
  const act = vi.fn(
    () =>
      new Promise((_ok, fail) => {
        reject = fail;
      }),
  );
  const model = fixture();
  required(model.notifications[0]).read_at = null;
  const refresh = vi.fn().mockResolvedValue(undefined);
  const wrapper = mount(NotificationsPanel, { props: { model, act, refresh } });
  await wrapper.get("#notification-mark-read-notif-1").trigger("click");
  await wrapper.get("#notification-accept-notif-1").trigger("click");
  expect(act).toHaveBeenCalledTimes(1);
  reject(Error("disconnected"));
  await flushPromises();
  expect(wrapper.get("#notification-action-message").text()).toContain("could not be confirmed");
  expect(wrapper.get("#notification-accept-notif-1").attributes("disabled")).toBeDefined();
  await wrapper.get("#refresh-notifications").trigger("click");
  await flushPromises();
  expect(wrapper.get("#notification-accept-notif-1").attributes("disabled")).toBeDefined();
  await wrapper.setProps({
    refresh: async () => {
      await wrapper.setProps({ model: { ...model, observed_at: "2026-09-01T00:01:00Z" } });
    },
  });
  await wrapper.get("#refresh-notifications").trigger("click");
  await flushPromises();
  expect(wrapper.get("#notification-accept-notif-1").attributes("disabled")).toBeUndefined();
  expect(act).toHaveBeenCalledTimes(1);
  wrapper.unmount();
});
test("older navigation preserves unread filters and newest resets the cursor", () => {
  const model = fixture();
  model.query = { unread: "true", before_at: "2026-08-31T00:00:00Z", before_id: "notif-2" };
  required(model.notifications[0]).read_at = null;
  model.next_cursor = { at: "2026-08-30T00:00:00Z", id: "notif-0" };
  const wrapper = mount(NotificationsPanel, { props: props(model) });
  expect(wrapper.get("#notifications-newest").attributes("href")).toBe(
    "/notifications?unread=true",
  );
  expect(wrapper.get("#notifications-older").attributes("href")).toBe(
    inboxHref({ unread: "true", before_at: model.next_cursor.at, before_id: model.next_cursor.id }),
  );
  wrapper.unmount();
});
test("recipient, version and malformed status are rejected while host retry remains available", async () => {
  const data = fixture(),
    refresh = vi.fn();
  const snapshot = {
    version: 1,
    page: "notifications",
    status: "ready",
    user_id: "user-1",
    action_token: "nonce",
    data,
  };
  const wrapper = mount(NotificationsPage, {
    props: { snapshot, userId: "other", act: vi.fn(), refresh },
  });
  expect(wrapper.find("#core-notifications-error").exists()).toBe(true);
  await wrapper.get("#core-notifications-retry").trigger("click");
  expect(refresh).toHaveBeenCalledTimes(1);
  await wrapper.setProps({ userId: "user-1" });
  expect(wrapper.find("#notifications-page").exists()).toBe(true);
  await wrapper.setProps({ snapshot: { ...snapshot, version: 2 } });
  expect(wrapper.find("#core-notifications-error").exists()).toBe(true);
  wrapper.unmount();
  for (const alter of [
    (d: Inbox) => {
      d.user_id = "other";
    },
    (d: Inbox) => {
      d.notifications.push(required(d.notifications[0]));
    },
    (d: Inbox) => {
      required(d.notifications[0]).invitation_status = "bogus" as never;
    },
    (d: Inbox) => {
      d.query.unread = "true";
    },
  ]) {
    const doc = fixture();
    alter(doc);
    expect(() => readInbox(doc, "user-1")).toThrow();
  }
});
const producer = producerFixture("CADENCE_NOTIFICATIONS_DOCUMENT", import.meta.url);
test.skipIf(!producer.available)(
  "actual producer renders a read but pending invitation and sends the recipient notification ID",
  async () => {
    const value = jsonFixture(required(producer.read()));
    const model = readInbox(value, value.user_id),
      input = props(model),
      wrapper = mount(NotificationsPanel, { props: input });
    const invitation = required(
      model.notifications.find((row) => row.invitation_status === "pending"),
    );
    expect(invitation.read_at).not.toBeNull();
    expect(wrapper.get(`#notification-state-${invitation.id}`).text()).toBe("Invitation pending");
    await wrapper.get(`#notification-accept-${invitation.id}`).trigger("click");
    await flushPromises();
    expect(input.act).toHaveBeenCalledWith("accept_invitation", { notification_id: invitation.id });
    wrapper.unmount();
  },
);
