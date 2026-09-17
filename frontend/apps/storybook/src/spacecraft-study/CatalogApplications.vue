<script setup lang="ts">
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import CadenceLink from "@cadence/ui/CadenceLink.vue";
import CadenceStatusSymbol from "@cadence/ui/CadenceStatusSymbol.vue";
import { revisions, type Configuration, type Inspector } from "./fixtures";
import { catalogPath } from "./navigation";
defineProps<{
  spacecraft: string;
  draft: Configuration;
  active: Configuration | null;
  missionNavigation: boolean;
}>();
defineEmits<{ inspect: [inspector: Inspector, event: MouseEvent] }>();
</script>

<template>
  <div class="sc-stack sc-stack--large">
    <div class="sc-section-heading">
      <div>
        <p class="sc-eyebrow">DEFINITIONS & CONSUMERS</p>
        <h2>Catalog & applications</h2>
        <p class="sc-muted">
          Choose the definitions for this onboard computer. Its applications use the same binding.
        </p>
      </div>
      <CadenceLink v-if="missionNavigation" :href="catalogPath"
        >Mission catalog<span class="sr-only"> usage</span
        ><template #icon><span class="hero-arrow-up-right" /></template
      ></CadenceLink>
    </div>
    <section class="sc-surface" aria-labelledby="sc-binding-title">
      <header class="sc-block-heading">
        <h3 id="sc-binding-title">Onboard computer</h3>
        <span class="sc-muted">{{ spacecraft }}</span>
      </header>
      <div class="sc-binding">
        <span class="sc-resource-icon"
          ><span class="hero-square-3-stack-3d sc-icon-lg" aria-hidden="true"
        /></span>
        <div class="sc-binding-copy">
          <span class="sc-eyebrow">FLIGHT SOFTWARE CATALOG</span>
          <h3>{{ draft.catalog ? "Kestrel FSW" : "Bind your flight software catalog" }}</h3>
          <span class="sc-muted">{{
            draft.catalog
              ? revisions[draft.catalog].software
              : "An imported catalog supplies command and telemetry definitions."
          }}</span>
        </div>
        <span v-if="draft.catalog" class="sc-revision">r{{ draft.catalog }}</span>
        <CadenceButton
          size="sm"
          :variant="draft.catalog ? 'secondary' : 'primary'"
          @click="$emit('inspect', 'catalog', $event)"
          >{{ draft.catalog ? "Change revision" : "Choose catalog" }}</CadenceButton
        >
      </div>
      <div v-if="draft.catalog" class="sc-definition-counts">
        <span
          ><strong>{{ revisions[draft.catalog].packets }}</strong> packets</span
        ><span
          ><strong>{{ revisions[draft.catalog].parameters }}</strong> parameters</span
        ><span
          ><strong>{{ revisions[draft.catalog].commands }}</strong> commands</span
        >
        <span class="sc-binding-state">{{
          active?.catalog === draft.catalog
            ? "Matches active binding"
            : active?.catalog
              ? `Draft binding · active r${active.catalog}`
              : "Draft binding · not yet active"
        }}</span>
      </div>
    </section>

    <section aria-labelledby="sc-applications-title">
      <header class="sc-block-heading sc-block-heading--plain">
        <div>
          <h3 id="sc-applications-title">Applications</h3>
          <p class="sc-muted">Enable a capability, then connect its inputs.</p>
        </div>
        <span class="sc-count"
          >{{ Number(draft.telemetryEnabled) + Number(draft.commandingEnabled) }} / 2 enabled</span
        >
      </header>
      <div class="sc-application-list">
        <button
          type="button"
          class="sc-application"
          aria-label="Configure Telemetry Decom"
          @click="$emit('inspect', 'telemetry', $event)"
        >
          <span class="sc-resource-icon"
            ><span class="hero-chart-bar sc-icon-lg" aria-hidden="true"
          /></span>
          <span class="sc-application-copy"
            ><strong>Telemetry Decom</strong
            ><span>Turn incoming packets into named, typed measurements.</span
            ><span v-if="draft.telemetryEnabled" class="sc-application-binding"
              >{{ draft.catalog ? `Kestrel FSW r${draft.catalog}` : "No catalog"
              }}<span aria-hidden="true"> · </span
              >{{ draft.telemetryInput ? "OBC downlink · VC 0" : "Packet input needed" }}</span
            ></span
          >
          <span class="sc-tag"
            ><CadenceStatusSymbol
              :status="
                !draft.telemetryEnabled ? 'off' : draft.telemetryInput ? 'normal' : 'caution'
              "
            />{{
              !draft.telemetryEnabled
                ? "Not enabled"
                : draft.telemetryInput
                  ? "Configured"
                  : "Needs input"
            }}</span
          ><span class="hero-chevron-right sc-icon-sm" aria-hidden="true" />
        </button>
        <button
          type="button"
          class="sc-application"
          aria-label="Configure Commanding"
          @click="$emit('inspect', 'commanding', $event)"
        >
          <span class="sc-resource-icon"
            ><span class="hero-command-line sc-icon-lg" aria-hidden="true"
          /></span>
          <span class="sc-application-copy"
            ><strong>Commanding</strong
            ><span>Build and validate commands for the onboard computer.</span
            ><span v-if="draft.commandingEnabled && draft.catalog" class="sc-application-binding"
              >Kestrel FSW r{{ draft.catalog }} · {{ revisions[draft.catalog].commands }} command
              definitions</span
            ></span
          >
          <span class="sc-tag"
            ><CadenceStatusSymbol :status="draft.commandingEnabled ? 'normal' : 'off'" />{{
              draft.commandingEnabled ? "Configured" : "Not enabled"
            }}</span
          ><span class="hero-chevron-right sc-icon-sm" aria-hidden="true" />
        </button>
      </div>
      <p class="sc-section-note">
        Application settings belong to {{ spacecraft }}. Changing this binding leaves the rest of
        the fleet on its own revisions.
      </p>
    </section>
    <div class="sc-inline-context">
      <span class="hero-arrow-path-rounded-square sc-icon" aria-hidden="true" />
      <div>
        <strong>One change, explicit impact</strong>
        <p>
          A catalog revision change updates the definitions used by enabled applications together.
          Review shows the affected consumers before activation.
        </p>
      </div>
    </div>
  </div>
</template>
