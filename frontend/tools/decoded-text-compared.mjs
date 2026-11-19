// Typing plan §12B, rule B (lead 11-15): a decoded field compared to a string literal must be a
// typed vocabulary, whatever the field is named.
//
// ast-grep can't see types, so this uses the TypeScript checker. A hit is an `===` / `!==` or a
// `switch` case against a string literal where the compared property was declared in a decoder
// shape as `token` or `string` (optionally `nullable` / `optional`). That includes fields whose
// decoder says `// free-text:`: branching on a field contradicts the claim that it is free text.
// Fix by decoding with `known([...])` / `knownText([...])` (and telling the server side if the
// vocabulary isn't in the contract yet). A comparison that really is against open text takes
// `// compared-as-text: <why>` on the line above it.
//
// Limit: `.ts` files only. Comparisons inside Vue SFCs (script or template) aren't checked.
//
// Usage: node tools/decoded-text-compared.mjs [--project <tsconfig>] [--json]
import { dirname, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import ts from "typescript";

/** @typedef {{ file: string; line: number; field: string; literal: string; freeText: boolean }} Hit */

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const TEXT_READER =
  /^(?:\w+\.)?(?:optional\()?(?:\w+\.)?(?:nullable\()?(?:\w+\.)?(?:token|string)\)*$/;
const OPT_OUT = /compared-as-text:\s*\S.{4,}/;

/**
 * Hits for every non-test `.ts` file of a project.
 * @param {string} project path to a tsconfig
 * @returns {Hit[]}
 */
export function decodedTextCompared(project) {
  const parsed = ts.getParsedCommandLineOfConfigFile(
    project,
    {},
    {
      ...ts.sys,
      onUnRecoverableConfigFileDiagnostic: (d) => {
        throw new Error(ts.flattenDiagnosticMessageText(d.messageText, "\n"));
      },
    },
  );
  if (!parsed) throw new Error(`cannot read ${project}`);
  const files = parsed.fileNames.filter(
    (f) => f.endsWith(".ts") && !f.endsWith(".test.ts") && !f.endsWith(".d.ts"),
  );
  const program = ts.createProgram(files, parsed.options);
  const checker = program.getTypeChecker();
  const wanted = new Set(files);
  const base = dirname(project);
  /** @type {Hit[]} */
  const hits = [];

  /** @param {ts.SourceFile} sf @param {number} pos */
  const lineOf = (sf, pos) => sf.getLineAndCharacterOfPosition(pos).line;
  /** @param {ts.SourceFile} sf @param {number} line */
  const lineText = (sf, line) => sf.text.split("\n")[line] ?? "";

  /**
   * The decoder entry behind `expr`, when it is a token/string reader.
   * @param {ts.Expression} expr
   * @returns {{ field: string; freeText: boolean } | null}
   */
  function textDecoder(expr) {
    /** @type {ts.Node | null} */
    let name = null;
    if (ts.isPropertyAccessExpression(expr)) name = expr.name;
    else if (ts.isElementAccessExpression(expr)) name = expr.argumentExpression;
    if (!name) return null;
    const symbol = checker.getSymbolAtLocation(name);
    for (const d of symbol?.declarations ?? []) {
      if (!ts.isPropertyAssignment(d)) continue;
      if (!TEXT_READER.test(d.initializer.getText().replace(/\s+/g, ""))) continue;
      const sf = d.getSourceFile();
      const above = lineText(sf, lineOf(sf, d.getStart()) - 1);
      return { field: d.name.getText(), freeText: /free-text:/.test(above) };
    }
    return null;
  }

  /** @param {ts.Node} node @param {ts.SourceFile} sf */
  function visit(node, sf) {
    /** @param {ts.Expression} expr @param {string} literal @param {ts.Node} at */
    const check = (expr, literal, at) => {
      const decoder = textDecoder(expr);
      if (!decoder) return;
      const line = lineOf(sf, at.getStart());
      if (OPT_OUT.test(lineText(sf, line - 1))) return;
      hits.push({ file: relative(base, sf.fileName), line: line + 1, literal, ...decoder });
    };
    if (
      ts.isBinaryExpression(node) &&
      (node.operatorToken.kind === ts.SyntaxKind.EqualsEqualsEqualsToken ||
        node.operatorToken.kind === ts.SyntaxKind.ExclamationEqualsEqualsToken)
    ) {
      if (ts.isStringLiteral(node.right)) check(node.left, node.right.text, node);
      else if (ts.isStringLiteral(node.left)) check(node.right, node.left.text, node);
    }
    if (ts.isSwitchStatement(node))
      for (const clause of node.caseBlock.clauses)
        if (ts.isCaseClause(clause) && ts.isStringLiteral(clause.expression))
          check(node.expression, clause.expression.text, clause);
    ts.forEachChild(node, (child) => visit(child, sf));
  }

  for (const sf of program.getSourceFiles()) if (wanted.has(sf.fileName)) visit(sf, sf);
  return hits;
}

/**
 * Hit counts by file, for the ratchet baseline.
 * @param {readonly Hit[]} hits
 * @returns {Record<string, number>}
 */
export function countByFile(hits) {
  /** @type {Record<string, number>} */
  const counts = {};
  for (const h of hits) counts[h.file] = (counts[h.file] ?? 0) + 1;
  return Object.fromEntries(Object.entries(counts).sort(([a], [b]) => a.localeCompare(b)));
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  const at = args.indexOf("--project");
  const project = resolve(
    at >= 0 ? (args[at + 1] ?? "") : resolve(root, "apps/console/tsconfig.app.json"),
  );
  const hits = decodedTextCompared(project);
  if (args.includes("--json")) console.log(JSON.stringify(hits, null, 2));
  else
    for (const h of hits)
      console.log(
        `${h.file}:${h.line}  .${h.field} compared to "${h.literal}"${h.freeText ? " (decoder says free-text)" : ""}`,
      );
}
