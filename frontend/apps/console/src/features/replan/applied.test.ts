import { describe, expect, it } from "vite-plus/test";
import { bookingRequests } from "./applied.ts";

describe("bookingRequests", () => {
  it("counts moves and adds; drops send nothing", () => {
    expect(bookingRequests({ moved: [1, 2, 3, 4], added: [1] })).toBe(5);
  });
});
