/** Bounded scalar JSON text. Numeric tokens never pass through a JavaScript number. */
export type ScalarJsonText = string;
const byteLength = (s: string) => new TextEncoder().encode(s).length;
const clean = (s: string) =>
  // oxlint-disable-next-line no-control-regex -- Reject control characters at this input boundary.
  !/[\uD800-\uDFFF]/u.test(s) && !/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/.test(s);
const bad = (): never => {
  throw Error("Invalid exact command arguments");
};
// oxlint-disable-next-line no-control-regex -- Reject control characters at this input boundary.
const jsonString = /^"(?:[^"\\\u0000-\u001f]|\\(?:["\\/bfnrt]|u[0-9a-fA-F]{4}))*"/;
const jsonScalar = /^(?:true|false|-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?)/;

/** Decode only keys and string tokens; retain every numeric token's exact source. */
export function parseArgumentValues(
  value: unknown,
  maxBytes: 32768 | 131072 = 32768,
): Record<string, ScalarJsonText> {
  if (
    ![32768, 131072].includes(maxBytes) ||
    typeof value !== "string" ||
    byteLength(value) > maxBytes ||
    !clean(value)
  )
    return bad();
  const entries: [string, string][] = [],
    names = new Set<string>();
  let index = 0;
  const whitespace = () => {
    while (/[\x20\t\r\n]/.test(value[index] ?? "") && index < value.length) index++;
  };
  const take = (expected: string) => {
    whitespace();
    if (value[index++] !== expected) bad();
  };
  const stringToken = () => {
    whitespace();
    const token = value.slice(index).match(jsonString)?.[0];
    if (!token) return bad();
    index += token.length;
    return token;
  };
  take("{");
  whitespace();
  if (value[index] !== "}")
    while (true) {
      const name: unknown = JSON.parse(stringToken());
      if (
        typeof name !== "string" ||
        !name ||
        byteLength(name) > 240 ||
        !clean(name) ||
        names.has(name) ||
        names.size >= 64
      )
        return bad();
      names.add(name);
      take(":");
      whitespace();
      let token: string;
      if (value[index] === '"') {
        token = stringToken();
        const decoded: unknown = JSON.parse(token);
        if (typeof decoded !== "string" || !clean(decoded)) return bad();
      } else {
        const match = value.slice(index).match(jsonScalar)?.[0];
        if (!match) return bad();
        token = match;
        index += token.length;
      }
      entries.push([name, token]);
      whitespace();
      if (value[index] !== ",") break;
      index++;
    }
  take("}");
  whitespace();
  if (index !== value.length) return bad();
  return Object.fromEntries(entries);
}
export function argumentValuesJson(values: Record<string, ScalarJsonText>): string {
  if (
    !values ||
    typeof values !== "object" ||
    Array.isArray(values) ||
    !Object.values(values).every((value) => typeof value === "string")
  )
    return bad();
  const result = `{${Object.entries(values)
    .map(([name, value]) => `${JSON.stringify(name)}:${value}`)
    .join(",")}}`;
  const parsed = parseArgumentValues(result),
    entries = Object.entries(values);
  if (
    Object.keys(parsed).length !== entries.length ||
    entries.some(([name, value]) => !Object.hasOwn(parsed, name) || parsed[name] !== value.trim())
  )
    return bad();
  return result;
}

/** Compare scalar meaning without rounding integers or depending on object key order. */
export function sameArgumentValues(left: string, right: string): boolean {
  const a = parseArgumentValues(left),
    b = parseArgumentValues(right);
  return (
    Object.keys(a).length === Object.keys(b).length &&
    Object.entries(a).every(([name, value]) => {
      const other = b[name];
      if (other === undefined) return false;
      if (value.startsWith('"') || other.startsWith('"'))
        return (
          value.startsWith('"') && other.startsWith('"') && JSON.parse(value) === JSON.parse(other)
        );
      if (value === "true" || value === "false" || other === "true" || other === "false")
        return value === other;
      return canonicalNumber(value) === canonicalNumber(other);
    })
  );
}
function canonicalNumber(value: string): string {
  const match = /^(-?)(\d+)(?:\.(\d+))?(?:[eE]([+-]?\d+))?$/.exec(value);
  if (!match) return bad();
  const fraction = match[3] ?? "";
  const digits = `${match[2]}${fraction}`.replace(/^0+/, "");
  if (!digits) return `${match[1]}0`;
  const significant = digits.replace(/0+$/, "");
  const exponent =
    BigInt(match[4] ?? "0") - BigInt(fraction.length) + BigInt(digits.length - significant.length);
  return `${match[1]}${significant}e${exponent}`;
}
export function scalarInputText(value: ScalarJsonText): string {
  if (typeof value !== "string") return bad();
  const values = parseArgumentValues(`{"value":${value}}`);
  const raw = values.value;
  if (raw === undefined) return bad();
  if (!raw.startsWith('"')) return raw;
  const decoded: unknown = JSON.parse(raw);
  return typeof decoded === "string" ? decoded : bad();
}

/** Preserve the existing decimal/scientific integer input syntax using digit arithmetic. */
export function exactInteger(raw: string): ScalarJsonText {
  if (typeof raw !== "string" || byteLength(raw) > 32768) return bad();
  const match = /^(-?)(?:(\d+)(?:\.(\d*))?|\.(\d+))(?:[eE]([+-]?\d+))?$/.exec(raw);
  if (!match) return bad();
  const fraction = match[3] ?? match[4] ?? "";
  let digits = `${match[2] ?? ""}${fraction}`.replace(/^0+/, "");
  if (!digits) return "0";
  const exponentText = (match[5] ?? "0").replace(/^\+/, "");
  const exponent = BigInt(exponentText);
  if (exponent < -32768n || exponent > 32768n) return bad();
  const scale = fraction.length - Number(exponent);
  if (scale > 0) {
    if (scale >= digits.length || !/^0*$/.test(digits.slice(-scale))) return bad();
    digits = digits.slice(0, -scale);
  } else if (scale < 0) {
    if (digits.length - scale > 32768) return bad();
    digits += "0".repeat(-scale);
  }
  const result = `${match[1]}${digits}`;
  if (byteLength(result) > 32768) return bad();
  return result;
}

/** Format the scalar object for review without reparsing its numeric values. */
export function formatArgumentValues(value: string): string {
  const entries = Object.entries(parseArgumentValues(value, 131072));
  return entries.length
    ? `{\n${entries.map(([name, raw]) => `  ${JSON.stringify(name)}: ${raw}`).join(",\n")}\n}`
    : "{}";
}
