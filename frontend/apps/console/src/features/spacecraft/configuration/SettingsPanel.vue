<script setup lang="ts">
import { computed } from "vue";
import { RouterLink } from "vue-router";
import { ApKeyValue, ApPanel, type ApKeyValueItem } from "@/ui";
import type { ConfigurationSnapshot } from "./api.ts";
import { compositionTitle, isComposed, madeOfLine } from "@/features/catalog/composition.ts";
import { apidsWord, catalogWord, changesFromLine, framingWord, sourceWord } from "./words.ts";

/**
 * The draft's settings, read-only until the draft routes land (lead: read side first). Which
 * appear follows the section: catalog & applications, communications, or both on the overview.
 */
const props = defineProps<{
  snapshot: ConfigurationSnapshot;
  show: "all" | "catalog" | "communications";
}>();
const items = computed((): readonly ApKeyValueItem[] => {
  const s = props.snapshot;
  const d = s.document;
  const catalog: ApKeyValueItem[] = [
    { key: "catalog", label: "Catalog revision", value: catalogWord(s, d.catalog_revision_id) },
    { key: "source", label: "Packet source", value: sourceWord(s, d.telemetry_source_endpoint_id) },
    { key: "apids", label: "Handled APIDs", value: apidsWord(d.handled_apids), mono: true },
  ];
  const comms: ApKeyValueItem[] = [
    { key: "framing", label: "Framing", value: framingWord(d.protocol), mono: true },
  ];
  return props.show === "catalog"
    ? catalog
    : props.show === "communications"
      ? comms
      : [...catalog, ...comms];
});
/** U94: on the Overview, the draft's pointer to the Changes tab ("2 changes from v3 · Review"). */
const changes = computed(() => (props.show === "all" ? changesFromLine(props.snapshot) : null));
const title = computed(() =>
  props.show === "catalog"
    ? "Catalog & applications"
    : props.show === "communications"
      ? "Communications"
      : "Draft",
);
</script>

<template>
  <ApPanel index="C2" :title="title" flush>
    <template v-if="changes" #meta>
      <span class="font-mono text-xs normal-case text-caution-text">{{ changes }}</span>
      <RouterLink
        :to="{
          name: 'setup.spacecraft.configuration',
          params: { spacecraftId: snapshot.spacecraft_id, section: 'changes' },
        }"
        class="max-md:hit-44 ml-2 text-sm text-readout underline hover:text-bright"
        >Review</RouterLink
      >
    </template>
    <div class="px-4 py-3">
      <ApKeyValue :items="items">
        <!-- U109: the field keeps its label and reads Composition 3, with Made of under it;
          with no number, Made of alone (mms-ux on #609). -->
        <template v-if="isComposed(snapshot.composition)" #value-catalog>
          <template v-if="compositionTitle(snapshot.composition)">
            {{ compositionTitle(snapshot.composition) }}
            <span class="block text-sm text-text-3">{{ madeOfLine(snapshot.composition) }}</span>
          </template>
          <template v-else>{{ madeOfLine(snapshot.composition) }}</template>
        </template>
      </ApKeyValue>
    </div>
  </ApPanel>
</template>
