import { describe, expect, it } from "vite-plus/test";
import { envelopePath, linePath, runs, scale, timeTicks, valueTicks, yDomain } from "./scale.ts";

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
