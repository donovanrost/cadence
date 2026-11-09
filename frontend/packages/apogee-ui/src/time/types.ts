/** A mission time offered first in the picker (from the spacecraft/mission in context). */
export type TimePreset = Readonly<{
  id: string;
  label: string;
  at: number;
  sub?: string | undefined;
}>;

/** A range preset for ApTimeRange (Last pass, 6 orbits, Around alarm, 24h…). */
export type RangePreset = Readonly<{ id: string; label: string; from: number; to: number }>;

export type TimeRange = Readonly<{ from: number; to: number }>;

/** Context drawn on the range track: umbra, passes, an alarm instant. */
export type TrackBand = Readonly<{ from: number; to: number; kind: "umbra" | "pass" | "alarm" }>;
