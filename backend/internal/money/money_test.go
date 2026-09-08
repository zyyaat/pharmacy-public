package money

import "testing"

func TestDivRoundHalfUp(t *testing.T) {
	cases := []struct {
		p    Piastres
		d    int64
		want Piastres
	}{
		{10500, 6, 1750},  // exact
		{10503, 6, 1751},  // 1750.5 -> half up
		{10000, 3, 3333},  // 3333.33 -> down
		{10000, 6, 1667},  // 1666.67 -> up
		{0, 4, 0},         // zero
		{9999, 2, 5000},   // 4999.5 -> half up
		{7, 2, 4},         // 3.5 -> half up
		{10500, 0, 0},     // guard
		{10500, -3, 0},    // guard
	}
	for _, c := range cases {
		if got := c.p.DivRoundHalfUp(c.d); got != c.want {
			t.Errorf("DivRoundHalfUp(%d, %d) = %d, want %d", c.p, c.d, got, c.want)
		}
	}
}

func TestAllocateSumsExactly(t *testing.T) {
	cases := []struct {
		total   Piastres
		weights []int64
	}{
		{21000, []int64{5, 7}},          // exact split
		{21006, []int64{5, 7}},          // remainder 1 piastre
		{100, []int64{1, 1, 1}},         // 33.33 each, remainder to first
		{9999, []int64{3, 3, 3, 3}},     // many parts
		{7, []int64{1, 1, 1}},           // 2.33 each
		{12345, []int64{7, 11, 13}},     // coprime weights
		{1, []int64{1, 1}},              // single piastre
		{0, []int64{5, 5}},              // zero total
	}
	for _, c := range cases {
		parts := Allocate(c.total, c.weights)
		var sum Piastres
		for _, p := range parts {
			sum += p
		}
		if sum != c.total {
			t.Errorf("Allocate(%d, %v) parts sum to %d, want %d (parts=%v)", c.total, c.weights, sum, c.total, parts)
		}
		if len(parts) != len(c.weights) {
			t.Fatalf("Allocate returned %d parts, want %d", len(parts), len(c.weights))
		}
	}
}

func TestAllocateExactShares(t *testing.T) {
	// 2 boxes = 21006 piastres over 12 strips across batches of 5 and 7:
	// per-strip share is 1750.5, so the split must be 8752/8754 or
	// 8753/12253... the only invariant that matters: sum == total.
	parts := Allocate(21006, []int64{5, 7})
	if parts[0] < 8752 || parts[0] > 8753 {
		t.Errorf("unexpected first share %d", parts[0])
	}
	if parts[0]+parts[1] != 21006 {
		t.Errorf("sum %d != 21006", parts[0]+parts[1])
	}

	// Deterministic: same input, same output.
	again := Allocate(21006, []int64{5, 7})
	if parts[0] != again[0] || parts[1] != again[1] {
		t.Errorf("Allocate is not deterministic: %v vs %v", parts, again)
	}
}

func TestPiastresArithmeticExact(t *testing.T) {
	box := Piastres(10500)
	line := box.MulQty(2).Add(Piastres(1750).MulQty(3))
	if line != 26250 {
		t.Errorf("2 boxes + 3 strips = %d, want 26250", line)
	}
	if !line.Valid() {
		t.Errorf("26250 must be valid")
	}
	if Piastres(-1).Valid() || Piastres(Max + 1).Valid() {
		t.Errorf("range validation broken")
	}
}
