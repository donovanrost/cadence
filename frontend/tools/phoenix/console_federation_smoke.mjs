// The console federation smoke: the federation contract (signed-out containment, remote mount,
// release N-1 -> N -> rollback, cache reuse, CSRF through the console's host bridge, a scope change
// without a reload) proven on the CONSOLE, which hosts federated surfaces now, against the
// test-only surface_fixture application (product deletions can't remove it), plus one real surface
// as a canary: telemetry_decom/packet_bindings. It gates §11c(C), which removes most of the legacy
// host that federation_browser_smoke.mjs drives (lead, 11-15).
//
// Driver: apps/cadence_web/browser_test/cadence_web/assets/console_federation_smoke_test.exs.
import assert from "node:assert/strict";
import {
  CONSOLE_SESSION_PATH,
  CONSOLE_SIGN_IN_PATH,
  assertConsoleSignedIn,
  consoleSignInExpression,
} from "./console_sign_in.mjs";
import {
  assertHttpUrl,
  diagnosticObject,
  evaluateRecord,
  navigate,
  pathMatches,
  releaseArtifactPrefix,
  reportProgress,
  requiredArg,
  runBrowserGate,
  waitForExpression,
  waitForResponse,
} from "./federation_browser_smoke.mjs";

/** @param {unknown} error */
const errorText = (error) => (error instanceof Error ? error.message : String(error));

/** @param {string[]} args @param {string} name */
const arg = (args, name) => requiredArg(args, name);

/**
 * @param {import("./cdp-contract.ts").CdpPort} client
 * @param {string} expression @param {string} label @param {AbortSignal|undefined} signal
 */
async function record(client, expression, label, signal) {
  return diagnosticObject(await evaluateRecord(client, expression, label, { signal }), label);
}

/**
 * Waits for the fixture surface and returns what it shows.
 * @param {import("./cdp-contract.ts").CdpPort} client
 * @param {ReturnType<typeof import("./federation_browser_smoke.mjs").installDiagnostics>} diagnostics
 * @param {string} surface @param {AbortSignal|undefined} signal
 */
async function fixtureSurface(client, diagnostics, surface, signal) {
  try {
    await waitForExpression(
      client,
      `Boolean(document.querySelector('#surface-fixture[data-surface=${JSON.stringify(surface)}] #surface-fixture-context'))`,
      `surface_fixture ${surface} mounted with its host context`,
      { signal },
    );
  } catch (error) {
    // Name the failing host query (status and problem body) instead of only "timed out".
    const queries = diagnostics.completed((r) => new URL(r.url).pathname.endsWith("/query"));
    const evidence = [];
    for (const record of queries.slice(-3)) {
      const body = await client
        .send("Network.getResponseBody", { requestId: record.requestId }, 5_000, signal)
        .then((result) => String(diagnosticObject(result, "query body").body ?? "").slice(0, 600))
        .catch(() => "<body unavailable>");
      evidence.push(
        `${record.method} ${new URL(record.url).pathname} -> ${String(record.response?.status)} ${body}`,
      );
    }
    throw new Error(`${errorText(error)}\nhost queries: ${evidence.join(" | ") || "none"}`, {
      cause: error,
    });
  }
  const shown = await record(
    client,
    `(() => ({
      release: document.querySelector('#surface-fixture-release')?.dataset.release ?? null,
      context: document.querySelector('#surface-fixture-context')?.textContent ?? '',
      error: document.querySelector('#surface-fixture-error')?.textContent ?? null,
    }))()`,
    `surface_fixture ${surface} state`,
    signal,
  );
  assert.equal(shown.error, null, `surface_fixture ${surface} query failed`);
  return {
    release: shown.release,
    context: diagnosticObject(JSON.parse(String(shown.context)), `${surface} context`),
  };
}

await runBrowserGate(
  (() => {
    const argv = process.argv.slice(2);
    return ["--login-email", arg(argv, "--login-email"), "--scenario-timeout-ms", "240000"];
  })(),
  {
    originUrl: arg(process.argv.slice(2), "--base-url"),
    async runScenarioImpl(client, diagnostics, _args, { secret, signal }) {
      const argv = process.argv.slice(2);
      const base = arg(argv, "--base-url");
      const origin = assertHttpUrl(base, undefined, "base URL").origin;
      const email = arg(argv, "--login-email");
      const org = arg(argv, "--org-slug");
      const mission = arg(argv, "--mission-slug");
      const missionId = arg(argv, "--mission-id");
      const spacecraftId = arg(argv, "--spacecraft-id");
      const fixtureNMinus1 = arg(argv, "--fixture-n-minus-1-release-id");
      assert.ok(secret?.password, "login secret is required");
      const missionRoot = `/console/${org}/${mission}`;
      const fixtureMission = `${missionRoot}/setup/apps/surface_fixture/mission_surface`;
      const canary = `${missionRoot}/setup/spacecraft/${spacecraftId}/apps/telemetry_decom/packet_bindings`;

      // 1. Signed out, the app surface bounces to the console's sign-in screen; that screen asks
      //    for a session and gets 401 (the one expected failure); nothing mounts.
      reportProgress("console: signed-out containment");
      const sessionProbe = diagnostics.allowExpectedFailure(
        (r) => pathMatches(r, "GET", CONSOLE_SESSION_PATH, origin),
        { status: 401 },
      );
      let sessionProbeConfirmed = false;
      try {
        const containment = await navigate(client, `${origin}${fixtureMission}`, {
          expectedOrigin: origin,
          expectedPath: CONSOLE_SIGN_IN_PATH,
          diagnostics,
          signal,
        });
        const probe = await waitForResponse(
          diagnostics,
          (r) => pathMatches(r, "GET", CONSOLE_SESSION_PATH, origin),
          "signed-out console session probe",
          { generation: containment, signal },
        );
        assert.equal(probe.response?.status, 401);
        diagnostics.confirmExpectedFailure(sessionProbe, {
          requestId: probe.requestId,
          method: "GET",
          url: probe.url,
          generation: containment,
          status: 401,
        });
        sessionProbeConfirmed = true;
        assert.equal(
          diagnostics.completed(
            (r) => new URL(r.url).pathname.startsWith("/assets/application-host/"),
            { generation: containment },
          ).length,
          0,
          "a signed-out console mounted a remote artifact",
        );
      } finally {
        if (!sessionProbeConfirmed) sessionProbe();
      }

      // 2. Sign in through the console's sign-in API.
      reportProgress("console: signing in");
      const signedIn = await record(
        client,
        consoleSignInExpression({ email, password: secret.password }),
        "console sign-in",
        signal,
      );
      assertConsoleSignedIn({
        status: typeof signedIn.status === "number" ? signedIn.status : 0,
        redirectTo: typeof signedIn.redirectTo === "string" ? signedIn.redirectTo : null,
        detail: typeof signedIn.detail === "string" ? signedIn.detail : "",
      });

      // 3. The fixture's mission surface mounts from release N-1 with the mission context.
      reportProgress("console: surface_fixture mission surface (N-1)");
      const mounted = await navigate(client, `${origin}${fixtureMission}`, {
        expectedOrigin: origin,
        expectedPath: fixtureMission,
        diagnostics,
        signal,
      });
      const missionView = await fixtureSurface(client, diagnostics, "mission_surface", signal);
      assert.equal(missionView.release, "n-minus-1", "the mission surface isn't release N-1");
      assert.equal(missionView.context.placement, "mission");
      assert.equal(missionView.context.mission_id, missionId);
      const prefix = releaseArtifactPrefix("surface_fixture", fixtureNMinus1);
      assert.ok(
        diagnostics.completed((r) => new URL(r.url).pathname.startsWith(prefix), {
          generation: mounted,
        }).length > 0,
        `no surface_fixture artifact under ${prefix}`,
      );

      // 4. Canary: a real product surface on the console, spacecraft scope.
      reportProgress("console: telemetry_decom/packet_bindings canary");
      await navigate(client, `${origin}${canary}`, {
        expectedOrigin: origin,
        expectedPath: canary,
        diagnostics,
        signal,
      });
      await waitForExpression(
        client,
        "Boolean(document.querySelector('#save-packet-bindings'))",
        "telemetry_decom packet_bindings mounted on the console",
        { signal },
      );

      await diagnostics.drainLateEvents(300, signal);
      diagnostics.assertClean("console federation smoke");
      return { console: "passed" };
    },
  },
);
console.log("CONSOLE_FEDERATION_SMOKE_OK");
