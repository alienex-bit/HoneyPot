# Environment Variables: HoneyPot

## Required Keys
| Key | Description | Example / Default |
|-----|-------------|-------------------|
| `APP_ENV` | Runtime environment | `development` |
| `PORT` | Application port | `3000` |
| `DATABASE_URL` | Database connection string | _(no default — must be set)_ |
| `SECRET_KEY` | Auth / encryption secret | _(no default — must be set)_ |

## Optional Keys
| Key | Description | Default |
|-----|-------------|---------|
| `LOG_LEVEL` | Logging verbosity | `info` |
| `DEBUG` | Enable debug mode | `false` |

## Local Setup
1. Copy `.env.example` to `.env` in the project root.
2. Fill in any keys marked _(no default)_.
3. **Never commit `.env` to version control** — add it to `.gitignore`.

## Notes
_Add any environment-specific notes here (e.g. cloud secrets, CI variables)._
