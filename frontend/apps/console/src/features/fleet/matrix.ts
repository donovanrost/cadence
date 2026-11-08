import type { OpState } from "@/ui";
import type { FleetSpacecraft, FleetState } from "./api.ts";

/** Fleet matrix shape, ux decision U8 (docs/apogee/ux/decisions.md). */

export const FLAT_ROW_SIZE = 50;

export type MatrixRow = Readonly<{
  key: string;
  label: string;
  /** Plane number for plane rows; null for the no-plane row and flat rows. */
  plane: number | null;
  /** One entry per column; null = empty slot. */
  cells: readonly (FleetSpacecraft | null)[];
}>;

export type MatrixLayout = Readonly<{
  mode: "planes" | "flat";
  columns: number;
  rows: readonly MatrixRow[];
}>;

const pad3 = (n: number) => String(n).padStart(3, "0");
const byScid = (a: FleetSpacecraft, b: FleetSpacecraft) => a.scid - b.scid;

function chunk<T>(items: readonly T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < items.length; i += size) out.push(items.slice(i, i + size));
  return out;
}

/** Places a plane's spacecraft by slot; unslotted or colliding ones fill the free cells after. */
function placeBySlot(members: readonly FleetSpacecraft[], columns: number) {
  const cells: (FleetSpacecraft | null)[] = Array.from({ length: columns }, () => null);
  const rest: FleetSpacecraft[] = [];
  for (const sc of [...members].sort(byScid)) {
    const index = sc.slot === null ? -1 : sc.slot - 1;
    if (index >= 0 && index < columns && cells[index] === null) cells[index] = sc;
    else rest.push(sc);
  }
  for (const sc of rest) {
    const free = cells.indexOf(null);
    if (free === -1) cells.push(sc);
    else cells[free] = sc;
  }
  return cells;
}

/**
 * Rows = planes when any spacecraft has a plane, columns = max slot (or the largest plane).
 * Spacecraft without a plane go in a trailing `—` row. No plane metadata at all: a flat grid by
 * SCID, 50 per row, labelled with the row's SCID range (`001–050`).
 */
export function layoutMatrix(fleet: readonly FleetSpacecraft[]): MatrixLayout {
  const planed = fleet.filter((sc) => sc.plane !== null);
  if (planed.length === 0) {
    const rows = chunk([...fleet].sort(byScid), FLAT_ROW_SIZE).map((members) => {
      const first = members[0]?.scid ?? 0;
      const last = members.at(-1)?.scid ?? first;
      return {
        key: `scid-${first}`,
        label: `${pad3(first)}–${pad3(last)}`,
        plane: null,
        cells: members,
      };
    });
    return { mode: "flat", columns: Math.min(FLAT_ROW_SIZE, fleet.length), rows };
  }

  const planes = new Map<number, FleetSpacecraft[]>();
  for (const sc of planed) {
    const plane = sc.plane ?? 0;
    const members = planes.get(plane) ?? [];
    members.push(sc);
    planes.set(plane, members);
  }
  const maxSlot = Math.max(0, ...planed.map((sc) => sc.slot ?? 0));
  const largest = Math.max(...[...planes.values()].map((members) => members.length));
  const columns = Math.max(maxSlot, largest);

  const rows: MatrixRow[] = [...planes.entries()]
    .sort(([a], [b]) => a - b)
    .map(([plane, members]) => ({
      key: `plane-${plane}`,
      label: `P${String(plane).padStart(2, "0")}`,
      plane,
      cells: placeBySlot(members, columns),
    }));

  const unplaned = fleet.filter((sc) => sc.plane === null).sort(byScid);
  chunk(unplaned, columns).forEach((members, index) =>
    rows.push({ key: `no-plane-${index}`, label: "—", plane: null, cells: members }),
  );
  return { mode: "planes", columns, rows };
}

/** Fleet state → Apogee state grammar. Never heard is "off" (dashed): nothing to judge yet. */
export function fleetOpState(state: FleetState): OpState {
  switch (state) {
    case "critical":
      return "crit";
    case "caution":
      return "caution";
    case "stale":
      return "stale";
    case "nominal":
      return "nominal";
    case "never_heard":
      return "off";
  }
}

export function fleetStateWord(state: FleetState): string {
  switch (state) {
    case "critical":
      return "Critical";
    case "caution":
      return "Caution";
    case "stale":
      return "Stale";
    case "nominal":
      return "Nominal";
    case "never_heard":
      return "Awaiting first contact";
  }
}

export const CELL_GAP = 2;
export const CELL_MIN = 8;
export const CELL_MAX = 16;
/** Row label column (36px) + its gap (8px). */
export const LABEL_W = 44;

/**
 * Cell size that fits `rows × columns` into the box (ux Now review, second look):
 * clamp(8px, available / count, 16px). Below 8px the matrix keeps 8px cells and scrolls.
 * `height: null` sizes by width only (the box grows with its content).
 */
export function fitCell(
  width: number,
  height: number | null,
  rows: number,
  columns: number,
): Readonly<{ cell: number; overflows: boolean }> {
  const byWidth = Math.floor((width - LABEL_W) / Math.max(columns, 1)) - CELL_GAP;
  const byHeight = height === null ? Infinity : Math.floor(height / Math.max(rows, 1)) - CELL_GAP;
  const ideal = Math.min(byWidth, byHeight, CELL_MAX);
  return { cell: Math.max(CELL_MIN, ideal), overflows: ideal < CELL_MIN };
}

/** Height the matrix rows need at the largest cell size (for the Now grid's row cap). */
export const matrixNaturalHeight = (rows: number) => rows * (CELL_MAX + CELL_GAP);

/** Space between side-by-side row blocks (U14). */
export const BLOCK_GAP = 16;

export type MatrixFit = Readonly<{ cell: number; overflows: boolean; blocks: number }>;

/**
 * U14: when height is the limit, wrap rows into side-by-side blocks (P01–P10 | P11–P20) and
 * pick the block count that gives the largest cell within 8–16px. At equal size, a layout that
 * doesn't overflow wins; otherwise fewer blocks win.
 */
export function fitMatrix(
  width: number,
  height: number | null,
  rows: number,
  columns: number,
  maxBlocks = 4,
): MatrixFit {
  let best: MatrixFit = { ...fitCell(width, height, rows, columns), blocks: 1 };
  if (height === null) return best;
  for (let blocks = 2; blocks <= Math.min(maxBlocks, rows); blocks++) {
    const blockWidth = (width - (blocks - 1) * BLOCK_GAP) / blocks;
    const fit = fitCell(blockWidth, height, Math.ceil(rows / blocks), columns);
    const fits = blockWidth >= LABEL_W + columns * (CELL_MIN + CELL_GAP);
    const better =
      fit.cell > best.cell || (fit.cell === best.cell && best.overflows && !fit.overflows);
    if (fits && better) best = { ...fit, blocks };
  }
  return best;
}

/** Splits rows into `blocks` consecutive groups of near-equal size. */
export function splitRows<T>(rows: readonly T[], blocks: number): T[][] {
  const size = Math.ceil(rows.length / Math.max(blocks, 1));
  const out: T[][] = [];
  for (let i = 0; i < rows.length; i += size) out.push(rows.slice(i, i + size));
  return out;
}
