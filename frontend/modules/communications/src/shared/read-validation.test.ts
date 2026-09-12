import { expect, test } from "vite-plus/test";
import { href } from "./read-validation";
const context = { missionId: "mission-1" };
test("mission-relative links retain their query and anchor", () => {
  const path = "/missions/mission-1/comms/transports?q=Lab%20TCP&page=2#results";
  expect(href(path, context)).toBe(path);
});
test.each([
  "javascript:alert(1)",
  "//evil.example",
  "/missions/mission-10/comms",
  "/missions/mission-1/../other",
  "/missions/mission-1/%2e%2e/other",
  "/missions/mission-1/%2E./other",
  "/missions/mission-1/%2fother",
  "/missions/mission-1/%5cother",
  "/missions/mission-1/%00other",
  "/missions/mission-1/%broken",
])("rejects an unsafe or cross-mission path: %s", (path) => {
  expect(() => href(path, context)).toThrow();
});
