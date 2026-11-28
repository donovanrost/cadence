import { organizationId as orgIdReader } from "@/api/index.ts";
import { afterEach, describe, expect, it, vi } from "vite-plus/test";
import { createServiceIdentity, serviceFailure } from "./services.ts";

afterEach(() => vi.unstubAllGlobals());

describe("createServiceIdentity (O6)", () => {
  it("sends mission_id only for mission_admin", async () => {
    const bodies: unknown[] = [];
    vi.stubGlobal("fetch", (_url: string, init: RequestInit) => {
      bodies.push(JSON.parse(init.body as string));
      return Promise.resolve(
        new Response(
          JSON.stringify({
            data: {
              service_identity: {
                id: "si_1",
                name: "ingest",
                capabilities: ["x"],
                mission_id: null,
              },
              api_token: "tok",
            },
          }),
          { status: 201 },
        ),
      );
    });
    await createServiceIdentity(orgIdReader("org"), {
      name: "ingest",
      scope: "mission_admin",
      missionId: "m1",
    });
    await createServiceIdentity(orgIdReader("org"), {
      name: "all",
      scope: "organization_admin",
      missionId: "m1",
    });
    expect(bodies).toEqual([
      { name: "ingest", capabilities: ["mission_admin"], mission_id: "m1" },
      { name: "all", capabilities: ["organization_admin"] },
    ]);
  });
});

describe("serviceFailure", () => {
  it("puts name / mission_id inline and says a lost reply may have issued a token", () => {
    expect(
      serviceFailure({
        kind: "invalid",
        code: "invalid_params",
        message: "x",
        details: { name: ["should be at most 120 character(s)"] },
      }),
    ).toEqual({ text: null, fields: { name: "should be at most 120 character(s)" } });
    expect(serviceFailure({ kind: "unavailable", status: 0, message: "" }).text).toContain(
      "rotate if you need one",
    );
  });
});
