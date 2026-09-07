<script setup>
import { inject, onBeforeUnmount, onMounted, ref } from "vue";
import { FederatedFullPageSurface } from "./federated_full_page_surface";
import { loadFederationHostModule } from "./federation-module";
import { pageChromeKey } from "@cadence/ui/page-chrome";
const pageChrome = inject(pageChromeKey, undefined);
const props = defineProps({ surface: Object, viewClass: String, navigate: Function });
const element = ref(null);
const error = ref(null);
let mounted;
let disposed = false;
onMounted(async () => {
  try {
    const module = await loadFederationHostModule();
    if (!disposed)
      mounted = module.bootstrapPhoenixHost(
        element.value.querySelector("#cadence-federation-root"),
        { navigate: props.navigate, pageChrome },
      );
  } catch {
    if (!disposed) error.value = "The application could not be loaded. Reload to try again.";
  }
});
onBeforeUnmount(() => {
  disposed = true;
  mounted?.unmount();
});
</script>
<template>
  <div ref="element" data-host-managed class="contents">
    <p v-if="error" role="alert">{{ error }}</p>
    <FederatedFullPageSurface v-bind="surface" :class="viewClass" />
  </div>
</template>
