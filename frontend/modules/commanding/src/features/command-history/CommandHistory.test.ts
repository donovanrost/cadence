import { mount, flushPromises } from "@vue/test-utils";
import { test, expect, vi } from "vite-plus/test";
import CommandHistory from "./CommandHistory.vue";
import { fixture } from "./fixtures";
import { readCommandHistory } from "./contracts";
import { commandHistoryHref, readHistoryQuery } from "./query";
import { commandHistoryContribution } from "./contribution";
const context = { organizationId: "org-a", missionId: "mission-a", resourceId: "request-a" };
function setup(model = fixture()) {
  const port = { navigate: vi.fn() },
    refresh = vi.fn(async () => {});
  const w = mount(CommandHistory, {
    props: { model: readCommandHistory(model, context), context, port, refresh },
  });
  return { w, port, refresh };
}
test("typed contribution renders exact selected evidence without a numeric round trip", () => {
  const model = fixture();
  expect(commandHistoryContribution.navigation).toBe(true);
  expect("actions" in commandHistoryContribution).toBe(false);
  expect(commandHistoryContribution.read(model, context)).toEqual({ model, context });
  const { w } = setup(model);
  try {
    expect(w.get("#command-history-raw-value").text()).toBe("18446744073709551615");
    expect(w.get("#command-history-engineering-value").text()).toBe(
      '{"counter":18446744073709551615}',
    );
    expect(w.get("[data-selected-release]").attributes("data-selected-release")).toBe("release-a");
    expect(w.get("[data-selected-verifier]").attributes("data-selected-verifier")).toBe(
      "verifier-a",
    );
    expect(w.find("form").exists()).toBe(false);
    const ids = w.findAll("[id]").map((e) => e.attributes("id"));
    expect(new Set(ids).size).toBe(ids.length);
  } finally {
    w.unmount();
  }
});
test("release selection clears incompatible cursors and verifier selection; native modifier click survives", async () => {
  const { w, port } = setup();
  try {
    const anchor = w.get("[data-history-select-release]");
    await anchor.trigger("click", { ctrlKey: true });
    expect(port.navigate).not.toHaveBeenCalled();
    await anchor.trigger("click");
    expect(port.navigate).toHaveBeenCalledExactlyOnceWith(
      "/missions/mission-a/ops/commands/requests/request-a/history?release=release-a",
    );
    await anchor.trigger("click");
    expect(port.navigate).toHaveBeenCalledOnce();
  } finally {
    w.unmount();
  }
});
test("paging keeps selections even when neither selected record is on the visible page", async () => {
  const model = fixture();
  model.releases.entries = Array.from({ length: 25 }, (_, n) => ({
    ...model.selection.release!,
    id: `release-${n}`,
  }));
  model.releases.next_after = "release-24";
  const { w, port } = setup(model);
  try {
    expect(w.get("[data-selected-release]").attributes("data-selected-release")).toBe("release-a");
    await w.get("#command-history-releases-next").trigger("click");
    const query = new URL(port.navigate.mock.calls[0]![0], "https://cadence.test").searchParams;
    expect(Object.fromEntries(query)).toEqual({
      release: "release-a",
      release_after: "release-24",
      verifier: "verifier-a",
    });
  } finally {
    w.unmount();
  }
});
test("refresh waits for the host and recovers its pending control after failure", async () => {
  const { w, refresh } = setup();
  try {
    refresh.mockRejectedValueOnce(Error("Host unavailable"));
    await w.get("#command-history-refresh").trigger("click");
    await flushPromises();
    expect(refresh).toHaveBeenCalledOnce();
    expect(w.get("#command-history-refresh").attributes("disabled")).toBeUndefined();
  } finally {
    w.unmount();
  }
});
test.each(["unavailable", "unmatched", "not_selected"] as const)(
  "%s evidence stays distinct from an empty ledger",
  (status) => {
    const model = fixture();
    model.evidence = { status, record: null };
    if (status === "unmatched") {
      model.selection.verifier!.matched_record_id = null;
      model.selection.verifier!.matched_record_kind = null;
    }
    if (status === "not_selected") {
      model.query.verifier = "";
      model.selection.verifier = null;
    }
    const { w } = setup(model);
    try {
      expect(w.find("[data-command-evidence]").exists()).toBe(false);
      expect(w.findAll("[data-history-verifier]")).toHaveLength(1);
      expect(w.get("#command-history-evidence").text()).toContain(
        status === "unavailable"
          ? "unavailable"
          : status === "unmatched"
            ? "no recorded match"
            : "Select a verifier",
      );
    } finally {
      w.unmount();
    }
  },
);
test("query identities preserve Unicode and delimiters through canonical native URLs", () => {
  const href = commandHistoryHref("mission é", "request:a", { release: "release/&?é" });
  const url = new URL(href, "https://cadence.test");
  expect(url.pathname).toBe("/missions/mission%20%C3%A9/ops/commands/requests/request%3Aa/history");
  expect(url.searchParams.get("release")).toBe("release/&?é");
  for (const q of [
    { release: null },
    { verifier: "v" },
    { release: "x\n" },
    { release: "\ud800" },
    { other: "x" },
  ])
    expect(() => readHistoryQuery(q)).toThrow();
  expect(() => commandHistoryHref("..", "request")).toThrow();
});
test.each([
  (m: any) => {
    m.version = 2;
  },
  (m: any) => {
    m.request.id = "foreign";
  },
  (m: any) => {
    m.organization_id = "foreign";
  },
  (m: any) => {
    m.selection.release = { ...m.selection.release, id: "foreign" };
  },
  (m: any) => {
    m.verifiers.entries[0].release_attempt_id = "foreign";
  },
  (m: any) => {
    m.releases.entries[0].request_id = "foreign";
  },
  (m: any) => {
    m.evidence.record.id = "other-sample";
  },
  (m: any) => {
    m.evidence.record.mission_id = "foreign";
  },
  (m: any) => {
    m.evidence.record.provenance = { secret: true };
  },
  (m: any) => {
    m.evidence.record.raw_value_json = "invalid JSON";
  },
  (m: any) => {
    m.evidence.record.raw_value_json = 18446744073709551615;
  },
  (m: any) => {
    m.evidence.record.raw_value_json = JSON.stringify("x".repeat(65536));
  },
  (m: any) => {
    m.releases.next_after = "not-the-last-row";
  },
  (m: any) => {
    m.verifiers.entries = Array(26).fill(m.verifiers.entries[0]);
  },
  (m: any) => {
    m.selection.verifier = { ...m.selection.verifier, state: "failed" };
  },
  (m: any) => {
    m.evidence = { status: "not_selected", record: null };
  },
])("rejects inconsistent or unbounded producer data %#", (mutate) => {
  const m = fixture();
  mutate(m);
  expect(() => readCommandHistory(m, context)).toThrow();
});

test("uncertain release remains selectable with exact identity and no successful completion", () => {
  const model = fixture();
  model.request.state = "queued";
  model.request.verification_state = null;
  model.selection.release!.state = "release_uncertain";
  model.selection.release!.released_at = null;
  model.selection.release!.verification_state = null;
  model.selection.verifier = null;
  model.query.verifier = "";
  model.verifiers.entries = [];
  model.evidence = { status: "not_selected", record: null };
  const { w } = setup(model);
  try {
    expect(w.get("#command-history-selected-uncertain").text()).toContain(
      "may have been transmitted",
    );
    expect(w.get("[data-history-release-uncertain]").text()).toContain(
      "no successful release completion",
    );
    expect(w.get("[data-selected-release]").attributes("data-selected-release")).toBe("release-a");
    expect(w.find("[data-history-verifier]").exists()).toBe(false);
  } finally {
    w.unmount();
  }
});
