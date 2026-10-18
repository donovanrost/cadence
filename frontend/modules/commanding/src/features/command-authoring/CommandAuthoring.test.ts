import { producerFixture } from "../../../../../test-support/producer-fixture";
import { containing } from "../../../../../test-support/matchers";
import {
  jsonFixture,
  fixtureContext,
  fixtureString,
} from "../../../../../test-support/json-fixture";
import { required } from "../../../../../test-support/required";
import { fixtureRecordAt } from "../../../../../test-support/json-fixture";
import { mount, flushPromises } from "@vue/test-utils";
import { pageHeaderHarness } from "@cadence/plugin-sdk/page-header-testing";
import { describe, expect, test, vi } from "vite-plus/test";
import { writeFileSync } from "node:fs";
import CommandAuthoring from "./CommandAuthoring.vue";
import CommandAuthoringPage from "./CommandAuthoringPage.vue";
import { readAuthoringContribution } from "./contracts";
import { authoringHref, readAuthoringPage, readOperation, type AuthoringPage } from "./contracts";
import { pageFixture, previewFixture } from "./fixtures.test-support";
function mountPage(page = pageFixture()) {
  const execute = vi.fn(
    async (_event: string, _input: Record<string, unknown>): Promise<unknown> => ({
      status: "previewed",
      preview: previewFixture(),
    }),
  );
  const navigate = vi.fn(),
    read = vi.fn(async (): Promise<unknown> => page),
    dispose = vi.fn();
  const guardNavigation = vi.fn((_guard: () => boolean) => dispose);
  const wrapper = mount(
    pageHeaderHarness("/missions/:mission_id/ops/commands/new").stage(CommandAuthoring),
    {
      props: { page, port: { execute, navigate, guardNavigation }, readPort: { read } },
    },
  );
  return { wrapper, execute, navigate, read, dispose, guardNavigation };
}
async function enterAndPreview(c: ReturnType<typeof mountPage>) {
  await c.wrapper.get('[data-argument-name="amount"]').setValue("2");
  await c.wrapper.get('[data-argument-name="enabled"]').setValue("false");
  await c.wrapper.get("#command-authoring-form").trigger("submit");
  await flushPromises();
}
describe("command authoring", () => {
  test("submits explicit defaults and false, leaving fixed arguments to the server", async () => {
    const c = mountPage();
    await enterAndPreview(c);
    expect(c.execute).toHaveBeenCalledWith("preview", {
      expected_basis: "a".repeat(64),
      source_endpoint_ref: "target_one",
      command_id: "command_one",
      argument_values_json: JSON.stringify({ amount: 2, delay_s: 5, enabled: false }),
      priority: 3,
      not_before: null,
      expires_at: null,
    });
    expect(c.wrapper.get("#authoring-resolved-arguments").text()).toContain('"delay_s": 5');
    expect(c.wrapper.find('[data-argument-name="channel"]').exists()).toBe(false);
    expect(c.wrapper.get("#command-authoring-create").attributes("disabled")).toBeDefined();
    c.wrapper.unmount();
  });
  test("requires confirmation and consumes one create attempt, recovering only an exact receipt", async () => {
    const c = mountPage();
    await enterAndPreview(c);
    await c.wrapper.get("#authoring-confirm").setValue(true);
    c.execute.mockRejectedValueOnce(Error("lost reply"));
    await c.wrapper.get("#command-authoring-create").trigger("click");
    await flushPromises();
    expect(c.execute.mock.calls.filter(([event]) => event === "create")).toEqual([
      ["create", { expected_preview: "b".repeat(64) }],
    ]);
    expect(c.wrapper.get("#command-authoring-result").text()).toContain("Creation is unconfirmed");
    expect(c.wrapper.find("#command-authoring-create").exists()).toBe(false);
    const p = pageFixture(),
      preview = previewFixture();
    p.preview = preview;
    p.operation = {
      status: "completed",
      receipt: {
        request_id: preview.request_id,
        actor_id: preview.actor_id,
        requested_at: preview.requested_at,
        lifecycle_state: "approval_pending",
      },
    };
    c.read.mockResolvedValue(p);
    await c.wrapper.get("#page-header-refresh").trigger("click");
    await flushPromises();
    expect(c.wrapper.get("#command-authoring-result").text()).toContain("Command request saved");
    expect(c.execute).toHaveBeenCalledTimes(2);
    c.wrapper.unmount();
  });
  test("editing arguments invalidates the preview and confirmation", async () => {
    const c = mountPage();
    await enterAndPreview(c);
    await c.wrapper.get("#authoring-confirm").setValue(true);
    await c.wrapper.get('[data-argument-name="amount"]').setValue("3");
    expect(c.wrapper.find("#command-authoring-preview-details").exists()).toBe(false);
    expect(c.execute).toHaveBeenCalledTimes(1);
    c.wrapper.unmount();
  });
  test("a changed basis clears the old preview and a foreign actor read is rejected", async () => {
    const c = mountPage();
    await enterAndPreview(c);
    const changed = pageFixture();
    changed.catalog.basis.token = "c".repeat(64);
    c.read.mockResolvedValue(changed);
    await c.wrapper.get("#page-header-refresh").trigger("click");
    await flushPromises();
    expect(c.wrapper.find("#command-authoring-preview-details").exists()).toBe(false);
    expect(c.wrapper.get("#command-authoring-feedback").text()).toContain("active model changed");
    changed.catalog.actor_id = "other_user";
    c.read.mockResolvedValue(changed);
    await c.wrapper.get("#page-header-refresh").trigger("click");
    await flushPromises();
    expect(c.wrapper.get("#command-authoring-feedback").text()).toContain("could not be refreshed");
    c.wrapper.unmount();
  });
  test("pending previews guard navigation and late replies cannot update a departed page", async () => {
    const c = mountPage();
    let resolve!: (v: unknown) => void;
    c.execute.mockImplementation(
      () =>
        new Promise((r) => {
          resolve = r;
        }),
    );
    await c.wrapper.get('[data-argument-name="amount"]').setValue("2");
    await c.wrapper.get("#command-authoring-form").trigger("submit");
    expect(required(c.guardNavigation.mock.calls[0])[0]()).toBe(false);
    expect(c.navigate).not.toHaveBeenCalled();
    c.wrapper.unmount();
    resolve({ status: "previewed", preview: previewFixture() });
    await flushPromises();
    expect(c.dispose).toHaveBeenCalledOnce();
  });
  test("native modifier navigation is preserved and selections use the public durable route", async () => {
    const p = pageFixture();
    p.catalog.selected_command = null;
    p.catalog.query.command = "";
    const c = mountPage(p);
    const link = c.wrapper.get("#authoring-commands a");
    await link.trigger("click", { ctrlKey: true });
    expect(c.navigate).not.toHaveBeenCalled();
    await link.trigger("click");
    expect(c.navigate).toHaveBeenCalledWith(
      authoringHref("mission_one", { ...p.catalog.query, command: "command_one" }),
    );
    c.wrapper.unmount();
  });
  test("invalid integers never reach preview execution", async () => {
    const c = mountPage();
    await c.wrapper.get('[data-argument-name="amount"]').setValue("9007199254740992.1");
    await c.wrapper.get("#command-authoring-form").trigger("submit");
    expect(c.execute).not.toHaveBeenCalled();
    expect(c.wrapper.get("#command-authoring-feedback").text()).toContain("integer");
    c.wrapper.unmount();
  });
  test("version, context, selection, paging and receipt identity are validated", () => {
    const p = pageFixture();
    expect(readAuthoringPage(p, p.catalog.context)).toEqual(p);
    for (const change of [
      (x: AuthoringPage) => {
        x.catalog.version = 1 as 2;
      },
      (x: AuthoringPage) => {
        x.catalog.context.missionId = "foreign";
      },
      (x: AuthoringPage) => {
        x.catalog.targets.next_after = "target_one";
      },
      (x: AuthoringPage) => {
        x.preview = { ...previewFixture(), command_id: "other" };
      },
    ]) {
      const malformed = structuredClone(p);
      change(malformed);
      expect(() => readAuthoringPage(malformed, p.catalog.context)).toThrow();
    }
    const preview = previewFixture();
    expect(() =>
      readOperation(
        {
          status: "completed",
          receipt: {
            request_id: "foreign",
            actor_id: preview.actor_id,
            requested_at: preview.requested_at,
            lifecycle_state: "validated",
          },
        },
        preview,
      ),
    ).toThrow();
  });
});
const producer = producerFixture("CADENCE_COMMAND_AUTHORING_DOCUMENT", import.meta.url);
test.skipIf(!producer.available)(
  "actual producer yields the feature-owned preview or create input",
  async () => {
    const raw = jsonFixture(required(producer.read()));
    const contribution = readAuthoringContribution(raw.data, fixtureContext(raw.context));
    if (!("catalog" in contribution)) {
      const execute = vi.fn();
      const wrapper = mount(
        pageHeaderHarness("/missions/:mission_id/ops/commands/new").stage(CommandAuthoringPage),
        {
          props: {
            page: contribution,
            port: { execute, navigate: vi.fn() },
            readPort: { read: vi.fn() },
            refresh: vi.fn(),
          },
        },
      );
      expect(wrapper.find("#command-authoring-prerequisite").exists()).toBe(true);
      expect(wrapper.find("#command-authoring-form").exists()).toBe(false);
      expect(execute).not.toHaveBeenCalled();
      writeFileSync(
        required(process.env.CADENCE_COMMAND_AUTHORING_INPUT_FILE),
        JSON.stringify({ prerequisite: contribution.state }),
      );
      wrapper.unmount();
      return;
    }
    const page = readAuthoringPage(raw.data, fixtureContext(raw.context));
    const c = mountPage(page);
    let captured: unknown;
    c.execute.mockImplementation(async (_event, input) => {
      captured = input;
      return { status: "rejected", feedback: "Probe only" };
    });
    if (!page.catalog.selected_command?.supported) {
      expect(c.wrapper.find("#authoring-command-unsupported").exists()).toBe(true);
      expect(c.wrapper.find("#command-authoring-form").exists()).toBe(false);
      expect(c.execute).not.toHaveBeenCalled();
      captured = { unavailable: true };
    } else if (page.preview) {
      await c.wrapper.get("#authoring-confirm").setValue(true);
      await c.wrapper.get("#command-authoring-create").trigger("click");
    } else {
      const inputs = process.env.CADENCE_COMMAND_AUTHORING_EXACT_INPUT
        ? jsonFixture(process.env.CADENCE_COMMAND_AUTHORING_EXACT_INPUT)
        : { amount: "2" };
      for (const [name, value] of Object.entries(inputs)) {
        const raw = fixtureString(value);
        const argument = page.catalog.selected_command.arguments.find((a) => a.name === name);
        if (argument?.type === "enumerated") {
          const field = c.wrapper.get(`[data-argument-name="${name}"]`);
          const select = field.find("select");
          if (select.exists()) await select.setValue(raw);
          else await field.get(`input[value="${raw}"]`).setValue(true);
          continue;
        }
        await c.wrapper
          .get(`[data-argument-name="${name}"]`)
          .setValue(raw.startsWith('"') ? JSON.parse(raw) : raw);
      }
      await c.wrapper.get("#command-authoring-form").trigger("submit");
    }
    await flushPromises();
    expect(captured).toBeDefined();
    writeFileSync(
      required(process.env.CADENCE_COMMAND_AUTHORING_INPUT_FILE),
      JSON.stringify(captured),
    );
    c.wrapper.unmount();
  },
);

test("named priority selection sends its canonical rank into the command preview", async () => {
  const c = mountPage();
  try {
    const select = c.wrapper.get<HTMLSelectElement>("#authoring-priority");
    expect(select.element.selectedOptions[0]?.textContent).toBe("Normal (rank 3)");
    await select.setValue("1");
    expect(select.element.selectedOptions[0]?.textContent).toBe("High (rank 1)");
    await enterAndPreview(c);
    expect(c.execute).toHaveBeenCalledExactlyOnceWith("preview", containing({ priority: 1 }));
  } finally {
    c.wrapper.unmount();
  }
});

test("old and mixed argument contracts fail closed while exact wide preview text survives", () => {
  const p = pageFixture();
  p.preview = {
    ...previewFixture(),
    argument_values_json: '{"amount":18446744073709551615}',
    resolved_argument_values_json: '{"amount":18446744073709551615}',
  };
  expect(readAuthoringPage(p, p.catalog.context).preview?.resolved_argument_values_json).toContain(
    "18446744073709551615",
  );
  for (const mutate of [
    (x: unknown) => {
      fixtureRecordAt(x, "catalog").version = 1;
    },
    (x: unknown) => {
      fixtureRecordAt(x, "catalog", "selected_command", "arguments", 0).default_value = 2;
    },
    (x: unknown) => {
      fixtureRecordAt(x, "preview").argument_values = { amount: 2 };
    },
    (x: unknown) => {
      delete fixtureRecordAt(x, "preview").argument_values_json;
    },
    (x: unknown) => {
      fixtureRecordAt(x, "preview").argument_values_json = '{"amount":1,"amount":2}';
    },
  ]) {
    const x = structuredClone(p);
    mutate(x);
    expect(() => readAuthoringPage(x, p.catalog.context)).toThrow();
  }
});

test("catalog enum choices require distinct exact integer values and bounded labels", () => {
  const page = pageFixture();
  const arg = required(required(page.catalog.selected_command).arguments[0]);
  arg.type = "enumerated";
  arg.choices = [{ label: "Maximum", value_json: "18446744073709551615" }];
  expect(readAuthoringPage(page, page.catalog.context)).toEqual(page);
  for (const choices of [
    undefined,
    null,
    [],
    [{ label: "One", value_json: 1 }],
    [{ label: "One", value_json: '"1"' }],
    [{ label: "One", value_json: "1.0" }],
    [{ label: "", value_json: "1" }],
    [
      { label: "One", value_json: "1" },
      { label: "Alias", value_json: "1" },
    ],
    Array.from({ length: 1025 }, (_, i) => ({ label: String(i), value_json: String(i) })),
  ]) {
    const malformed = structuredClone(page);
    fixtureRecordAt(malformed, "catalog", "selected_command", "arguments", 0).choices = choices;
    expect(() => readAuthoringPage(malformed, page.catalog.context)).toThrow();
  }
  required(page.catalog.selected_command).supported = false;
  arg.choices = [];
  expect(readAuthoringPage(page, page.catalog.context)).toEqual(page);
});
