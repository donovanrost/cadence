import "@fontsource/saira/400.css";
import "@fontsource/saira/500.css";
import "@fontsource/saira/600.css";
import "@fontsource/saira-condensed/500.css";
import "@fontsource/saira-condensed/600.css";
import "@fontsource/saira-condensed/700.css";
import "@fontsource/azeret-mono/400.css";
import "@fontsource/azeret-mono/500.css";
import "@fontsource/azeret-mono/600.css";
import "./styles/app.css";
import { createApp } from "vue";
import App from "./App.vue";
import { createConsoleRouter } from "./router/index.ts";

// oxlint-disable-next-line typescript/no-unsafe-argument -- vue-tsc checks the SFC constructor at this registration or render boundary.
createApp(App).use(createConsoleRouter()).mount("#app");
