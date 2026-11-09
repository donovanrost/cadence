import { fileURLToPath } from "node:url";

// Defaults match mise.toml, dev/apogee_qa_personas.exs and docs/apogee/qa/runbook.md.
// These are public local-development values.
export const BASE_URL = process.env["BASE_URL"] ?? "http://127.0.0.1:4011";

export interface Persona {
  readonly key: PersonaKey;
  readonly email: string;
  readonly password: string;
}

export type PersonaKey = "admin" | "operator" | "second" | "orgAdmin" | "orgAdmin2";

const personaPassword = process.env["E2E_PERSONA_PASSWORD"] ?? "apogee-qa-password";

/**
 * admin: the environment administrator (platform admin mode; can mask capability gating).
 * operator / second: organization members (two-person rule needs two distinct users).
 * orgAdmin: organization_admin without platform administration.
 */
export const PERSONAS: Readonly<Record<PersonaKey, Persona>> = {
  admin: {
    key: "admin",
    email: process.env["CADENCE_ADMIN_EMAIL"] ?? "admin@example.com",
    password: process.env["CADENCE_ADMIN_PASSWORD"] ?? "change-me",
  },
  operator: { key: "operator", email: "qa-operator@example.com", password: personaPassword },
  second: { key: "second", email: "qa-second@example.com", password: personaPassword },
  orgAdmin: { key: "orgAdmin", email: "qa-org-admin@example.com", password: personaPassword },
  /** A second organization admin, for approvals the author can't give (#38, policy versions). */
  orgAdmin2: { key: "orgAdmin2", email: "qa-org-admin-2@example.com", password: personaPassword },
};

/** Saved browser session for a persona, written by auth.setup.ts. */
export function storageStateFor(key: PersonaKey): string {
  return fileURLToPath(new URL(`../.auth/${key}.json`, import.meta.url));
}

export const ADMIN_STORAGE_STATE = storageStateFor("admin");

/**
 * Specs run as an organization admin by default. The env administrator (platform admin mode) has
 * no Reflect Orbital membership and currently can't open the org in the console (qa #15).
 */
export const DEFAULT_STORAGE_STATE = storageStateFor("orgAdmin");

// Seeded demo data (dev/reflect_orbital_demo.exs). Override when testing another dataset.
export const DEMO = {
  organizationName: process.env["E2E_ORG_NAME"] ?? "Reflect Orbital",
  organizationId: process.env["E2E_ORG_ID"] ?? "org-reflect-orbital-demo",
  organizationSlug: process.env["E2E_ORG_SLUG"] ?? "reflect-orbital",
  missionName: process.env["E2E_MISSION_NAME"] ?? "Earendil",
  missionId: process.env["E2E_MISSION_ID"] ?? "mission-earendil-demo",
  missionSlug: process.env["E2E_MISSION_SLUG"] ?? "earendil",
  spacecraftCount: Number(process.env["E2E_SPACECRAFT_COUNT"] ?? "500"),
} as const;
