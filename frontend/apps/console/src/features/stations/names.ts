import type { Station } from "./api.ts";

/** ux U82: a station as people read it, 'Inuvik · INU' (no code: the name only). */
export const stationName = (s: Pick<Station, "display_name" | "code">) =>
  s.code ? `${s.display_name} · ${s.code}` : s.display_name;
