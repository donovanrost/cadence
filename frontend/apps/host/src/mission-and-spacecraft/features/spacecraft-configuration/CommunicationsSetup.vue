<script setup lang="ts">
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import CadenceCheckbox from "@cadence/ui/CadenceCheckbox.vue";
import CadenceField from "@cadence/ui/CadenceField.vue";
import CadenceLink from "@cadence/ui/CadenceLink.vue";
import type { ConfigurationDocument, ConfigurationSnapshot, Protocol } from "./contracts";
const props = defineProps<{
  snapshot: ConfigurationSnapshot;
  draft: ConfigurationDocument;
  busy: boolean;
}>();
const emit = defineEmits<{ edit: [patch: Partial<ConfigurationDocument>] }>();
function protocol(patch: Partial<Protocol>) {
  if (props.draft.protocol) emit("edit", { protocol: { ...props.draft.protocol, ...patch } });
}
function number(
  event: Event,
  key: "frame_size" | "secondary_header_length" | "insert_zone_length",
) {
  if (event.target instanceof HTMLInputElement) protocol({ [key]: event.target.valueAsNumber });
}
function preset(event: Event) {
  if (event.target instanceof HTMLSelectElement) {
    const selectedValue = event.target.value;
    const selected = props.snapshot.presets.find(
      (item) => `${item.id}/${item.version}` === selectedValue,
    );
    if (selected) emit("edit", { protocol: selected.protocol });
  }
}
function select(event: Event, key: "downlink" | "uplink" | "ocf_length") {
  if (!(event.target instanceof HTMLSelectElement)) return;
  const value = event.target.value;
  if (key === "downlink" && (value === "tm" || value === "aos" || value === "uslp"))
    protocol({ downlink: value });
  if (key === "uplink" && (value === "tc" || value === "uslp")) protocol({ uplink: value });
  if (key === "ocf_length" && (value === "0" || value === "4"))
    protocol({ ocf_length: value === "4" ? 4 : 0 });
}
</script>
<template>
  <div class="scw-stack">
    <div class="scw-section-heading">
      <div>
        <p class="scw-eyebrow">LINK INTERPRETATION & DELIVERY</p>
        <h2>Communications</h2>
        <p class="scw-muted">
          Configure this spacecraft’s framing, then connect its paths in Comms.
        </p>
      </div>
      <CadenceLink :href="snapshot.links.communications"
        >Open Comms<template #icon><span class="hero-arrow-up-right" /></template
      ></CadenceLink>
    </div>
    <section class="scw-surface">
      <header class="scw-block-heading">
        <h3>Framing</h3>
        <span class="scw-muted">{{ snapshot.name }}</span>
      </header>
      <div class="scw-block-body scw-stack">
        <CadenceField
          v-if="snapshot.presets.length"
          control-id="spacecraft-protocol-preset"
          label="Copy an optional protocol preset"
          ><select
            id="spacecraft-protocol-preset"
            class="select select-sm"
            value=""
            :disabled="busy"
            @change="preset"
          >
            <option value="">Choose a starting point</option>
            <option
              v-for="item in snapshot.presets"
              :key="`${item.id}/${item.version}`"
              :value="`${item.id}/${item.version}`"
            >
              {{ item.name }} · v{{ item.version }}
            </option></select
          ><template #help
            ><p class="scw-muted">
              Copies the preset into this draft. Future preset changes do not change this
              spacecraft.
            </p></template
          ></CadenceField
        >
        <template v-if="draft.protocol"
          ><div class="scw-form-grid">
            <CadenceField control-id="spacecraft-downlink" label="Downlink protocol"
              ><select
                id="spacecraft-downlink"
                class="select select-sm"
                :value="draft.protocol.downlink"
                :disabled="busy"
                @change="select($event, 'downlink')"
              >
                <option value="tm">TM</option>
                <option value="aos">AOS</option>
                <option value="uslp">USLP</option>
              </select></CadenceField
            >
            <CadenceField control-id="spacecraft-uplink" label="Uplink protocol"
              ><select
                id="spacecraft-uplink"
                class="select select-sm"
                :value="draft.protocol.uplink"
                :disabled="busy"
                @change="select($event, 'uplink')"
              >
                <option value="tc">TC</option>
                <option value="uslp">USLP</option>
              </select></CadenceField
            >
            <CadenceField control-id="spacecraft-frame-size" label="Frame size (bytes)"
              ><input
                id="spacecraft-frame-size"
                type="number"
                class="input input-sm"
                min="1"
                max="65536"
                :value="draft.protocol.frame_size"
                :disabled="busy"
                @input="number($event, 'frame_size')"
            /></CadenceField>
            <CadenceField control-id="spacecraft-secondary-header" label="Secondary header (bytes)"
              ><input
                id="spacecraft-secondary-header"
                type="number"
                class="input input-sm"
                min="0"
                max="255"
                :value="draft.protocol.secondary_header_length"
                :disabled="busy"
                @input="number($event, 'secondary_header_length')"
            /></CadenceField>
            <CadenceField control-id="spacecraft-insert-zone" label="Insert zone (bytes)"
              ><input
                id="spacecraft-insert-zone"
                type="number"
                class="input input-sm"
                min="0"
                max="65535"
                :value="draft.protocol.insert_zone_length"
                :disabled="busy"
                @input="number($event, 'insert_zone_length')"
            /></CadenceField>
            <CadenceField control-id="spacecraft-ocf" label="Operational control field"
              ><select
                id="spacecraft-ocf"
                class="select select-sm"
                :value="draft.protocol.ocf_length"
                :disabled="busy"
                @change="select($event, 'ocf_length')"
              >
                <option value="0">Absent</option>
                <option value="4">4 bytes</option>
              </select></CadenceField
            >
          </div>
          <CadenceCheckbox
            :model-value="draft.protocol.truncated_primary_header"
            :disabled="busy"
            @update:model-value="(value) => protocol({ truncated_primary_header: value })"
            >Truncated primary header</CadenceCheckbox
          ></template
        >
        <div v-else class="scw-empty">
          <span class="hero-signal scw-icon" aria-hidden="true" />
          <p>Choose framing directly or copy a protocol preset.</p>
          <CadenceButton
            size="sm"
            :disabled="busy"
            @click="
              $emit('edit', {
                protocol: {
                  downlink: 'tm',
                  uplink: 'tc',
                  frame_size: 1115,
                  secondary_header_length: 0,
                  insert_zone_length: 0,
                  ocf_length: 0,
                  truncated_primary_header: false,
                },
              })
            "
            >Configure framing</CadenceButton
          >
        </div>
      </div>
    </section>
    <section class="scw-surface">
      <header class="scw-block-heading">
        <h3>Packet sources & delivery paths</h3>
        <CadenceLink :href="snapshot.links.communications">Configure in Comms</CadenceLink>
      </header>
      <div class="scw-block-body scw-stack">
        <p>
          {{ snapshot.sources.length }} packet
          {{ snapshot.sources.length === 1 ? "source" : "sources" }} associated with this
          spacecraft.
        </p>
        <p class="scw-muted">
          Transports, channel routing, and delivery policy are managed in Comms. Review the
          spacecraft’s operational readiness before command execution.
        </p>
        <CadenceLink :href="snapshot.links.readiness">Check spacecraft readiness</CadenceLink>
      </div>
    </section>
  </div>
</template>
