<script setup lang="ts" generic="Row">
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

defineProps<{
  columns: readonly ApColumn[];
  rows: readonly Row[];
  rowKey: (row: Row) => string;
  caption?: string | undefined;
  /** Wash + tint for problem rows. */
  rowState?: (row: Row) => "crit" | "caution" | "stale" | null | undefined;
}>();

function cellText(row: Row, key: string): string {
  if (row === null || typeof row !== "object") return "";
  const value: unknown = Reflect.get(row, key);
  return value === null || value === undefined ? "" : String(value);
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
  <div class="overflow-x-auto">
    <table class="w-full border-collapse text-md">
      <caption v-if="caption" class="sr-only">
        {{
          caption
        }}
      </caption>
      <thead>
        <tr>
          <th
            v-for="column in columns"
            :key="column.key"
            scope="col"
            class="border-b border-hairline px-4 py-2.5 font-display text-xs font-semibold tracking-tag whitespace-nowrap text-text-4 uppercase"
            :class="column.align === 'end' ? 'text-right' : 'text-left'"
          >
            <span :class="column.hiddenLabel ? 'sr-only' : ''">{{ column.label }}</span>
          </th>
        </tr>
      </thead>
      <tbody>
        <tr
          v-for="row in rows"
          :key="rowKey(row)"
          class="border-b border-hairline-faint last:border-b-0"
          :class="{
            'bg-[var(--apogee-wash-crit)]': rowState?.(row) === 'crit',
            'bg-[var(--apogee-wash-caution)]': rowState?.(row) === 'caution',
          }"
        >
          <td
            v-for="column in columns"
            :key="column.key"
            class="px-4 py-2.5 align-middle"
            :class="[
              column.align === 'end' ? 'text-right tabular' : 'text-left',
              column.mono ? 'font-mono whitespace-nowrap' : '',
            ]"
          >
            <slot :name="`cell-${column.key}`" :row="row">
              <slot name="cell" :row="row" :column="column">{{ cellText(row, column.key) }}</slot>
            </slot>
          </td>
        </tr>
      </tbody>
    </table>
    <slot name="footer" />
  </div>
</template>
