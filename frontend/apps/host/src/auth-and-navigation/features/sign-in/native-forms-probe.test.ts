import { producerFixture } from "../../../../../../test-support/producer-fixture";
import "../../../module-pages.test-support";
import { jsonFixture } from "../../../../../../test-support/json-fixture";
import BrowserHost from "../../../shell/BrowserHost.vue";
import type { useLiveVue } from "live_vue";
vi.mock("live_vue", () => ({
  useLiveVue: (): ReturnType<typeof useLiveVue> => ({
    pushEvent: vi.fn(),
    handleEvent: (event, callback) => ({ event, callback: (value) => callback(value.detail) }),
    removeHandleEvent: vi.fn(),
  }),
}));
vi.mock("../../../shell/host-browser-history", async () => {
  const { createMemoryHistory } = await import("vue-router");
  return { hostBrowserHistory: createMemoryHistory(), ownBrowserHistory: vi.fn() };
});
import { writeFileSync } from "node:fs";
import { mount, flushPromises } from "@vue/test-utils";
import { test, expect, vi } from "vite-plus/test";
import {
  SignInPanel,
  AdminModePanel,
  OrganizationAccessPanel,
  InvitationAcceptancePanel,
  AccountMenu,
} from "../../index";

const producer = producerFixture("CADENCE_AUTH_DOCUMENT", import.meta.url);
test.skipIf(!producer.available)(
  "actual producer documents submit native fields through their feature owners",
  async () => {
    const data = jsonFixture(producer.read());
    if (typeof data.other_organization_id !== "string")
      throw Error("Missing organization fixture identity");
    const inputs: Record<string, unknown> = {};
    const signin = mount(SignInPanel, { props: { page: data.sign_in } });
    await signin.get("#user_email").setValue(data.email);
    await signin.get("#user_password").setValue(data.password);
    inputs.sign_in = submit(signin.get("#sign-in-form").element);
    const mode = mount(AdminModePanel, { props: { page: data.admin_mode } });
    await mode.get("#admin_mode_password").setValue(data.password);
    inputs.admin_mode = submit(mode.get("#admin-mode-form").element);
    const access = mount(OrganizationAccessPanel, { props: { page: data.organization_access } });
    inputs.organization_access = submit(access.get("#no-organization-sign-out").element);
    const invite = mount(InvitationAcceptancePanel, { props: { page: data.invitation } });
    await invite
      .get("#organization_invitation_acceptance_display_name")
      .setValue("Accepted through the native form");
    await invite.get("#organization_invitation_acceptance_password").setValue(data.password);
    await invite
      .get("#organization_invitation_acceptance_password_confirmation")
      .setValue(data.password);
    inputs.invitation = submit(invite.get("#organization-invitation-acceptance-form").element);
    const host = mount(BrowserHost, {
      attachTo: document.body,
      props: { snapshot: data.snapshot },
    });
    await flushPromises();
    const account = host.getComponent(AccountMenu);
    const accountId = account.props("id");
    if (typeof accountId !== "string") throw Error("Missing account menu identity");
    await account.get(`#${accountId}-user`).trigger("click");
    inputs.switch_organization = submit(
      account.get(`#${accountId}-switch-${data.other_organization_id}`).element,
    );
    inputs.sign_out = submit(account.get(`#${accountId}-sign-out`).element);
    expect(host.get('nav[aria-label="Primary navigation"] a[href="/missions"]').text()).toContain(
      "Missions",
    );
    if (!process.env.CADENCE_AUTH_INPUT_FILE) throw Error("Missing output file");
    writeFileSync(process.env.CADENCE_AUTH_INPUT_FILE, JSON.stringify(inputs));
    for (const wrapper of [signin, mode, access, invite, host]) wrapper.unmount();
  },
);
function submit(element: Element) {
  if (!(element instanceof HTMLFormElement)) throw Error("Expected a native form");
  const form = element;
  const event = new Event("submit", { bubbles: true, cancelable: true });
  form.dispatchEvent(event);
  expect(event.defaultPrevented).toBe(false);
  return {
    action: form.getAttribute("action"),
    method: form.getAttribute("method"),
    fields: Object.fromEntries(new FormData(form)),
  };
}
