<script setup lang="ts">
import { computed, ref, useId, watch } from "vue";
import { RouterLink } from "vue-router";
import { formatCount, plural, ApButton, ApCallout, ApChip, ApPanel, ApSelect } from "@/ui";
import {
  FleetMatrix,
  fleetStates,
  fleetStateWord,
  type FleetSpacecraft,
} from "@/features/fleet/index.ts";
import { chipWords, leftQueryWords, type TargetQuery } from "./targets.ts";

/** C1 · Targets by live query (R02); identity on every line (R01). */
const props = defineProps<{
  fleet: readonly FleetSpacecraft[];
  query: TargetQuery;
  targets: readonly FleetSpacecraft[];
  /** U51: each target's catalog revision, only when the targets span more than one. */
  revisions?: ReadonlyMap<string, string> | null | undefined;
}>();
const emit = defineEmits<{ change: [query: TargetQuery] }>();
const set = (patch: Partial<TargetQuery>) => emit("change", { ...props.query, ...patch });

/**
 * The query stays live until release (Command.md C1): a spacecraft that was a target and left it
 * (e.g. back in limits) is offered back with Keep / Drop. Editing the query starts over.
 */
const seen = ref<ReadonlySet<string>>(new Set());
const dropped = ref<ReadonlySet<string>>(new Set());
watch(
  () => [props.query, props.targets] as const,
  ([q, now], before) => {
    const ids = now.map((sc) => sc.id);
    if (!before || before[0] !== q) {
      seen.value = new Set(ids);
      dropped.value = new Set();
    } else seen.value = new Set([...seen.value, ...ids]);
  },
  { immediate: true },
);
const left = computed(() => {
  const now = new Set(props.targets.map((sc) => sc.id));
  return props.fleet.filter(
    (sc) => seen.value.has(sc.id) && !now.has(sc.id) && !dropped.value.has(sc.id),
  );
});
const keepLeft = () =>
  set({ explicit: [...props.query.explicit, ...left.value.map((sc) => sc.id)] });
const dropLeft = () =>
  (dropped.value = new Set([...dropped.value, ...left.value.map((sc) => sc.id)]));

/**
 * The target list (lead, scale 11-15): rendered only while its <details> is open, and capped at
 * LIST_CAP rows until 'Show all', so 1,000 targets don't cost 6,000 nodes on every Compose mount.
 */
const LIST_CAP = 200;
const listOpen = ref(false);
const showAll = ref(false);
/** a11y B3 (#243): Show all N ↔ Hide stays put with aria-expanded (it used to unmount on click). */
const listId = useId();
const onToggle = (e: Event) => {
  if (e.target instanceof HTMLDetailsElement) listOpen.value = e.target.open;
};
const listed = computed(() => (showAll.value ? props.targets : props.targets.slice(0, LIST_CAP)));

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
// Target ids come from the draft and the URL as text, so the lookup is by text.
const byId = computed(() => new Map<string, FleetSpacecraft>(props.fleet.map((sc) => [sc.id, sc])));
/** The keyboard path to one craft (the matrix is aria-hidden; qa note on #25). */
const addOptions = computed(() => [
  { value: "", label: "Add spacecraft…" },
  ...props.fleet
    .filter((sc) => !props.query.explicit.includes(sc.id))
    .map((sc) => ({ value: sc.id, label: `${sc.name} · SCID ${sc.scid}` })),
]);
function addOne(id: string) {
  if (id && !props.query.explicit.includes(id)) set({ explicit: [...props.query.explicit, id] });
}
</script>

<template>
  <ApPanel index="C1" title="Targets · live query" :meta="plural(targets.length, 'target')" flush>
    <div class="flex flex-col gap-3 p-4">
      <ApCallout v-if="left.length" tone="caution">
        {{ leftQueryWords(left) }}
        <template #action>
          <span class="flex gap-1">
            <ApButton size="compact" @click="keepLeft">Keep</ApButton>
            <ApButton size="compact" variant="ghost" @click="dropLeft">Drop</ApButton>
          </span>
        </template>
      </ApCallout>
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
        <ApSelect
          model-value=""
          label="Spacecraft"
          size="compact"
          :options="addOptions"
          @update:model-value="addOne"
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
      <details v-if="targets.length" @toggle="onToggle">
        <summary class="ap-label cursor-pointer">
          Show {{ plural(targets.length, "target") }}
        </summary>
        <ul v-if="listOpen" :id="listId" class="m-0 max-h-48 list-none overflow-auto p-0 pt-2">
          <li v-for="sc in listed" :key="sc.id" class="flex gap-3 py-0.5 font-mono text-sm">
            <RouterLink
              :to="{ name: 'ops.spacecraft', params: { scId: sc.scid } }"
              class="text-readout no-underline hover:underline"
              >{{ sc.name }}</RouterLink
            >
            <span class="text-text-3">SCID {{ sc.scid }}</span>
            <span class="text-text-3">{{ sc.profile?.name ?? "no profile" }}</span>
            <span v-if="revisions?.get(sc.id)" class="text-text-4">{{ revisions.get(sc.id) }}</span>
          </li>
          <li v-if="targets.length > LIST_CAP" class="pt-1">
            <ApButton
              size="compact"
              variant="ghost"
              :aria-expanded="showAll"
              :aria-controls="listId"
              @click="showAll = !showAll"
              >{{ showAll ? "Hide" : `Show all ${formatCount(targets.length)}` }}</ApButton
            >
          </li>
        </ul>
      </details>
    </div>
  </ApPanel>
</template>
