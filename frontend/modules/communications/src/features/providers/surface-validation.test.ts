import { required } from "../../../../../test-support/required";
import { expect, test } from "vite-plus/test";
import { readList, readDetail } from "./read-validation";
import { readForm } from "./form-validation";
import { admitProviderSurface } from "../../providers";
import {
  providerNewSurface,
  providerDetailSurface,
  providerListSurface,
} from "./surface-fixtures.test-support";
const context = { missionId: "mission-1" };
test("all provider surfaces admit only their known version and feature-owned fields", () => {
  for (const [name, payload] of [
    ["provider_list", providerListSurface()],
    ["provider_new", providerNewSurface()],
    ["provider_show", providerDetailSurface()],
  ] as const) {
    expect(() => admitProviderSurface(name, 1, payload, context)).not.toThrow();
    expect(() => admitProviderSurface(name, 2, payload, context)).toThrow();
    expect(() => admitProviderSurface(name, 1, payload, { missionId: "other" })).toThrow();
  }
  expect(readForm(providerNewSurface(true), context).accounts.empty).toBe(true);
});
test("provider presentation cannot supply event handlers or unsafe navigation", () => {
  const unsafe = providerListSurface();
  Object.assign(unsafe.data.presentation.root.attrs, { onclick: "private()" });
  expect(() => readList(unsafe, context)).toThrow();
  const row = providerListSurface();
  required(row.data.presentation.card.rows[0]).href = "javascript:bad()";
  expect(() => readList(row, context)).toThrow();
});
test("provider detail identity, emptiness, versions and diagnostic shape must agree", () => {
  const wrong = providerDetailSurface();
  wrong.data.provider.provider_id = "other";
  expect(() => readDetail(wrong, context)).toThrow();
  const empty = providerDetailSurface();
  empty.data.profiles.service.empty = false;
  expect(() => readDetail(empty, context)).toThrow();
  const versions = providerDetailSurface();
  versions.data.provider_versions = [];
  expect(() => readDetail(versions, context)).toThrow();
  const json = providerDetailSurface();
  json.data.diagnostics.json = "not json";
  expect(() => readDetail(json, context)).toThrow();
});
test("creation binds allowed grants to their exact summaries and validates field references", () => {
  const wrong = providerNewSurface();
  wrong.data.accounts.selected = required(wrong.data.accounts.bindings[1]).summary;
  expect(() => readForm(wrong, context)).toThrow();
  const field = providerNewSurface();
  field.data.form.fields.display_name.name = "provider[credential]";
  expect(() => readForm(field, context)).toThrow();
  const keys = providerNewSurface();
  keys.data.form.sections.binding.field_keys.push("display_name");
  expect(() => readForm(keys, context)).toThrow();
  const number = providerNewSurface();
  number.data.form.fields.minimum_retained_duration_seconds.type = "text";
  expect(() => readForm(number, context)).toThrow();
  const policy = providerNewSurface();
  required(policy.data.form.fields.policy_mode.options[0]).value = "automatic_without_limits";
  expect(() => readForm(policy, context)).toThrow();
});
