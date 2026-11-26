import { describe, expect, it } from "vite-plus/test";
import type { ApiError } from "@/api";
import { checksRefusal } from "./checkRefusals.ts";

/** #534 (mms-ux; #548/#549): a packet definition version race, retryable, nothing written. */
const taken = (details: unknown): ApiError => ({
  kind: "conflict",
  code: "packet_definition_version_taken",
  message: "server line",
  details,
});
const DETAILS = { packet_definition_id: "pd_hk", version: 3, retryable: true };

describe("packet_definition_version_taken", () => {
  it("says nothing changed and to try again, worded by the act", () => {
    expect(checksRefusal(taken(DETAILS), "apply")?.sentence).toBe(
      "Not applied: another change saved a packet definition at the same moment, so nothing changed. Try again.",
    );
    expect(checksRefusal(taken(DETAILS), "request_review")?.sentence).toBe(
      "Not sent for review: another change saved a packet definition at the same moment, so nothing changed. Try again.",
    );
    expect(checksRefusal(taken(DETAILS), "approve")?.sentence).toBe(
      "Not approved: another change saved a packet definition at the same moment, so nothing was applied and the change set stays in review. Your approval wasn't recorded. Try again.",
    );
    expect(checksRefusal(taken(DETAILS), "apply")?.changed).toBe(false);
  });

  it("keeps its details in Technical details only", () => {
    const r = checksRefusal(taken(DETAILS), "apply");
    expect(r?.technical).toBe("packet_definition_version_taken: pd_hk v3");
    expect(r?.sentence).not.toContain("pd_hk");
    expect(checksRefusal(taken(null), "apply")?.technical).toBe("packet_definition_version_taken");
  });
});
