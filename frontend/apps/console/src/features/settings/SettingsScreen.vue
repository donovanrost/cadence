<script setup lang="ts">
import { computed } from "vue";
import { useRoute } from "vue-router";
import { useRemoteQuery } from "@/api";
import { useConsoleScope } from "@/shell";
import { ApEmptyState, ApPageHeader, ApPanel, ApRemote, ApTabLinks, formatShort } from "@/ui";
import { fetchSettings, sourceLabel, valueText, type Settings, type SettingsScope } from "./api.ts";

/** Mission or organization settings, sections from the server registry (read-only v1). */
const route = useRoute();
const scope = useConsoleScope();
const target = computed((): SettingsScope | null => {
  const s = scope.value;
  if (s.kind === "mission" && route.name === "setup.settings")
    return { kind: "mission", id: s.mission.id };
  if (s.kind === "organization" || s.kind === "mission")
    return { kind: "organization", id: s.organization.id };
  return null;
});
const { state, refetch } = useRemoteQuery(target, fetchSettings);
const notProvided = computed(
  () => state.value.status === "failed" && state.value.error.kind === "not_found",
);
const routeName = computed(() =>
  route.name === "setup.settings" ? "setup.settings" : "org.settings",
);
const active = (s: Settings) =>
  typeof route.params.section === "string" && route.params.section
    ? route.params.section
    : (s.sections[0]?.key ?? "");
const links = (s: Settings) =>
  s.sections.map((x) => ({
    key: x.key,
    label: x.title,
    to: { name: routeName.value, params: { section: x.key } },
  }));
const label = computed(() => {
  const s = scope.value;
  return s.kind === "mission" && target.value?.kind === "mission"
    ? `${s.mission.name} · settings`
    : s.kind === "organization" || s.kind === "mission"
      ? `${s.organization.name} · settings`
      : "Settings";
});
</script>

<template>
  <div class="mx-auto flex w-full max-w-[1400px] flex-col gap-4">
    <ApPageHeader :label="label" title="Settings" size="reading">
      <template v-if="state.status === 'ready' && state.value.version" #subtitle>
        <span class="font-mono text-sm text-text-3"
          >v{{ state.value.version.version }} · {{ formatShort(new Date(state.value.version.at))
          }}{{ state.value.version.actor ? ` by ${state.value.version.actor.name}` : "" }}</span
        >
      </template>
    </ApPageHeader>
    <ApPanel v-if="notProvided" index="S1" title="Settings" flush>
      <ApEmptyState
        state="off"
        headline="Settings aren't available in the console yet"
        sentence="This server doesn't serve the settings registry to the console yet."
      />
    </ApPanel>
    <ApRemote v-else :state="state" loading-label="Loading settings…" @retry="refetch">
      <template #default="{ value }">
        <ApTabLinks
          v-if="value.sections.length > 1"
          :links="links(value)"
          :active="active(value)"
          label="Settings sections"
        />
        <ApPanel
          v-for="section in value.sections.filter((s) => s.key === active(value))"
          :key="section.key"
          index="S1"
          :title="section.title"
          :meta="section.key"
          flush
        >
          <p
            v-if="section.purpose"
            class="m-0 border-b border-hairline px-4 py-2.5 text-md text-text-3"
          >
            {{ section.purpose }}
          </p>
          <dl class="m-0 grid grid-cols-1 gap-px bg-hairline md:grid-cols-2">
            <div
              v-for="f in section.fields"
              :key="f.path"
              class="flex flex-col gap-1 bg-panel px-4 py-3"
            >
              <dt class="ap-label">{{ f.label }}</dt>
              <dd
                class="m-0 font-mono text-md"
                :class="f.source === (target?.kind ?? 'mission') ? 'text-readout' : 'text-text-3'"
              >
                {{ valueText(f) }}
              </dd>
              <dd class="m-0 font-mono text-xs text-text-4 uppercase">
                {{ sourceLabel(f, target?.kind ?? "mission") }}
              </dd>
              <dd v-if="f.help" class="m-0 text-sm text-text-3">{{ f.help }}</dd>
            </div>
          </dl>
        </ApPanel>
        <p v-if="!value.permissions.includes('settings.edit')" class="m-0 text-sm text-text-3">
          Org admins change settings.
        </p>
      </template>
    </ApRemote>
  </div>
</template>
