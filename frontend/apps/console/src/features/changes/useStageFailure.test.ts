import { nextTick, ref } from "vue";
import { describe, expect, it } from "vite-plus/test";
import { useStageFailure } from "./useStageFailure.ts";

const refused = { changed: false as const, sentence: "Nothing was staged." };

describe("useStageFailure (ux 11-16: an old refusal never sits beside a fresh Check)", () => {
  it("clears on the next edit of any watched value, nested ones included", async () => {
    const values = ref({ name: "A", legs: [{ role: "primary" }] });
    const rollout = ref("all");
    const failure = useStageFailure([values, rollout]);

    failure.value = refused;
    const [leg] = values.value.legs;
    if (leg) leg.role = "candidate";
    await nextTick();
    expect(failure.value).toBeNull();

    failure.value = refused;
    rollout.value = "none";
    await nextTick();
    expect(failure.value).toBeNull();
  });

  it("stays until something is edited", async () => {
    const failure = useStageFailure([ref("a")]);
    failure.value = refused;
    await nextTick();
    expect(failure.value).toEqual(refused);
  });
});
