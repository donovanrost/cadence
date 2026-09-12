import { jsonFixture, fixtureContext } from "../../../../../test-support/json-fixture";
import { required } from "../../../../../test-support/required";
import { mount, flushPromises } from "@vue/test-utils";
import { test, expect, vi } from "vite-plus/test";
import { writeFileSync } from "node:fs";
import QueueSubmission from "./QueueSubmission.vue";
import { fixture, completed } from "./fixtures.test-support";
import { readQueuePage } from "./contracts";
function mountPage(page = fixture()) {
  const execute = vi.fn(async (_event: string, _input: Record<string, unknown>): Promise<unknown> =>
    completed(page),
  );
  const read = vi.fn(async (): Promise<unknown> => page);
  const wrapper = mount(QueueSubmission, {
    props: {
      page,
      port: { execute, navigate: vi.fn(), guardNavigation: vi.fn(() => vi.fn()) },
      readPort: { read },
    },
  });
  return { wrapper, execute, read };
}
test("confirmation gates one queue operation and its durable receipt", async () => {
  const page = fixture(),
    c = mountPage(page);
  try {
    await c.wrapper.get("#command-queue-form").trigger("submit");
    expect(c.execute).not.toHaveBeenCalled();
    await c.wrapper.get("#command-queue-confirm").setValue(true);
    await c.wrapper.get("#command-queue-form").trigger("submit");
    await flushPromises();
    expect(c.execute).toHaveBeenCalledExactlyOnceWith("submit", {
      expected_queue: required(page.preview).token,
    });
    expect(c.wrapper.get("#command-queue-receipt").text()).toContain("queue_saved");
    expect(c.wrapper.find("#command-queue-form").exists()).toBe(false);
  } finally {
    c.wrapper.unmount();
  }
});
test("an uncertain reply is recovered through a read without sending another action", async () => {
  const page = fixture(),
    c = mountPage(page);
  c.execute.mockRejectedValue(Error("Lost reply"));
  c.read.mockResolvedValue({ ...page, operation: completed(page) });
  try {
    await c.wrapper.get("#command-queue-confirm").setValue(true);
    await c.wrapper.get("#command-queue-form").trigger("submit");
    await flushPromises();
    expect(c.wrapper.find("#command-queue-unconfirmed").exists()).toBe(true);
    await c.wrapper.get("#command-queue-refresh").trigger("click");
    await flushPromises();
    expect(c.read).toHaveBeenCalledOnce();
    expect(c.execute).toHaveBeenCalledOnce();
    expect(c.wrapper.find("#command-queue-receipt").exists()).toBe(true);
  } finally {
    c.wrapper.unmount();
  }
});
test.each(["operation_id", "actor_id", "request_id", "approved_content_sha256"] as const)(
  "a mismatched %s cannot become a receipt",
  async (field) => {
    const page = fixture(),
      c = mountPage(page);
    const result = completed(page);
    if (result.status !== "completed") throw Error();
    result.receipt[field] = "wrong";
    c.execute.mockResolvedValue(result);
    try {
      await c.wrapper.get("#command-queue-confirm").setValue(true);
      await c.wrapper.get("#command-queue-form").trigger("submit");
      await flushPromises();
      expect(c.wrapper.find("#command-queue-unconfirmed").exists()).toBe(true);
      expect(c.wrapper.find("#command-queue-receipt").exists()).toBe(false);
      await c.wrapper.get("#command-queue-refresh").trigger("click");
      await flushPromises();
      expect(c.wrapper.find("#command-queue-unconfirmed").exists()).toBe(true);
      expect(c.execute).toHaveBeenCalledOnce();
    } finally {
      c.wrapper.unmount();
    }
  },
);
test("a fresh review token clears confirmation before queueing", async () => {
  const page = fixture(),
    c = mountPage(page),
    next = fixture();
  required(next.preview).token = "22222222-2222-4222-8222-222222222222";
  c.read.mockResolvedValue(next);
  try {
    await c.wrapper.get("#command-queue-confirm").setValue(true);
    await c.wrapper.get("#command-queue-refresh").trigger("click");
    await flushPromises();
    await c.wrapper.get("#command-queue-form").trigger("submit");
    expect(c.execute).not.toHaveBeenCalled();
  } finally {
    c.wrapper.unmount();
  }
});
test("server JSON text retains exact integers beyond JavaScript's safe range", () => {
  const page = fixture(),
    exact = '{"amount":9223372036854775807}';
  page.model.request.resolved_argument_values_json = exact;
  required(page.preview).request.resolved_argument_values_json = exact;
  const c = mountPage(readQueuePage(page, page.model.context));
  try {
    expect(c.wrapper.get("#command-queue-resolved").text()).toBe(exact);
    expect(c.wrapper.text()).toContain("Normal (rank 3)");
  } finally {
    c.wrapper.unmount();
  }
});
test("pending approval has no queue control", () => {
  const page = fixture();
  page.preview = null;
  page.model.availability = "approval_required";
  page.model.request.lifecycle_state = "approval_pending";
  const c = mountPage(readQueuePage(page, page.model.context));
  try {
    expect(c.wrapper.find("#command-queue-form").exists()).toBe(false);
    expect(c.wrapper.find("#command-queue-unavailable").exists()).toBe(true);
  } finally {
    c.wrapper.unmount();
  }
});
test.skipIf(!process.env.CADENCE_COMMAND_QUEUE_DOCUMENT)(
  "actual producer yields the feature-owned queue action or receipt",
  async () => {
    const raw = jsonFixture(required(process.env.CADENCE_COMMAND_QUEUE_DOCUMENT));
    const page = readQueuePage(raw.data, fixtureContext(raw.context)),
      c = mountPage(page);
    let captured: unknown;
    c.execute.mockImplementation(async (_event, input) => {
      captured = input;
      return { status: "rejected", feedback: "Probe only" };
    });
    try {
      if (page.operation?.status === "completed") {
        expect(c.wrapper.get("#command-queue-receipt").text()).toContain(
          page.operation.receipt.queue_id,
        );
        captured = { receipt: page.operation.receipt };
      } else if (page.preview && page.model.availability === "available") {
        await c.wrapper.get("#command-queue-confirm").setValue(true);
        await c.wrapper.get("#command-queue-form").trigger("submit");
        await flushPromises();
      } else {
        captured = { unavailable: true };
        expect(c.execute).not.toHaveBeenCalled();
      }
      expect(captured).toBeDefined();
      writeFileSync(
        required(process.env.CADENCE_COMMAND_QUEUE_INPUT_FILE),
        JSON.stringify(captured),
      );
    } finally {
      c.wrapper.unmount();
    }
  },
);
