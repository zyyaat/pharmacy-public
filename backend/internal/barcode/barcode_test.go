package barcode

import (
	"strings"
	"sync"
	"testing"
)

// TestEAN13CheckDigitKnownVectors uses published GS1 example codes.
func TestEAN13CheckDigitKnownVectors(t *testing.T) {
	cases := []struct {
		payload string
		check   int
	}{
		{"400638133393", 1}, // Stabilo pen (classic GS1 example)
		{"590123412345", 7}, // widely published example
		{"200000000001", 5}, // RCN payload: 2+3 = 5
		{"200000000002", 2}, // 2 + 2*3 = 8 -> (10-8)%10 = 2
	}
	for _, tc := range cases {
		got, err := EAN13CheckDigit(tc.payload)
		if err != nil {
			t.Fatalf("EAN13CheckDigit(%q) unexpected error: %v", tc.payload, err)
		}
		if got != tc.check {
			t.Errorf("EAN13CheckDigit(%q) = %d, want %d", tc.payload, got, tc.check)
		}
	}
}

func TestEAN13CheckDigitRejectsBadPayload(t *testing.T) {
	if _, err := EAN13CheckDigit("12345"); err == nil {
		t.Error("short payload must fail")
	}
	if _, err := EAN13CheckDigit("40063813339A"); err == nil {
		t.Error("non-digit payload must fail")
	}
}

func TestEAN13IsValid(t *testing.T) {
	if !EAN13IsValid("4006381333931") {
		t.Error("valid GTIN EAN-13 rejected")
	}
	if EAN13IsValid("4006381333932") {
		t.Error("wrong check digit accepted")
	}
	if EAN13IsValid("40063813339") {
		t.Error("12-digit code accepted as EAN-13")
	}
	if EAN13IsValid("400638133393X") {
		t.Error("non-digit check accepted")
	}
}

func TestUPCAIsValid(t *testing.T) {
	// 036000291452 is the standard UPC-A example (check digit 2).
	if !UPCAIsValid("036000291452") {
		t.Error("valid UPC-A rejected")
	}
	if UPCAIsValid("036000291453") {
		t.Error("wrong UPC-A check digit accepted")
	}
	if UPCAIsValid("4006381333931") {
		t.Error("EAN-13 accepted as UPC-A")
	}
}

func TestBuildRCNEAN13Structure(t *testing.T) {
	for _, seq := range []int64{1, 2, 42, 123456, 9_999_999_999} {
		code, err := BuildRCNEAN13(seq)
		if err != nil {
			t.Fatalf("BuildRCNEAN13(%d) unexpected error: %v", seq, err)
		}
		if len(code) != 13 {
			t.Fatalf("BuildRCNEAN13(%d) = %q, want 13 digits", seq, code)
		}
		if !strings.HasPrefix(code, "20") {
			t.Errorf("code %q must start with the RCN prefix 20", code)
		}
		if !EAN13IsValid(code) {
			t.Errorf("generated code %q is not a valid EAN-13", code)
		}
		if got := DeriveType(code); got != TypeRCNEAN13 {
			t.Errorf("DeriveType(%q) = %s, want %s", code, got, TypeRCNEAN13)
		}
		// The sequence must be recoverable from the payload (human-readable
		// monotony, review report §1.3).
		payloadSeq := code[2:12]
		want := ""
		s := seq
		for i := 0; i < 10; i++ {
			want = string(rune('0'+s%10)) + want
			s /= 10
		}
		if payloadSeq != want {
			t.Errorf("payload sequence %q, want %q", payloadSeq, want)
		}
	}
}

func TestBuildRCNEAN13RejectsOutOfRange(t *testing.T) {
	if _, err := BuildRCNEAN13(0); err == nil {
		t.Error("sequence 0 must fail")
	}
	if _, err := BuildRCNEAN13(-1); err == nil {
		t.Error("negative sequence must fail")
	}
	if _, err := BuildRCNEAN13(10_000_000_000); err != ErrSequenceExhausted {
		t.Errorf("overflow must return ErrSequenceExhausted, got %v", err)
	}
}

func TestDeriveType(t *testing.T) {
	cases := []struct {
		code string
		want string
	}{
		{"4006381333931", TypeGTINEAN13},  // valid GTIN EAN-13
		{"2000000000015", TypeRCNEAN13},   // valid internal RCN
		{"036000291452", TypeGTINUPCA},    // valid UPC-A
		{"ABC-123-XYZ", TypeCODE128},      // alphanumeric
		{"INHOUSE-1", TypeCODE128},        // free-form internal
		{"4006381333932", TypeOTHER},      // numeric, broken check digit
		{"1234567890123", TypeOTHER},      // 13 digits, bad check
	}
	for _, tc := range cases {
		if got := DeriveType(tc.code); got != tc.want {
			t.Errorf("DeriveType(%q) = %s, want %s", tc.code, got, tc.want)
		}
	}
}

// TestParallelGenerationUnique mirrors the concurrency invariant: two
// goroutines drawing distinct sequence values must never build the same
// code. The database test (e2e) proves the same against nextval().
func TestParallelGenerationUnique(t *testing.T) {
	const workers = 32
	const perWorker = 250

	mu := sync.Mutex{}
	seen := make(map[string]bool, workers*perWorker)
	var wg sync.WaitGroup
	for w := 0; w < workers; w++ {
		wg.Add(1)
		go func(worker int) {
			defer wg.Done()
			for i := 1; i <= perWorker; i++ {
				code, err := BuildRCNEAN13(int64(worker*perWorker + i))
				if err != nil {
					t.Errorf("unexpected error: %v", err)
					return
				}
				mu.Lock()
				if seen[code] {
					t.Errorf("duplicate generated code: %s", code)
				}
				seen[code] = true
				mu.Unlock()
			}
		}(w)
	}
	wg.Wait()
	if len(seen) != workers*perWorker {
		t.Errorf("generated %d unique codes, want %d", len(seen), workers*perWorker)
	}
}
