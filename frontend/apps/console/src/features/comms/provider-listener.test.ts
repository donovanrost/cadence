import { describe, expect, it } from "vite-plus/test";
import type { ApiError } from "@/api";
import { STOPS_SHARING } from "./listener.ts";
import {
  effectiveListener,
  listenerOptions,
  stageListenerRefusal,
  stopsSharing,
  storedListener,
} from "./provider-listener.ts";

/** A refused stage in changes.md's shape: `invalid_op` with the op's field errors. */
const refused = (errors: unknown[]): ApiError => ({
  kind: "invalid",
  code: "invalid_op",
  message: "A staged change is invalid.",
  details: { index: 0, errors },
});

describe("provider-managed Listener (#202)", () => {
  it("offers the schema's two choices in its words", () => {
    expect(listenerOptions).toEqual([
      { value: "own", label: "Own listener for each pass" },
      { value: "shared", label: "Shared, routed by SCID" },
    ]);
  });

  it("reads a missing or unknown stored choice as Own", () => {
    expect(storedListener({})).toBe("own");
    expect(storedListener({ configuration: { host: "gs" } })).toBe("own");
    expect(storedListener({ configuration: { listener: "own" } })).toBe("own");
    expect(storedListener({ configuration: { listener: "shared" } })).toBe("shared");
  });

  it("shares only while the delivery listens for downlink", () => {
    expect(effectiveListener("shared", true)).toBe("shared");
    expect(effectiveListener("shared", false)).toBe("own");
  });

  it("says a stored Shared will stop sharing only when the choice is hidden", () => {
    const sharing = { configuration: { listener: "shared" } };
    expect(stopsSharing(sharing, false)).toBe(STOPS_SHARING);
    expect(stopsSharing(sharing, true)).toBeNull();
    expect(stopsSharing(sharing, null)).toBeNull();
    expect(stopsSharing({}, false)).toBeNull();
  });

  it("words a coded Listener refusal, and keeps the server's sentence for an unknown code", () => {
    expect(
      stageListenerRefusal(
        refused([
          {
            path: "configuration.listener",
            code: "shared_listener_requires_mtls",
            message: "Sharing across provider bindings needs mutual TLS.",
          },
        ]),
      ),
    ).toBe(
      "Another transport already listens on this endpoint without mutual TLS. Sharing it across providers needs mutual TLS.",
    );
    expect(
      stageListenerRefusal(
        refused([
          { path: "configuration.listener", code: "something_new", message: "As written." },
        ]),
      ),
    ).toBe("As written.");
  });

  it("ignores refusals on other fields and other errors", () => {
    expect(
      stageListenerRefusal(refused([{ path: "configuration.port", message: "Port in use." }])),
    ).toBeNull();
    expect(stageListenerRefusal({ kind: "not_found", code: "x", message: "" })).toBeNull();
  });
});
