<script setup lang="ts">
import { computed, ref } from "vue";
import { codeOf, useRemoteQuery } from "@/api/index.ts";
import { ApButton, ApOption, ApSheet, ApTag } from "@/ui";
import {
  fetchPacketChoices,
  type ConfigurationDocument,
  type ConfigurationSnapshot,
  type WorkspaceKey,
} from "./api.ts";
import { catalogCounts, catalogRowTitle, droppedApidsLine, rowState } from "./catalog-words.ts";
import { packetsOffReason } from "./draft-words.ts";
import { catalogWord } from "./words.ts";

/**
 * #595b (U94; mms-ux): choose the draft's catalog revision. Radio rows, newest first, named by the
 * sheet's title; focus starts on the current one. A row's approval says whether it can be chosen
 * (rowState). Choosing one that doesn't define some handled APIDs says so first, and they go.
 */
const props = defineProps<{
  workspace: WorkspaceKey;
  snapshot: ConfigurationSnapshot;
  doc: ConfigurationDocument;
}>();
const emit = defineEmits<{ choose: [patch: Partial<ConfigurationDocument>] }>();
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
const picked = ref<string | null>(null);
const title = computed(() => `Choose a catalog revision for ${props.snapshot.name}`);
const activeId = computed(() => props.snapshot.active?.document.catalog_revision_id ?? null);
const rows = computed(() =>
  [...props.snapshot.catalogs]
    .sort((a, b) => (b.number ?? -1) - (a.number ?? -1))
    .map((c) => ({ c, state: rowState(c, activeId.value) })),
);

const packetsKey = computed(() =>
  picked.value && picked.value !== props.doc.catalog_revision_id
    ? { ...props.workspace, catalogRevisionId: picked.value }
    : null,
);
const packets = useRemoteQuery(packetsKey, (k, signal) =>
  fetchPacketChoices(k.missionId, k.spacecraftId, k.catalogRevisionId, signal),
);
const dropped = computed(() => {
  const st = packets.state.value;
  if (!packetsKey.value || st.status !== "ready") return [];
  const defined = new Set(st.value.packets.map((p) => p.apid));
  return props.doc.handled_apids.filter((a) => !defined.has(a));
});
const droppedLine = computed(() =>
  droppedApidsLine(catalogWord(props.snapshot, picked.value), dropped.value),
);
/** A6: Choose's reason, first that applies. */
const blocked = computed(() => {
  if (!picked.value || picked.value === props.doc.catalog_revision_id)
    return "Pick a different catalog revision first.";
  const st = packets.state.value;
  const read =
    st.status === "failed" ? { status: st.status, code: codeOf(st.error) } : { status: st.status };
  return packetsOffReason(
    props.snapshot,
    { ...props.doc, catalog_revision_id: picked.value },
    read,
  );
});

/** U20: a status the console doesn't know, said in Technical details. */
const unknown = computed(() =>
  rows.value.flatMap((r) =>
    r.state.technical ? [`${catalogRowTitle(r.c)}: ${r.state.technical}`] : [],
  ),
);
function open() {
  picked.value = props.doc.catalog_revision_id;
  sheet.value?.open();
}
function choose() {
  const id = picked.value;
  if (blocked.value !== null || !id) return;
  const gone = new Set(dropped.value);
  emit("choose", {
    catalog_revision_id: id,
    handled_apids: props.doc.handled_apids.filter((a) => !gone.has(a)),
  });
  sheet.value?.close();
}
defineExpose({ open });
</script>

<template>
  <ApSheet
    ref="sheet"
    :title="title"
    width="wide"
    initial-focus="input[type=radio]:checked, input[type=radio]"
  >
    <fieldset class="m-0 flex flex-col gap-2 border-0 p-0">
      <legend class="sr-only">{{ title }}</legend>
      <ApOption
        v-for="r in rows"
        :key="r.c.id"
        v-model="picked"
        :value="r.c.id"
        name="catalog-revision"
        :title="catalogRowTitle(r.c)"
        :description="[catalogCounts(r.c), r.state.line].filter(Boolean).join(' · ')"
        :disabled="!r.state.choosable"
      >
        <template v-if="r.state.tag" #tag><ApTag v-bind="r.state.tag" /></template>
      </ApOption>
    </fieldset>
    <details v-if="unknown.length" class="mt-2 text-sm">
      <summary class="ap-label cursor-pointer">Technical details</summary>
      <p v-for="u in unknown" :key="u" class="m-0 mt-1 font-mono text-xs text-text-3">{{ u }}</p>
    </details>
    <p v-if="droppedLine" class="m-0 mt-3 text-md text-caution-text">{{ droppedLine }}</p>
    <template #footer>
      <ApButton variant="ghost" @click="sheet?.close()">Cancel</ApButton>
      <ApButton :disabled="blocked !== null" :disabled-reason="blocked ?? undefined" @click="choose"
        >Choose</ApButton
      >
    </template>
  </ApSheet>
</template>
