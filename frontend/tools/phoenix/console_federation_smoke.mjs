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
  applyReleaseTransition,
  armNextActionCsrfRejection,
  assertHttpUrl,
  assertImmutableReleaseCacheReuse,
  assertNoReleaseArtifactRequests,
  diagnosticObject,
  evaluateRecord,
  navigate,
  pathMatches,
  releaseArtifactPrefix,
  removeNewDocumentScript,
  reportProgress,
  requiredArg,
  runBrowserGate,
  waitForExpression,
  waitForResponse,
} from "./federation_browser_smoke.mjs";

/**
 * The release fixture's application key -> release id map for one generation (the coordinator's
 * transition response must equal it).
 * @param {unknown} value @param {string} label
 * @returns {Record<import("./browser-diagnostics.ts").ApplicationKey, string>}
 */
function releaseIdMap(value, label) {
  const entries = Object.entries(diagnosticObject(value, label));
  assert.ok(entries.length > 0, `${label} is empty`);
  for (const [key, id] of entries)
    assert.equal(typeof id, "string", `${label}.${key} isn't a string`);
  return /** @type {Record<import("./browser-diagnostics.ts").ApplicationKey, string>} */ (
    Object.fromEntries(entries)
  );
}

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
        .then((result) => {
          const body = diagnosticObject(result, "query body").body;
          return (typeof body === "string" ? body : JSON.stringify(body)).slice(0, 600);
        })
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
      const fixtureN = arg(argv, "--fixture-n-release-id");
      const lifecycleUrl = arg(argv, "--federation-lifecycle-url");
      const releaseIds = diagnosticObject(
        JSON.parse(arg(argv, "--release-ids-json")),
        "release ids",
      );
      const releasesN = releaseIdMap(releaseIds.n, "release ids n");
      const releasesNMinus1 = releaseIdMap(releaseIds.n_minus_1, "release ids n-1");
      assert.ok(secret?.password, "login secret is required");
      const missionRoot = `/console/${org}/${mission}`;
      const fixtureMission = `${missionRoot}/setup/apps/surface_fixture/mission_surface`;
      const canary = `${missionRoot}/setup/spacecraft/${spacecraftId}/apps/telemetry_decom/packet_bindings`;
      const actionsPath = `/api/cadence/application-host/v1/missions/${encodeURIComponent(missionId)}/actions`;

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

      // 4. Scope change without a reload, both ways: the console's router (the history API it
      //    listens to) moves to the canary, a real product surface at spacecraft scope, then back;
      //    the same document mounts each, and the fixture shows the mission context again.
      reportProgress("console: mission -> spacecraft (canary) -> mission in the same document");
      await record(
        client,
        "(() => { window.__consoleDocumentProbe = Date.now(); return { ok: true }; })()",
        "mark the document",
        signal,
      );
      await record(
        client,
        `(() => {
          history.pushState(history.state, "", ${JSON.stringify(canary)});
          dispatchEvent(new PopStateEvent("popstate", { state: history.state }));
          return { ok: true };
        })()`,
        "router navigation to the canary",
        signal,
      );
      await waitForExpression(
        client,
        "Boolean(document.querySelector('#save-packet-bindings'))",
        "telemetry_decom packet_bindings mounted on the console",
        { signal },
      );
      await record(client, "(() => { history.back(); return { ok: true }; })()", "back", signal);
      await waitForExpression(
        client,
        `location.pathname === ${JSON.stringify(fixtureMission)} && !document.querySelector('#save-packet-bindings')`,
        "router back to the fixture",
        { signal },
      );
      const returnedView = await fixtureSurface(client, diagnostics, "mission_surface", signal);
      assert.equal(returnedView.context.placement, "mission");
      assert.equal(returnedView.context.mission_id, missionId);
      assert.equal(returnedView.context.spacecraft_id, null);
      const sameDocument = await record(
        client,
        "({ marked: typeof window.__consoleDocumentProbe === 'number' })",
        "document survived the scope changes",
        signal,
      );
      assert.equal(sameDocument.marked, true, "a scope change reloaded the document");

      // 5. Release N-1 -> N: the next load serves N and nothing of N-1.
      reportProgress("console: promoting release generation N");
      await applyReleaseTransition(`${lifecycleUrl}/`, "promote", releasesN);
      const promoted = await navigate(client, `${origin}${fixtureMission}`, {
        expectedOrigin: origin,
        expectedPath: fixtureMission,
        diagnostics,
        signal,
      });
      const promotedView = await fixtureSurface(client, diagnostics, "mission_surface", signal);
      assert.equal(promotedView.release, "n", "the promoted surface isn't release N");
      assert.ok(
        diagnostics.completed(
          (r) =>
            new URL(r.url).pathname.startsWith(releaseArtifactPrefix("surface_fixture", fixtureN)),
          { generation: promoted },
        ).length > 0,
        "release N's artifacts weren't loaded",
      );
      assertNoReleaseArtifactRequests(
        diagnostics.completed(() => true, { generation: promoted }),
        [{ applicationKey: "surface_fixture", releaseId: fixtureNMinus1 }],
        "generation N load",
      );

      // 6. Rollback to N-1: served again, from Chrome's immutable cache.
      reportProgress("console: rolling back to generation N-1");
      await applyReleaseTransition(`${lifecycleUrl}/`, "rollback", releasesNMinus1);
      const rolledBack = await navigate(client, `${origin}${fixtureMission}`, {
        expectedOrigin: origin,
        expectedPath: fixtureMission,
        diagnostics,
        signal,
      });
      const rolledBackView = await fixtureSurface(client, diagnostics, "mission_surface", signal);
      assert.equal(
        rolledBackView.release,
        "n-minus-1",
        "the rolled-back surface isn't release N-1",
      );
      assertNoReleaseArtifactRequests(
        diagnostics.completed(() => true, { generation: rolledBack }),
        [{ applicationKey: "surface_fixture", releaseId: fixtureN }],
        "generation N-1 rollback",
      );
      assertImmutableReleaseCacheReuse(
        diagnostics.completed(() => true, { generation: rolledBack }),
        [{ applicationKey: "surface_fixture", releaseId: fixtureNMinus1 }],
        "generation N-1 rollback",
      );

      // 7. CSRF through the console's host bridge: a rejected token stops the action once, with no
      //    replay; the next click succeeds.
      reportProgress("console: CSRF rejection through the host bridge");
      const csrfScript = await armNextActionCsrfRejection(client, signal);
      const csrfFailure = diagnostics.allowExpectedFailure(
        (r) => pathMatches(r, "POST", actionsPath, origin),
        { status: 403 },
      );
      let csrfConfirmed = false;
      try {
        const csrfGeneration = await navigate(client, `${origin}${fixtureMission}`, {
          expectedOrigin: origin,
          expectedPath: fixtureMission,
          diagnostics,
          signal,
        });
        await fixtureSurface(client, diagnostics, "mission_surface", signal);
        const startedAt = Date.now();
        await record(
          client,
          "(() => { document.querySelector('#surface-fixture-record').click(); return { ok: true }; })()",
          "record (rejected CSRF)",
          signal,
        );
        const rejected = await waitForResponse(
          diagnostics,
          (r) => pathMatches(r, "POST", actionsPath, origin) && r.startedAtMs >= startedAt,
          "rejected action",
          { generation: csrfGeneration, signal },
        );
        assert.equal(rejected.response?.status, 403, "the CSRF rejection didn't stop the action");
        diagnostics.confirmExpectedFailure(csrfFailure, {
          requestId: rejected.requestId,
          method: "POST",
          url: rejected.url,
          generation: csrfGeneration,
          status: 403,
        });
        csrfConfirmed = true;
        await removeNewDocumentScript(client, csrfScript, signal);
        await waitForExpression(
          client,
          "Boolean(document.querySelector('#surface-fixture-action-error'))",
          "the rejected action is reported",
          { signal },
        );
        await record(
          client,
          "(() => { document.querySelector('#surface-fixture-record').click(); return { ok: true }; })()",
          "record (valid CSRF)",
          signal,
        );
        await waitForExpression(
          client,
          "Boolean(document.querySelector('#surface-fixture-receipt'))",
          "the second action succeeds",
          { signal },
        );
        assert.equal(
          diagnostics.completed((r) => pathMatches(r, "POST", actionsPath, origin), {
            generation: csrfGeneration,
          }).length,
          2,
          "the rejected action was replayed",
        );
      } finally {
        if (!csrfConfirmed) csrfFailure();
      }

      await diagnostics.drainLateEvents(300, signal);
      diagnostics.assertClean("console federation smoke");
      return { console: "passed" };
    },
  },
);
console.log("CONSOLE_FEDERATION_SMOKE_OK");
