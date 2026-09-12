<script setup>
import { onBeforeUnmount, onMounted } from "vue";

const DashboardEditorGuardController = {
  mounted() {
    this.beforeUnload = (event) => {
      if (!this.dirty()) return;

      event.preventDefault();
      event.returnValue = "";
    };

    this.documentClick = (event) => {
      if (!this.dirty()) return;

      const anchor = event.target.closest?.("a[href]");
      if (!anchor || anchor.hasAttribute("data-editor-discard")) return;
      if (anchor.target === "_blank" || anchor.hasAttribute("download")) return;

      if (!window.confirm("Discard unsaved dashboard changes and leave the Editor?")) {
        event.preventDefault();
        event.stopImmediatePropagation();
      }
    };

    window.addEventListener("beforeunload", this.beforeUnload);
    document.addEventListener("click", this.documentClick, true);
  },

  destroyed() {
    window.removeEventListener("beforeunload", this.beforeUnload);
    document.removeEventListener("click", this.documentClick, true);
  },

  dirty() {
    return this.dirtyValue();
  },
};

const props = defineProps({
  editor_dirty: { type: Boolean, default: false },
});

let controller = null;

onMounted(() => {
  controller = Object.create(DashboardEditorGuardController);
  controller.dirtyValue = () => props.editor_dirty;
  controller.mounted();
});

onBeforeUnmount(() => {
  controller?.destroyed();
  controller = null;
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
