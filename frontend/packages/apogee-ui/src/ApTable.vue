<script setup lang="ts" generic="Row">
import { computed, onBeforeUnmount, onMounted, ref } from "vue";
import { useScrollable } from "./lib/scrollable.ts";
import { useRowWindow, type VirtualOptions } from "./lib/virtualRows.ts";

/**
 * Data table. Columns declare alignment and mono; cells render through `#cell-<key>` slots
 * (default: the row's value as text). The Name cell is the row link; never whole-row click.
 */
export type ApColumn<K extends string = string> = Readonly<{
  key: K;
  label: string;
  align?: "start" | "end";
  mono?: boolean;
  /** Visually hidden header (e.g. an actions column). */
  hiddenLabel?: boolean;
}>;

const props = defineProps<{
  columns: readonly ApColumn[];
  rows: readonly Row[];
  rowKey: (row: Row) => string;
  caption?: string | undefined;
  /** Wash + tint for problem rows. */
  rowState?: (row: Row) => "crit" | "caution" | "stale" | null | undefined;
  /**
   * Opt-in windowing for long tables (off by default): only the rows in view, plus `overscan`
   * (default 10) either side, render between spacer rows. Every row must be `rowHeight` px tall.
   * The table reports `aria-rowcount` and each row its `aria-rowindex`; a focused row stays
   * rendered, so Tab walks every row. Known limit: the browser's find-in-page (Ctrl+F) can't see
   * rows that aren't rendered; give the table a filter (Fleet's) instead.
   */
  virtual?: VirtualOptions | undefined;
  /** The element that scrolls the rows; default the nearest scrolling ancestor, else the page. */
  scroller?: HTMLElement | null | undefined;
  /**
   * The table is its own scroll box, both ways (OpsLists.md › Fleet, option A): it fills its
   * parent's height, the heading row stays at the top and the first column at the left, and a
   * row tabbed to scrolls in below the heading, never under it. Always a focusable region named
   * by `caption`. The parent gives it a bounded height.
   */
  scrollBox?: boolean | undefined;
}>();

function cellText(row: Row, key: string): string {
  if (row === null || typeof row !== "object") return "";
  const value: unknown = Reflect.get(row, key);
  return value === null || value === undefined ? "" : String(value);
}

/** A table wider than the screen scrolls sideways: keyboard reachable and named then (qa §6). */
const wrapper = ref<HTMLElement | null>(null);
const scrollable = useScrollable(wrapper);
const scrolls = computed(() => scrollable.value || props.scrollBox === true);

/** scrollBox: the heading's height is the scroll padding, so focus never lands under it. */
const head = ref<HTMLElement | null>(null);
const headHeight = ref(0);
let headObserver: ResizeObserver | null = null;
onMounted(() => {
  const el = head.value;
  if (!props.scrollBox || !el) return;
  headHeight.value = el.offsetHeight;
  if (typeof ResizeObserver === "undefined") return;
  headObserver = new ResizeObserver(() => (headHeight.value = el.offsetHeight));
  headObserver.observe(el);
});
onBeforeUnmount(() => headObserver?.disconnect());

const body = ref<HTMLElement | null>(null);
const win = useRowWindow(
  body,
  computed(() => props.rows.length),
  computed(() => props.virtual),
  computed(() => props.scroller ?? (props.scrollBox ? wrapper.value : undefined)),
  wrapper,
);
/** Before the first measurement a virtual table renders only this many rows, not all of them. */
const FIRST_PAINT = 50;
/** The rows to render, each with its 0-based index in `rows`. */
const shown = computed(() => {
  const w = props.virtual ? win.value : null;
  const start = w?.start ?? 0;
  const list = w
    ? props.rows.slice(w.start, w.end)
    : props.virtual
      ? props.rows.slice(0, FIRST_PAINT)
      : props.rows;
  return list.map((row, i) => ({ row, index: start + i }));
});

/**
 * scrollBox stickies need opaque fills (rows pass under them) and, under border-collapse, lose
 * their borders, so their rules are inset shadows. A sticky Name cell keeps its row's wash as a
 * layer over the panel fill.
 */
const STICKY_HEAD = "sticky top-0 z-[2] bg-panel shadow-[inset_0_-1px_0_var(--color-hairline)]";
const STICKY_CORNER =
  "sticky top-0 left-0 z-[3] bg-panel shadow-[inset_-1px_-1px_0_var(--color-hairline)]";
const STICKY_NAME = "sticky left-0 z-[1] bg-panel shadow-[inset_-1px_0_0_var(--color-hairline)]";
const WASH_LAYER = {
  crit: "bg-[image:linear-gradient(var(--apogee-wash-crit),var(--apogee-wash-crit))]",
  caution: "bg-[image:linear-gradient(var(--apogee-wash-caution),var(--apogee-wash-caution))]",
} as const;
function headSticky(i: number): string {
  if (!props.scrollBox) return "";
  return i === 0 ? STICKY_CORNER : STICKY_HEAD;
}
function cellSticky(row: Row, i: number): string {
  if (!props.scrollBox || i !== 0) return "";
  const state = props.rowState?.(row);
  return `${STICKY_NAME} ${state === "crit" || state === "caution" ? WASH_LAYER[state] : ""}`;
}

defineSlots<
  {
    [K in `cell-${string}`]?: (props: { row: Row }) => unknown;
  } & {
    cell?: (props: { row: Row; column: ApColumn }) => unknown;
    footer?: () => unknown;
  }
>();
</script>

<template>
  <div
    ref="wrapper"
    :class="scrollBox ? 'h-full overflow-auto' : 'overflow-x-auto'"
    :style="scrollBox && headHeight ? { scrollPaddingTop: `${headHeight}px` } : undefined"
    :tabindex="scrolls ? 0 : undefined"
    :role="scrolls ? 'region' : undefined"
    :aria-label="scrolls ? (props.caption ?? 'Table') : undefined"
  >
    <table
      class="w-full border-collapse text-md"
      :aria-rowcount="virtual ? rows.length + 1 : undefined"
    >
      <caption v-if="caption" class="sr-only">
        {{
          caption
        }}
      </caption>
      <thead ref="head">
        <tr :aria-rowindex="virtual ? 1 : undefined">
          <th
            v-for="(column, c) in columns"
            :key="column.key"
            scope="col"
            class="border-b border-hairline px-4 py-2.5 font-display text-xs font-semibold tracking-tag whitespace-nowrap text-text-4 uppercase"
            :class="[column.align === 'end' ? 'text-right' : 'text-left', headSticky(c)]"
          >
            <span :class="column.hiddenLabel ? 'sr-only' : ''">{{ column.label }}</span>
          </th>
        </tr>
      </thead>
      <tbody ref="body">
        <tr v-if="virtual && win && win.before > 0" aria-hidden="true">
          <td :colspan="columns.length" :style="{ height: `${win.before}px`, padding: 0 }" />
        </tr>
        <tr
          v-for="{ row, index } in shown"
          :key="rowKey(row)"
          :aria-rowindex="virtual ? index + 2 : undefined"
          :style="virtual ? { height: `${virtual.rowHeight}px` } : undefined"
          class="border-b border-hairline-faint last:border-b-0"
          :class="{
            'bg-[var(--apogee-wash-crit)]': rowState?.(row) === 'crit',
            'bg-[var(--apogee-wash-caution)]': rowState?.(row) === 'caution',
          }"
        >
          <td
            v-for="(column, c) in columns"
            :key="column.key"
            class="px-4 py-2.5 align-middle"
            :class="[
              column.align === 'end' ? 'text-right tabular' : 'text-left',
              column.mono ? 'font-mono whitespace-nowrap' : '',
              // Windowing needs every row at rowHeight: a narrow table scrolls sideways, never wraps.
              virtual ? 'whitespace-nowrap' : '',
              cellSticky(row, c),
            ]"
          >
            <slot :name="`cell-${column.key}`" :row="row">
              <slot name="cell" :row="row" :column="column">{{ cellText(row, column.key) }}</slot>
            </slot>
          </td>
        </tr>
        <tr v-if="virtual && win && win.after > 0" aria-hidden="true">
          <td :colspan="columns.length" :style="{ height: `${win.after}px`, padding: 0 }" />
        </tr>
      </tbody>
    </table>
    <slot name="footer" />
  </div>
</template>
