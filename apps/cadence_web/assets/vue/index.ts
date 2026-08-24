import {createLiveVue, findComponent} from "live_vue"

const components = import.meta.glob("./**/*.vue", {eager: true})

export default createLiveVue({
  resolve: (name) => findComponent(components, name)
})
