import { mount } from "@vue/test-utils";
import { expect, test } from "vite-plus/test";
import { exposedComponents } from "../../../../../organization-admin/src/federated-application";
import FederatedNotificationBell from "./FederatedNotificationBell.vue";

const fixture = () => ({
  version: 1,
  user: { user_id: "recipient" },
  unread_count: 6,
  notifications: [{ notification_id: "notice", title: "Notice", body: "Details", read_at: null }],
});

test("the remote bell delegates to the recipient owner and compiles inbox links", async () => {
  expect(exposedComponents.NotificationsBell).toBe(FederatedNotificationBell);
  const context = fixture();
  const wrapper = mount(exposedComponents.NotificationsBell, {
    props: { context, expectedUserId: "recipient" },
    attachTo: document.body,
  });
  await wrapper.get("#notifications-bell-application").trigger("click");
  expect(wrapper.findAll("a").map((link) => link.attributes("href"))).toEqual([
    "/notifications",
    "/notifications",
  ]);
  await wrapper.get("a").trigger("click");
  expect(wrapper.emitted("mark-read")).toBeUndefined();
  expect(context.notifications[0]!.read_at).toBeNull();
  wrapper.unmount();
});

test("a remote bell requires the exact host recipient and a valid summary", async () => {
  const value = fixture();
  const wrapper = mount(FederatedNotificationBell, {
    props: { context: value, expectedUserId: "recipient" },
  });
  for (const expectedUserId of [undefined, null, "", "other", ["recipient"]]) {
    await wrapper.setProps({ expectedUserId });
    expect(wrapper.find("#notifications-bell-application").exists()).toBe(false);
    expect(wrapper.find("#notifications-bell-application-unavailable").exists()).toBe(true);
  }
  await wrapper.setProps({ expectedUserId: "recipient" });
  for (const context of [
    {},
    { ...value, version: 2 },
    { ...value, user: { user_id: "other" } },
    { ...value, unread_count: -1 },
    { ...value, notifications: [value.notifications[0], value.notifications[0]] },
    { ...value, notifications: [{ ...value.notifications[0], read_at: "invalid" }] },
  ]) {
    await wrapper.setProps({ context });
    expect(wrapper.find("#notifications-bell-application").exists()).toBe(false);
  }
  await wrapper.setProps({ context: value });
  expect(wrapper.find("#notifications-bell-application").exists()).toBe(true);
  wrapper.unmount();
});

test("actual native bell props mount through the exposed remote owner", async () => {
  const input = process.env.CADENCE_FEDERATED_BELL_DOCUMENT
    ? JSON.parse(process.env.CADENCE_FEDERATED_BELL_DOCUMENT)
    : { context: fixture(), expectedUserId: "recipient" };
  const wrapper = mount(exposedComponents.NotificationsBell, {
    props: input,
    attachTo: document.body,
  });
  expect(wrapper.get("#notifications-bell-application").text()).toBe("6");
  await wrapper.get("#notifications-bell-application").trigger("click");
  expect(wrapper.findAll("a")).toHaveLength(input.context.notifications.length + 1);
  for (const link of wrapper.findAll("a")) expect(link.attributes("href")).toBe("/notifications");
  wrapper.unmount();
});
