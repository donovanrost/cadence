import { defineComponent, h } from "vue";
import { mount, flushPromises } from "@vue/test-utils";
import { expect, test, vi } from "vite-plus/test";
import { useFormWorkflow } from "./useFormWorkflow";
import { validationResult } from "./validation-receipt";
import { FormActionFailure, type FormPort } from "./form-workflow.contracts";
const input = (name = "A") => ({ ground_station: { display_name: name } });
const valid = { result: { valid: true } };
const saved = { result: { navigation: { href: "/missions/mission-1/comms/ground-stations/a" } } };
function harness(execute: FormPort["execute"]) {
  const port = { execute, navigate: vi.fn() };
  const context = { missionId: "mission-1" };
  let api!: ReturnType<typeof useFormWorkflow>;
  const wrapper = mount(
    defineComponent({
      setup() {
        api = useFormWorkflow(
          () => port,
          () => context,
          validationResult,
        );
        return () => h("div");
      },
    }),
  );
  return {
    wrapper,
    port,
    get api() {
      return api;
    },
  };
}
test("validation is serial, coalesces newer drafts and ignores the obsolete result", async () => {
  let finish!: (value: unknown) => void;
  const execute = vi
    .fn()
    .mockReturnValueOnce(
      new Promise((resolve) => {
        finish = resolve;
      }),
    )
    .mockResolvedValue(valid);
  const h = harness(execute);
  try {
    h.api.validate(input("A"));
    h.api.validate(input("B"));
    h.api.validate(input("C"));
    expect(execute).toHaveBeenCalledTimes(1);
    expect(h.api.feedback.value.canSubmit).toBe(false);
    finish(valid);
    await flushPromises();
    expect(execute.mock.calls.map((call) => call[1])).toEqual([input("A"), input("C")]);
    expect(h.api.feedback.value.canSubmit).toBe(true);
  } finally {
    h.wrapper.unmount();
  }
});
test("invalid or failed validation stays recoverable without authorizing a save", async () => {
  const execute = vi
    .fn()
    .mockRejectedValueOnce(new Error("private failure"))
    .mockResolvedValueOnce({ result: { valid: false } })
    .mockResolvedValue(valid);
  const h = harness(execute);
  try {
    h.api.validate(input());
    await flushPromises();
    expect(h.api.feedback.value.canSubmit).toBe(false);
    expect(h.api.feedback.value.message).not.toContain("private");
    expect(h.api.feedback.value.canRevalidate).toBe(true);
    h.api.validate(input());
    await flushPromises();
    expect(h.api.feedback.value.canSubmit).toBe(false);
    h.api.validate(input());
    await flushPromises();
    expect(h.api.feedback.value.canSubmit).toBe(true);
  } finally {
    h.wrapper.unmount();
  }
});
test("save requires the exact accepted snapshot and never queues an implicit save", async () => {
  const execute = vi.fn().mockResolvedValue(valid);
  const h = harness(execute);
  try {
    h.api.validate(input());
    await flushPromises();
    await h.api.save(input("B"));
    await flushPromises();
    expect(execute.mock.calls.every((call) => call[0] === "validate")).toBe(true);
    expect(execute.mock.calls.at(-1)?.[1]).toEqual(input("B"));
  } finally {
    h.wrapper.unmount();
  }
});
test("an in-flight save disables edits and duplicate submission, then navigates once", async () => {
  let finish!: (value: unknown) => void;
  const execute = vi
    .fn()
    .mockResolvedValueOnce(valid)
    .mockReturnValue(
      new Promise((resolve) => {
        finish = resolve;
      }),
    );
  const h = harness(execute);
  try {
    h.api.validate(input());
    await flushPromises();
    const saving = h.api.save(input());
    h.api.validate(input("ignored"));
    await h.api.save(input());
    expect(h.api.saving.value).toBe(true);
    expect(execute).toHaveBeenCalledTimes(2);
    finish(saved);
    await saving;
    expect(h.port.navigate).toHaveBeenCalledExactlyOnceWith(saved.result.navigation.href);
    await h.api.save(input());
    expect(execute).toHaveBeenCalledTimes(2);
  } finally {
    h.wrapper.unmount();
  }
});
test.each(["validate", "save"] as const)(
  "unmount invalidates pending %s replies and queued drafts",
  async (action) => {
    let finish!: (value: unknown) => void;
    const pending = new Promise((resolve) => {
      finish = resolve;
    });
    const execute = vi
      .fn()
      .mockImplementation((kind) => (kind === action ? pending : Promise.resolve(valid)));
    const h = harness(execute);
    h.api.validate(input());
    if (action === "save") {
      await flushPromises();
      void h.api.save(input());
    } else h.api.validate(input("B"));
    h.wrapper.unmount();
    finish(action === "save" ? saved : valid);
    await flushPromises();
    expect(h.port.navigate).not.toHaveBeenCalled();
    expect(execute).toHaveBeenCalledTimes(action === "save" ? 2 : 1);
  },
);
test("known rejections preserve retry, while unknown save outcomes prevent duplicate creation", async () => {
  for (const outcome of ["rejected", "unknown"] as const) {
    const execute = vi
      .fn()
      .mockResolvedValueOnce(valid)
      .mockRejectedValue(new FormActionFailure(outcome));
    const h = harness(execute);
    try {
      h.api.validate(input());
      await flushPromises();
      await h.api.save(input());
      expect(h.api.feedback.value.canSubmit).toBe(outcome === "rejected");
      expect(h.port.navigate).not.toHaveBeenCalled();
      if (outcome === "unknown") {
        h.api.validate(input());
        await h.api.save(input());
        expect(execute).toHaveBeenCalledTimes(2);
      }
    } finally {
      h.wrapper.unmount();
    }
  }
});
test.each([null, { result: {} }, { result: { navigation: { href: "/missions/other/comms" } } }])(
  "successful but unusable receipts cannot cause a second save: %j",
  async (receipt) => {
    const execute = vi.fn().mockResolvedValueOnce(valid).mockResolvedValue(receipt);
    const h = harness(execute);
    try {
      h.api.validate(input());
      await flushPromises();
      await h.api.save(input());
      expect(h.port.navigate).not.toHaveBeenCalled();
      expect(h.api.feedback.value.canSubmit).toBe(false);
      await h.api.save(input());
      expect(execute).toHaveBeenCalledTimes(2);
    } finally {
      h.wrapper.unmount();
    }
  },
);
