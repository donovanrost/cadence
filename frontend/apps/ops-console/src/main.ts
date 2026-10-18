import "./styles.css";
import { createApp } from "vue";
import StandaloneApp from "./StandaloneApp.vue";

// oxlint-disable-next-line typescript/no-unsafe-argument -- vue-tsc checks the SFC constructor at this registration or render boundary.
createApp(StandaloneApp).mount("#app");
