// Single home of currency handling in the frontend.
//
// The backend stores and computes every amount as an integer count of
// piastres (1 EGP = 100 piastres). All arithmetic in app code happens on
// these integers, so fractional money like 0.00000000000001 can never
// appear. Formatting to "1.00" style strings happens only here, at the
// display boundary, and parsing user input happens only through
// parseEGPToPiastres at the entry boundary.

export const PIASTRES_PER_UNIT = 100

const currencyFormatter = new Intl.NumberFormat('ar-EG-u-nu-latn', {
  style: 'currency',
  currency: 'EGP',
})

/** Format an integer piastres amount for display, e.g. 10000 -> "100.00 ج.م". */
export function formatPiastres(piastres: number): string {
  const value = Number.isFinite(piastres) ? Math.trunc(piastres) : 0
  return currencyFormatter.format(value / PIASTRES_PER_UNIT)
}

/** Parse a user-entered EGP amount ("105.5") into exact piastres (10550). */
export function parseEGPToPiastres(input: string): number | null {
  const trimmed = input.trim().replace(/٫/g, '.').replace(/,/g, '')
  if (!trimmed) return null
  const value = Number(trimmed)
  if (!Number.isFinite(value) || value < 0) return null
  const piastres = Math.round(value * PIASTRES_PER_UNIT)
  return Number.isSafeInteger(piastres) ? piastres : null
}

/** Convert piastres back to a plain EGP string for editing, e.g. 10550 -> "105.50". */
export function piastresToEGPInput(piastres: number): string {
  return (Math.trunc(piastres) / PIASTRES_PER_UNIT).toFixed(2)
}

/**
 * Effective strip price in piastres. New products always carry an explicit
 * partial price; a legacy product without one falls back to the same
 * documented half-up division the backend uses, so display and checkout
 * never disagree.
 */
export function stripPricePiastres(product: {
  selling_price_piastres: number
  partial_selling_price_piastres: number
  units_per_box: number
}): number {
  if (product.partial_selling_price_piastres > 0) return product.partial_selling_price_piastres
  if (product.units_per_box > 0) return Math.round(product.selling_price_piastres / product.units_per_box)
  return product.selling_price_piastres
}
