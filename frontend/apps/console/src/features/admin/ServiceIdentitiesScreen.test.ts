import { flushPromises, mount } from "@vue/test-utils";
import { describe, expect, it } from "vite-plus/test";
import ServiceIdentitiesScreen from "./ServiceIdentitiesScreen.vue";

/** qa 11-13: the platform list paused on a null key and never loaded. */
describe("Admin › Service identities", () => {
  it("requests every organization's service identities on mount", async () => {
    const urls: string[] = [];
    const original = globalThis.fetch;
    globalThis.fetch = async (input) => {
      urls.push(typeof input === "string" ? input : input instanceof URL ? input.href : input.url);
      return new Response(JSON.stringify({ data: { service_identities: [] } }), { status: 200 });
    };
    try {
      mount(ServiceIdentitiesScreen, { shallow: true });
      await flushPromises();
    } finally {
      globalThis.fetch = original;
    }
    expect(urls.some((u) => u.endsWith("/admin/service-identities"))).toBe(true);
  });
});
