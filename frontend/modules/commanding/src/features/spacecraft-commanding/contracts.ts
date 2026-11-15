export type SpacecraftCommandingProps = { mission_id?: string; spacecraft_id?: string };
export const identifier = (v: unknown): v is string =>
  typeof v === "string" && v.length <= 120 && /^[A-Za-z0-9][A-Za-z0-9_.:-]*$/.test(v);
/**
 * The spacecraft's legacy commanding URL. §11c B5: it redirects to the spacecraft's console Setup
 * page; the in-host commanding panel that read this route's document is gone.
 */
export function spacecraftCommandingHref(mission: unknown, spacecraft: unknown): string {
  if (!identifier(mission) || !identifier(spacecraft)) throw Error("Invalid spacecraft identity");
  return `/missions/${encodeURIComponent(mission)}/spacecraft/${encodeURIComponent(spacecraft)}/commanding`;
}
