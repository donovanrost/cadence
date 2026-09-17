import { expect, test, vi } from "vite-plus/test";
import type { OpsPageReadRequest } from "@cadence/plugin-sdk/ops-pages";
import { createOpsReadPort } from "./read-port";

test("live readers capture identity, discard stale notifications and dispose once", async () => {
  const id = "commanding.workspace",
    token = "11111111-1111-4111-8111-111111111111";
  const context = { organizationId: "org", missionId: "mission" };
  let active = true,
    notify = () => {};
  const dispose = vi.fn(),
    listener = vi.fn();
  const subscribe = vi.fn((request: OpsPageReadRequest, callback: () => void) => {
    expect(request).toEqual({ id, token });
    notify = callback;
    return dispose;
  });
  const query = vi.fn(async () => ({
    id,
    token,
    context,
    version: 1,
    slot: "ops.page",
    status: "ready",
    data: "current",
  }));
  const port = createOpsReadPort(id, token, context, () => active, query, subscribe);
  if (!port || !("subscribe" in port)) throw Error("Expected a live reader");
  const stop = port.subscribe(listener);
  notify();
  expect(listener).toHaveBeenCalledOnce();
  await expect(port.read()).resolves.toBe("current");
  active = false;
  notify();
  expect(listener).toHaveBeenCalledOnce();
  expect(() => port.subscribe(listener)).toThrow("Inactive");
  await expect(port.read()).rejects.toThrow("Inactive");
  stop();
  stop();
  active = true;
  notify();
  expect(listener).toHaveBeenCalledOnce();
  expect(dispose).toHaveBeenCalledOnce();
});
