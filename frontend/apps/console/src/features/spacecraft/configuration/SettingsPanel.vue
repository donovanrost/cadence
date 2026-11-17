<script setup lang="ts">
import { computed } from "vue";
import { ApKeyValue, ApPanel, type ApKeyValueItem } from "@/ui";
import type { ConfigurationSnapshot } from "./api.ts";
import { apidsWord, catalogWord, framingWord, sourceWord } from "./words.ts";

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
const title = computed(() =>
  props.show === "catalog"
    ? "Catalog & applications"
    : props.show === "communications"
      ? "Communications"
      : "Draft",
);
</script>

<template>
  <ApPanel index="C1" :title="title" flush>
    <div class="px-4 py-3"><ApKeyValue :items="items" /></div>
  </ApPanel>
</template>
