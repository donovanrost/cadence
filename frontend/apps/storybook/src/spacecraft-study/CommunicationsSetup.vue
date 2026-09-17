<script setup lang="ts">
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import CadenceStatusSymbol from "@cadence/ui/CadenceStatusSymbol.vue";
import type { Configuration, Inspector } from "./fixtures";
defineProps<{ draft: Configuration }>();
defineEmits<{
  edit: [patch: Partial<Configuration>];
  preset: [];
  inspect: [inspector: Inspector, event: MouseEvent];
}>();
</script>

<template>
  <div class="sc-stack sc-stack--large">
    <div class="sc-section-heading">
      <div>
        <p class="sc-eyebrow">BYTES IN & OUT</p>
        <h2>Communications</h2>
        <p class="sc-muted">
          Configure this spacecraft’s framing and connect it to mission delivery paths.
        </p>
      </div>
    </div>
    <div class="sc-preset">
      <span class="hero-adjustments-horizontal sc-icon-lg" aria-hidden="true" />
      <div>
        <strong>A familiar bus? Start from a preset.</strong>
        <p>
          Kestrel bus · TM downlink / TC uplink. Copy the framing settings, then adjust them here.
        </p>
      </div>
      <CadenceButton size="sm" @click="$emit('preset')">Use Kestrel bus preset</CadenceButton>
    </div>
    <section class="sc-surface" aria-labelledby="sc-framing-title">
      <header class="sc-block-heading">
        <h3 id="sc-framing-title">Framing</h3>
        <span class="sc-muted">Owned by this spacecraft</span>
      </header>
      <div class="sc-protocol-row">
        <span class="sc-direction"
          ><span class="hero-arrow-down sc-icon" aria-hidden="true"
        /></span>
        <div>
          <strong>Downlink</strong>
          <p class="sc-muted">Frames received from the spacecraft</p>
        </div>
        <div class="sc-segmented" role="group" aria-label="Downlink framing">
          <button
            v-for="protocol in ['TM', 'AOS'] as const"
            :key="protocol"
            type="button"
            :aria-pressed="draft.downlink === protocol"
            @click="$emit('edit', { downlink: protocol })"
          >
            {{ protocol }}
          </button>
        </div>
      </div>
      <div class="sc-protocol-row">
        <span class="sc-direction"><span class="hero-arrow-up sc-icon" aria-hidden="true" /></span>
        <div>
          <strong>Uplink</strong>
          <p class="sc-muted">Frames sent to the spacecraft</p>
        </div>
        <div class="sc-segmented" role="group" aria-label="Uplink framing">
          <button
            type="button"
            :aria-pressed="draft.uplink === 'TC'"
            @click="$emit('edit', { uplink: 'TC' })"
          >
            TC
          </button>
        </div>
      </div>
      <div v-if="draft.downlink || draft.uplink" class="sc-framing-detail">
        <span
          ><span class="sc-eyebrow">DOWNLINK FRAME</span
          ><code>{{
            draft.downlink === "AOS" ? "2,048 bytes" : draft.downlink ? "1,024 bytes" : "Not set"
          }}</code></span
        ><span><span class="sc-eyebrow">PACKET DELIVERY</span><code>OBC · VC 0</code></span
        ><span
          ><span class="sc-eyebrow">UPLINK FORMAT</span
          ><code>{{ draft.uplink ? "TC · sequence controlled" : "Not set" }}</code></span
        >
      </div>
    </section>
    <section class="sc-surface" aria-labelledby="sc-delivery-title">
      <header class="sc-block-heading">
        <h3 id="sc-delivery-title">Delivery path</h3>
        <span class="sc-tag"
          ><CadenceStatusSymbol :status="draft.route ? 'normal' : 'standby'" />{{
            draft.route ? "Connected in draft" : "Not connected"
          }}</span
        >
      </header>
      <div class="sc-binding">
        <span class="sc-resource-icon"
          ><span class="hero-signal sc-icon-lg" aria-hidden="true"
        /></span>
        <div class="sc-binding-copy">
          <h3>S-band · primary</h3>
          <p class="sc-muted">Mission transport · downlink and uplink</p>
        </div>
        <CadenceButton size="sm" variant="quiet" @click="$emit('inspect', 'route', $event)"
          >Inspect path</CadenceButton
        ><CadenceButton
          size="sm"
          :variant="draft.route ? 'secondary' : 'primary'"
          @click="$emit('edit', { route: draft.route ? null : 's-band' })"
          >{{ draft.route ? "Disconnect path" : "Connect path" }}</CadenceButton
        >
      </div>
      <div v-if="draft.route" class="sc-delivery-flow" aria-label="Configured delivery">
        <span>Ground station</span><span aria-hidden="true">↔</span><strong>S-band</strong
        ><span aria-hidden="true">↔</span><span>Spacecraft · OBC</span>
      </div>
      <p class="sc-section-note">
        Mission transports are shared. This connection and its spacecraft routing are part of this
        spacecraft’s configuration.
      </p>
    </section>
  </div>
</template>
