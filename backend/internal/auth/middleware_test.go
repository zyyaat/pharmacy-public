package auth

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/gin-gonic/gin"
	"github.com/stretchr/testify/require"
)

func TestRequireEmployeePrincipalRejectsCompanyUsers(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.Use(func(c *gin.Context) {
		setPrincipal(c, &Principal{
			Type:      CompanyUserPrincipal,
			CompanyID: "company-id",
			Role:      "super_admin",
		})
		c.Next()
	})
	router.Use(RequireEmployeePrincipal())
	router.GET("/pharmacy", func(c *gin.Context) {
		c.Status(http.StatusNoContent)
	})

	request := httptest.NewRequest(http.MethodGet, "/pharmacy", nil)
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)

	require.Equal(t, http.StatusForbidden, response.Code)
	require.Contains(t, response.Body.String(), "pharmacy_employee_required")
}

func TestRequirePharmacyPrincipalAllowsCompanyUsersWithPharmacy(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.Use(func(c *gin.Context) {
		setPrincipal(c, &Principal{
			Type:       CompanyUserPrincipal,
			CompanyID:  "company-id",
			PharmacyID: "pharmacy-id",
			Role:       "company_admin",
		})
		c.Next()
	})
	router.Use(RequirePharmacyPrincipal())
	router.GET("/pharmacy", func(c *gin.Context) {
		c.Status(http.StatusNoContent)
	})

	request := httptest.NewRequest(http.MethodGet, "/pharmacy", nil)
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)

	require.Equal(t, http.StatusNoContent, response.Code)
}

func TestRequirePharmacyMutationPrincipalAllowsCompanyAdmin(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.Use(func(c *gin.Context) {
		setPrincipal(c, &Principal{
			Type:       CompanyUserPrincipal,
			ID:         "company-user-id",
			CompanyID:  "company-id",
			PharmacyID: "pharmacy-id",
			Role:       "company_admin",
		})
		c.Next()
	})
	router.Use(RequirePharmacyMutationPrincipal())
	router.POST("/pharmacy", func(c *gin.Context) {
		c.Status(http.StatusNoContent)
	})

	request := httptest.NewRequest(http.MethodPost, "/pharmacy", nil)
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)

	require.Equal(t, http.StatusNoContent, response.Code)
}

func TestRequirePharmacyMutationPrincipalRejectsCompanyViewer(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.Use(func(c *gin.Context) {
		setPrincipal(c, &Principal{
			Type:       CompanyUserPrincipal,
			ID:         "company-user-id",
			CompanyID:  "company-id",
			PharmacyID: "pharmacy-id",
			Role:       "company_viewer",
		})
		c.Next()
	})
	router.Use(RequirePharmacyMutationPrincipal())
	router.POST("/pharmacy", func(c *gin.Context) {
		c.Status(http.StatusNoContent)
	})

	request := httptest.NewRequest(http.MethodPost, "/pharmacy", nil)
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)

	require.Equal(t, http.StatusForbidden, response.Code)
	require.Contains(t, response.Body.String(), "pharmacy_mutation_account_required")
}

func TestRequirePharmacyPrincipalRejectsSuperAdminWithPharmacy(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.Use(func(c *gin.Context) {
		setPrincipal(c, &Principal{
			Type:       CompanyUserPrincipal,
			CompanyID:  "company-id",
			PharmacyID: "pharmacy-id",
			Role:       "super_admin",
		})
		c.Next()
	})
	router.Use(RequirePharmacyPrincipal())
	router.GET("/pharmacy", func(c *gin.Context) {
		c.Status(http.StatusNoContent)
	})

	request := httptest.NewRequest(http.MethodGet, "/pharmacy", nil)
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)

	require.Equal(t, http.StatusForbidden, response.Code)
	require.Contains(t, response.Body.String(), "pharmacy_account_required")
}

func TestRequirePharmacyPrincipalRejectsUnassignedCompanyUsers(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.Use(func(c *gin.Context) {
		setPrincipal(c, &Principal{
			Type:      CompanyUserPrincipal,
			CompanyID: "company-id",
		})
		c.Next()
	})
	router.Use(RequirePharmacyPrincipal())
	router.GET("/pharmacy", func(c *gin.Context) {
		c.Status(http.StatusNoContent)
	})

	request := httptest.NewRequest(http.MethodGet, "/pharmacy", nil)
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)

	require.Equal(t, http.StatusForbidden, response.Code)
	require.Contains(t, response.Body.String(), "pharmacy_account_required")
}

func TestRequireEmployeePrincipalAllowsEmployeeWithPharmacy(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := gin.New()
	router.Use(func(c *gin.Context) {
		setPrincipal(c, &Principal{
			Type:       EmployeePrincipal,
			PharmacyID: "pharmacy-id",
		})
		c.Next()
	})
	router.Use(RequireEmployeePrincipal())
	router.GET("/pharmacy", func(c *gin.Context) {
		c.Status(http.StatusNoContent)
	})

	request := httptest.NewRequest(http.MethodGet, "/pharmacy", nil)
	response := httptest.NewRecorder()
	router.ServeHTTP(response, request)

	require.Equal(t, http.StatusNoContent, response.Code)
}

func TestPrincipalRealmBoundaries(t *testing.T) {
	require.True(t, principalAllowedInRealm(&Principal{
		Type:     CompanyUserPrincipal,
		Role:     "super_admin",
		IsActive: true,
	}, PlatformRealm))
	require.False(t, principalAllowedInRealm(&Principal{
		Type:       CompanyUserPrincipal,
		Role:       "super_admin",
		PharmacyID: "pharmacy-id",
	}, PharmacyRealm))
	require.True(t, principalAllowedInRealm(&Principal{
		Type:       CompanyUserPrincipal,
		Role:       "company_manager",
		PharmacyID: "pharmacy-id",
		IsActive:   true,
	}, PharmacyRealm))
	require.False(t, principalAllowedInRealm(&Principal{
		Type: CompanyUserPrincipal,
		Role: "company_manager",
	}, PharmacyRealm))
}
