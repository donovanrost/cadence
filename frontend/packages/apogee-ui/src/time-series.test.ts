import { describe, expect, it } from "vite-plus/test";
import {
  envelopePath,
  linePath,
  runs,
  scale,
  timeTicks,
  valueTicks,
  yDomain,
} from "./time-series.ts";

const p = (t: number, mean: number) => ({ t, min: mean - 1, mean, max: mean + 1 });

describe("chart scale", () => {
  it("covers data and limits in the y-domain", () => {
    const [lo, hi] = yDomain(
      [[p(0, 25), p(1, 26)]],
      [{ from: 0, to: 1, value: 20, kind: "crit", side: "low" }],
    );
    expect(lo).toBeLessThan(20);
    expect(hi).toBeGreaterThan(27);
  });

  it("maps linearly and inverts for the y axis", () => {
    const y = scale(0, 10, 100, 0);
    expect(y(0)).toBe(100);
    expect(y(10)).toBe(0);
    expect(y(5)).toBe(50);
  });

  it("breaks the line across omitted buckets", () => {
    const points = [p(0, 1), p(10, 1), p(20, 1), p(100, 1), p(110, 1)];
    expect(runs(points)).toHaveLength(2);
    const id = (n: number) => n;
    expect(linePath(points, id, id).match(/M/g)).toHaveLength(2);
    expect(envelopePath(points, id, id).match(/Z/g)).toHaveLength(2);
  });

  it("picks round UTC ticks", () => {
    const hour = 3_600_000;
    expect(timeTicks({ from: 0, to: 6 * hour })).toEqual(
      [0, 1, 2, 3, 4, 5, 6].map((h) => h * hour),
    );
    expect(timeTicks({ from: 1000, to: 6 * hour }, 3)[0]).toBe(2 * hour);
  });

  it("picks readable value ticks", () => {
    expect(valueTicks([22, 28], 3)).toEqual([22, 24, 26, 28]);
  });
});

describe("isolated buckets", () => {
  it("still draw: a mean tick and a min–max bar", () => {
    const id = (n: number) => n;
    const lone = [p(100, 5)];
    expect(linePath(lone, id, id)).toBe("M97 5H103");
    expect(envelopePath(lone, id, id)).toBe("M98.5 6H101.5V4H98.5Z");
  });
});

describe("gaps with few buckets (qa #8)", () => {
  it("splits on the bucket width where the median can't see the gap", () => {
    const t = (iso: string) => Date.parse(iso);
    const points = [
      p(t("2026-11-08T22:28:00Z"), 1),
      p(t("2026-11-08T22:54:54Z"), 2),
      p(t("2026-11-08T22:55:48Z"), 3),
    ];
    expect(runs(points)).toHaveLength(1); // median fallback: the gap is the median
    expect(runs(points, 54_000)).toHaveLength(2);
    const id = (n: number) => n;
    expect(linePath(points, id, id, 54_000).match(/M/g)).toHaveLength(2);
  });
});

describe("pointAt (crosshair readout)", () => {
  const pts = [
    { t: 0, min: 1, mean: 1, max: 1 },
    { t: 60_000, min: 2, mean: 2, max: 2 },
    { t: 300_000, min: 3, mean: 3, max: 3 },
  ];
  it("reads the nearest point, but never inside a gap", async () => {
    const { pointAt } = await import("./time-series.ts");
    expect(pointAt(pts, 50_000, 45_000)?.mean).toBe(2);
    expect(pointAt(pts, 180_000, 45_000)).toBeNull();
    expect(pointAt([], 0, 45_000)).toBeNull();
  });
});
