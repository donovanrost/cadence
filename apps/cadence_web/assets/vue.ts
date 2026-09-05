import {createLiveVue, findComponent} from "live_vue"
import {FederatedFullPageSurface} from "./vue/federated_full_page_surface"

const components = import.meta.glob("./vue/**/*.vue", {eager: true})

export default createLiveVue({
  resolve: (name) =>
    name === "FederatedFullPageSurface"
      ? FederatedFullPageSurface
      : findComponent(components, name)
})
