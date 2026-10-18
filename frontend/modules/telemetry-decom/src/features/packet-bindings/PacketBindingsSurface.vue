<script lang="ts">
import { defineComponent, h, type PropType } from "vue";
import PacketBindingsPanel from "./PacketBindingsPanel.vue";
import { admitPacketDocument, type PacketPort } from "./contracts";
export default defineComponent({
  name: "PacketBindingsSurface",
  inheritAttrs: false,
  props: {
    document: null,
    hostContext: null,
    port: { type: Object as PropType<PacketPort>, required: true },
  },
  setup(props) {
    return () => {
      const page = admitPacketDocument(props.document, props.hostContext);
      if (!page)
        return h(
          "section",
          {
            id: "packet-bindings-contract-unavailable",
            role: "alert",
            class: "border border-warning/40 p-5 text-sm",
          },
          "Packet configuration is unavailable. Refresh to request current scoped evidence.",
        );
      return h(PacketBindingsPanel, { initial: page, port: props.port });
    };
  },
});
</script>
