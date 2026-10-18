import { expect } from "vite-plus/test";

// Vitest types asymmetric matchers as any. They are expectation values, not domain data.
export const anyInstanceOf = (constructor: new (...args: never[]) => unknown): unknown =>
  expect.any(constructor);
export const containing = (expected: Record<string, unknown>): unknown =>
  expect.objectContaining(expected);
export const matchingString = (pattern: string | RegExp): unknown => expect.stringMatching(pattern);

export const containingString = (text: string): unknown => expect.stringContaining(text);
