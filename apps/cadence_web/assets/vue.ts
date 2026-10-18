import {createLiveVue} from "live_vue"
import {resolveHostComponent} from "../../../frontend/apps/host/src/shell/registry"

export default createLiveVue({resolve: resolveHostComponent})
