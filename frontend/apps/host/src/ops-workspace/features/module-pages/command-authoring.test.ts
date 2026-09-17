import "../../../module-pages.test-support";
import { mount, flushPromises } from "@vue/test-utils";
import { test, expect, vi } from "vite-plus/test";
import OpsModulePage from "./OpsModulePage.vue";
import {
  pageFixture,
  previewFixture,
} from "../../../../../../modules/commanding/src/features/command-authoring/fixtures.test-support";

function initial() {
  const data = pageFixture();
  return {
    id: "commanding.authoring",
    slot: "ops.page",
    version: 1,
    status: "ready",
    token: "11111111-1111-4111-8111-111111111111",
    context: data.catalog.context,
    data,
  };
}

test("the compiled authoring owner receives captured preview, create, and receipt ports", async () => {
  const snapshot = initial();
  const preview = previewFixture();
  const operation = {
    status: "completed",
    receipt: {
      request_id: preview.request_id,
      actor_id: preview.actor_id,
      requested_at: preview.requested_at,
      lifecycle_state: preview.lifecycle_state,
    },
  };
  const execute = vi
    .fn()
    .mockResolvedValueOnce({ status: "previewed", preview })
    .mockRejectedValueOnce(Error("Lost create response"));
  const query = vi.fn(async () => ({
    ...snapshot,
    data: { ...snapshot.data, preview, operation },
  }));
  const w = mount(OpsModulePage, {
    props: {
      contributionId: snapshot.id,
      snapshot,
      context: snapshot.context,
      execute,
      query,
      refresh: vi.fn(),
      navigate: vi.fn(),
    },
  });
  try {
    await w.get('[data-argument-name="amount"]').setValue("2");
    await w.get("#command-authoring-form").trigger("submit");
    await flushPromises();
    expect(execute).toHaveBeenNthCalledWith(1, {
      id: snapshot.id,
      token: snapshot.token,
      event: "preview",
      input: {
        expected_basis: snapshot.data.catalog.basis.token,
        source_endpoint_ref: "target_one",
        command_id: "command_one",
        argument_values_json: JSON.stringify({ amount: 2, delay_s: 5, enabled: false }),
        priority: 3,
        not_before: null,
        expires_at: null,
      },
    });
    await w.get("#authoring-confirm").setValue(true);
    await w.get("#command-authoring-create").trigger("click");
    await flushPromises();
    expect(execute).toHaveBeenNthCalledWith(2, {
      id: snapshot.id,
      token: snapshot.token,
      event: "create",
      input: { expected_preview: preview.token },
    });
    await w.get("#command-authoring-refresh").trigger("click");
    await flushPromises();
    expect(query).toHaveBeenCalledExactlyOnceWith({ id: snapshot.id, token: snapshot.token });
    expect(w.get("#command-authoring-result").text()).toContain("Command request saved");
    expect(execute).toHaveBeenCalledTimes(2);
    await w.setProps({ context: { ...snapshot.context, missionId: "other" } });
    expect(w.find("#ops-module-unavailable").exists()).toBe(true);
    expect(w.find("#command-authoring-form").exists()).toBe(false);
  } finally {
    w.unmount();
  }
});

test("a late preview cannot reach a replaced authoring instance", async () => {
  const snapshot = initial();
  let reply!: (value: unknown) => void;
  const execute = vi.fn(
    () =>
      new Promise<unknown>((resolve) => {
        reply = resolve;
      }),
  );
  const w = mount(OpsModulePage, {
    props: {
      contributionId: snapshot.id,
      snapshot,
      context: snapshot.context,
      execute,
      query: vi.fn(),
      refresh: vi.fn(),
      navigate: vi.fn(),
    },
  });
  try {
    await w.get('[data-argument-name="amount"]').setValue("2");
    await w.get("#command-authoring-form").trigger("submit");
    await flushPromises();
    await w.setProps({ snapshot: { ...snapshot, token: "22222222-2222-4222-8222-222222222222" } });
    reply({ status: "previewed", preview: previewFixture() });
    await flushPromises();
    expect(w.find("#command-authoring-preview-details").exists()).toBe(false);
    expect(w.find("#command-authoring-form").exists()).toBe(true);
    expect(execute).toHaveBeenCalledOnce();
  } finally {
    w.unmount();
  }
});
