import type { APIRequestContext } from "@playwright/test";
import { DEMO } from "./env.ts";

/**
 * Contact-planning API helpers (contract: docs/apogee/api/scheduling.md). Specs use them to set up
 * state "from another tab" while the UI is open.
 */
type Json = Record<string, unknown>;
const base = `/api/console/v1/missions/${DEMO.missionId}`;

function isJson(value: unknown): value is Json {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

async function data(response: { json(): Promise<unknown>; status(): number }): Promise<Json> {
  const body: unknown = await response.json();
  if (!isJson(body) || !isJson(body["data"]))
    throw new Error(`planning API ${response.status()}: ${JSON.stringify(body).slice(0, 300)}`);
  return body["data"];
}

async function csrf(request: APIRequestContext): Promise<string> {
  const token = (await data(await request.get("/api/console/v1/session")))["csrf_token"];
  if (typeof token !== "string") throw new Error("session has no csrf_token");
  return token;
}

/** UTC calendar day `offset` days from now, `YYYY-MM-DD`. */
export function utcDay(offset: number): string {
  return new Date(Date.now() + offset * 86_400_000).toISOString().slice(0, 10);
}

/** The plans listed for a day (newest first, as the plan screen reads them). */
export async function plansForDay(request: APIRequestContext, day: string): Promise<Json[]> {
  const plans = (await data(await request.get(`${base}/contact-plans?day=${day}`)))["plans"];
  return Array.isArray(plans) ? plans.filter(isJson) : [];
}

/**
 * Days (today … today+horizon-1) other than `except` that hold a live draft: state `draft`, not
 * superseded. A template version supersedes every such draft, not just the one under test.
 */
export async function liveDraftDays(
  request: APIRequestContext,
  except: string,
  horizon = 8,
): Promise<string[]> {
  const days = Array.from({ length: horizon }, (_, i) => utcDay(i)).filter((d) => d !== except);
  const live = await Promise.all(
    days.map(async (day) =>
      (await plansForDay(request, day)).some((p) => p["state"] === "draft" && !p["superseded"])
        ? day
        : null,
    ),
  );
  return live.filter((day): day is string => day !== null);
}

/**
 * Saves a new version of the contact-rule template that applies to `spacecraftName`, changing only
 * its rationale. Every draft that took up the template's requirements becomes superseded
 * (`template_changed`). Permanent: adds a template version.
 */
export async function bumpTemplate(
  request: APIRequestContext,
  spacecraftName: string,
  note: string,
): Promise<number> {
  const list = (await data(await request.get(`${base}/contact-planning/templates`)))["templates"];
  const template = (Array.isArray(list) ? list.filter(isJson) : []).find(
    (t) => t["applies_to"] === spacecraftName,
  );
  if (!template) throw new Error(`no contact-rule template applies to ${spacecraftName}`);
  const url = `${base}/contact-planning/templates/${String(template["id"])}`;
  const current = await data(await request.get(url));
  const document = structuredClone(current["document"]) as { requirement: Json };
  document.requirement["rationale"] = note;
  const response = await request.post(url, {
    headers: { "x-csrf-token": await csrf(request) },
    data: { document, expected_version: current["version"] },
  });
  return response.status();
}
