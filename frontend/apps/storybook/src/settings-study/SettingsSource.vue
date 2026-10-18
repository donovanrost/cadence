<script setup lang="ts">
import { computed } from "vue";
import CadenceLink from "@cadence/ui/CadenceLink.vue";
import { settingsPath, scopeNames } from "./fixtures";
import type { SettingsStudy } from "./state";
const props = defineProps<{ study: SettingsStudy }>();
const label = computed(
  () =>
    ({
      organization: "Organization default",
      inherited: "Inherited from organization",
      overridden: "Mission override",
      enforced: "Required by organization",
    })[props.study.source.value],
);
</script>
<template>
  <div class="st-source" :data-source="study.source.value" data-testid="settings-source">
    <span
      :class="[
        study.source.value === 'enforced' ? 'hero-lock-closed' : 'hero-arrow-down-on-square',
        'st-icon',
      ]"
      aria-hidden="true"
    />
    <div>
      <strong>{{ label }}</strong
      ><span
        >{{ scopeNames.organization
        }}<template v-if="study.scope.value !== 'organization'">
          <span aria-hidden="true">→</span> {{ scopeNames[study.scope.value] }}</template
        ></span
      >
    </div>
    <CadenceLink
      v-if="study.scope.value !== 'organization'"
      :href="settingsPath('organization', study.section.value)"
      >View organization setting</CadenceLink
    >
    <span v-else class="st-tag">2 missions</span>
  </div>
</template>
