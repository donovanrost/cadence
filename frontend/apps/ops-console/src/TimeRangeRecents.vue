<script setup>
import { onMounted } from "vue";
import { useOpsEvent } from "./ops-events";

const STORAGE_KEY = "cadence:dashboard-time-recents";
const MAX_RECENTS = 4;

const props = defineProps({
  ranges: { type: Array, default: () => [] },
});

const emit = defineEmits(["recents-loaded", "select-range"]);

const readRecents = () => {
  try {
    const parsed = JSON.parse(localStorage.getItem(STORAGE_KEY));
    if (!Array.isArray(parsed)) return [];

    return parsed
      .filter((range) => range && typeof range.from === "string" && typeof range.to === "string")
      .slice(0, MAX_RECENTS);
  } catch (_error) {
    return [];
  }
};

const pushRecents = (ranges) => emit("recents-loaded", { ranges });

const storeRecent = ({ from, to }) => {
  if (typeof from !== "string" || typeof to !== "string") return;

  const deduped = readRecents().filter((range) => range.from !== from || range.to !== to);
  const recents = [{ from, to }, ...deduped].slice(0, MAX_RECENTS);

  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(recents));
  } catch (_error) {
    // Storage may be unavailable (private browsing quota); the current
    // LiveView session still receives the updated list.
  }

  pushRecents(recents);
};

const selectRange = (range) => {
  emit("select-range", { from: range.from, to: range.to });
};

useOpsEvent("cadence:store-time-recent", (payload) => storeRecent(payload));
onMounted(() => pushRecents(readRecents()));
</script>

<template>
  <p class="text-xs font-semibold text-base-content/85">Recently used absolute ranges</p>
  <p v-if="props.ranges.length === 0" class="mt-1 text-[0.68rem] text-base-content/60">
    Apply an absolute range and it will appear here for quick reuse.
  </p>
  <ul v-else class="mt-1" role="presentation">
    <li v-for="range in props.ranges" :key="`${range.from}:${range.to}`">
      <button
        type="button"
        data-dashboard-time-recent-range
        class="w-full truncate px-1 py-0.5 text-left font-mono text-[0.68rem] text-base-content/70 hover:bg-base-300/40 hover:text-base-content"
        :title="`Apply ${range.from} to ${range.to}`"
        @click="selectRange(range)"
      >
        {{ range.label }}
      </button>
    </li>
  </ul>
</template>
