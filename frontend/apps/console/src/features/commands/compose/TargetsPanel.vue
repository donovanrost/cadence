<script setup lang="ts">
import { computed } from "vue";
import { RouterLink } from "vue-router";
import { plural, ApChip, ApPanel, ApSelect } from "@/ui";
import {
  FleetMatrix,
  fleetStates,
  fleetStateWord,
  type FleetSpacecraft,
} from "@/features/fleet/index.ts";
import { chipWords, type TargetQuery } from "./targets.ts";

/** C1 · Targets by live query (R02); identity on every line (R01). */
const props = defineProps<{
  fleet: readonly FleetSpacecraft[];
  query: TargetQuery;
  targets: readonly FleetSpacecraft[];
}>();
const emit = defineEmits<{ change: [query: TargetQuery] }>();
const set = (patch: Partial<TargetQuery>) => emit("change", { ...props.query, ...patch });

const planes = computed(() =>
  [...new Set(props.fleet.flatMap((sc) => (sc.plane === null ? [] : [sc.plane])))].sort(
    (a, b) => a - b,
  ),
);
const profiles = computed(() => {
  const m = new Map<string, string>();
  for (const sc of props.fleet)
    if (sc.profile) m.set(sc.profile.id, sc.profile.name ?? sc.profile.id);
  return m;
});
const planeModel = computed({
  get: () => (props.query.plane === null ? "" : String(props.query.plane)),
  set: (v: string) => set({ plane: v === "" ? null : Number(v) }),
});
const profileModel = computed({
  get: () => props.query.profile ?? "",
  set: (v: string) => set({ profile: v || null }),
});
const stateModel = computed({
  get: () => props.query.states[0] ?? "",
  set: (v: string) => set({ states: fleetStates.filter((s) => s === v) }),
});
const ids = computed(() => new Set(props.targets.map((sc) => sc.id)));
const words = computed(() => chipWords(props.query, (id) => profiles.value.get(id) ?? id));
const byId = computed(() => new Map(props.fleet.map((sc) => [sc.id, sc])));
</script>

<template>
  <ApPanel index="C1" title="Targets · live query" :meta="plural(targets.length, 'target')" flush>
    <div class="flex flex-col gap-3 p-4">
      <div class="flex flex-wrap items-end gap-2">
        <ApSelect
          v-model="planeModel"
          label="Plane"
          size="compact"
          :options="[
            { value: '', label: 'Any plane' },
            ...planes.map((p) => ({
              value: String(p),
              label: `Plane ${String(p).padStart(2, '0')}`,
            })),
          ]"
        />
        <ApSelect
          v-model="profileModel"
          label="Profile"
          size="compact"
          :options="[
            { value: '', label: 'Any profile' },
            ...[...profiles].map(([value, label]) => ({ value, label })),
          ]"
        />
        <ApSelect
          v-model="stateModel"
          label="State"
          size="compact"
          :options="[
            { value: '', label: 'Any state' },
            ...fleetStates.map((s) => ({ value: s, label: fleetStateWord(s) })),
          ]"
        />
      </div>
      <div v-if="words.length || query.explicit.length" class="flex flex-wrap gap-1.5">
        <ApChip v-for="w in words" :key="w">{{ w }}</ApChip>
        <ApChip
          v-for="id in query.explicit"
          :key="id"
          removable
          :remove-label="`Remove ${byId.get(id)?.name ?? id}`"
          @remove="set({ explicit: query.explicit.filter((x) => x !== id) })"
          >{{ byId.get(id)?.name ?? id }}</ApChip
        >
      </div>
      <details :open="targets.length === 0">
        <summary class="ap-label cursor-pointer">
          Fleet matrix · click a cell to add or remove
        </summary>
        <div class="pt-2">
          <FleetMatrix
            mode="selection"
            :spacecraft="fleet"
            :selected-plane="query.plane"
            :matches="(sc) => ids.has(sc.id)"
            no-plane-picker
            @open="
              (sc) =>
                set({
                  explicit: query.explicit.includes(sc.id)
                    ? query.explicit
                    : [...query.explicit, sc.id],
                })
            "
          />
        </div>
      </details>
      <details v-if="targets.length">
        <summary class="ap-label cursor-pointer">
          Show {{ plural(targets.length, "target") }}
        </summary>
        <ul class="m-0 max-h-48 list-none overflow-auto p-0 pt-2">
          <li v-for="sc in targets" :key="sc.id" class="flex gap-3 py-0.5 font-mono text-sm">
            <RouterLink
              :to="{ name: 'ops.spacecraft', params: { scId: String(sc.scid) } }"
              class="text-readout no-underline hover:underline"
              >{{ sc.name }}</RouterLink
            >
            <span class="text-text-3">SCID {{ sc.scid }}</span>
            <span class="text-text-3">{{ sc.profile?.name ?? "no profile" }}</span>
          </li>
        </ul>
      </details>
    </div>
  </ApPanel>
</template>
