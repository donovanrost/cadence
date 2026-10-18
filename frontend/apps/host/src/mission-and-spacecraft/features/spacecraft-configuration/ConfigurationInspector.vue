<script setup lang="ts">
import { computed, onBeforeUnmount, ref, watch } from "vue";
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import CadenceCheckbox from "@cadence/ui/CadenceCheckbox.vue";
import CadenceField from "@cadence/ui/CadenceField.vue";
import CadenceLink from "@cadence/ui/CadenceLink.vue";
import CadencePane from "@cadence/ui/CadencePane.vue";
import type {
  ConfigurationDocument,
  ConfigurationPort,
  ConfigurationSnapshot,
  Inspector,
  PacketChoices,
} from "./contracts";
const props = defineProps<{
  kind: Inspector;
  snapshot: ConfigurationSnapshot;
  draft: ConfigurationDocument;
  port: ConfigurationPort;
  busy: boolean;
}>();
const emit = defineEmits<{
  close: [];
  edit: [patch: Partial<ConfigurationDocument>];
  chooseCatalog: [];
}>();
const search = ref("");
const revisions = computed(() =>
  props.snapshot.catalogs.filter((item) =>
    `${item.name} ${item.label}`.toLowerCase().includes(search.value.toLowerCase()),
  ),
);
const selected = computed(() =>
  props.snapshot.catalogs.find((item) => item.id === props.draft.catalog_revision_id),
);
type PacketState =
  | { status: "idle" | "loading" }
  | { status: "ready"; value: PacketChoices }
  | { status: "failed"; message: string };
const packets = ref<PacketState>({ status: "idle" });
let generation = 0;
onBeforeUnmount(() => {
  generation++;
});
watch(
  () => [props.kind, props.draft.catalog_revision_id] as const,
  async ([kind, id]) => {
    const current = ++generation;
    if (kind !== "telemetry" || !id) {
      packets.value = { status: "idle" };
      return;
    }
    packets.value = { status: "loading" };
    try {
      const value = await props.port.catalog(id);
      if (generation === current) packets.value = { status: "ready", value };
    } catch (error) {
      if (generation === current)
        packets.value = {
          status: "failed",
          message: error instanceof Error ? error.message : "Packet definitions are unavailable.",
        };
    }
  },
  { immediate: true },
);
function toggleApid(apid: number, enabled: boolean) {
  emit("edit", {
    handled_apids: enabled
      ? [...props.draft.handled_apids, apid].sort((a, b) => a - b)
      : props.draft.handled_apids.filter((item) => item !== apid),
  });
}
function source(event: Event) {
  if (event.target instanceof HTMLSelectElement)
    emit("edit", { telemetry_source_endpoint_id: event.target.value || null });
}
function choose(id: string) {
  emit("edit", { catalog_revision_id: id, handled_apids: [] });
  emit("close");
}
</script>
<template>
  <aside class="scw-inspector" aria-label="Configuration inspector">
    <CadencePane
      id="spacecraft-inspector"
      :title="
        kind === 'catalog'
          ? 'Choose catalog'
          : kind === 'telemetry'
            ? 'Telemetry Decom'
            : 'Commanding'
      "
    >
      <template #title
        ><span id="spacecraft-inspector-focus" tabindex="-1">{{
          kind === "catalog"
            ? "Choose catalog"
            : kind === "telemetry"
              ? "Telemetry Decom"
              : "Commanding"
        }}</span></template
      >
      <template #actions
        ><CadenceButton
          size="sm"
          variant="quiet"
          aria-label="Close inspector"
          @click="$emit('close')"
          ><span class="hero-x-mark scw-icon" aria-hidden="true" /></CadenceButton
      ></template>
      <div class="scw-inspector-body scw-stack">
        <template v-if="kind === 'catalog'">
          <p class="scw-muted">Select the revision matching the software on {{ snapshot.name }}.</p>
          <CadenceField control-id="spacecraft-catalog-search" label="Search catalogs"
            ><input
              id="spacecraft-catalog-search"
              v-model="search"
              class="input input-sm w-full"
              type="search"
              placeholder="Name or revision"
          /></CadenceField>
          <div
            v-for="revision in revisions"
            :key="revision.id"
            class="scw-revision-option"
            :data-selected="draft.catalog_revision_id === revision.id"
          >
            <div class="scw-section-heading">
              <strong>{{ revision.name }}</strong
              ><code>{{ revision.label }}</code>
            </div>
            <p class="scw-muted">
              {{ revision.packets }} packets · {{ revision.commands }} commands
            </p>
            <div class="scw-actions">
              <CadenceLink :href="revision.href" target="_blank" rel="noopener"
                >Inspect revision<span class="sr-only"> (opens a new tab)</span></CadenceLink
              ><CadenceButton
                size="sm"
                :disabled="busy || draft.catalog_revision_id === revision.id"
                @click="choose(revision.id)"
                >{{
                  draft.catalog_revision_id === revision.id ? "Selected" : "Use in draft"
                }}</CadenceButton
              >
            </div>
          </div>
          <p v-if="!revisions.length" class="scw-muted">
            No matching imported catalogs.
            <CadenceLink :href="snapshot.links.catalog">Open Catalog</CadenceLink>
          </p>
        </template>
        <template v-else>
          <p class="scw-muted">
            {{
              kind === "telemetry"
                ? "Decode selected packets into measurements using this spacecraft’s catalog."
                : "Expose this spacecraft’s active command definitions in Ops."
            }}
          </p>
          <CadenceCheckbox
            :model-value="kind === 'telemetry' ? draft.telemetry_enabled : draft.commanding_enabled"
            :disabled="busy"
            @update:model-value="
              (value) =>
                $emit(
                  'edit',
                  kind === 'telemetry'
                    ? {
                        telemetry_enabled: value,
                        telemetry_source_endpoint_id:
                          draft.telemetry_source_endpoint_id ?? snapshot.sources[0]?.id ?? null,
                      }
                    : { commanding_enabled: value },
                )
            "
            >{{
              kind === "telemetry" ? "Enable Telemetry Decom" : "Enable Commanding"
            }}</CadenceCheckbox
          >
          <div class="scw-bound-catalog">
            <span class="scw-eyebrow">CATALOG BINDING</span
            ><strong>{{
              selected ? `${selected.name} · ${selected.label}` : "No catalog selected"
            }}</strong
            ><CadenceButton size="sm" variant="quiet" @click="$emit('chooseCatalog')">{{
              selected ? "Change revision" : "Choose catalog"
            }}</CadenceButton>
          </div>
          <template v-if="kind === 'telemetry' && draft.telemetry_enabled">
            <CadenceField control-id="spacecraft-packet-source" label="Packet source"
              ><select
                id="spacecraft-packet-source"
                class="select select-sm w-full"
                :value="draft.telemetry_source_endpoint_id ?? ''"
                :disabled="busy"
                @change="source"
              >
                <option value="">Select a source</option>
                <option v-for="source in snapshot.sources" :key="source.id" :value="source.id">
                  {{ source.name }}
                </option>
              </select></CadenceField
            >
            <p v-if="!snapshot.sources.length" class="scw-muted">
              Saving this catalog creates a spacecraft packet source. Connect its ingress path in
              <CadenceLink :href="snapshot.links.communications">Comms</CadenceLink>.
            </p>
            <div class="scw-block-heading scw-block-heading--plain">
              <h3>Packet inputs</h3>
              <span class="scw-count">{{ draft.handled_apids.length }} APIDs</span>
            </div>
            <p v-if="packets.status === 'loading'" role="status">Loading packet definitions…</p>
            <p v-else-if="packets.status === 'failed'" role="alert">{{ packets.message }}</p>
            <div v-else-if="packets.status === 'ready'" class="scw-packet-list">
              <CadenceCheckbox
                v-for="packet in packets.value.packets"
                :key="packet.apid"
                :model-value="draft.handled_apids.includes(packet.apid)"
                :disabled="busy"
                @update:model-value="(value) => toggleApid(packet.apid, value)"
                ><span
                  ><strong>{{ packet.name }}</strong
                  ><span class="scw-muted"
                    >APID {{ packet.apid }} · {{ packet.definitions }} definitions</span
                  ></span
                ></CadenceCheckbox
              >
              <p v-if="!packets.value.packets.length" class="scw-muted">
                This revision has no telemetry packets.
              </p>
            </div>
          </template>
          <p v-if="kind === 'commanding'" class="scw-note">
            Saving stages these settings. Ops uses the reviewed, active revision for each selected
            spacecraft.
          </p>
        </template>
      </div>
      <template #footer
        ><span>Editing {{ snapshot.name }}</span
        ><CadenceButton size="sm" @click="$emit('close')">Done</CadenceButton></template
      >
    </CadencePane>
  </aside>
</template>
