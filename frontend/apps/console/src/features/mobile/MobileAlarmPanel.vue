<script setup lang="ts">
import { computed } from "vue";
import type { RemoteState } from "@/api";
import { ApPanel, ApStatStrip, ApStatTile, ApTag } from "@/ui";
import { lastValueReadout, type Alarm, type EpisodeDetail } from "@/features/alarms/index.ts";
import type { FleetSpacecraft } from "@/features/fleet/index.ts";
import {
  formatRate,
  TrendBlock,
  type History,
  type LimitSegment,
  type SeriesPoint,
  type TimeWindow,
} from "@/features/investigate/index.ts";

/**
 * Mobile.md §1: spacecraft + severity, the episode's last value with its time, rate, and an 80px
 * trend. An alarm row carries no value or limits (#1117); the episode does.
 */
const props = defineProps<{
  sc: FleetSpacecraft;
  alarm: Alarm;
  /** The alarm's episode, when loaded: its last value and when it was evaluated. */
  episode?: EpisodeDetail | null;
  history: RemoteState<History>;
  view: {
    window: TimeWindow;
    series: readonly SeriesPoint[];
    limits: readonly LimitSegment[];
    sentence: string;
    stepMs: number;
    rate: number | null;
  } | null;
  rangeLabel: string;
  /** "3 sisters in P07 out of limits" (B4's v1 rule; null without a plane or any). */
  sisters?: string | null;
}>();
defineEmits<{ retry: [] }>();

const tone = computed(() => (props.alarm.severity === "critical" ? "crit" : "caution"));
const last = computed(() => lastValueReadout(props.episode));
const unit = computed(() => props.alarm.point.unit ?? undefined);
</script>

<template>
  <ApPanel :alert="tone" flush>
    <div class="flex flex-col gap-3 p-4">
      <div class="flex flex-wrap items-center gap-3">
        <h1 class="m-0 font-display text-[22px] font-bold tracking-id uppercase">{{ sc.name }}</h1>
        <ApTag :state="tone" :label="tone === 'crit' ? 'Critical' : 'Caution'" />
      </div>
      <p class="m-0 font-mono text-sm text-text-3">
        <span class="normal-case">{{ alarm.point.name }}</span> · SCID {{ sc.scid }}
      </p>
      <ApStatStrip v-if="last" :columns="1" label="Readouts">
        <ApStatTile
          :label="last.label"
          :value="last.value"
          :caption="last.caption"
          :unit="unit"
          :state="tone"
        />
      </ApStatStrip>
      <p class="m-0 font-mono text-xs text-text-3">
        {{
          view?.rate == null
            ? "Rate needs 15 min of data"
            : `${formatRate(view.rate)} ${unit ?? ""}/h`.replace(" /h", "/h")
        }}<template v-if="sisters"> · {{ sisters }}</template>
      </p>
    </div>
    <TrendBlock
      :point-name="alarm.point.name"
      :unit="alarm.point.unit"
      :range-label="rangeLabel"
      :history="history"
      :view="view"
      :height="80"
      compact
      @retry="$emit('retry')"
    />
  </ApPanel>
</template>
