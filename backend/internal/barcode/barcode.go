// Package barcode implements the platform's internal barcode standard:
// GS1 Restricted Circulation Number (RCN) EAN-13 with the fixed prefix "20"
// (GS1 General Specifications §8.2).
//
// Structure of a generated code:
//
//	"20" + 10-digit platform sequence + Mod-10 check digit  => 13 digits
//
// Properties (barcode-design-v2-review.md §1.3, §7.1):
//   - It is an INTERNAL barcode, not a global GTIN: GS1 does not issue
//     company prefixes starting with 2, so a normal factory GTIN can never
//     structurally begin with the same digit. RCNs are not globally unique
//     though — uniqueness here is enforced by the database unique index,
//     not claimed against the rest of the world.
//   - It is mechanically readable by any EAN/UPC scanner: valid length,
//     digits only, valid Mod-10 check digit.
//
// Nothing in this package touches randomness: generation is a pure
// function of the atomic database sequence value, which makes retries
// deterministic and collisions with other generated codes impossible.
package barcode

import (
	"errors"
	"fmt"
	"strconv"
)

// Locked barcode_type vocabulary (global_products.barcode_type CHECK).
// Derived server-side at write time — the user never picks a type.
const (
	TypeGTINEAN13 = "GTIN_EAN13" // 13 digits, valid Mod-10, prefix != 2
	TypeGTINUPCA  = "GTIN_UPCA"  // 12 digits, valid UPC-A check
	TypeRCNEAN13  = "RCN_EAN13"  // 13 digits, valid Mod-10, prefix 2 (internal)
	TypeCODE128   = "CODE128"    // contains non-digits (alphanumeric code)
	TypeOTHER     = "OTHER"      // numeric but fails every check above
)

const (
	rcnPrefix      = "20"
	sequenceDigits = 10
	ean13Length    = 13
	upcaLength     = 12
)

// SequenceMax is the largest sequence value that keeps the payload at
// exactly 10 digits. The database sequence is capped at the same value, so
// exhaustion fails loudly at nextval() instead of emitting a longer code.
const SequenceMax = int64(9_999_999_999)

// ErrSequenceExhausted is returned when the platform sequence has consumed
// the entire 10-digit space (10 billion codes).
var ErrSequenceExhausted = errors.New("internal barcode sequence exhausted")

// digit checks whether r is an ASCII digit and returns its value.
func digit(r byte) (int, bool) {
	if r < '0' || r > '9' {
		return 0, false
	}
	return int(r - '0'), true
}

// EAN13CheckDigit computes the GS1 Mod-10 check digit for a 12-digit data
// payload (weights 1,3,1,3,... from the left).
func EAN13CheckDigit(data12 string) (int, error) {
	if len(data12) != ean13Length-1 {
		return 0, fmt.Errorf("EAN-13 payload must be %d digits, got %d", ean13Length-1, len(data12))
	}
	sum := 0
	for i := 0; i < len(data12); i++ {
		d, ok := digit(data12[i])
		if !ok {
			return 0, errors.New("EAN-13 payload must contain digits only")
		}
		if i%2 == 0 {
			sum += d
		} else {
			sum += 3 * d
		}
	}
	return (10 - sum%10) % 10, nil
}

// EAN13IsValid reports whether code is a structurally valid EAN-13:
// 13 digits with a correct Mod-10 check digit.
func EAN13IsValid(code string) bool {
	if len(code) != ean13Length {
		return false
	}
	check, err := EAN13CheckDigit(code[:ean13Length-1])
	if err != nil {
		return false
	}
	last, ok := digit(code[ean13Length-1])
	return ok && last == check
}

// UPCAIsValid reports whether code is a structurally valid UPC-A:
// 12 digits with a correct check digit (weights 3,1,3,1,... on the first 11).
func UPCAIsValid(code string) bool {
	if len(code) != upcaLength {
		return false
	}
	sum := 0
	for i := 0; i < upcaLength-1; i++ {
		d, ok := digit(code[i])
		if !ok {
			return false
		}
		if i%2 == 0 {
			sum += 3 * d
		} else {
			sum += d
		}
	}
	last, ok := digit(code[upcaLength-1])
	if !ok {
		return false
	}
	return last == (10-sum%10)%10
}

// BuildRCNEAN13 assembles the complete internal barcode for one sequence
// value: "20" + zero-padded 10-digit sequence + Mod-10 check digit.
func BuildRCNEAN13(seq int64) (string, error) {
	if seq < 1 {
		return "", fmt.Errorf("internal barcode sequence must be positive, got %d", seq)
	}
	if seq > SequenceMax {
		return "", ErrSequenceExhausted
	}
	payload := rcnPrefix + fmt.Sprintf("%0*d", sequenceDigits, seq)
	check, err := EAN13CheckDigit(payload)
	if err != nil {
		return "", err
	}
	return payload + strconv.Itoa(check), nil
}

// DeriveType classifies a stored, scanned or manually entered code into the
// locked vocabulary. The classification is mechanical so the same code always
// maps to the same type on every platform (web, mobile, import).
func DeriveType(code string) string {
	if EAN13IsValid(code) {
		if code[0] == '2' {
			return TypeRCNEAN13
		}
		return TypeGTINEAN13
	}
	if UPCAIsValid(code) {
		return TypeGTINUPCA
	}
	for i := 0; i < len(code); i++ {
		if _, ok := digit(code[i]); !ok {
			return TypeCODE128
		}
	}
	return TypeOTHER
}
