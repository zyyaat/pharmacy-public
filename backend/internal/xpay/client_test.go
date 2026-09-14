package xpay

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"testing"
	"time"
)

// sign is the reference signer — the EXACT algorithm from the official
// docs (https://docs.xpay.app/en/integrate/webhooks/verifying-signatures):
//
//	signedPayload = `${timestamp}.${rawRequestBody}`
//	signature     = hex(HMAC-SHA256(endpointSecret, signedPayload))
func sign(t *testing.T, secret, timestamp, rawBody string) string {
	t.Helper()
	mac := hmac.New(sha256.New, []byte(secret))
	mac.Write([]byte(timestamp))
	mac.Write([]byte("."))
	mac.Write([]byte(rawBody))
	return hex.EncodeToString(mac.Sum(nil))
}

func TestVerifyWebhookSignatureHappyPath(t *testing.T) {
	secret := "whsec_test_abc123"
	rawBody := `{"id":"evt_test_1","type":"checkout.session.completed","data":{"object":{"id":"cs_test_1"}}}`
	ts := fmt.Sprintf("%d", time.Now().Unix())
	sig := sign(t, secret, ts, rawBody)
	header := "t=" + ts + ",v1=" + sig
	if !VerifyWebhookSignature([]byte(rawBody), header, secret) {
		t.Fatal("valid signature rejected")
	}
}

func TestVerifyWebhookSignatureRejectsTamperedBody(t *testing.T) {
	secret := "whsec_test_abc123"
	rawBody := `{"amountTotal":10000}`
	ts := fmt.Sprintf("%d", time.Now().Unix())
	header := "t=" + ts + ",v1=" + sign(t, secret, ts, rawBody)
	if VerifyWebhookSignature([]byte(`{"amountTotal":99000}`), header, secret) {
		t.Fatal("tampered body accepted")
	}
}

func TestVerifyWebhookSignatureRejectsWrongSecret(t *testing.T) {
	rawBody := `{"x":1}`
	ts := fmt.Sprintf("%d", time.Now().Unix())
	header := "t=" + ts + ",v1=" + sign(t, "whsec_right", ts, rawBody)
	if VerifyWebhookSignature([]byte(rawBody), header, "whsec_wrong") {
		t.Fatal("wrong secret accepted")
	}
}

func TestVerifyWebhookSignatureReplayWindow(t *testing.T) {
	secret := "whsec_test_abc123"
	rawBody := `{"x":1}`
	old := time.Now().Add(-6 * time.Minute).Unix() // beyond the 300s window
	ts := fmt.Sprintf("%d", old)
	header := "t=" + ts + ",v1=" + sign(t, secret, ts, rawBody)
	if VerifyWebhookSignature([]byte(rawBody), header, secret) {
		t.Fatal("stale timestamp accepted (replay window violated)")
	}
	// just inside the window must pass
	recent := fmt.Sprintf("%d", time.Now().Add(-4*time.Minute).Unix())
	header = "t=" + recent + ",v1=" + sign(t, secret, recent, rawBody)
	if !VerifyWebhookSignature([]byte(rawBody), header, secret) {
		t.Fatal("recent signature rejected inside window")
	}
}

func TestParseSignatureHeaderMalformed(t *testing.T) {
	cases := []string{
		"",
		"t=123",                 // missing v1
		"v1=abcd",               // missing t
		"t=abc,v1=abcd",         // non-numeric t
		"garbage",
		"t=123,v1=",             // empty v1
	}
	for _, header := range cases {
		if _, _, ok := ParseSignatureHeader(header); ok {
			t.Fatalf("malformed header accepted: %q", header)
		}
	}
}

// The verifier hashes the RAW bytes; re-serializing JSON (different
// whitespace / key order) must NOT verify against the original signature —
// the exact failure mode the docs warn about with framework body parsers.
func TestVerifyWebhookSignatureRawBytesOnly(t *testing.T) {
	secret := "whsec_test_abc123"
	rawBody := `{"id":"evt_1",  "type":"checkout.session.completed"}`
	ts := fmt.Sprintf("%d", time.Now().Unix())
	header := "t=" + ts + ",v1=" + sign(t, secret, ts, rawBody)
	reserialized := `{"type":"checkout.session.completed","id":"evt_1"}`
	if VerifyWebhookSignature([]byte(reserialized), header, secret) {
		t.Fatal("re-serialized body accepted — raw-byte contract violated")
	}
}
