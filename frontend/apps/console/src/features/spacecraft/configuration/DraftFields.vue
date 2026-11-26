<script setup lang="ts">
import { computed } from "vue";
import { codeOf, useRemoteQuery } from "@/api/index.ts";
import { ApPanel, ApSelect } from "@/ui";
import ApidChips from "./ApidChips.vue";
import CatalogField from "./CatalogField.vue";
import {
  fetchPacketChoices,
  type ConfigurationDocument,
  type ConfigurationSnapshot,
  type WorkspaceKey,
} from "./api.ts";
import FramingFields from "./FramingFields.vue";
import { packetsOffReason } from "./draft-words.ts";

/**
 * #595a (U94): the draft's editable fields for one section. Catalog & applications: the catalog
 * revision (its picker, #595b), the packet source and the handled APIDs. Communications: framing.
 */
const props = defineProps<{
  workspace: WorkspaceKey;
  snapshot: ConfigurationSnapshot;
  doc: ConfigurationDocument;
  show: "catalog" | "communications";
  errors: Readonly<Record<string, string>>;
}>();
const emit = defineEmits<{
  edit: [patch: Partial<ConfigurationDocument>];
  invalid: [count: number];
}>();

const packetsKey = computed(() =>
  props.show === "catalog" && props.doc.catalog_revision_id
    ? { ...props.workspace, catalogRevisionId: props.doc.catalog_revision_id }
    : null,
);
const packets = useRemoteQuery(packetsKey, (k, signal) =>
  fetchPacketChoices(k.missionId, k.spacecraftId, k.catalogRevisionId, signal),
);
const packetsRead = computed(() => {
  const st = packets.state.value;
  return st.status === "failed"
    ? { status: st.status, code: codeOf(st.error) }
    : { status: st.status };
});
const offReason = computed(() => packetsOffReason(props.snapshot, props.doc, packetsRead.value));
const sourceOptions = computed(() =>
  props.snapshot.sources.map((x) => ({ value: x.id, label: x.name })),
);
</script>

<template>
  <ApPanel :title="show === 'catalog' ? 'Catalog & applications' : 'Communications'">
    <div class="flex flex-col gap-4 px-4 py-3">
      <template v-if="show === 'catalog'">
        <CatalogField
          :workspace="workspace"
          :snapshot="snapshot"
          :doc="doc"
          @edit="emit('edit', $event)"
        />
        <ApSelect
          :model-value="doc.telemetry_source_endpoint_id ?? ''"
          label="Packet source"
          placeholder="Choose a packet source…"
          :options="sourceOptions"
          :error="errors.telemetry_source_endpoint_id"
          @update:model-value="emit('edit', { telemetry_source_endpoint_id: $event || null })"
        />
        <ApidChips
          :apids="doc.handled_apids"
          :packets="packets.state.value.status === 'ready' ? packets.state.value.value : null"
          :unavailable="offReason"
          :error="errors.handled_apids"
          @change="emit('edit', { handled_apids: $event })"
        />
      </template>
      <FramingFields
        v-else
        :snapshot="snapshot"
        :protocol="doc.protocol"
        :errors="errors"
        @change="emit('edit', { protocol: $event })"
        @invalid="emit('invalid', $event)"
      />
    </div>
  </ApPanel>
</template>
