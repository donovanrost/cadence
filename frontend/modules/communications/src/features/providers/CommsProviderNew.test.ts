import { mount } from "@vue/test-utils";
import { expect, test } from "vite-plus/test";
import CommsProviderNew from "./CommsProviderNew.vue";
import { providerNewPayload } from "./fixtures.test-support";
import { providerFieldKeys } from "./provider-new.contracts";

test("a delayed provider validation cannot overwrite newer typing", async () => {
  const props = providerNewPayload();
  const wrapper = mount(CommsProviderNew, { props });
  try {
    await wrapper.get("#provider_display_name").setValue("First");
    await wrapper.get("#provider_display_name").setValue("Latest");
    const form = structuredClone(props.form);
    form.fields.display_name.value = "First";
    await wrapper.setProps({ form });
    expect((wrapper.get("#provider_display_name").element as HTMLInputElement).value).toBe(
      "Latest",
    );
    await wrapper.get("#mission-provider-form").trigger("submit");
    expect(wrapper.emitted("save")?.[0]).toEqual([
      {
        provider: Object.fromEntries(
          providerFieldKeys.map((key) => [key, key === "display_name" ? "Latest" : ""]),
        ),
      },
    ]);
  } finally {
    wrapper.unmount();
  }
});

test("provider creation is unavailable without an account grant", () => {
  const props = providerNewPayload();
  props.accounts.empty = true;
  const wrapper = mount(CommsProviderNew, { props });
  try {
    expect(wrapper.find("#mission-provider-form").exists()).toBe(false);
    expect(wrapper.get("#open-provider-accounts-link").attributes("href")).toBe(
      "/provider-accounts",
    );
  } finally {
    wrapper.unmount();
  }
});
