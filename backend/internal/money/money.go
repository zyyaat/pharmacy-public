// Package money is the single home of monetary arithmetic.
//
// Every monetary amount in the system is a Piastres value: an integer count
// of the currency's smallest unit. For EGP the smallest unit is the piastre
// and one pound equals 100 piastres, so a product priced at 100 EGP is
// stored and computed as 10000.
//
// Integer addition, subtraction and multiplication are exact. Fractional
// money can therefore never exist anywhere in the system. The ONLY allowed
// divisions are the helpers below, which are deterministic:
//
//   - DivRoundHalfUp rounds halves away from zero (documented rounding rule
//     for derived per-unit costs such as box cost divided by strips per box),
//   - Allocate splits an amount across weights with the largest-remainder
//     method; the parts ALWAYS sum to the original amount exactly.
package money

import (
        "math/big"
        "sort"
)

// MinorUnitFactor is how many minor units (piastres) make one major unit
// (pound) for the supported currency (EGP, currency_minor_unit = 2).
const MinorUnitFactor int64 = 100

// Max guards against absurd inputs from malformed requests.
const Max Piastres = 9_999_999_999 // ~99,999,999.99 EGP

// Piastres is an exact monetary amount in the currency's smallest unit.
type Piastres int64

// Valid reports whether p is inside the representable business range.
func (p Piastres) Valid() bool { return p >= 0 && p <= Max }

// Add returns p + q (exact integer addition).
func (p Piastres) Add(q Piastres) Piastres { return p + q }

// MulQty multiplies an amount by an integer quantity (exact).
func (p Piastres) MulQty(qty int64) Piastres { return p * Piastres(qty) }

// DivRoundHalfUp divides p by d (d > 0), rounding halves away from zero.
// This is the documented rule for derived unit costs, e.g. the per-strip
// cost of a box: an unrepresentable fraction contributes at most half a
// piastre of cost rounding per box and never affects revenue amounts.
func (p Piastres) DivRoundHalfUp(d int64) Piastres {
        if d <= 0 {
                return 0
        }
        quo, rem := new(big.Int).QuoRem(big.NewInt(int64(p)), big.NewInt(d), new(big.Int))
        // Round up when 2*|rem| >= d (exact rational comparison, no truncation).
        twiceRem := new(big.Int).Abs(rem)
        twiceRem.Lsh(twiceRem, 1)
        if twiceRem.Cmp(big.NewInt(d)) >= 0 {
                sign := 1
                if p < 0 {
                        sign = -1
                }
                quo.Add(quo, big.NewInt(int64(sign)))
        }
        return Piastres(quo.Int64())
}

// Allocate splits total across weights proportionally using the
// largest-remainder method. The returned parts always sum to total exactly
// and, when the division is exact, every part equals its exact share.
// Weights must be positive; a zero or negative total yields all zeros.
func Allocate(total Piastres, weights []int64) []Piastres {
        parts := make([]Piastres, len(weights))
        if total <= 0 {
                return parts
        }
        var weightSum int64
        for _, w := range weights {
                if w <= 0 {
                        return make([]Piastres, len(weights))
                }
                weightSum += w
        }
        if weightSum == 0 {
                return parts
        }

        type slot struct {
                index   int
                floored int64
                remNum  int64 // numerator of the fractional remainder over weightSum
        }
        slots := make([]slot, len(weights))
        allocated := int64(0)
        for i, w := range weights {
                num := int64(total) * w
                floored := num / weightSum
                slots[i] = slot{index: i, floored: floored, remNum: num % weightSum}
                allocated += floored
        }

        remaining := int64(total) - allocated
        sort.SliceStable(slots, func(a, b int) bool {
                if slots[a].remNum != slots[b].remNum {
                        return slots[a].remNum > slots[b].remNum
                }
                return slots[a].index < slots[b].index
        })
        for i := 0; i < len(slots) && remaining > 0; i++ {
                slots[i].floored++
                remaining--
        }
        for _, s := range slots {
                parts[s.index] = Piastres(s.floored)
        }
        return parts
}
