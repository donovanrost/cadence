<script setup lang="ts">
import { onBeforeUnmount, onMounted } from "vue";
const props = withDefaults(defineProps<{ editor_dirty?: boolean }>(), { editor_dirty: false });
function beforeUnload(event: BeforeUnloadEvent) {
  if (!props.editor_dirty) return;
  event.preventDefault();
  event.returnValue = "";
}
function documentClick(event: MouseEvent) {
  if (!props.editor_dirty || !(event.target instanceof Element)) return;
  const anchor = event.target.closest("a[href]");
  if (!anchor || anchor.hasAttribute("data-editor-discard")) return;
  if (anchor.getAttribute("target") === "_blank" || anchor.hasAttribute("download")) return;
  if (!window.confirm("Discard unsaved dashboard changes and leave the Editor?")) {
    event.preventDefault();
    event.stopImmediatePropagation();
  }
}
onMounted(() => {
  window.addEventListener("beforeunload", beforeUnload);
  document.addEventListener("click", documentClick, true);
});
onBeforeUnmount(() => {
  window.removeEventListener("beforeunload", beforeUnload);
  document.removeEventListener("click", documentClick, true);
});
</script>

<template>
  <span
    data-dashboard-editor-guard
    :data-editor-dirty="String(props.editor_dirty)"
    aria-hidden="true"
    hidden
  ></span>
</template>
