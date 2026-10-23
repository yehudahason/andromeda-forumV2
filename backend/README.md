# Andromeda Forum V2 — Go API

The uploaded Go API has been reorganized into packages, keeping its routes, queries,
response types, validation logic, and existing behavior intact. The original `go.mod`
and `go.sum` are unchanged.

## Layout

```text
andromeda-forumV2/
├── cmd/
│   └── api/
│       └── main.go                 # App startup, database/JWKS initialization
├── internal/
│   ├── auth/
│   │   └── auth.go                # Supabase JWT/JWKS verification + current user
│   ├── handlers/
│   │   ├── handler.go             # Shared handler dependencies (DB, logger, auth)
│   │   ├── forums.go              # Forum API
│   │   ├── threads.go             # Thread API
│   │   ├── replies.go             # Reply API
│   │   ├── follows.go             # Follow/unfollow API
│   │   ├── posts.go               # Latest posts API
│   │   ├── notifications.go       # Notification helpers
│   │   ├── private_messages.go    # Private messaging API
│   │   ├── users.go               # User and /api/me API
│   │   ├── uploads.go             # Image upload HTTP endpoint
│   │   └── admin.go               # Administrative delete endpoint
│   ├── models/
│   │   └── models.go              # Shared request and response types
│   ├── server/
│   │   ├── routes.go              # HTTP method and path registration
│   │   ├── loggerMiddleware.go
│   │   ├── recoverMiddleware.go
│   │   ├── corsMiddleware.go
│   │   └── response_writer.go
│   └── storage/
│       └── r2.go                  # Cloudflare R2 client and upload utilities
├── go.mod
├── go.sum
└── README.md
```

## Run

Use the Go version stated in `go.mod` (Go 1.26.5) and supply your existing
`.env` in the project root, then run:

```bash
go mod download
go run ./cmd/api
```

To build the binary:

```bash
go build -o api ./cmd/api
```

The server still listens on `:4000` and loads `.env` from its working directory.

## Existing environment configuration

The code reads these environment variables (copy their existing values from your deployment):

- `DATABASE_URL`
- `JWKS_URL`
- `R2_ACCESS_KEY_ID`
- `R2_SECRET_ACCESS_KEY`
- `R2_ENDPOINT`
- `R2_BUCKET`
- `R2_PUBLIC_URL`

Do not commit `.env` or credentials to version control.

## Migration notes

- `package main` now only contains startup code in `cmd/api/main.go`.
- Shared types live in `internal/models` (for example `models.User`, `models.Forum`).
- Handlers are methods of `*handlers.Handler`. They receive the database pool,
  logger, and authentication service explicitly instead of importing globals
  from `main`.
- To add an endpoint: implement a method in `internal/handlers`, then register
  it in `internal/server/routes.go`.
- No database migrations were modified or required by this code reorganization.

## Validation

All Go files passed `gofmt` and local Go AST parsing. A structural check found
no missing handler methods, duplicate method declarations, or unused imports.
The 30 HTTP route registrations and all 190 Go raw string literals were compared
with the uploads and found unchanged.

A full `go test ./...` could not be run in the refactoring environment because
Go 1.26.5 and the module dependencies were not installed and outbound
module downloads were unavailable. Please run the build and test commands
in your normal Go environment.
