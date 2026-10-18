import { mount } from "@vue/test-utils";
import { expect, test } from "vite-plus/test";
import NotificationBell from "./NotificationBell.vue";
import { context } from "../../shared/context.test-support";

test("the recipient bell owns summaries and only links to the compiled inbox", async () => {
  const value = {
    ...context,
    unread_count: 12,
    notifications: [
      {
        notification_id: "n",
        title: "Title",
        body: "First line\nSecond line",
        read_at: null,
        action_url: "https://untrusted.example",
      },
    ],
  };
  const wrapper = mount(NotificationBell, {
    attachTo: document.body,
    props: { context: value, id: "bell" },
  });
  expect(wrapper.get("#bell").text()).toBe("9+");
  await wrapper.get("#bell").trigger("click");
  expect(wrapper.findAll("a").map((link) => link.attributes("href"))).toEqual([
    "/notifications",
    "/notifications",
  ]);
  for (const bad of [
    { ...value, version: 2 },
    { ...value, unread_count: -1 },
    { ...value, notifications: [value.notifications[0], value.notifications[0]] },
    { ...value, notifications: [{ ...value.notifications[0], read_at: "invalid" }] },
  ]) {
    await wrapper.setProps({ context: bad });
    expect(wrapper.find("#bell").exists()).toBe(false);
    expect(wrapper.find("#bell-unavailable").exists()).toBe(true);
  }
  wrapper.unmount();
});
