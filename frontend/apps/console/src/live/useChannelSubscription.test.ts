import { effectScope, nextTick, ref } from "vue";
import { beforeEach, describe, expect, it, vi } from "vite-plus/test";

type Hook = () => void;
const created: FakeChannel[] = [];

class FakePush {
  hooks: Hook[] = [];
  receive(status: string, callback: Hook) {
    if (status === "ok") this.hooks.push(callback);
    return this;
  }
}

class FakeChannel {
  state = "joining";
  pushes: string[] = [];
  payloads: unknown[] = [];
  joinPush = new FakePush();
  left = false;
  constructor(readonly topic: string) {
    created.push(this);
  }
  join() {
    return this.joinPush;
  }
  /** Simulates a successful (re)join. */
  joinOk() {
    this.state = "joined";
    for (const hook of this.joinPush.hooks) hook();
  }
  push(event: string, payload?: unknown) {
    this.pushes.push(event);
    this.payloads.push(payload);
    return new FakePush();
  }
  on() {
    return 1;
  }
  off() {}
  leave() {
    this.left = true;
    this.state = "closed";
  }
}

vi.mock("phoenix", () => ({
  Socket: class {
    onOpen() {}
    onError() {}
    onClose() {}
    connect() {}
    disconnect() {}
    channel(topic: string) {
      return new FakeChannel(topic);
    }
  },
}));

const { startSocket, stopSocket } = await import("./socket.ts");
const { useChannelSubscription } = await import("./useChannelSubscription.ts");

const messages = {
  subscribe: ["fleet:subscribe", {}],
  unsubscribe: ["fleet:unsubscribe", {}],
} as const;

describe("useChannelSubscription", () => {
  beforeEach(() => {
    stopSocket();
    created.length = 0;
    startSocket("/socket/console", "csrf");
  });

  it("subscribes after every (re)join and unsubscribes on dispose", async () => {
    const scope = effectScope();
    scope.run(() => useChannelSubscription(ref("mission:m1"), messages));
    const channel = created[0];
    expect(channel?.pushes).toEqual([]);
    channel?.joinOk();
    channel?.joinOk(); // reconnect: the server starts a fresh channel process
    expect(channel?.pushes).toEqual(["fleet:subscribe", "fleet:subscribe"]);
    scope.stop();
    await nextTick();
    expect(channel?.pushes.at(-1)).toBe("fleet:unsubscribe");
    expect(channel?.left).toBe(true);
  });

  it("moves the subscription when the topic changes and skips unsubscribe on an unjoined channel", async () => {
    const topic = ref<string | null>("mission:m1");
    const scope = effectScope();
    scope.run(() => useChannelSubscription(topic, messages));
    topic.value = "mission:m2";
    await nextTick();
    expect(created[0]?.pushes).toEqual([]);
    expect(created[0]?.left).toBe(true);
    created[1]?.joinOk();
    expect(created[1]?.pushes).toEqual(["fleet:subscribe"]);
    scope.stop();
  });

  it("resubscribe pushes unsubscribe then subscribe", () => {
    const scope = effectScope();
    const handle = scope.run(() => useChannelSubscription(ref("mission:m1"), messages));
    created[0]?.joinOk();
    handle?.resubscribe();
    expect(created[0]?.pushes).toEqual(["fleet:subscribe", "fleet:unsubscribe", "fleet:subscribe"]);
    scope.stop();
  });

  it("sends a getter payload's current value on (re)join and pushes `update` when it changes while joined", async () => {
    const range = ref({ from: "a", to: "b" });
    const scope = effectScope();
    scope.run(() =>
      useChannelSubscription(ref("dashboard:m1:d1"), {
        subscribe: ["view:subscribe", () => ({ runtime: range.value })],
        unsubscribe: ["view:unsubscribe", {}],
        update: "view:set",
      }),
    );
    const channel = created[0];
    range.value = { from: "a", to: "c" }; // not joined yet: nothing pushed
    await nextTick();
    expect(channel?.pushes).toEqual([]);
    channel?.joinOk();
    expect(channel?.payloads[0]).toEqual({ runtime: { from: "a", to: "c" } });
    range.value = { from: "x", to: "y" };
    await nextTick();
    expect(channel?.pushes).toEqual(["view:subscribe", "view:set"]);
    expect(channel?.payloads[1]).toEqual({ runtime: { from: "x", to: "y" } });
    scope.stop();
  });
});
