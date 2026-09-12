#!/usr/bin/env node
/**
 * Web-side golden vector runner for the quantity display SSOT (Final Decision 12).
 * Compiles the pure core (frontend/apps/pos-app/src/lib/quantity.ts) with the
 * project's own TypeScript compiler into a temp dir (no new dependencies) and
 * asserts every shared vector from scripts/golden_quantity_vectors.json.
 *
 * The SAME JSON drives the Flutter test mobile/test/quantity_golden_test.dart,
 * so the two platforms cannot drift (barcode-design-v2-review.md §6).
 *
 * Run from the repo root:  node scripts/run_golden_quantity_vectors.js
 * (paths resolve relative to this file — no hardcoded absolute paths)
 */
const { execFileSync } = require('child_process')
const fs = require('fs')
const path = require('path')

const REPO = path.join(__dirname, '..')
const APP = path.join(REPO, 'frontend', 'apps', 'pos-app')
const VECTORS = path.join(__dirname, 'golden_quantity_vectors.json')
const OUT = path.join(require('os').tmpdir(), 'golden_quantity_build')

const tsc = path.join(APP, 'node_modules/.bin/tsc')
if (!fs.existsSync(tsc)) {
  console.error('tsc not found — run npm ci in frontend/apps/pos-app first')
  process.exit(1)
}

fs.rmSync(OUT, { recursive: true, force: true })
fs.mkdirSync(OUT, { recursive: true })

execFileSync(tsc, [
  path.join(APP, 'src/lib/quantity.ts'),
  '--outDir', OUT,
  '--module', 'commonjs',
  '--target', 'es2020',
  '--skipLibCheck',
], { stdio: 'inherit' })

const { soldQuantityIntent } = require(path.join(OUT, 'quantity.js'))
const { vectors } = JSON.parse(fs.readFileSync(VECTORS, 'utf8'))

let failures = 0
for (const vector of vectors) {
  const got = soldQuantityIntent(vector.input)
  const sameUnit = got.unit === vector.expected.unit
  const sameCount = Math.abs(got.count - vector.expected.count) < 1e-9
  if (!sameUnit || !sameCount) {
    failures++
    console.error(`FAIL ${vector.name}: got ${JSON.stringify(got)}, want ${JSON.stringify(vector.expected)}`)
  } else {
    console.log(`ok   ${vector.name} -> ${got.unit} ${got.count}`)
  }
}

if (failures > 0) {
  console.error(`${failures} golden vector(s) FAILED`)
  process.exit(1)
}
console.log(`All ${vectors.length} golden vectors passed (web core).`)
