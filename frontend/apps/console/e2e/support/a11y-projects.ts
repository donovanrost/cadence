import type { TestInfo } from "@playwright/test";
import type { PersonaKey } from "./env.ts";

/** qa run 2's widths: desktop 1440×900 and phone 390×844 (a11y checklist, D for 390 only). */
export const A11Y_VIEWPORTS = [
  { name: "desktop", viewport: { width: 1440, height: 900 } },
  { name: "phone", viewport: { width: 390, height: 844 } },
] as const;

/** qa run 2's roles: `admin` is an organization admin, `member` an operator without admin. */
export const A11Y_PERSONAS = [
  { name: "admin", key: "orgAdmin" },
  { name: "member", key: "operator" },
] as const satisfies readonly { name: string; key: PersonaKey }[];

export type A11yPersona = (typeof A11Y_PERSONAS)[number]["name"];

/** Which persona this a11y project signs in as, for specs whose screens differ by role. */
export function a11yPersona(info: TestInfo): A11yPersona {
  return info.project.metadata["persona"] === "member" ? "member" : "admin";
}

/** True on the 390 projects. */
export function onPhone(info: TestInfo): boolean {
  return (info.project.use.viewport?.width ?? 1440) < 768;
}
