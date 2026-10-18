import {
  boolean,
  choice,
  href,
  identifier,
  invalid,
  navigation,
  record,
  text,
} from "./read-validation.ts";
import type { ReadContext } from "./read-contracts.ts";

export type Reader<T> = (value: unknown) => T;
export const string: Reader<string> = (value) => text(value, true);
export const id: Reader<string> = (value) => {
  const result = identifier(value);
  if (/\s/.test(result)) return invalid();
  return result;
};
export { boolean };
export const nullable =
  <T>(read: Reader<T>): Reader<T | null> =>
  (value) =>
    value === null ? null : read(value);
export const oneOf =
  <const T extends readonly string[]>(values: T): Reader<T[number]> =>
  (value) =>
    choice(value, values);
export const literal =
  <const T extends string>(expected: T): Reader<T> =>
  (value) =>
    value === expected ? expected : invalid();
export function object<S extends Record<string, Reader<unknown>>>(
  shape: S,
): Reader<{ [K in keyof S]: ReturnType<S[K]> }> {
  return (value) => {
    const input = record(value);
    return Object.fromEntries(
      Object.entries(shape).map(([key, read]) => [key, read(input[key])]),
    ) as { [K in keyof S]: ReturnType<S[K]> };
  };
}
export const array =
  <T>(read: Reader<T>, max = 100): Reader<T[]> =>
  (value) => {
    if (!Array.isArray(value) || value.length > max) return invalid();
    return value.map(read);
  };
export const number: Reader<number> = (value) =>
  typeof value === "number" && Number.isFinite(value) ? value : invalid();
export const section = object({ id, number: string, title: string });
export const formSection = object({ number: string, title: string });
export const link =
  (context: ReadContext): Reader<string> =>
  (value) =>
    href(value, context);
export const breadcrumbs = (context: ReadContext) =>
  array(
    object({
      label: string,
      href: nullable(link(context)),
    }),
    12,
  );
export const page = (context: ReadContext) =>
  object({
    id,
    title: string,
    subtitle: string,
    breadcrumbs: breadcrumbs(context),
  });
export const actions = (context: ReadContext, cancel: string) =>
  object({
    submit: object({ id, label: string }),
    cancel: object({
      id,
      label: string,
      href: (value) => {
        const result = href(value, context);
        return result === cancel ? result : invalid();
      },
    }),
  });
export function envelope(value: unknown, context: ReadContext, expected: string) {
  const input = record(value);
  navigation(input.navigation, context, expected);
  return input.data;
}
export function unique(values: string[]) {
  if (new Set(values).size !== values.length) invalid();
}
