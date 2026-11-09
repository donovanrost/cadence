import type { APIRequestContext } from "@playwright/test";
import { DEMO } from "./env.ts";

/**
 * Mission configuration helpers (contract: docs/apogee/api/changes.md). Writes need the session's
 * CSRF token. Specs stage through the API and then exercise the UI on top of it.
 */
type Json = Record<string, unknown>;
const base = `/api/console/v1/missions/${DEMO.missionId}/config`;

function isJson(value: unknown): value is Json {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

async function data(response: { json(): Promise<unknown>; status(): number }): Promise<Json> {
  const body: unknown = await response.json();
  if (!isJson(body) || !isJson(body["data"]))
    throw new Error(`config API ${response.status()}: ${JSON.stringify(body).slice(0, 300)}`);
  return body["data"];
}

async function csrf(request: APIRequestContext): Promise<string> {
  const session = await data(await request.get("/api/console/v1/session"));
  const token = session["csrf_token"];
  if (typeof token !== "string") throw new Error("session has no csrf_token");
  return token;
}

export async function configState(request: APIRequestContext): Promise<Json> {
  return data(await request.get(base));
}

/** Stages a rename of one spacecraft; returns the stage result. */
export async function stageRename(
  request: APIRequestContext,
  spacecraftId: string,
  name: string,
  summary: string,
): Promise<Json> {
  const response = await request.post(`${base}/stage`, {
    headers: { "x-csrf-token": await csrf(request) },
    data: {
      summary,
      source: "qa-e2e",
      ops: [
        {
          kind: "spacecraft",
          action: "update",
          entity_id: spacecraftId,
          changes: [{ path: "display_name", value: name }],
        },
      ],
    },
  });
  if (response.status() !== 201)
    throw new Error(`stage ${response.status()}: ${(await response.text()).slice(0, 300)}`);
  return data(response);
}

/** Discards the open change set if it only holds QA changes (never someone else's work). */
export async function discardQaChanges(request: APIRequestContext, marker: string): Promise<void> {
  const state = await configState(request);
  const set = state["change_set"];
  if (!isJson(set)) return;
  const changes = Array.isArray(set["changes"]) ? set["changes"].filter(isJson) : [];
  if (changes.length === 0) return;
  if (!changes.every((c) => typeof c["summary"] === "string" && c["summary"].includes(marker)))
    return;
  await request.post(`${base}/change-sets/${String(set["id"])}/discard`, {
    headers: { "x-csrf-token": await csrf(request) },
    data: { expected_version: set["version"] },
  });
}

/** True when the mission has staged changes that aren't QA's (so specs must not touch them). */
export async function hasForeignStagedChanges(
  request: APIRequestContext,
  marker: string,
): Promise<boolean> {
  const set = (await configState(request))["change_set"];
  if (!isJson(set)) return false;
  const changes = Array.isArray(set["changes"]) ? set["changes"].filter(isJson) : [];
  return changes.some((c) => !(typeof c["summary"] === "string" && c["summary"].includes(marker)));
}
