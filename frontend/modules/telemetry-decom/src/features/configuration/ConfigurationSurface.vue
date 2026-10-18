<script lang="ts">
import { defineComponent, h } from "vue";
import ConfigurationPanel from "./ConfigurationPanel.vue";
import { admitConfiguration } from "./contracts";

export default defineComponent({
  name: "ConfigurationSurface",
  inheritAttrs: false,
  props: {
    contract_version: null,
    context: null,
    configuration: null,
    review: null,
    page: null,
    card: null,
    status: null,
    revision: null,
    no_revisions: null,
    packet_handoff: null,
    preview: null,
    preflight: null,
    pending_activation: null,
    lifecycle_actions: null,
    hostContext: null,
    busy: Boolean,
  },
  emits: ["save_catalog_revision", "enable", "disable"],
  setup(props, { emit }) {
    return () => {
      const page = admitConfiguration(props, props.hostContext);
      if (!page)
        return h(
          "section",
          {
            id: "telemetry-decom-contract-unavailable",
            role: "alert",
            class: "card border border-warning/40 bg-base-200 p-6",
          },
          "Telemetry configuration is unavailable. Refresh this page to request current evidence.",
        );
      return h(ConfigurationPanel, {
        ...page,
        busy: props.busy,
        onSave_catalog_revision: (input) => emit("save_catalog_revision", input),
        onEnable: (input) => emit("enable", input),
        onDisable: (input) => emit("disable", input),
      });
    };
  },
});
</script>
