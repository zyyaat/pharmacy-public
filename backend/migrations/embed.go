package migrations

import "embed"

// FS contains the SQL migrations that are packaged into the backend binary.
// The Docker runtime only contains the compiled binary, so migrations must be
// embedded instead of read from the container filesystem at runtime.
//go:embed *.sql
var FS embed.FS