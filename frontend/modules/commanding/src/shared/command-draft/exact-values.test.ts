import { required } from "../../../../../test-support/required";
import { test } from "vite-plus/test";
import assert from "node:assert/strict";
import {
  exactInteger,
  parseArgumentValues,
  argumentValuesJson,
  scalarInputText,
  formatArgumentValues,
  sameArgumentValues,
} from "./exact-values";
test("argument comparison tolerates serialization differences while preserving integer and scalar identity", () => {
  assert.equal(
    sameArgumentValues(
      '{"counter":18446744073709551615,"rate":0.00001,"enabled":false}',
      '{"enabled":false,"rate":1.0e-5,"counter":18446744073709551615}',
    ),
    true,
  );
  assert.equal(
    sameArgumentValues('{"counter":9007199254740992}', '{"counter":9007199254740993}'),
    false,
  );
  assert.equal(
    sameArgumentValues('{"counter":"9007199254740993"}', '{"counter":9007199254740993}'),
    false,
  );
  assert.equal(sameArgumentValues('{"enabled":false}', "{}"), false);
  assert.equal(sameArgumentValues('{"offset":-0.0}', '{"offset":0.0}'), false);
  assert.equal(sameArgumentValues('{"name":"A"}', '{"name":"\\u0041"}'), true);
});
test("exact decimal and scientific integers preserve boundary digits", () => {
  for (const [input, expected] of [
    ["18446744073709551615", "18446744073709551615"],
    ["-9223372036854775808", "-9223372036854775808"],
    ["9007199254740993.0", "9007199254740993"],
    ["184467440737095516150e-1", "18446744073709551615"],
    ["1.8446744073709551615e19", "18446744073709551615"],
    ["00012.00", "12"],
    ["1e3", "1000"],
    ["0.10e1", "1"],
    [".001e3", "1"],
    ["-0.0e999999", "0"],
    ["10e-1", "1"],
    ["-1.2e2", "-120"],
  ])
    assert.equal(exactInteger(required(input)), expected, input);
});
test("fractional, nonfinite and unbounded integers fail before transport", () => {
  for (const input of [
    ".1",
    "1e-1",
    "1.2",
    "NaN",
    "Infinity",
    "0x10",
    "",
    " ",
    "1e100000",
    "1e-100000",
    "-",
    "1.2.3",
    "1e",
    "12 " + "0",
    "9".repeat(32769),
  ])
    assert.throws(() => exactInteger(input), input.slice(0, 40));
});
test("scalar JSON map retains lexical values and differentiates numeric-looking strings", () => {
  const raw =
    ' { "wide":18446744073709551615, "text":"18446744073709551615", "enabled":false, "float":1.25e-7, "__proto__":"own" } ';
  const values = parseArgumentValues(raw);
  assert.equal(values.wide, "18446744073709551615");
  assert.equal(values.text, '"18446744073709551615"');
  assert.equal(values.enabled, "false");
  assert.equal(values.float, "1.25e-7");
  assert.equal(Object.hasOwn(values, "__proto__"), true);
  assert.deepEqual(parseArgumentValues(argumentValuesJson(values)), values);
  assert.equal(scalarInputText(required(values.wide)), "18446744073709551615");
  assert.equal(scalarInputText(required(values.text)), "18446744073709551615");
});
test("malformed, duplicate, nested and unbounded argument maps are rejected", () => {
  for (const raw of [
    '{"a":1,"a":2}',
    '{"a":1,"\\u0061":2}',
    '{"a":01}',
    '{"a":1,}',
    '{"a":null}',
    '{"a":[]}',
    '{"a":{}}',
    "{}x",
    "[1]",
    '{"a":NaN}',
    '{"a":"\\u0000"}',
    '{"a":"\\ud800"}',
    '{"":1}',
    argumentValuesJson({ a: "1" }) + " ".repeat(32769),
  ])
    assert.throws(() => parseArgumentValues(raw));
  assert.throws(() =>
    argumentValuesJson(Object.fromEntries(Array.from({ length: 65 }, (_, n) => [`arg${n}`, "1"]))),
  );
});
test("every integer around the safe-number boundary round-trips exactly", () => {
  for (let n = 9007199254740900n; n < 9007199254741100n; n++) {
    for (const value of [n, -n]) {
      const token = exactInteger(`${value}.000`);
      assert.equal(token, String(value));
      assert.equal(
        parseArgumentValues(argumentValuesJson({ amount: token })).amount,
        String(value),
      );
    }
  }
});

test("builders reject implicit numeric coercion and injected scalar fragments", () => {
  assert.throws(() => {
    // @ts-expect-error Negative runtime fixture: a rounded number is not exact source text.
    argumentValuesJson({ amount: Number("18446744073709551615") });
  });
  assert.throws(() => argumentValuesJson({ amount: 'true,"injected":42' }));
  assert.throws(() => {
    // @ts-expect-error The runtime boundary also rejects untyped numeric input.
    exactInteger(42);
  });
  assert.throws(() => {
    // @ts-expect-error The runtime boundary also rejects untyped numeric input.
    scalarInputText(42);
  });
});
test("resolved values retain their larger existing read allowance", () => {
  const value = JSON.stringify({ default: "x".repeat(40000) });
  assert.throws(() => parseArgumentValues(value));
  assert.equal(parseArgumentValues(value, 131072).default, JSON.stringify("x".repeat(40000)));
});

test("review formatting retains exact numeric tokens and string distinctions", () => {
  const value =
    '{"counter":18446744073709551615,"signed":-9223372036854775808,"text":"18446744073709551615"}';
  assert.equal(
    formatArgumentValues(value),
    '{\n  "counter": 18446744073709551615,\n  "signed": -9223372036854775808,\n  "text": "18446744073709551615"\n}',
  );
});
