<script setup lang="ts">
import { computed } from "vue";
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import CadenceLink from "@cadence/ui/CadenceLink.vue";
import GovernanceSettings from "./GovernanceSettings.vue";
import CommandingSettings from "./CommandingSettings.vue";
import { activationPath, approvalNames, scopeNames, sections, settingsPath } from "./fixtures";
import type { SettingsStudy } from "./state";
const props = defineProps<{ study: SettingsStudy }>();
const visibleSections = computed(() =>
  sections.filter(
    (item) =>
      item.scopes.includes(
        props.study.scope.value === "organization" ? "organization" : "mission",
      ) &&
      `${item.title} ${item.description} ${item.owner.label}`
        .toLowerCase()
        .includes(props.study.search.value.trim().toLowerCase()),
  ),
);
const selected = computed(() => sections.find((item) => item.id === props.study.section.value));
const groups = computed(() => [
  {
    label: "Organization & mission",
    entries: visibleSections.value.filter((item) => item.owner.kind === "host"),
  },
  {
    label: "Applications",
    entries: visibleSections.value.filter((item) => item.owner.kind === "application"),
  },
]);
</script>
<template>
  <div class="st-settings">
    <aside class="st-sections" aria-label="Settings navigation">
      <label class="st-search"
        ><span class="hero-magnifying-glass st-icon" aria-hidden="true" /><input
          v-model="study.search.value"
          type="search"
          aria-label="Find settings sections"
          placeholder="Find settings…"
      /></label>
      <nav aria-label="Settings sections">
        <template v-for="group in groups" :key="group.label"
          ><p class="st-nav-group">
            {{ group.label }}
          </p>
          <a
            v-for="entry in group.entries"
            :key="entry.id"
            :href="settingsPath(study.scope.value, entry.id)"
            :aria-current="study.section.value === entry.id ? 'page' : undefined"
            class="st-section-link"
            ><span
              :class="[
                entry.owner.kind === 'host' ? 'hero-adjustments-horizontal' : 'hero-command-line',
                'st-icon',
              ]"
              aria-hidden="true" /><span>{{ entry.title }}</span
            ><span
              v-if="study.sectionDirty(study.scope.value, entry.id)"
              class="st-unsaved-dot"
              aria-label="Unsaved changes" /></a
        ></template>
        <p v-if="!visibleSections.length" class="st-muted" role="status">No matching sections.</p>
      </nav>
      <div class="st-scope-note">
        <span class="hero-building-office-2 st-icon" aria-hidden="true" />
        <p>
          {{
            study.scope.value === "organization"
              ? "Organization defaults provide a starting point for every mission."
              : "Mission settings inherit organization defaults unless an override is configured."
          }}
        </p>
      </div>
    </aside>
    <div class="st-content">
      <div class="st-section-heading">
        <div>
          <h2>{{ selected?.title }}</h2>
          <p>{{ selected?.description }}</p>
        </div>
        <span class="st-tag">{{
          study.scope.value === "organization" ? "Organization" : "Mission"
        }}</span>
      </div>
      <div v-if="!study.canEdit" class="st-explanation" role="status">
        <span class="hero-eye st-icon" aria-hidden="true" />
        <p>
          You can view these settings. Changing them requires permission to manage
          {{ study.section.value === "cadence.governance" ? "governance" : "Commanding defaults" }}
          for this {{ study.scope.value === "organization" ? "organization" : "mission" }}.
        </p>
      </div>
      <div class="st-content-grid">
        <div class="st-editor">
          <GovernanceSettings v-if="study.section.value === 'cadence.governance'" :study="study" />
          <CommandingSettings v-else :study="study" />
          <div
            v-if="study.dirty.value"
            class="st-save-bar"
            role="region"
            aria-label="Unsaved settings"
          >
            <div>
              <strong>Unsaved changes</strong
              ><small>{{ scopeNames[study.scope.value] }} · {{ selected?.title }}</small>
            </div>
            <div class="st-actions">
              <CadenceButton size="sm" variant="quiet" @click="study.discard">Discard</CadenceButton
              ><CadenceButton
                size="sm"
                variant="primary"
                :disabled="!study.editable.value"
                @click="study.save"
                >Save changes</CadenceButton
              >
            </div>
          </div>
          <p class="st-save-message" role="status" aria-live="polite">{{ study.notice.value }}</p>
        </div>
        <aside class="st-context-panel" aria-label="Settings context">
          <div class="st-context-section">
            <p class="st-eyebrow">
              {{ study.dirty.value ? "Preview after saving" : "Effective setting" }}
            </p>
            <template v-if="study.section.value === 'cadence.governance'"
              ><div class="st-people" aria-hidden="true">
                <span>MC</span><span v-if="study.approval.value === 'independent'">EN</span>
              </div>
              <h3 data-testid="effective-approval">{{ approvalNames[study.approval.value] }}</h3>
              <p>
                {{
                  study.approval.value === "independent"
                    ? "Configuration changes wait for approval from a different person."
                    : "An authorized operator can review and activate a saved configuration."
                }}
              </p>
              <CadenceLink :href="activationPath(study.activeMission.value)"
                >Explore activation journey<template #icon
                  ><span class="hero-arrow-right" /></template></CadenceLink
              ><small v-if="study.dirty.value"
                >The journey uses saved settings. Save first to try this requirement.</small
              ></template
            ><template v-else
              ><h3>
                {{
                  study.shelf.value === "expanded"
                    ? "Staged commands visible"
                    : "More room to prepare"
                }}
              </h3>
              <p>
                This default sets the initial layout. Operators can adjust the shelf during their
                session.
              </p></template
            >
          </div>
          <div class="st-context-section">
            <p class="st-eyebrow">Changes & history</p>
            <template v-if="study.activity.value.length"
              ><div
                v-for="event in study.activity.value.slice(0, 3)"
                :key="event.id"
                class="st-activity"
              >
                <span class="hero-check-circle st-icon" aria-hidden="true" />
                <div>
                  <strong>{{ event.section }}</strong
                  ><span>{{ event.scope }} · {{ event.actor }}</span
                  ><small>Saved in this study</small>
                </div>
              </div></template
            >
            <p v-else>Saved changes will appear here with the person and scope they affect.</p>
          </div>
          <div class="st-study-label">
            <span class="hero-beaker st-icon" aria-hidden="true" /><span
              >Interactive design study<br />Changes stay in this preview.</span
            >
          </div>
        </aside>
      </div>
    </div>
  </div>
</template>
