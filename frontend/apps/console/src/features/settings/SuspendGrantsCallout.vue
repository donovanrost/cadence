<script setup lang="ts">
import { computed, nextTick, ref, watch } from "vue";
import type { RouteLocationRaw } from "vue-router";
import { useConsoleScope } from "@/shell";
import { ApButton, ApCallout, formatShort } from "@/ui";
import {
  changedLine,
  confirmLabel,
  grantRow,
  suspendLead,
  type SuspendedGrant,
} from "./suspensions.ts";
import type { PendingSuspension } from "./useSectionSave.ts";

/**
 * #499 (ca-ux, U105 "The settings save that suspends"): in place of the save line, the grants this
 * save would suspend. Nothing is saved until Save and suspend; focus starts on Cancel.
 */
const props = defineProps<{ pending: PendingSuspension; busy: boolean }>();
const emit = defineEmits<{ confirm: []; cancel: [] }>();
const where = useConsoleScope();
const organizationLevel = computed(() => where.value.kind === "organization");
const grants = computed(() =>
  [...props.pending.suspensions.grants].sort((a, b) =>
    (a.mission.name ?? "").localeCompare(b.mission.name ?? ""),
  ),
);
/** Each mission's Contact planning page, where its grants live; none for a mission not in scope. */
function grantsLink(g: SuspendedGrant): RouteLocationRaw | null {
  const w = where.value;
  if (w.kind === "mission") return { name: "setup.contact-planning" };
  if (w.kind !== "organization") return null;
  const m = w.organization.missions.find((x) => x.id === g.mission.id);
  return m
    ? { name: "setup.contact-planning", params: { org: w.organization.slug, mission: m.slug } }
    : null;
}
/** One link per mission: on its first row. */
const linkedRows = computed(() =>
  grants.value.map((g, i) => ({
    grant: g,
    link: i === 0 || grants.value[i - 1]?.mission.id !== g.mission.id ? grantsLink(g) : null,
  })),
);

const actions = ref<HTMLElement | null>(null);
watch(
  () => props.pending,
  async () => {
    await nextTick();
    actions.value?.querySelector<HTMLElement>("[data-cancel]")?.focus();
  },
  { immediate: true },
);
</script>

<template>
  <ApCallout tone="caution" role="alert" data-suspend-grants>
    <div class="flex min-w-0 flex-col gap-2">
      <p v-if="pending.changed" class="m-0">{{ changedLine }}</p>
      <p class="m-0">{{ suspendLead(pending.suspensions, organizationLevel) }}</p>
      <details class="text-sm">
        <summary class="ap-label cursor-pointer">Show all</summary>
        <ul class="m-0 mt-1 flex list-none flex-col gap-1 p-0">
          <li v-for="row in linkedRows" :key="row.grant.id">
            {{
              grantRow(row.grant, organizationLevel, formatShort(new Date(row.grant.valid_until)))
            }}
            <RouterLink v-if="row.link" :to="row.link" class="ml-2 text-readout hover:underline"
              >Open grants</RouterLink
            >
          </li>
        </ul>
      </details>
      <div ref="actions" class="flex flex-wrap gap-2">
        <ApButton
          variant="danger"
          :disabled="busy"
          disabled-reason="Saving…"
          @click="emit('confirm')"
          >{{ confirmLabel(pending.suspensions) }}</ApButton
        >
        <ApButton data-cancel :disabled="busy" disabled-reason="Saving…" @click="emit('cancel')"
          >Cancel</ApButton
        >
      </div>
    </div>
  </ApCallout>
</template>
