import { producerFixture } from "../../../../../test-support/producer-fixture";
import { jsonFixture, fixtureContext } from "../../../../../test-support/json-fixture";
import { required } from "../../../../../test-support/required";
import { fixtureRecordAt } from "../../../../../test-support/json-fixture";
import { mount, flushPromises } from "@vue/test-utils";
import { test, expect, vi } from "vite-plus/test";
import { writeFileSync } from "node:fs";
import CommandReview from "./CommandReview.vue";
import { commandReviewContribution } from "./contribution";
import { commandReviewHref, readCommandReviewPage, type CommandReviewPage } from "./contracts";
import { completed, fixture } from "./fixtures.test-support";
function setup(
  page: CommandReviewPage = fixture(),
  executeFn: (action: string, input: Record<string, unknown>) => Promise<unknown> = async () =>
    completed(page),
) {
  const execute = vi.fn(executeFn);
  const port = { execute, navigate: vi.fn() },
    readPort = {
      read: vi.fn<() => Promise<unknown>>(async () => ({ ...page, operation: completed(page) })),
    };
  const w = mount(CommandReview, { props: { page, port, readPort } });
  return { w, port, readPort };
}
async function decide(w: ReturnType<typeof setup>["w"]) {
  await w.get("#command-review-choice").setValue("approved");
  await w.get("#command-review-reason").setValue("Reviewed exact target and resolved arguments");
  await w.get("#command-review-confirm").setValue(true);
  await w.get("#command-review-form").trigger("submit");
  await flushPromises();
}
test("review shows exact identities, requested and resolved arguments, criticality and durable receipt", async () => {
  const { w, port } = setup();
  try {
    expect(w.get('[data-review-field="Request ID"]').text()).toBe("request_review");
    expect(w.get('[data-review-field="Target endpoint"]').text()).toBe("endpoint_review");
    expect(w.get('[data-review-field="Command name"]').text()).toBe("Set_power");
    expect(JSON.parse(w.get("#review-resolved-arguments").text())).toEqual({
      amount: 3,
      channel: "primary",
    });
    expect(w.find("#command-review-criticality").exists()).toBe(true);
    await decide(w);
    expect(port.execute).toHaveBeenCalledExactlyOnceWith("decide", {
      decision: "approved",
      reason: "Reviewed exact target and resolved arguments",
      expected_review: "a".repeat(64),
    });
    expect(w.get("[data-review-receipt]").text()).toContain("approval_saved");
    expect(w.find("#command-review-form").exists()).toBe(false);
  } finally {
    w.unmount();
  }
});
test("unknown result recovers by read without repeating the decision", async () => {
  const execute = vi.fn(async () => {
    throw Error("Lost response");
  });
  const { w, readPort } = setup(fixture(), execute);
  try {
    await decide(w);
    expect(w.get("#command-review-operation").text()).toContain("unconfirmed");
    expect(w.find("#command-review-form").exists()).toBe(false);
    await w.get("#command-review-refresh").trigger("click");
    await flushPromises();
    expect(readPort.read).toHaveBeenCalledOnce();
    expect(execute).toHaveBeenCalledOnce();
    expect(w.get("[data-review-receipt]").text()).toContain("approval_saved");
  } finally {
    w.unmount();
  }
});
test("a missing recovered operation does not rearm an unknown decision", async () => {
  const { w, port, readPort } = setup(
    fixture(),
    vi.fn(async () => {
      throw Error("Lost");
    }),
  );
  readPort.read.mockResolvedValue(fixture());
  try {
    await decide(w);
    await w.get("#command-review-refresh").trigger("click");
    await flushPromises();
    expect(w.get("#command-review-operation").text()).toContain("unconfirmed");
    expect(w.find("#command-review-form").exists()).toBe(false);
    expect(port.execute).toHaveBeenCalledOnce();
  } finally {
    w.unmount();
  }
});
test("another actor or request receipt cannot turn an unknown outcome into success", async () => {
  for (const changed of ["actor_id", "request_id"] as const) {
    const page = fixture(),
      result = completed(page);
    if (result.status !== "completed") throw Error("fixture");
    result.receipt[changed] = "foreign";
    const { w } = setup(
      page,
      vi.fn(async () => result),
    );
    try {
      await decide(w);
      expect(w.get("#command-review-operation").text()).toContain("unconfirmed");
      expect(w.find("[data-review-receipt]").exists()).toBe(false);
    } finally {
      w.unmount();
    }
  }
});
test("read failures and changed actor preserve the consumed submission", async () => {
  const { w, readPort } = setup(
    fixture(),
    vi.fn(async () => {
      throw Error("lost");
    }),
  );
  const other = fixture();
  other.review.actor_id = "other";
  readPort.read.mockResolvedValue(other);
  try {
    await decide(w);
    await w.get("#command-review-refresh").trigger("click");
    await flushPromises();
    expect(w.find("#command-review-feedback").exists()).toBe(true);
    expect(w.get("#command-review-operation").text()).toContain("unconfirmed");
  } finally {
    w.unmount();
  }
});
test("self-review and decided requests show evidence without decision controls", () => {
  for (const value of ["self", "decided"]) {
    const page = fixture();
    page.review.can_decide = false;
    if (value === "self") page.review.request.requested_by.user_id = page.review.actor_id;
    else page.review.request.lifecycle_state = "approved";
    readCommandReviewPage(page, page.review.context);
    const { w } = setup(page);
    try {
      expect(w.find("#command-review-form").exists()).toBe(false);
      expect(w.find("#command-review-readonly").exists()).toBe(true);
    } finally {
      w.unmount();
    }
  }
});
test("a known rejection stays consumed and the saved feedback is shown", async () => {
  const { w, port } = setup(
    fixture(),
    vi.fn(async () => ({ status: "rejected", feedback: "The reviewed request changed." })),
  );
  try {
    await decide(w);
    expect(w.get("#command-review-operation").text()).toContain("changed");
    expect(w.find("#command-review-form").exists()).toBe(false);
    expect(port.execute).toHaveBeenCalledOnce();
  } finally {
    w.unmount();
  }
});
test("reason byte limit rejects before an effect and confirmation is required", async () => {
  const { w, port } = setup();
  try {
    await w.get("#command-review-form").trigger("submit");
    expect(port.execute).not.toHaveBeenCalled();
    await w.get("#command-review-choice").setValue("approved");
    await w.get("#command-review-confirm").setValue(true);
    await w.get("#command-review-reason").setValue("é".repeat(1001));
    await w.get("#command-review-form").trigger("submit");
    expect(port.execute).not.toHaveBeenCalled();
    expect(w.find("#command-review-feedback").exists()).toBe(true);
  } finally {
    w.unmount();
  }
});
test("history navigation preserves durable resource and cursor; modifier clicks remain native", async () => {
  const page = fixture();
  page.review.history.entries = Array.from({ length: 25 }, (_, i) => ({
    id: `approval-${String(i).padStart(3, "0")}`,
    decision: "rejected" as const,
    actor: { user_id: "reviewer" },
    decided_at: "2026-09-10T08:00:00Z",
    reason: null,
  }));
  page.review.history.next_after = "approval-024";
  readCommandReviewPage(page, page.review.context);
  const { w, port } = setup(page);
  try {
    const link = w.get("#review-history-next");
    expect(link.attributes("href")).toBe(
      commandReviewHref("mission-review", "request_review", "approval-024"),
    );
    await link.trigger("click", { ctrlKey: true });
    expect(port.navigate).not.toHaveBeenCalled();
    await link.trigger("click");
    expect(port.navigate).toHaveBeenCalledWith(link.attributes("href"));
  } finally {
    w.unmount();
  }
});
test("contract rejects malformed, foreign, oversized and incoherent review evidence", () => {
  expect(commandReviewContribution.actions).toEqual(["decide"]);
  for (const mutate of [
    (p: unknown) => (fixtureRecordAt(p, "review").version = 2),
    (p: unknown) => (fixtureRecordAt(p, "review", "context").resourceId = "foreign"),
    (p: unknown) => (fixtureRecordAt(p, "review").can_decide = "true"),
    (p: unknown) => (fixtureRecordAt(p, "review", "request", "requested_by").user_id = "reviewer"),
    (p: unknown) => (fixtureRecordAt(p, "review", "request").resolved_argument_values_json = "[]"),
    (p: unknown) =>
      (fixtureRecordAt(p, "review", "request").argument_values_json = JSON.stringify({
        payload: "x".repeat(140001),
      })),
    (p: unknown) => (fixtureRecordAt(p, "review").expected_review = "changed"),
    (p: unknown) => (fixtureRecordAt(p, "review", "history").next_after = "missing"),
    (p: unknown) => (fixtureRecordAt(p, "review", "request").priority = -1),
    (p: unknown) => (fixtureRecordAt(p, "review", "request").requested_at = null),
  ]) {
    const page = fixture();
    mutate(page);
    expect(() => readCommandReviewPage(page, fixture().review.context)).toThrow();
  }
});
const producer = producerFixture("CADENCE_COMMAND_REVIEW_DOCUMENT", import.meta.url);
test.skipIf(!producer.available)(
  "actual producer review mounts the feature and captures its decision input",
  async () => {
    const document = jsonFixture(producer.read());
    const page = readCommandReviewPage(document.data, fixtureContext(document.context));
    const { w, port } = setup(page);
    try {
      expect(w.get("#review-submitted-arguments").text()).toBe(
        page.review.request.argument_values_json,
      );
      expect(w.get("#review-resolved-arguments").text()).toBe(
        page.review.request.resolved_argument_values_json,
      );
      for (const [label, expected] of [
        ["Target endpoint", page.review.request.source_endpoint_ref],
        ["Model revision", page.review.request.mission_model_revision_id],
        ["Requested by", page.review.request.requested_by.user_id],
      ])
        expect(w.get(`[data-review-field="${label}"]`).text()).toBe(expected);
      await decide(w);
      expect(port.execute).toHaveBeenCalledOnce();
      if (!process.env.CADENCE_COMMAND_REVIEW_INPUT_FILE) throw Error("Missing output");
      writeFileSync(
        process.env.CADENCE_COMMAND_REVIEW_INPUT_FILE,
        JSON.stringify(required(port.execute.mock.calls[0])[1]),
      );
    } finally {
      w.unmount();
    }
  },
);

test("refreshing changed semantics clears the earlier decision and confirmation", async () => {
  const { w, port, readPort } = setup();
  const changed = fixture();
  changed.review.expected_review = "b".repeat(64);
  changed.review.request.resolved_argument_values_json = JSON.stringify(
    { amount: 9, channel: "primary" },
    null,
    2,
  );
  readPort.read.mockResolvedValue(changed);
  try {
    await w.get("#command-review-choice").setValue("approved");
    await w.get("#command-review-confirm").setValue(true);
    await w.get("#command-review-refresh").trigger("click");
    await flushPromises();
    expect(w.get<HTMLSelectElement>("#command-review-choice").element.value).toBe("");
    expect(w.get<HTMLInputElement>("#command-review-confirm").element.checked).toBe(false);
    expect(jsonFixture(w.get("#review-resolved-arguments").text()).amount).toBe(9);
    expect(w.get("#command-review-feedback").text()).toContain("confirm again");
    await w.get("#command-review-form").trigger("submit");
    expect(port.execute).not.toHaveBeenCalled();
  } finally {
    w.unmount();
  }
});
test("pending decisions guard host navigation and release the guard on disposal", async () => {
  let guard!: () => boolean, reply!: (value: unknown) => void;
  const dispose = vi.fn(),
    page: CommandReviewPage = fixture(),
    execute = vi.fn(
      () =>
        new Promise<unknown>((resolve) => {
          reply = resolve;
        }),
    );
  const w = mount(CommandReview, {
    props: {
      page,
      port: {
        execute,
        navigate: vi.fn(),
        guardNavigation: (g: () => boolean) => {
          guard = g;
          return dispose;
        },
      },
      readPort: { read: vi.fn() },
    },
  });
  expect(guard()).toBe(true);
  await decide(w);
  expect(guard()).toBe(false);
  w.unmount();
  expect(dispose).toHaveBeenCalledOnce();
  reply(completed(page));
  await flushPromises();
  expect(execute).toHaveBeenCalledOnce();
});

test("review preserves exact integer evidence without numeric display conversion", async () => {
  const p = fixture();
  const exact = '{"counter":9007199254740993,"maximum":18446744073709551615}';
  p.review.request.argument_values_json = exact;
  p.review.request.resolved_argument_values_json = exact;
  p.review.request.opcode_json = "9007199254740993";
  const admitted = readCommandReviewPage(JSON.parse(JSON.stringify(p)), p.review.context);
  const { w, port } = setup(admitted);
  try {
    expect(w.get("#review-submitted-arguments").text()).toBe(exact);
    expect(w.get("#review-resolved-arguments").text()).toBe(exact);
    expect(w.get('[data-review-field="Opcode"]').text()).toBe("9007199254740993");
    await decide(w);
    expect(port.execute).toHaveBeenCalledExactlyOnceWith("decide", {
      decision: "approved",
      reason: "Reviewed exact target and resolved arguments",
      expected_review: p.review.expected_review,
    });
  } finally {
    w.unmount();
  }
});

function rejectedReviewMutation(page: CommandReviewPage) {
  // @ts-expect-error Admitted request evidence is readonly.
  page.review.request.priority = 99;
  // @ts-expect-error The reviewed context always identifies a command request.
  page.review.context.resourceId = undefined;
}
void rejectedReviewMutation;

test("review state admission rejects objects with a matching string conversion", () => {
  const page = fixture();
  fixtureRecordAt(page, "review", "request").lifecycle_state = {
    toString: () => "approval_pending",
  };
  expect(() => readCommandReviewPage(page, page.review.context)).toThrow();
});
