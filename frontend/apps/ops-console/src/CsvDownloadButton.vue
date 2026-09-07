<script setup>
import CadenceButton from "@cadence/ui/CadenceButton.vue";

const props = defineProps({
  csv: { type: String, default: "" },
  filename: { type: String, default: "widget-data.csv" },
  disabled: { type: Boolean, default: false },
});

const downloadCsv = () => {
  const blob = new Blob([props.csv || ""], { type: "text/csv;charset=utf-8" });
  const url = URL.createObjectURL(blob);

  try {
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = props.filename || "widget-data.csv";
    anchor.click();
  } finally {
    URL.revokeObjectURL(url);
  }
};
</script>

<template>
  <CadenceButton
    id="dashboard-widget-inspect-download"
    type="button"
    :disabled="props.disabled"
    size="sm"
    variant="outline"
    class="justify-start"
    @click="downloadCsv"
    ><span class="hero-arrow-down-tray h-4 w-4"></span> Download CSV
  </CadenceButton>
</template>
