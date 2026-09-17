<script setup lang="ts">
import { computed, onBeforeUnmount, ref, watch } from "vue";
import type {
  SettingsContext,
  SettingsSectionPort,
  SettingsWriteResult,
} from "@cadence/plugin-sdk/settings";
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import CadenceLink from "@cadence/ui/CadenceLink.vue";
import SettingsSectionBoundary from "./SettingsSectionBoundary.vue";
import { readSettingsPage, settingsDraftKey, settingsHref, type SettingsAction } from "./contracts";
import type { SettingsDrafts } from "./drafts";
const props = defineProps<{
  snapshot: unknown;
  context: SettingsContext;
  sectionId: string;
  drafts: SettingsDrafts;
  execute: (action: SettingsAction) => Promise<SettingsWriteResult>;
  refresh: () => Promise<void>;
  navigating: boolean;
}>();
const search = ref("");
let alive = true;
onBeforeUnmount(() => {
  alive = false;
});
watch(
  () => props.sectionId,
  () => {
    search.value = "";
  },
);
const page = computed(() => {
  try {
    return readSettingsPage(props.snapshot, props.context, props.sectionId);
  } catch {
    return { status: "unavailable" as const };
  }
});
const sections = computed(() =>
  page.value.status === "ready"
    ? page.value.sections.filter((section) =>
        `${section.title} ${section.description} ${section.owner.label}`
          .toLowerCase()
          .includes(search.value.trim().toLowerCase()),
      )
    : [],
);
const groups = computed(() => [
  {
    name: "Organization & mission",
    entries: sections.value.filter((section) => section.owner.kind === "host"),
  },
  {
    name: "Applications",
    entries: sections.value.filter((section) => section.owner.kind === "application"),
  },
]);
const sectionPort = computed<SettingsSectionPort | null>(() => {
  const captured = page.value;
  if (captured.status !== "ready") return null;
  const key = settingsDraftKey(props.context, captured.selected.id);
  const current = () =>
    alive &&
    !props.navigating &&
    page.value.status === "ready" &&
    page.value.token === captured.token &&
    settingsDraftKey(props.context, props.sectionId) === key;
  return {
    async save(revisionToken, document) {
      if (!current() || !captured.canEdit)
        return { status: "rejected", message: "This settings page is no longer editable." };
      const result = await props.execute({ token: captured.token, revisionToken, document });
      return current() ? result : { status: "unconfirmed" };
    },
    async refresh() {
      if (!current()) throw Error("Inactive settings page.");
      await props.refresh();
    },
    restoreDraft: () => props.drafts.get(key),
    retainDraft: (value, dirty) => props.drafts.retain(key, value, dirty),
  };
});
async function retry() {
  try {
    await props.refresh();
  } catch {
    /* The unavailable state stays visible. */
  }
}
</script>
<template>
  <div class="settings-page">
    <CadencePageHeading>
      <template #eyebrow>{{
        context.scope === "mission" ? context.missionName : context.organizationName
      }}</template>
      <template #title>{{
        context.scope === "mission" ? "Mission settings" : "Organization settings"
      }}</template>
      <template #description>{{
        context.scope === "mission"
          ? "Configure this mission and see what it inherits from your organization."
          : "Set shared defaults and requirements for your missions."
      }}</template>
      <template #metadata
        ><span class="settings-page__metadata"
          ><span class="hero-building-office-2" aria-hidden="true" />{{
            context.organizationName
          }}</span
        ></template
      >
    </CadencePageHeading>
    <div v-if="page.status === 'ready' && sectionPort" class="settings-page__layout">
      <aside class="settings-page__sections" aria-label="Settings navigation">
        <label class="settings-page__search"
          ><span class="hero-magnifying-glass" aria-hidden="true" /><input
            v-model="search"
            type="search"
            aria-label="Find settings sections"
            placeholder="Find settings…"
        /></label>
        <nav aria-label="Settings sections">
          <template v-for="group in groups" :key="group.name">
            <p v-if="group.entries.length" class="settings-page__group">{{ group.name }}</p>
            <CadenceLink
              v-for="section in group.entries"
              :key="section.id"
              :href="settingsHref(context, section)"
              :aria-current="section.id === sectionId ? 'page' : undefined"
              class="settings-page__link"
            >
              <span
                :class="
                  section.owner.kind === 'host'
                    ? 'hero-adjustments-horizontal'
                    : 'hero-command-line'
                "
                aria-hidden="true"
              />{{ section.title }}
              <span
                v-if="drafts.dirty(settingsDraftKey(context, section.id))"
                class="settings-page__dirty"
                aria-label="Unsaved changes"
              />
            </CadenceLink>
          </template>
          <p v-if="!sections.length" role="status">No matching sections.</p>
        </nav>
        <p class="settings-page__scope-note">
          {{
            context.scope === "mission"
              ? "Mission settings inherit organization defaults unless an override is configured."
              : "Organization defaults provide a starting point for every mission."
          }}
        </p>
      </aside>
      <div class="settings-page__content">
        <header class="settings-page__section-heading">
          <div>
            <h2>{{ page.selected.title }}</h2>
            <p>{{ page.selected.description }}</p>
          </div>
          <span class="settings-page__tag">{{
            context.scope === "mission" ? "Mission" : "Organization"
          }}</span>
        </header>
        <p v-if="!page.canEdit" role="status" class="settings-page__read-only">
          You can view these settings. Changing them requires permission to manage
          {{ page.selected.title.toLowerCase() }} for this {{ context.scope }}.
        </p>
        <SettingsSectionBoundary
          :key="settingsDraftKey(context, sectionId)"
          :section="page.selected"
          :snapshot="page.settings"
          :context="context"
          :can-edit="page.canEdit && !navigating"
          :port="sectionPort"
        >
          <template #history
            ><section class="settings-page__history" aria-label="Settings history">
              <p class="settings-page__eyebrow">Changes & history</p>
              <p v-if="!page.history.length">
                Saved changes will appear here with the person and scope they affect.
              </p>
              <div v-for="event in page.history.slice(0, 3)" :key="event.id">
                <span class="hero-check-circle" aria-hidden="true" />
                <div>
                  <strong>{{ event.actor }}</strong
                  ><span>Revision {{ event.version }}</span
                  ><time :datetime="event.saved_at">{{
                    new Date(event.saved_at).toLocaleString()
                  }}</time>
                </div>
              </div>
            </section></template
          >
        </SettingsSectionBoundary>
      </div>
    </div>
    <section v-else class="settings-page__unavailable" role="alert">
      <h2>Settings are unavailable</h2>
      <p>The current section could not be loaded.</p>
      <CadenceButton size="sm" @click="retry">Retry loading</CadenceButton
      ><CadenceLink :href="settingsHref(context, 'cadence.governance')"
        >Open Governance settings</CadenceLink
      >
    </section>
  </div>
</template>
<style scoped>
.settings-page {
  color: var(--text-bright);
  font: 12px/1.6 var(--font-sans);
}
.settings-page__metadata {
  display: inline-flex;
  align-items: center;
  gap: 8px;
}
.settings-page__metadata > span,
.settings-page__search > span,
.settings-page__link > span:not(.settings-page__dirty),
.settings-page__history > div > span {
  display: block;
  flex: none;
  width: 15px;
  height: 15px;
}
.settings-page__layout {
  display: grid;
  grid-template-columns: 176px minmax(0, 1fr);
  gap: 30px;
  align-items: start;
}
.settings-page__sections {
  position: sticky;
  top: 16px;
  min-width: 0;
}
.settings-page__search {
  display: flex;
  align-items: center;
  gap: 8px;
  border: 1px solid var(--border-default);
  border-radius: 4px;
  padding: 8px 9px;
  color: var(--text-subtle);
  background: var(--elevation-sunken);
}
input {
  min-width: 0;
  width: 100%;
  outline: 0;
  border: 0;
  background: transparent;
  color: var(--text-bright);
  font: 11px var(--font-sans);
}
.settings-page__search:focus-within {
  outline: 2px solid var(--border-focus);
  outline-offset: 2px;
}
.settings-page__group {
  padding: 24px 8px 9px;
  margin: 0;
  color: var(--text-subtle);
  font: 9px/1.5 var(--font-mono);
  letter-spacing: 0.06em;
  text-transform: uppercase;
}
.settings-page__link {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 9px 10px;
  border: 1px solid transparent;
  border-radius: 4px;
  color: var(--text-subtle);
  text-decoration: none;
  font-size: 12px;
}
.settings-page__link[aria-current="page"] {
  color: var(--color-action);
  border-color: color-mix(in srgb, var(--color-action) 25%, transparent);
  background: color-mix(in srgb, var(--color-action) 8%, transparent);
}
.settings-page__link:hover {
  background: var(--state-hover);
}
.settings-page__dirty {
  display: block;
  width: 6px;
  height: 6px;
  background: var(--color-warning);
  border-radius: 50%;
  margin-left: auto;
}
.settings-page__scope-note {
  margin-top: 30px;
  padding: 18px 8px;
  border-top: 1px solid var(--border-subtle);
  color: var(--text-subtle);
  font-size: 11px;
}
.settings-page__content {
  min-width: 0;
}
.settings-page__section-heading {
  display: flex;
  align-items: start;
  justify-content: space-between;
  gap: 14px;
  margin-bottom: 22px;
}
h2 {
  margin: 0;
  font-size: 19px;
  font-weight: 600;
  letter-spacing: -0.02em;
  line-height: 1.4;
}
p {
  margin: 0;
  color: var(--text-subtle);
}
.settings-page__section-heading p {
  margin-top: 5px;
}
.settings-page__tag {
  padding: 3px 7px;
  border: 1px solid var(--border-default);
  border-radius: 4px;
  color: var(--text-subtle);
  font: 10px/1.4 var(--font-mono);
}
.settings-page__history {
  border-top: 1px solid var(--border-subtle);
  padding-top: 20px;
  display: flex;
  flex-direction: column;
  gap: 16px;
}
.settings-page__eyebrow {
  font: 9px/1.6 var(--font-mono);
  letter-spacing: 0.06em;
  text-transform: uppercase;
}
.settings-page__history > div {
  display: flex;
  gap: 9px;
  font-size: 11px;
}
.settings-page__history > div > div {
  display: flex;
  flex-direction: column;
  gap: 4px;
}
time,
.settings-page__history span {
  color: var(--text-subtle);
  font-size: 10px;
}
.settings-page__read-only {
  padding: 16px;
  margin-bottom: 20px;
  border: 1px solid var(--border-default);
  background: var(--surface-elevated);
}
.settings-page__unavailable {
  padding: 24px;
  display: flex;
  flex-direction: column;
  align-items: start;
  gap: 16px;
}
@media (width < 850px) {
  .settings-page__layout {
    grid-template-columns: minmax(0, 1fr);
    gap: 24px;
  }
  .settings-page__sections {
    position: static;
  }
  nav {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
    margin-top: 12px;
  }
  .settings-page__group,
  .settings-page__scope-note {
    display: none;
  }
}
</style>
