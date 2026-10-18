<script lang="ts">
import { defineComponent, h, type PropType } from "vue";
import PosturePanel from "./PosturePanel.vue";
import { admitDocument, type PosturePort } from "./contracts";
export default defineComponent({
  name: "LimitsPostureSurface",
  inheritAttrs: false,
  props: {
    document: null,
    hostContext: null,
    port: { type: Object as PropType<PosturePort>, required: true },
  },
  setup(props) {
    return () => {
      const page = admitDocument(props.document, props.hostContext);
      return page
        ? h(PosturePanel, { initial: page, port: props.port })
        : h(
            "section",
            {
              id: "limits-posture-unavailable",
              role: "alert",
              class: "border border-warning/40 p-5 text-sm",
            },
            "Limit evidence is unavailable. Refresh to request the current scoped view.",
          );
    };
  },
});
</script>
