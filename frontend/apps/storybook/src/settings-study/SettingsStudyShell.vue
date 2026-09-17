<script setup lang="ts">
import { computed, ref } from "vue";
import ApplicationShell from "../../../host/src/shell/ApplicationShell.vue";
import HostPage from "../../../host/src/shell/HostPage.vue";
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import CadenceLink from "@cadence/ui/CadenceLink.vue";
import SettingsStudy from "./SettingsStudy.vue";
import ActivationPreview from "./ActivationPreview.vue";
import { useSettingsStudy } from "./state";
import {
  actors,
  missions,
  scopeNames,
  settingsPath,
  activationPath,
  type Scenario,
  type ScopeKey,
} from "./fixtures";
import "./settings-study.css";
const props = withDefaults(defineProps<{ initial?: Scenario }>(), { initial: "inherited" });
const study = useSettingsStudy(props.initial);
const shell = ref<HTMLElement | null>(null);
const mission = computed(() => study.scope.value !== "organization");
const context = computed(() => ({
  version: 1,
  user: {
    user_id: study.actor.value,
    display_name: actors[study.actor.value],
    email: `${study.actor.value}@example.test`,
  },
  organization: { organization_id: "flight", display_name: scopeNames.organization },
  organizations: [],
  capabilities: [],
  platform_admin: false,
  admin_mode: false,
  csrf_token: "storybook-csrf",
  notifications: [],
  unread_count: 0,
  nav_context: mission.value ? "mission" : "organization",
  nav_item: study.destination.value === "activation" ? "spacecraft" : "settings",
  ...(mission.value
    ? {
        mission: {
          mission_id: study.scope.value,
          display_name: scopeNames[study.scope.value],
          slug: study.scope.value,
        },
      }
    : { mission: null }),
}));
const title = computed(() =>
  study.destination.value === "activation"
    ? "Review configuration"
    : study.destination.value === "outside"
      ? study.outsideTitle.value
      : mission.value
        ? "Mission settings"
        : "Organization settings",
);
const breadcrumbs = computed(() => [
  { label: scopeNames.organization, href: "/" },
  ...(mission.value
    ? [{ label: scopeNames[study.scope.value], href: `/missions/${study.scope.value}` }]
    : []),
]);
function navigate(event: MouseEvent) {
  if (
    event.defaultPrevented ||
    event.button !== 0 ||
    event.metaKey ||
    event.ctrlKey ||
    event.altKey ||
    event.shiftKey
  )
    return;
  const anchor = event.target instanceof Element ? event.target.closest("a") : null;
  const href = anchor?.getAttribute("href");
  if (
    !anchor ||
    anchor.target ||
    anchor.hasAttribute("download") ||
    !href?.startsWith("/") ||
    href.startsWith("//") ||
    href.startsWith("/iframe.html")
  )
    return;
  event.preventDefault();
  study.notice.value = "";
  const keys: readonly ScopeKey[] = ["organization", "kestrel", "pathfinder"];
  let found = false;
  for (const key of keys) {
    for (const section of ["cadence.governance", "commanding.defaults"] as const) {
      if (href === settingsPath(key, section)) {
        study.scope.value = key;
        study.section.value = section;
        study.destination.value = "settings";
        study.search.value = "";
        found = true;
      }
    }
    if (key !== "organization" && href === activationPath(key)) {
      study.scope.value = key;
      study.destination.value = "activation";
      found = true;
    }
  }
  if (!found) {
    study.destination.value = "outside";
    study.outsideTitle.value = anchor.textContent?.trim() || "Cadence";
  }
  const drawer = shell.value?.querySelector<HTMLInputElement>("#sidebar-drawer");
  if (drawer) drawer.checked = false;
}
</script>
<template>
  <div ref="shell" class="st-shell" @click="navigate" @submit.prevent>
    <ApplicationShell
      class="st-shell-frame"
      :variant="mission ? 'mission_sidebar' : 'sidebar'"
      :context="context"
      managed-page
    >
      <template #navigation-footer
        ><nav aria-label="Scope settings" class="st-nav-footer">
          <a
            :href="settingsPath(study.scope.value, study.section.value)"
            class="cd-side-nav-item"
            :aria-current="study.destination.value === 'settings' ? 'page' : undefined"
            aria-label="Settings"
            title="Settings"
            ><span class="hero-cog-6-tooth cd-side-nav-icon h-4 w-4" aria-hidden="true" /><span
              class="sidebar-label"
              >Settings</span
            ></a
          >
        </nav></template
      >
      <HostPage :title="title" :breadcrumbs="breadcrumbs">
        <CadencePageHeading
          ><template #eyebrow>{{
            study.destination.value === "activation"
              ? "Spacecraft configuration"
              : scopeNames[study.scope.value]
          }}</template
          ><template #title>{{ title }}</template
          ><template #description>{{
            study.destination.value === "settings"
              ? mission
                ? "Configure this mission and see what it inherits from your organization."
                : "Set shared defaults and requirements for your missions."
              : "Review the exact saved revision and its activation requirements."
          }}</template
          ><template #metadata
            ><span class="st-inline st-heading-meta"
              ><span class="hero-building-office-2 st-icon" aria-hidden="true" />{{
                scopeNames.organization
              }}</span
            ><span v-if="mission" class="st-inline"
              ><span class="hero-rocket-launch st-icon" aria-hidden="true" />{{
                scopeNames[study.scope.value]
              }}</span
            ></template
          ></CadencePageHeading
        >
        <nav
          v-if="!mission && study.destination.value === 'settings'"
          class="st-scope-navigation"
          aria-label="Settings scope"
        >
          <a
            :href="settingsPath('organization', study.section.value)"
            :aria-current="study.scope.value === 'organization' ? 'page' : undefined"
            ><span class="hero-building-office-2 st-icon" aria-hidden="true" /><span
              >Organization</span
            ><span
              v-if="study.sectionDirty('organization', study.section.value)"
              class="st-unsaved-dot"
              aria-label="Unsaved changes" /></a
          ><span class="st-scope-divider" aria-hidden="true" /><a
            v-for="item in missions"
            :key="item.id"
            :href="settingsPath(item.id, study.section.value)"
            :aria-current="study.scope.value === item.id ? 'page' : undefined"
            ><span class="hero-rocket-launch st-icon" aria-hidden="true" />{{ item.name
            }}<span
              v-if="study.sectionDirty(item.id, study.section.value)"
              class="st-unsaved-dot"
              aria-label="Unsaved changes"
          /></a>
        </nav>
        <SettingsStudy v-if="study.destination.value === 'settings'" :study="study" />
        <ActivationPreview v-else-if="study.destination.value === 'activation'" :study="study" />
        <section v-else class="st-outside">
          <h2>{{ study.outsideTitle.value }}</h2>
          <p>This destination is outside the settings study. Your settings drafts are preserved.</p>
          <CadenceLink :href="settingsPath(study.scope.value, study.section.value)"
            >Return to settings</CadenceLink
          >
        </section>
      </HostPage>
    </ApplicationShell>
  </div>
</template>
