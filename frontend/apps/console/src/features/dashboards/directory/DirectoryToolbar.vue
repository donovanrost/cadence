<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { ApField, ApSegmented, ApSelect } from "@/ui";
import type { DirectoryQuery } from "./api.ts";

/** Search (debounced into the URL), sort, the All / Starred / Archived view, and tag filters. */
const props = defineProps<{ query: DirectoryQuery; tags: readonly string[] }>();
const emit = defineEmits<{ set: [changes: Record<string, string | null>] }>();
const q = ref(props.query.q);
let timer: ReturnType<typeof setTimeout> | undefined;
watch(q, (value) => {
  clearTimeout(timer);
  timer = setTimeout(() => emit("set", { q: value.trim() || null }), 300);
});
const view = computed({
  get: () => (props.query.starred ? "starred" : props.query.archived ? "archived" : "all"),
  set: (v: "all" | "starred" | "archived") =>
    emit("set", { starred: v === "starred" ? "1" : null, archived: v === "archived" ? "1" : null }),
});
const sort = computed({
  get: () => props.query.sort,
  set: (v: string) => emit("set", { sort: v === "updated" ? null : v }),
});
const tag = computed({
  get: () => props.query.tags[0] ?? "",
  set: (v: string) => emit("set", { tags: v || null }),
});
const tagOptions = computed(() => [
  { value: "", label: "All tags" },
  ...props.tags.map((t) => ({ value: t, label: t })),
]);
</script>

<template>
  <div class="flex flex-wrap items-end gap-3">
    <ApField
      v-model="q"
      type="search"
      label="Search dashboards"
      hidden-label
      placeholder="Search dashboards"
      class="min-w-[240px] flex-1"
    />
    <ApSegmented
      v-model="view"
      label="Show"
      variant="micro"
      :options="[
        { value: 'all', label: 'All' },
        { value: 'starred', label: 'Starred' },
        { value: 'archived', label: 'Archived' },
      ]"
    />
    <ApSelect v-model="tag" label="Tag" hidden-label size="compact" :options="tagOptions" />
    <ApSelect
      v-model="sort"
      label="Sort"
      hidden-label
      size="compact"
      :options="[
        { value: 'updated', label: 'Recently updated' },
        { value: 'name', label: 'Name A–Z' },
        { value: 'name_desc', label: 'Name Z–A' },
      ]"
    />
  </div>
</template>
