<script setup lang="ts">
import { ref, watch } from "vue";
import CadenceButton from "./CadenceButton.vue";
import CadenceSpinner from "./CadenceSpinner.vue";

const props = withDefaults(
  defineProps<{
    root: HTMLElement | null;
    hasMore: boolean;
    loading: boolean;
    disabled?: boolean;
    error?: string;
    label?: string;
  }>(),
  { disabled: false, error: "", label: "Loading more results…" },
);
const emit = defineEmits<{ loadMore: []; retry: [] }>();
const sentinel = ref<HTMLElement | null>(null);
watch(
  [
    () => props.root,
    sentinel,
    () => props.loading,
    () => props.disabled,
    () => props.error,
    () => props.hasMore,
  ],
  ([root, element, loading, disabled, error, hasMore], _, onCleanup) => {
    if (!root || !element || loading || disabled || error || !hasMore) return;
    let requested = false;
    let active = true;
    const observer = new IntersectionObserver(
      (entries) => {
        if (active && !requested && entries.some((entry) => entry.isIntersecting)) {
          requested = true;
          emit("loadMore");
        }
      },
      { root, rootMargin: "0px 0px 160px 0px" },
    );
    observer.observe(element);
    onCleanup(() => {
      active = false;
      observer.disconnect();
    });
  },
  { flush: "post" },
);
</script>
<template>
  <div ref="sentinel" class="cadence-infinite-scroll" :aria-busy="loading">
    <span v-if="loading" role="status"><CadenceSpinner size="sm" />{{ label }}</span>
    <span v-else-if="error" role="status">
      {{ error
      }}<CadenceButton size="xs" variant="quiet" :disabled="disabled" @click="emit('retry')"
        >Retry</CadenceButton
      >
    </span>
  </div>
</template>
<style scoped>
.cadence-infinite-scroll {
  min-height: 1px;
  color: var(--text-subtle);
  font-size: 11px;
}
.cadence-infinite-scroll > span {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  padding: 10px;
}
</style>
