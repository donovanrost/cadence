import { describe, expect, it } from "vite-plus/test";

import commandsSource from "./OpsCommands.vue?raw";

describe("mission operations cohort bindings", () => {
  it("delegates commands to the domain module's public feature entry", () => {
    expect(commandsSource).toContain("@cadence/commanding/mission-commands");
    expect(commandsSource).toContain("export default OpsCommands");
    expect(commandsSource).not.toContain("<template>");
  });
});
