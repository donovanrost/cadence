<script setup lang="ts">
import CadenceSettingsSection from "@cadence/ui/CadenceSettingsSection.vue";
import CadenceSettingRow from "@cadence/ui/CadenceSettingRow.vue";
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import SettingsSource from "./SettingsSource.vue";
import type { SettingsStudy } from "./state";
defineProps<{ study: SettingsStudy }>();
</script>
<template>
  <div v-if="!study.applicationAvailable.value" class="st-unavailable" role="status">
    <span class="hero-puzzle-piece st-large-icon" aria-hidden="true" />
    <h3>Commanding settings are unavailable</h3>
    <p>
      Your saved defaults are retained. Other settings are available from the section navigation.
    </p>
    <CadenceButton size="sm" @click="study.applicationAvailable.value = true"
      >Retry loading</CadenceButton
    >
  </div>
  <div v-else class="st-stack">
    <SettingsSource :study="study" />
    <CadenceSettingsSection
      title="Workspace defaults"
      description="Give operators a consistent starting point when they open Commanding."
      ><template #status><span class="st-tag">Commanding</span></template>
      <CadenceSettingRow
        label="Command shelf"
        description="Choose how the command shelf opens. Operators can expand or minimize the shelf while they work."
      >
        <fieldset class="st-choices" :disabled="!study.editable.value">
          <legend class="sr-only">Command shelf opening state</legend>
          <label class="st-choice" :data-selected="study.shelf.value === 'expanded'"
            ><input
              type="radio"
              name="command-shelf"
              value="expanded"
              :checked="study.shelf.value === 'expanded'"
              @change="study.chooseShelf('expanded')"
            /><span class="hero-view-columns st-choice-icon" aria-hidden="true" /><span
              ><strong>Expanded</strong><small>Start with staged commands visible.</small></span
            ></label
          >
          <label class="st-choice" :data-selected="study.shelf.value === 'minimized'"
            ><input
              type="radio"
              name="command-shelf"
              value="minimized"
              :checked="study.shelf.value === 'minimized'"
              @change="study.chooseShelf('minimized')"
            /><span class="hero-bars-3-bottom-left st-choice-icon" aria-hidden="true" /><span
              ><strong>Minimized</strong><small>Give command building more room.</small></span
            ></label
          >
        </fieldset>
        <template v-if="study.source.value === 'overridden'" #detail
          ><CadenceButton
            size="xs"
            variant="quiet"
            :disabled="!study.editable.value"
            @click="study.resetToOrganization"
            >Use organization default</CadenceButton
          ></template
        >
      </CadenceSettingRow>
      <template #footer><span>Applies when opening the command workspace.</span></template>
    </CadenceSettingsSection>
    <section
      class="st-workspace-preview"
      :data-shelf="study.shelf.value"
      aria-label="Command workspace preview"
    >
      <div class="st-preview-heading">
        <span class="hero-command-line st-icon" aria-hidden="true" /> Commanding<span class="st-tag"
          >Layout preview</span
        >
      </div>
      <div class="st-mini-workspace">
        <div class="st-mini-shelf">
          <span class="hero-square-3-stack-3d st-icon" aria-hidden="true" /><template
            v-if="study.shelf.value === 'expanded'"
            ><strong>Command shelf</strong><span>Stage · 2 commands</span
            ><span>Review & submit</span><span>Execution</span></template
          >
        </div>
        <div class="st-mini-command">
          <small>KESTREL-02</small><strong>Prepare a command</strong
          ><span class="st-skeleton" /><span class="st-skeleton" /><span class="st-skeleton" />
        </div>
      </div>
    </section>
  </div>
</template>
