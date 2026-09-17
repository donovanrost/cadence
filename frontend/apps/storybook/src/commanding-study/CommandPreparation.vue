<script setup lang="ts">
import { computed, ref } from "vue";
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import type { Command, Draft, Spacecraft } from "./fixtures";
const props = defineProps<{
  command: Command;
  targets: Spacecraft[];
  incompatible: Spacecraft[];
  draft: Draft;
  canStage: boolean;
}>();
const emit = defineEmits<{
  close: [];
  value: [value: string];
  override: [id: string, value: string];
  removeTarget: [id: string];
  stage: [];
}>();
const overrides = ref(false);
const singleTarget = computed(() => (props.targets.length === 1 ? props.targets[0] : undefined));
const activeOverrideCount = computed(
  () => props.targets.filter((target) => props.draft.overrides[target.id] !== undefined).length,
);
const selectedValue = computed(() =>
  singleTarget.value
    ? (props.draft.overrides[singleTarget.value.id] ?? props.draft.value)
    : props.draft.value,
);
function chooseValue(value: string) {
  if (singleTarget.value && props.draft.overrides[singleTarget.value.id] !== undefined)
    emit("override", singleTarget.value.id, value);
  else emit("value", value);
}
function changeOverride(id: string, event: Event) {
  if (event.target instanceof HTMLSelectElement) emit("override", id, event.target.value);
}
</script>
<template>
  <section class="study-pane study-preparation" aria-labelledby="study-preparation-title">
    <header class="study-pane-heading">
      <h2 id="study-preparation-title">Prepare command</h2>
      <CadenceButton
        size="xs"
        variant="quiet"
        aria-label="Close preparation"
        @click="emit('close')"
      >
        <span class="hero-x-mark study-icon" aria-hidden="true" />
      </CadenceButton>
    </header>
    <div class="study-scroll study-preparation-body">
      <div class="study-command-identity">
        <span :class="[command.icon, 'study-command-glyph']" aria-hidden="true" />
        <span class="study-eyebrow">{{ command.subsystem }}</span>
        <h3>{{ command.title }}</h3>
        <code>{{ command.id }}</code>
      </div>
      <p class="study-description">{{ command.description }}</p>
      <section class="study-preparation-section" aria-label="Command targets">
        <div class="study-section-heading">
          <h4>Targets</h4>
          <span>{{ targets.length }} spacecraft</span>
        </div>
        <div class="study-target-chips">
          <button
            v-for="target in targets"
            :key="target.id"
            type="button"
            :class="['study-target-chip', { 'is-incompatible': incompatible.includes(target) }]"
            :aria-label="'Remove ' + target.id + ' from selection'"
            @click="emit('removeTarget', target.id)"
          >
            {{ target.id }}<span aria-hidden="true">×</span>
          </button>
        </div>
        <p v-if="!targets.length" class="study-notice">
          Select spacecraft to continue. Your settings are retained.
        </p>
        <p v-else class="study-fine-print">
          Onboard computer · one endpoint per selected spacecraft
        </p>
      </section>
      <section
        v-if="command.choices.length"
        class="study-preparation-section"
        aria-label="Command settings"
      >
        <div class="study-section-heading">
          <h4>{{ command.setting }}</h4>
          <span>{{ singleTarget ? singleTarget.id : "Shared value" }}</span>
        </div>
        <div class="study-choice-group" :aria-label="command.setting" role="group">
          <button
            v-for="choice in command.choices"
            :key="choice"
            type="button"
            :aria-pressed="selectedValue === choice"
            @click="chooseValue(choice)"
          >
            {{ choice }}
          </button>
        </div>
        <button
          v-if="targets.length > 1 || activeOverrideCount"
          class="study-disclosure"
          type="button"
          :aria-expanded="overrides"
          aria-controls="study-target-overrides"
          @click="overrides = !overrides"
        >
          <span
            :class="[overrides ? 'hero-chevron-down' : 'hero-chevron-right', 'study-icon-small']"
            aria-hidden="true"
          />
          Adjust per spacecraft
          <span v-if="activeOverrideCount" class="study-count">{{ activeOverrideCount }}</span>
        </button>
        <div
          v-if="overrides && (targets.length > 1 || activeOverrideCount)"
          id="study-target-overrides"
          class="study-override-list"
        >
          <label v-for="target in targets" :key="target.id" class="study-override-row">
            <span class="study-mono">{{ target.id }}</span>
            <select
              :aria-label="command.setting + ' for ' + target.id"
              :value="draft.overrides[target.id] ?? ''"
              @change="changeOverride(target.id, $event)"
            >
              <option value="">Shared · {{ draft.value }}</option>
              <option v-for="choice in command.choices" :key="choice" :value="choice">
                {{ choice }}
              </option>
            </select>
          </label>
        </div>
      </section>
      <section
        class="study-effect"
        :class="{ 'is-hazardous': command.hazardous }"
        aria-label="Expected effect"
      >
        <span
          :class="[
            command.hazardous ? 'hero-exclamation-triangle' : 'hero-arrow-right-circle',
            'study-icon',
          ]"
          aria-hidden="true"
        />
        <div>
          <h4>{{ command.hazardous ? "Operational consequence" : "Expected effect" }}</h4>
          <p>{{ command.effect }}</p>
        </div>
      </section>
      <section v-if="incompatible.length" class="study-notice" role="status">
        <strong>{{ incompatible.length }} incompatible spacecraft</strong>
        <p>
          {{ incompatible.map((target) => target.id).join(", ") }} use a model without this command.
          Remove them from the selection to stage. No targets are silently skipped.
        </p>
      </section>
      <div v-else-if="targets.length" class="study-compatibility">
        <span class="hero-check-circle study-icon" aria-hidden="true" />
        <span>Defined for all {{ targets.length }} selected endpoints</span>
      </div>
      <details class="study-definition">
        <summary>Definition &amp; endpoint details</summary>
        <dl v-for="target in targets" :key="target.id">
          <dt>{{ target.id }}</dt>
          <dd>{{ target.endpoint }} · Model {{ target.model }}</dd>
        </dl>
      </details>
    </div>
    <footer class="study-preparation-footer">
      <span class="study-fine-print">Draft preparation · approval and release follow</span>
      <CadenceButton
        id="study-stage-command"
        variant="primary"
        size="sm"
        :disabled="!canStage"
        @click="emit('stage')"
      >
        <span class="hero-plus study-icon" aria-hidden="true" />
        Stage for {{ targets.length }} spacecraft
      </CadenceButton>
    </footer>
  </section>
</template>
