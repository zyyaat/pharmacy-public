package auth

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestSuperAdminThrottleIsScopedToEmailAndIP(t *testing.T) {
	service := &Service{
		superAdminThrottles: make(map[string]superAdminThrottle),
	}

	for i := 0; i < superAdminFailureLimit-1; i++ {
		require.False(t, service.recordSuperAdminFailure("admin@example.com", "203.0.113.10"))
	}
	require.True(t, service.recordSuperAdminFailure("admin@example.com", "203.0.113.10"))
	require.True(t, service.superAdminLoginRateLimited("admin@example.com", "203.0.113.10"))

	require.False(t, service.superAdminLoginRateLimited("admin@example.com", "203.0.113.11"))
	require.False(t, service.superAdminLoginRateLimited("other@example.com", "203.0.113.10"))
}

func TestSuccessfulSuperAdminLoginClearsThrottle(t *testing.T) {
	service := &Service{
		superAdminThrottles: make(map[string]superAdminThrottle),
	}

	for i := 0; i < superAdminFailureLimit; i++ {
		service.recordSuperAdminFailure("admin@example.com", "203.0.113.10")
	}
	require.True(t, service.superAdminLoginRateLimited("admin@example.com", "203.0.113.10"))
	service.clearSuperAdminFailures("admin@example.com", "203.0.113.10")
	require.False(t, service.superAdminLoginRateLimited("admin@example.com", "203.0.113.10"))
}
