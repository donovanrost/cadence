import { containing } from "../../../test-support/matchers";
import { describe, expect, it, vi } from "vite-plus/test";
import type { HostActionReceipt, HostContext } from "./bridge";
import { createFederatedActionLifecycle } from "./bridge";

const context: HostContext = {
  scope: "mission",
  organizationId: "org-1",
  missionId: "mission-1",
  missionName: "Firebird",
  spacecraftId: null,
  spacecraftName: null,
  actor: { displayName: "Mara Vance", permissions: ["operate_mission"] },
};

describe("federated action lifecycle receipt validation", () => {
  it("rejects a successful response without a non-empty receipt identity", async () => {
    const onCompleted = vi.fn();
    const onRejected = vi.fn();
    const requery = vi.fn().mockResolvedValue(undefined);
    const navigate = vi.fn();
    const lifecycle = createFederatedActionLifecycle({
      applicationKey: "mission_catalog",
      applicationVersion: 1,
      surfaceId: "mission_applications",
      surfaceVersion: 1,
      declaredActions: ["install"],
      context,
      execute: async <_TInput, TResult>() =>
        ({ receiptId: "", completedAt: "", result: {} }) as HostActionReceipt<TResult>,
      requery,
      navigate,
      onStarted: vi.fn(),
      onCompleted,
      onRejected,
      onFinished: vi.fn(),
    });

    await lifecycle.execute("install", { key: "telemetry_decom" });

    expect(onRejected).toHaveBeenCalledWith(
      "install",
      containing({ message: "The host action returned an invalid receipt." }),
    );
    expect(onCompleted).not.toHaveBeenCalled();
    expect(requery).not.toHaveBeenCalled();
    expect(navigate).not.toHaveBeenCalled();
  });

  it("forwards the exact application and surface identity and ignores stale completions", async () => {
    const first = deferredReceipt();
    const second = deferredReceipt();
    const execute = vi.fn().mockReturnValueOnce(first.promise).mockReturnValueOnce(second.promise);
    const onStarted = vi.fn();
    const onCompleted = vi.fn();
    const onRejected = vi.fn();
    const onFinished = vi.fn();
    const requery = vi.fn().mockResolvedValue(undefined);
    const lifecycle = createFederatedActionLifecycle({
      applicationKey: "mission_catalog",
      applicationVersion: 3,
      surfaceId: "mission_applications",
      surfaceVersion: 1,
      declaredActions: ["install", "remove"],
      context,
      execute,
      requery,
      navigate: vi.fn(),
      onStarted,
      onCompleted,
      onRejected,
      onFinished,
    });

    const stale = lifecycle.execute("install", { key: "telemetry_decom" });
    const current = lifecycle.execute("remove", { key: "telemetry_decom" });
    first.resolve({ receiptId: "stale", completedAt: "2026-09-05T00:00:00.000Z", result: {} });
    await Promise.resolve();
    second.resolve({ receiptId: "current", completedAt: "2026-09-05T00:00:01.000Z", result: {} });
    await Promise.all([stale, current]);

    expect(execute).toHaveBeenNthCalledWith(1, {
      applicationKey: "mission_catalog",
      applicationVersion: 3,
      surfaceId: "mission_applications",
      surfaceVersion: 1,
      actionId: "install",
      input: { key: "telemetry_decom" },
      context,
    });
    expect(onCompleted).toHaveBeenCalledTimes(1);
    expect(onCompleted).toHaveBeenCalledWith("remove", containing({ receiptId: "current" }));
    expect(onRejected).not.toHaveBeenCalled();
    expect(requery).toHaveBeenCalledTimes(1);
    expect(onFinished).toHaveBeenCalledTimes(1);
    expect(onStarted).toHaveBeenNthCalledWith(2, "remove");
  });

  it.each(["javascript:alert(1)", "https://evil.example/steal"])(
    "does not navigate to an unsafe action receipt target: %s",
    async (href) => {
      const navigate = vi.fn();
      const requery = vi.fn().mockResolvedValue(undefined);
      const lifecycle = createFederatedActionLifecycle({
        applicationKey: "mission_catalog",
        applicationVersion: 1,
        surfaceId: "mission_applications",
        surfaceVersion: 1,
        declaredActions: ["install"],
        context,
        execute: async <_TInput, TResult>() =>
          ({
            receiptId: "receipt-unsafe",
            completedAt: "2026-09-05T00:00:00.000Z",
            result: { navigation: { href } },
          }) as HostActionReceipt<TResult>,
        requery,
        navigate,
        onStarted: vi.fn(),
        onCompleted: vi.fn(),
        onRejected: vi.fn(),
        onFinished: vi.fn(),
      });

      await lifecycle.execute("install", {});

      expect(navigate).not.toHaveBeenCalled();
      expect(requery).toHaveBeenCalledTimes(1);
    },
  );
});

function deferredReceipt() {
  let resolve!: (value: HostActionReceipt<unknown>) => void;
  const promise = new Promise<HostActionReceipt<unknown>>((resolvePromise) => {
    resolve = resolvePromise;
  });
  return { promise: promise as Promise<never>, resolve };
}
