import { producerFixture } from "../../../../../test-support/producer-fixture";
import { jsonFixture, fixtureContext } from "../../../../../test-support/json-fixture";
import { required } from "../../../../../test-support/required";
import { readFileSync, writeFileSync } from "node:fs";
import { mount, flushPromises } from "@vue/test-utils";
import { test, expect, vi } from "vite-plus/test";
import StageCreate from "./StageCreate.vue";
import { creationFixture } from "./fixtures.test-support";
import { createInput, readCreationPage } from "./contracts";
test("creation emits finite owner-free input and recovers a lost reply by reading", async () => {
  const page = creationFixture(),
    operation = {
      status: "completed",
      event: "create",
      write_token: required(page.write_token),
      receipt: {
        operation: "stage_created",
        stage_id: page.creation.stage_id,
        actor_id: page.creation.actor_id,
        name: "Flight stage",
        visibility: "shared",
        state: "draft",
      },
    };
  const execute = vi.fn().mockRejectedValueOnce(Error("lost")),
    read = vi.fn(async () => ({ ...page, write_token: null, operation }));
  const w = mount(StageCreate, {
    props: { page, port: { execute, navigate: vi.fn() }, readPort: { read } },
  });
  try {
    await w.get("#stage-create-name").setValue("Flight stage");
    await w.get("#stage-create-shared").setValue();
    await w.get("#stage-create-form").trigger("submit");
    await flushPromises();
    expect(execute).toHaveBeenCalledExactlyOnceWith("create", {
      expected_write: page.write_token,
      name: "Flight stage",
      description: null,
      visibility: "shared",
    });
    expect(w.get("#stage-create-result").text()).toContain("unconfirmed");
    await w.get("#stage-create-refresh").trigger("click");
    await flushPromises();
    expect(w.get("#stage-create-open").attributes("href")).toBe(
      "/missions/mission_one/ops/commands/stages/stage_new",
    );
    expect(execute).toHaveBeenCalledOnce();
  } finally {
    w.unmount();
  }
});
test("creation bounds Unicode and binds receipt actor and reserved stage", () => {
  const p = creationFixture();
  expect(
    createInput(required(p.write_token), "Flight", "é".repeat(2000), "private").description,
  ).toHaveLength(2000);
  expect(() =>
    createInput(required(p.write_token), "Flight", "é".repeat(2001), "private"),
  ).toThrow();
  expect(() =>
    readCreationPage({ ...p, creation: { ...p.creation, actor_id: "../bad" } }, p.creation.context),
  ).toThrow();
  expect(() =>
    readCreationPage(
      {
        ...p,
        write_token: null,
        operation: {
          status: "completed",
          write_token: p.write_token,
          event: "create",
          receipt: {
            operation: "stage_created",
            actor_id: "other",
            stage_id: p.creation.stage_id,
            name: "Flight",
            visibility: "private",
            state: "draft",
          },
        },
      },
      p.creation.context,
    ),
  ).toThrow();
});
const producer = producerFixture("CADENCE_COMMAND_STAGES_DOCUMENT", import.meta.url);
test.skipIf(!producer.available)(
  "actual producer stage creation controls yield the Phoenix input",
  async () => {
    const source = producer.read();
    const document = jsonFixture(readFileSync(source, "utf8")),
      page = readCreationPage(document.data, fixtureContext(document.context)),
      execute = vi.fn(async (_event: string, _input: Record<string, unknown>) => ({
        status: "rejected",
        feedback: "Probe only",
      }));
    const w = mount(StageCreate, {
      props: { page, port: { execute, navigate: vi.fn() }, readPort: { read: vi.fn() } },
    });
    try {
      await w.get("#stage-create-name").setValue("Reviewed flight stage");
      await w.get("#stage-create-description").setValue("é".repeat(2000));
      await w.get("#stage-create-form").trigger("submit");
      await flushPromises();
      expect(execute).toHaveBeenCalledOnce();
      writeFileSync(
        required(process.env.CADENCE_COMMAND_STAGES_INPUT_FILE),
        JSON.stringify({
          event: required(execute.mock.calls[0])[0],
          input: required(execute.mock.calls[0])[1],
        }),
      );
    } finally {
      w.unmount();
    }
  },
);
