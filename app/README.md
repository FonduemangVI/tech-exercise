# tasky

Two-tier todo app used by the exercise: Go (gin) front end, MongoDB back end.

Copied from [jeffthorne/tasky](https://github.com/jeffthorne/tasky) at commit
`4c432729814c8056df37c31e5d18fa325fd862d1`. Its README states the MIT licence; the
original project is [dogukanozdemir/golang-todo-mongodb](https://github.com/dogukanozdemir/golang-todo-mongodb).

## Changes from upstream

| Change | Why |
|---|---|
| `database/database.go` no longer prints `MONGODB_URI` at startup | The URI contains the database password, which ended up in container logs |
| Dependencies updated (gin, mongo-driver v1, x/crypto, x/net and the rest) | Upstream pins 2021-22 versions with 34 HIGH CVEs; the pipeline's Trivy gate fails on HIGH and CRITICAL |
| `github.com/dgrijalva/jwt-go` replaced with `github.com/golang-jwt/jwt` v3.2.2 (`replace` in `go.mod`) | Unmaintained, CVE-2020-26160. The fork has the same API, so no code change |
| `Dockerfile` rewritten | Base images from ACR, non-root user, `wizexercise.txt` added (R16) |
| `wizexercise.txt` added | Required by the brief: contains my name |

Everything else is upstream code, unchanged.

## Configuration

| Variable | Source in the cluster |
|---|---|
| `MONGODB_URI` | Key Vault secret `mongo-app-uri`, synced by the Secrets Store CSI driver |
| `SECRET_KEY` | Key Vault secret `tasky-jwt-secret`, same route |

Listens on port 8080.
