/**
 * Column counts for a tile strip of `tiles` tiles at each breakpoint: never more columns than
 * tiles, and prefer a count that divides the tiles evenly so no blank hairline cells remain.
 */
export function stripColumns(tiles: number): { small: number; medium: number; wide: number } {
  const n = Math.max(1, Math.floor(tiles));
  const fit = (max: number) => {
    if (n <= max) return n;
    for (let c = max; c > 1; c -= 1) if (n % c === 0) return c;
    return max;
  };
  return { small: fit(2), medium: fit(3), wide: n };
}
