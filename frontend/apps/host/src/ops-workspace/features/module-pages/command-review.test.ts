import { mount, flushPromises } from "@vue/test-utils";
import { test, expect, vi } from "vite-plus/test";
import OpsModulePage from "./OpsModulePage.vue";
import {
  fixture,
  completed,
} from "../../../../../../modules/commanding/src/features/command-review/fixtures.test-support";
function initial() {
  const data = fixture();
  return {
    id: "commanding.review",
    slot: "ops.page",
    version: 1,
    status: "ready",
    token: "11111111-1111-4111-8111-111111111111",
    context: data.review.context,
    data,
  };
}
test("the compiled commanding owner receives only captured decision and receipt ports", async () => {
  const snapshot = initial(),
    execute = vi.fn(async () => {
      throw Error("Lost response");
    }),
    query = vi.fn(async () => ({
      ...snapshot,
      data: { ...snapshot.data, operation: completed(snapshot.data) },
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
    await w.get("#command-review-choice").setValue("approved");
    await w.get("#command-review-confirm").setValue(true);
    await w.get("#command-review-form").trigger("submit");
    await flushPromises();
    expect(execute).toHaveBeenCalledExactlyOnceWith({
      id: snapshot.id,
      token: snapshot.token,
      event: "decide",
      input: {
        decision: "approved",
        reason: "",
        expected_review: snapshot.data.review.expected_review,
      },
    });
    await w.get("#command-review-refresh").trigger("click");
    await flushPromises();
    expect(query).toHaveBeenCalledExactlyOnceWith({ id: snapshot.id, token: snapshot.token });
    expect(w.get("[data-review-receipt]").text()).toContain("approval_saved");
    await w.setProps({ context: { ...snapshot.context, resourceId: "other" } });
    expect(w.find("#ops-module-unavailable").exists()).toBe(true);
    expect(w.find("#command-review").exists()).toBe(false);
  } finally {
    w.unmount();
  }
});
test("a retained response cannot reach a replaced command review", async () => {
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
    await w.get("#command-review-choice").setValue("approved");
    await w.get("#command-review-confirm").setValue(true);
    await w.get("#command-review-form").trigger("submit");
    await flushPromises();
    await w.setProps({ snapshot: { ...snapshot, token: "22222222-2222-4222-8222-222222222222" } });
    reply(completed(snapshot.data));
    await flushPromises();
    expect(w.find("[data-review-receipt]").exists()).toBe(false);
    expect(w.find("#command-review-form").exists()).toBe(true);
    expect(execute).toHaveBeenCalledOnce();
  } finally {
    w.unmount();
  }
});
