#!/usr/bin/env sh
set -eu

if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
fi

domain="${DOMAIN:-nodeget.example.com}"
backend_url="${STATUS_BACKEND_URL:-wss://${domain}/ws}"

mkdir -p statushow
cat >statusshow/config.json <<EOF
{
  "site_name": "${STATUS_SITE_NAME:-NodeGet Status}",
  "site_logo": "${STATUS_SITE_LOGO:-}",
  "footer": "${STATUS_SITE_FOOTER:-Powered by NodeGet}",
  "site_tokens": [
    {
      "name": "${STATUS_BACKEND_NAME:-main}",
      "backend_url": "${backend_url}",
      "token": "${STATUS_TOKEN:-}"
    }
  ]
}
EOF

echo "Wrote statushow/config.json"

