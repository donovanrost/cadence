<script lang="ts">
import { defineComponent, h, type PropType } from "vue";
import DefinitionsPanel from "./DefinitionsPanel.vue";
import { admitDocument, type DefinitionsPort } from "./contracts";
export default defineComponent({
  name: "DefinitionsSurface",
  inheritAttrs: false,
  props: {
    document: null,
    hostContext: null,
    port: { type: Object as PropType<DefinitionsPort>, required: true },
  },
  setup(props) {
    return () => {
      const page = admitDocument(props.document, props.hostContext);
      return page
        ? h(DefinitionsPanel, { initial: page, port: props.port })
        : h(
            "section",
            {
              id: "derived-contract-unavailable",
              role: "alert",
              class: "border border-warning/40 p-5 text-sm",
            },
            "Derived telemetry evidence is unavailable. Refresh to request the current scoped view.",
          );
    };
  },
});
</script>
