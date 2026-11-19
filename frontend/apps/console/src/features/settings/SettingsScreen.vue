<script setup lang="ts">
import { computed } from "vue";
import { useRoute } from "vue-router";
import { useRemoteQuery } from "@/api";
import { useConsoleScope } from "@/shell";
import { ApEmptyState, ApPageHeader, ApPanel, ApRemote, ApTabLinks, type ApTabLink } from "@/ui";
import SettingsSectionPanel from "./SettingsSectionPanel.vue";
import { fetchSettings, type Settings, type SettingsScope } from "./api.ts";

/** Mission or organization settings, sections from the server registry (editable with settings.edit; saves are direct (ST1)). */
const route = useRoute<"setup.settings" | "org.settings">();
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
const routeName = computed((): "setup.settings" | "org.settings" =>
  route.name === "setup.settings" ? "setup.settings" : "org.settings",
);
const active = (s: Settings) =>
  typeof route.params.section === "string" && route.params.section
    ? route.params.section
    : (s.sections[0]?.key ?? "");
const links = (s: Settings): readonly ApTabLink[] =>
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
    <ApPageHeader :label="label" title="Settings" size="reading" />
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
        <SettingsSectionPanel
          v-for="section in value.sections.filter((s) => s.key === active(value))"
          :key="section.key"
          :scope="target ?? { kind: 'mission', id: '' }"
          :section="section"
          :can-edit="value.permissions.includes('settings.edit')"
          @saved="refetch"
        />
        <p v-if="!value.permissions.includes('settings.edit')" class="m-0 text-sm text-text-3">
          Org admins change settings.
        </p>
      </template>
    </ApRemote>
  </div>
</template>
