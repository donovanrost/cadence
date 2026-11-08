import { describe, expect, it } from "vite-plus/test";
import { stripColumns } from "./stat-strip.ts";

describe("stripColumns", () => {
  it("never uses more columns than tiles", () => {
    expect(stripColumns(2)).toEqual({ small: 2, medium: 2, wide: 2 });
    expect(stripColumns(1)).toEqual({ small: 1, medium: 1, wide: 1 });
  });

  it("prefers even divisions", () => {
    expect(stripColumns(4)).toEqual({ small: 2, medium: 2, wide: 4 });
    expect(stripColumns(6)).toEqual({ small: 2, medium: 3, wide: 6 });
    expect(stripColumns(5)).toEqual({ small: 2, medium: 3, wide: 5 });
  });
});
