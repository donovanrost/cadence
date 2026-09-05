import { describe, expect, it, vi } from "vite-plus/test";
import type { HostContext } from "./bridge";
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
      execute: async () => ({ receiptId: "", completedAt: "", result: {} }),
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
      expect.objectContaining({ message: "The host action returned an invalid receipt." }),
    );
    expect(onCompleted).not.toHaveBeenCalled();
    expect(requery).not.toHaveBeenCalled();
    expect(navigate).not.toHaveBeenCalled();
  });
});
