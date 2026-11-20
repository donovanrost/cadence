import { effectScope, nextTick, ref } from "vue";
import { describe, expect, it } from "vite-plus/test";
import { useActed } from "./acted.ts";

describe("useActed (a11y B6, #276)", () => {
  it("is polite until the person acts, an alert after, and polite again once a load succeeds", async () => {
    const ok = ref(false);
    const scope = effectScope();
    const a = scope.run(() => useActed(ok));
    if (!a) throw new Error("no scope");
    expect(a.role.value).toBe("status");
    let calls = 0;
    a.after(() => (calls += 1))();
    expect(calls).toBe(1);
    expect(a.role.value).toBe("alert");
    ok.value = true;
    await nextTick();
    expect(a.role.value).toBe("status");
    a.mark();
    expect(a.role.value).toBe("alert");
    scope.stop();
  });
});
