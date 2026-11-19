<script setup lang="ts">
import { computed } from "vue";
import { useRouter, type RouteLocationRaw } from "vue-router";
import {
  formatCountdown,
  useNow,
  ApBreadcrumb,
  ApButton,
  ApFact,
  ApPageHeader,
  ApStatStrip,
  ApTabLinks,
  ApTag,
  type ApCrumb,
  type ApTabLink,
  type OpState,
} from "@/ui";
import { spacecraftTabs, type SpacecraftTab } from "@/shell";
import { useCommandAccess } from "@/features/commands/index.ts";
import type { FleetSpacecraft } from "@/features/fleet/index.ts";
import { usePrevNextKeys } from "./usePrevNextKeys.ts";

/** Shared spacecraft header (Investigate spec): breadcrumb, title + state, actions, facts, tabs. */
const props = defineProps<{
  sc: FleetSpacecraft;
  /** Worst active state (alarm first), computed by the owner from the alarms read. */
  hero: { state: OpState; label: string };
  prev: FleetSpacecraft | null;
  next: FleetSpacecraft | null;
  tab: SpacecraftTab;
}>();
const router = useRouter();
/** Members without command access get no Command button (DECISIONS #38). */
const access = useCommandAccess();
const now = useNow();

const at = (sc: FleetSpacecraft): RouteLocationRaw => ({
  name: "ops.spacecraft",
  params: { scId: sc.scid, tab: props.tab },
});
usePrevNextKeys(
  () => (props.prev ? at(props.prev) : null),
  () => (props.next ? at(props.next) : null),
  router,
);

const crumbs = computed((): readonly ApCrumb[] => {
  const plane: readonly ApCrumb[] =
    props.sc.plane === null
      ? []
      : [
          {
            label: `Plane ${String(props.sc.plane).padStart(2, "0")}`,
            to: { name: "ops.fleet", query: { plane: String(props.sc.plane) } },
          },
        ];
  return [{ label: "Fleet", to: { name: "ops.fleet" } }, ...plane, { label: props.sc.name }];
});

const facts = computed(() => {
  const sc = props.sc;
  const list: { label: string; value: string; next?: boolean }[] = [
    { label: "SCID", value: String(sc.scid) },
  ];
  if (sc.profile?.name)
    list.push({
      label: "Profile",
      value: `${sc.profile.name}${sc.profile.version === null ? "" : ` · v${sc.profile.version}`}`,
    });
  if (sc.plane !== null)
    list.push({
      label: "Orbit",
      value: `P${String(sc.plane).padStart(2, "0")}${sc.slot === null ? "" : ` · slot ${String(sc.slot).padStart(2, "0")}`}`,
    });
  if (sc.last_received_at)
    list.push({
      label: "Last TLM",
      value: formatCountdown(new Date(sc.last_received_at), now.value),
    });
  if (sc.last_los_at)
    list.push({ label: "Last LOS", value: formatCountdown(new Date(sc.last_los_at), now.value) });
  if (sc.next_aos_at)
    list.push({
      label: "Next AOS",
      value: formatCountdown(new Date(sc.next_aos_at), now.value),
      next: true,
    });
  return list;
});

const tabs = computed((): readonly ApTabLink[] =>
  spacecraftTabs.map((key) => ({
    key,
    label: key[0]?.toUpperCase() + key.slice(1),
    to: { name: "ops.spacecraft", params: { scId: props.sc.scid, tab: key } },
  })),
);
</script>

<template>
  <div class="flex flex-none flex-col gap-2.5">
    <div class="flex items-center justify-between gap-3">
      <ApBreadcrumb :crumbs="crumbs" />
      <div class="flex gap-1.5">
        <ApButton
          size="compact"
          variant="ghost"
          :to="prev ? at(prev) : undefined"
          :disabled="!prev"
          :disabled-reason="`First in ${sc.plane === null ? 'the fleet' : 'its plane'}`"
          :aria-label="
            prev ? `${prev.scid}, previous spacecraft ${prev.name}` : 'Previous spacecraft'
          "
          ><span aria-hidden="true">[</span> {{ prev?.scid ?? "" }}</ApButton
        >
        <ApButton
          size="compact"
          variant="ghost"
          :to="next ? at(next) : undefined"
          :disabled="!next"
          :disabled-reason="`Last in ${sc.plane === null ? 'the fleet' : 'its plane'}`"
          :aria-label="next ? `${next.scid}, next spacecraft ${next.name}` : 'Next spacecraft'"
          >{{ next?.scid ?? "" }} <span aria-hidden="true">]</span></ApButton
        >
      </div>
    </div>
    <ApPageHeader :title="sc.name">
      <template #status><ApTag :state="hero.state" :label="hero.label" /></template>
      <ApButton
        v-if="access.request"
        size="compact"
        :to="{ name: 'ops.commands.new', query: { targets: `sc:${sc.id}` } }"
        >Command</ApButton
      >
    </ApPageHeader>
    <ApStatStrip :columns="facts.length" label="Spacecraft facts">
      <ApFact
        v-for="fact in facts"
        :key="fact.label"
        :label="fact.label"
        :value="fact.value"
        :next="fact.next ?? false"
      />
    </ApStatStrip>
    <ApTabLinks :links="tabs" :active="tab" label="Spacecraft sections" />
  </div>
</template>
