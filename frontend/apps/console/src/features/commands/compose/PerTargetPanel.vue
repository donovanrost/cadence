<script setup lang="ts">
import { computed, ref } from "vue";
import { useRemoteQuery } from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";
import { useMissionScope } from "@/shell/index.ts";
import { ApButton, ApCallout, ApNumberField, ApTextarea } from "@/ui";
import type { FleetSpacecraft } from "@/features/fleet/index.ts";
import { fetchLatestValues } from "@/features/telemetry/index.ts";
import { argInput } from "../args.ts";
import {
  checkItem,
  clearPerTarget,
  fillFromCurrent,
  fillFromForm,
  pastePerTargetCsv,
  sameUnit,
  setTargetValue,
  type CurrentValues,
  type StackItem,
} from "./stack.ts";

/**
 * B2 Per-target values (CommandFlow.md C1; api f1bed1880): one row per target, one cell per
 * Per-target argument. An empty cell inherits the form's value (shown faint); fill from the form,
 * clear, or paste CSV. Out-of-range values are marked and block the check, as the form's do.
 */
const props = defineProps<{ item: StackItem; targets: readonly FleetSpacecraft[] }>();
const emit = defineEmits<{ change: [perTarget: StackItem["perTarget"]] }>();

const args = computed(() =>
  props.item.command.arguments.filter((a) => a.id in props.item.perTarget),
);
const ids = computed(() => props.targets.map((t) => t.id));
const check = computed(() => checkItem(props.item, ids.value));

/** B2 Now column (api, per-target values): each target's current value of an argument's point. */
const scope = useMissionScope();
const missionId = computed(() => scope.value.mission.id);
const pointArgs = computed(() =>
  args.value.flatMap((a) => (a.current_point ? [{ arg: a, point: a.current_point }] : [])),
);
const latest = useRemoteQuery(
  computed(() =>
    pointArgs.value.length && ids.value.length
      ? {
          m: missionId.value,
          p: [...new Set(pointArgs.value.map((x) => x.point.id))],
          sc: ids.value,
        }
      : null,
  ),
  (k, signal) => fetchLatestValues(k.m, k.p, k.sc, signal),
);
useMissionInvalidation(missionId, ["telemetry"], latest.refetch, { throttleMs: 10_000 });
const current = computed((): CurrentValues => {
  const s = latest.state.value;
  const values = s.status === "ready" ? s.value.values : [];
  return new Map(
    pointArgs.value.map(({ arg, point }) => [
      arg.id,
      new Map(
        values.filter((v) => v.point_id === point.id).map((v) => [v.spacecraft_id, v.value_json]),
      ),
    ]),
  );
});
const staleOf = computed(() => {
  const s = latest.state.value;
  const values = s.status === "ready" ? s.value.values : [];
  return new Set(values.filter((v) => v.stale).map((v) => `${v.point_id}|${v.spacecraft_id}`));
});
const nowWords = (argId: string, scId: string) => {
  const x = pointArgs.value.find((p) => p.arg.id === argId);
  const v = current.value.get(argId)?.get(scId) ?? null;
  return v === null || !x ? "—" : `${v}${x.point.unit ? ` ${x.point.unit}` : ""}`;
};
const isStale = (argId: string, scId: string) => {
  const x = pointArgs.value.find((p) => p.arg.id === argId);
  return x ? staleOf.value.has(`${x.point.id}|${scId}`) : false;
};
/** `Current + 2.0`: only for arguments whose current point reads in their own unit. */
const addable = computed(() => args.value.filter((a) => sameUnit(a)));
const addWords = computed(() =>
  addable.value
    .map((a) => `${props.item.values[a.id] || "0"}${a.unit ? ` ${a.unit}` : ""}`)
    .join(", "),
);
const formWords = computed(() =>
  args.value
    .map((a) => `${props.item.values[a.id] || "—"}${a.unit ? ` ${a.unit}` : ""}`)
    .join(", "),
);
const numberProps = (argId: string) => {
  const arg = props.item.command.arguments.find((a) => a.id === argId);
  const input = arg ? argInput(arg) : null;
  if (!arg || input?.kind !== "number") return {};
  return {
    integer: input.integer,
    ...(input.min === undefined ? {} : { min: input.min }),
    ...(input.max === undefined ? {} : { max: input.max }),
    ...(arg.unit ? { unit: arg.unit } : {}),
  };
};

const pasting = ref(false);
const csv = ref("");
const pasteNote = ref<string | null>(null);
function paste() {
  const r = pastePerTargetCsv(props.item, csv.value, props.targets);
  emit("change", r.perTarget);
  pasteNote.value = r.unmatched.length
    ? `No target named ${r.unmatched.join(", ")}; those rows were skipped.`
    : null;
  pasting.value = false;
  csv.value = "";
}
</script>

<template>
  <section
    class="flex flex-col gap-2 border-t border-hairline-faint pt-3"
    aria-label="Per-target values"
  >
    <h3 class="ap-label m-0">Per-target values</h3>
    <p v-if="targets.length === 0" class="m-0 text-sm text-text-3">
      Pick targets first; each can then have its own value.
    </p>
    <template v-else>
      <div class="flex flex-wrap gap-2">
        <ApButton
          size="compact"
          variant="secondary"
          @click="emit('change', fillFromForm(item, ids))"
          >All from form · {{ formWords }}</ApButton
        >
        <ApButton
          v-if="addable.length"
          size="compact"
          variant="secondary"
          :disabled="latest.state.value.status !== 'ready'"
          @click="emit('change', fillFromCurrent(item, ids, current))"
          >Current + {{ addWords }}</ApButton
        >
        <ApButton
          size="compact"
          variant="secondary"
          :aria-expanded="pasting"
          :aria-controls="`paste-${item.key}`"
          @click="pasting = !pasting"
          >Paste CSV</ApButton
        >
        <ApButton size="compact" variant="ghost" @click="emit('change', clearPerTarget(item))"
          >Clear</ApButton
        >
      </div>
      <div v-if="pasting" :id="`paste-${item.key}`" class="flex flex-col gap-2">
        <ApTextarea
          v-model="csv"
          label="CSV"
          hint="SCID OR NAME, THEN ONE COLUMN PER ARGUMENT"
          :rows="4"
          placeholder="312, 8.0"
        />
        <div class="flex gap-2">
          <ApButton size="compact" variant="primary" :disabled="!csv.trim()" @click="paste"
            >Apply</ApButton
          >
          <ApButton size="compact" variant="ghost" @click="pasting = false">Cancel</ApButton>
        </div>
      </div>
      <ApCallout v-if="pasteNote" tone="caution">{{ pasteNote }}</ApCallout>
      <table class="w-full border-collapse text-sm">
        <thead>
          <tr class="text-left text-text-3">
            <th scope="col" class="py-1 pr-3 font-normal">Target</th>
            <template v-for="a in args" :key="a.id">
              <th scope="col" class="py-1 pr-3 font-normal">{{ a.name }}</th>
              <th v-if="a.current_point" scope="col" class="py-1 pr-3 font-normal">
                Now · {{ a.current_point.name }}
              </th>
            </template>
          </tr>
        </thead>
        <tbody>
          <tr v-for="t in targets" :key="t.id" class="border-t border-hairline-faint">
            <th scope="row" class="py-1 pr-3 text-left font-mono font-normal text-readout">
              {{ t.name }}
            </th>
            <template v-for="a in args" :key="a.id">
              <td class="py-1 pr-3">
                <!-- Empty inherits the form's value (B2: inherited reads faint, as the hint). -->
                <ApNumberField
                  :model-value="item.perTarget[a.id]?.[t.id] ?? ''"
                  :label="`${a.name} for ${t.name}`"
                  hidden-label
                  v-bind="{
                    ...numberProps(a.id),
                    ...(item.perTarget[a.id]?.[t.id] === undefined
                      ? { hint: `Form: ${item.values[a.id] || '—'}` }
                      : {}),
                  }"
                  @update:model-value="
                    (v: string) => emit('change', setTargetValue(item, a.id, t.id, v))
                  "
                />
                <p
                  v-if="check.targetErrors[a.id]?.[t.id]"
                  class="m-0 pt-0.5 text-xs text-caution-text"
                >
                  {{ check.targetErrors[a.id]?.[t.id] }}
                </p>
              </td>
              <td
                v-if="a.current_point"
                class="py-1 pr-3 font-mono"
                :class="isStale(a.id, t.id) ? 'text-stale-text' : 'text-text-2'"
              >
                {{ nowWords(a.id, t.id) }}<span v-if="isStale(a.id, t.id)"> · stale</span>
              </td>
            </template>
          </tr>
        </tbody>
      </table>
    </template>
  </section>
</template>
