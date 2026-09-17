<script setup lang="ts">
import { computed, ref } from "vue";
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import { revisions, type Configuration } from "./fixtures";
const props = defineProps<{ spacecraft: string; active: Configuration; draft: Configuration }>();
defineEmits<{ back: [] }>();
const selected = ref("NOOP");
const commands = computed(() => [
  { id: "NOOP", description: "Verify command reception", system: "C&DH" },
  { id: "SET_TLM_RATE", description: "Set housekeeping cadence", system: "C&DH" },
  { id: "SET_ATTITUDE", description: "Set attitude control mode", system: "ADCS" },
  ...(props.active.catalog === "3.4"
    ? [{ id: "CAPTURE_IMAGE", description: "Acquire an image", system: "Payload" }]
    : []),
]);
</script>

<template>
  <div class="sc-stack sc-stack--large">
    <div class="sc-section-heading">
      <div>
        <p class="sc-eyebrow">OPS HANDOFF / PREVIEW</p>
        <h2>Commanding · {{ spacecraft }}</h2>
        <p class="sc-muted">Explore the commands supplied by this spacecraft’s active catalog.</p>
      </div>
      <CadenceButton size="sm" @click="$emit('back')">Back to spacecraft</CadenceButton>
    </div>
    <div class="sc-active-context">
      <span class="hero-command-line sc-icon-lg" aria-hidden="true" />
      <div>
        <strong>{{ spacecraft }} · onboard computer</strong
        ><span data-testid="sc-ops-binding"
          >Active Kestrel FSW r{{ active.catalog }} ·
          {{ active.catalog ? revisions[active.catalog].commands : 0 }} command definitions</span
        >
      </div>
      <span class="sc-tag">Active definitions</span>
    </div>
    <p v-if="draft.catalog !== active.catalog" class="sc-issues sc-block-body">
      Draft r{{ draft.catalog }} is not active. Command discovery continues to use r{{
        active.catalog
      }}
      until activation.
    </p>
    <div class="sc-ops-preview">
      <section class="sc-surface">
        <header class="sc-block-heading">
          <h3>Command catalog</h3>
          <span class="sc-muted">Sample definitions</span>
        </header>
        <button
          v-for="command in commands"
          :key="command.id"
          type="button"
          class="sc-command-row"
          :aria-pressed="selected === command.id"
          @click="selected = command.id"
        >
          <span class="hero-command-line sc-icon" aria-hidden="true" /><span
            ><code>{{ command.id }}</code
            ><span>{{ command.description }}</span></span
          ><span class="sc-muted">{{ command.system }}</span>
        </button>
      </section>
      <section class="sc-surface sc-block-body sc-stack">
        <p class="sc-eyebrow">SELECTED DEFINITION</p>
        <h3>
          <code>{{ selected }}</code>
        </h3>
        <dl class="sc-facts sc-facts--inset">
          <div>
            <dt>Target</dt>
            <dd>{{ spacecraft }}</dd>
          </div>
          <div>
            <dt>Definition basis</dt>
            <dd>Kestrel FSW r{{ active.catalog }}</dd>
          </div>
        </dl>
        <p class="sc-muted">
          The production handoff would open the commanding workspace with this target selected.
        </p>
        <p class="sc-section-note">
          This study ends at command discovery. Preparation, staging and execution are covered by
          the Commanding study.
        </p>
      </section>
    </div>
  </div>
</template>
