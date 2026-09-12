import "../../../module-pages.test-support";
import { mount, flushPromises } from "@vue/test-utils";
import { test, expect, vi } from "vite-plus/test";
import OpsModulePage from "./OpsModulePage.vue";
import {
  workbenchFixture,
  batchPreviewFixture,
} from "../../../../../../modules/commanding/src/features/stage-workbench/fixtures.test-support";
import { creationFixture } from "../../../../../../modules/commanding/src/features/stage-create/fixtures.test-support";
test("compiled stage creation receives only captured host write and read ports", async () => {
  const data = creationFixture(),
    snapshot = {
      id: "commanding.stage-create",
      slot: "ops.page",
      version: 1,
      status: "ready",
      token: "11111111-1111-4111-8111-111111111111",
      context: data.creation.context,
      data,
    };
  const execute = vi.fn().mockRejectedValueOnce(Error("lost")),
    query = vi.fn(async () => ({
      ...snapshot,
      data: {
        ...data,
        write_token: null,
        operation: {
          status: "completed",
          event: "create",
          write_token: data.write_token,
          receipt: {
            operation: "stage_created",
            stage_id: data.creation.stage_id,
            actor_id: data.creation.actor_id,
            name: "Flight",
            visibility: "private",
            state: "draft",
          },
        },
      },
    }));
  const w = mount(OpsModulePage, {
    props: {
      contributionId: snapshot.id,
      snapshot,
      context: snapshot.context,
      execute,
      query,
      navigate: vi.fn(),
      refresh: vi.fn(),
    },
  });
  try {
    await w.get("#stage-create-name").setValue("Flight");
    await w.get("#stage-create-form").trigger("submit");
    await flushPromises();
    expect(execute).toHaveBeenCalledExactlyOnceWith({
      id: snapshot.id,
      token: snapshot.token,
      event: "create",
      input: {
        expected_write: data.write_token,
        name: "Flight",
        description: null,
        visibility: "private",
      },
    });
    await w.get("#stage-create-refresh").trigger("click");
    await flushPromises();
    expect(query).toHaveBeenCalledExactlyOnceWith({ id: snapshot.id, token: snapshot.token });
    expect(w.get("#stage-create-open").attributes("href")).toContain("stage_new");
    expect(execute).toHaveBeenCalledOnce();
  } finally {
    w.unmount();
  }
});
test("a late batch preview cannot reach a replaced workbench instance or foreign context", async () => {
  const data = workbenchFixture(),
    snapshot = {
      id: "commanding.stage-workbench",
      slot: "ops.page",
      version: 1,
      status: "ready",
      token: "11111111-1111-4111-8111-111111111111",
      context: data.workbench.context,
      data,
    };
  let reply!: (value: unknown) => void;
  const execute = vi.fn(
    () =>
      new Promise((r) => {
        reply = r;
      }),
  );
  const w = mount(OpsModulePage, {
    props: {
      contributionId: snapshot.id,
      snapshot,
      context: snapshot.context,
      execute,
      query: vi.fn(),
      navigate: vi.fn(),
      refresh: vi.fn(),
    },
  });
  try {
    await w.get('[data-select-item="item_one"]').setValue(true);
    await w.get("#stage-preview-batch").trigger("click");
    await w.setProps({ snapshot: { ...snapshot, token: "22222222-2222-4222-8222-222222222222" } });
    reply({ status: "previewed", preview: batchPreviewFixture() });
    await flushPromises();
    expect(w.find("#stage-batch-preview").exists()).toBe(false);
    await w.setProps({ context: { ...snapshot.context, missionId: "other" } });
    expect(w.find("#stage-workbench").exists()).toBe(false);
    expect(w.find("#ops-module-unavailable").exists()).toBe(true);
    expect(execute).toHaveBeenCalledOnce();
  } finally {
    w.unmount();
  }
});
