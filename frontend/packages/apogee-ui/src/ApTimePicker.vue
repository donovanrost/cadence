<script setup lang="ts">
import { computed, ref } from "vue";
import ApButton from "./ApButton.vue";
import ApCallout from "./ApCallout.vue";
import ApKbd from "./ApKbd.vue";
import { useNow } from "./lib/clock.ts";
import { formatAbsolute, formatDayTime, formatMet, formatRelative } from "./lib/format.ts";
import TimeCalendar from "./time/TimeCalendar.vue";
import TimeEntry from "./time/TimeEntry.vue";
import TimePresets from "./time/TimePresets.vue";
import TimeSpinners from "./time/TimeSpinners.vue";
import type { TimePreset } from "./time/types.ts";

/**
 * Single UTC time, to the second (board TimePicker A). Mission presets come first and are
 * supplied by the caller from real context; the picker never invents AOS or umbra times.
 * `warn` lets the caller flag a time (umbra, no pass) with a crit callout before it's set.
 */
const props = withDefaults(
  defineProps<{
    label: string;
    presets?: readonly TimePreset[] | undefined;
    /** `YYYY-MM-DD` days ticked in the calendar, e.g. queued uplinks. */
    markedDays?: readonly string[] | undefined;
    markedLabel?: string | undefined;
    /** Mission epoch (ms). MET appears only when the mission defines one (U7). */
    metEpoch?: number | null | undefined;
    warn?: ((at: number) => string | null) | undefined;
    /** Release-style pickers: a time in the past is flagged (caution) with `pastMessage`. */
    future?: boolean | undefined;
    pastMessage?: string | undefined;
    placeholder?: string | undefined;
  }>(),
  {
    presets: () => [],
    markedDays: () => [],
    markedLabel: "Queued uplinks",
    metEpoch: null,
    placeholder: "Pick a time",
    future: false,
    pastMessage: "In the past.",
  },
);
const model = defineModel<number | null>({ required: true });

const now = useNow();
const dialog = ref<HTMLDialogElement | null>(null);
const draft = ref(model.value ?? now.value.getTime());
const preset = ref<string | null>(null);
const marked = computed(() => new Set(props.markedDays));
const warning = computed(() => props.warn?.(draft.value) ?? null);
const past = computed(() => props.future && draft.value < now.value.getTime() - 1_000);
const id = `ap-tp-${Math.random().toString(36).slice(2, 9)}`;

function open() {
  draft.value = model.value ?? now.value.getTime();
  preset.value = null;
  dialog.value?.showModal();
}
function setDraft(at: number, presetId: string | null = null) {
  draft.value = at;
  preset.value = presetId;
}
function commit() {
  model.value = draft.value;
  dialog.value?.close();
}
</script>

<template>
  <div class="flex flex-col gap-1.5">
    <span :id="`${id}-label`" class="ap-label">{{ label }}</span>
    <button
      type="button"
      :aria-labelledby="`${id}-label ${id}-value`"
      aria-haspopup="dialog"
      class="flex h-11 cursor-pointer items-center gap-3 border border-line bg-well px-3 text-left hover:border-text-4"
      @click="open"
    >
      <svg
        aria-hidden="true"
        width="14"
        height="14"
        viewBox="0 0 24 24"
        fill="none"
        stroke="currentColor"
        stroke-width="2"
        class="text-text-4"
      >
        <circle cx="12" cy="12" r="9" />
        <path d="M12 7v5l3 2" />
      </svg>
      <span
        :id="`${id}-value`"
        class="flex-1 font-mono text-base"
        :class="model === null ? 'text-text-4' : 'text-readout'"
      >
        {{ model === null ? placeholder : formatAbsolute(new Date(model)) }}
      </span>
      <span v-if="model !== null" class="font-mono text-sm text-text-3">{{
        formatRelative(new Date(model), now)
      }}</span>
    </button>

    <dialog
      ref="dialog"
      :aria-label="label"
      class="m-auto w-[min(920px,calc(100vw-32px))] border border-line bg-panel p-0 text-readout backdrop:bg-[rgba(5,7,10,0.72)]"
      @keydown.enter.exact="($event.target as HTMLElement | null)?.tagName !== 'BUTTON' && commit()"
    >
      <div class="flex flex-col gap-4 p-5">
        <TimeEntry
          :now="now.getTime()"
          :met-available="metEpoch !== null"
          @parsed="setDraft($event)"
        />
        <div class="grid grid-cols-1 gap-6 md:grid-cols-[minmax(0,1.1fr)_minmax(0,1fr)_auto]">
          <TimePresets
            :presets="presets"
            :selected="preset"
            @pick="setDraft($event.at, $event.id)"
          />
          <TimeCalendar
            :model-value="draft"
            :today="now.getTime()"
            :marked="marked"
            :marked-label="markedLabel"
            @update:model-value="setDraft($event)"
          />
          <TimeSpinners :model-value="draft" @update:model-value="setDraft($event)" />
        </div>
        <dl
          class="m-0 grid grid-cols-[repeat(auto-fit,minmax(160px,1fr))] gap-px border border-hairline bg-hairline"
        >
          <div class="bg-panel px-4 py-2.5">
            <dt class="ap-label">UTC</dt>
            <dd class="m-0 font-mono text-base">{{ formatDayTime(new Date(draft)) }}</dd>
          </div>
          <div class="bg-panel px-4 py-2.5">
            <dt class="ap-label">From now</dt>
            <dd class="m-0 font-mono text-base" :class="past ? 'text-caution-text' : ''">
              {{ formatRelative(new Date(draft), now) }}
            </dd>
          </div>
          <div v-if="metEpoch !== null" class="bg-panel px-4 py-2.5">
            <dt class="ap-label">MET</dt>
            <dd class="m-0 font-mono text-base">
              {{ formatMet(new Date(draft), new Date(metEpoch)) }}
            </dd>
          </div>
        </dl>
        <ApCallout v-if="past" tone="caution">{{ pastMessage }}</ApCallout>
        <ApCallout v-if="warning" tone="crit">{{ warning }}</ApCallout>
      </div>
      <footer class="flex flex-wrap items-center gap-3 border-t border-hairline px-5 py-3">
        <span class="flex flex-wrap items-center gap-2 font-mono text-xs text-text-4 uppercase">
          <ApKbd>↑↓</ApKbd> adjust <ApKbd>Tab</ApKbd> next field <ApKbd>↵</ApKbd> set
          <ApKbd>Esc</ApKbd> cancel
        </span>
        <span class="ml-auto flex gap-2">
          <ApButton variant="ghost" @click="dialog?.close()">Cancel</ApButton>
          <ApButton variant="primary" @click="commit"
            >Set {{ formatDayTime(new Date(draft)) }}</ApButton
          >
        </span>
      </footer>
    </dialog>
  </div>
</template>
