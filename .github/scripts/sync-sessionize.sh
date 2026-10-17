#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="${CONFIG:-hugo.yaml}"
TARGET_FILE="data/sessionize.json"

# Extract sessionizeId from hugo.yaml if SESSIONIZE_ID is not already set
if [[ -z "${SESSIONIZE_ID:-}" ]]; then
  SESSIONIZE_ID="$(grep -E '^\s*sessionizeId:\s*' "$CONFIG_FILE" | head -n1 | sed -E 's/^\s*sessionizeId:\s*["'\'']?([^"'\''#[:space:]]*)["'\'']?.*$/\1/')"
fi

if [[ -z "$SESSIONIZE_ID" ]]; then
  echo "::error::No se encontró sessionizeId en ${CONFIG_FILE}"
  exit 1
fi

API_URL="https://sessionize.com/api/v2/${SESSIONIZE_ID}/view/all"
TMP_FILE="$(mktemp)"
trap 'rm -f "$TMP_FILE"' EXIT

echo "Consultando Sessionize API (${API_URL})..."
curl -fsSL --retry 3 --retry-delay 2 -H "Accept: application/json" "$API_URL" -o "$TMP_FILE"

# Validate structure and format deterministically so git diff only triggers on real changes
jq -S '
  if (type == "object") and (.sessions | type == "array") and (.speakers | type == "array") then
    {
      categories: (.categories // []),
      questions: (.questions // []),
      rooms: (.rooms // []),
      sessions: (.sessions | sort_by(.startsAt // "", (.id | tostring))),
      speakers: (.speakers | sort_by(.fullName // "", (.id | tostring)))
    }
  else
    error("Respuesta inválida desde Sessionize API")
  end
' "$TMP_FILE" > "$TARGET_FILE"

SPEAKER_COUNT="$(jq '.speakers | length' "$TARGET_FILE")"
SESSION_COUNT="$(jq '[.sessions[] | select((.isServiceSession // false) == false)] | length' "$TARGET_FILE")"
echo "Sessionize sincronizado: ${SPEAKER_COUNT} orador(es), ${SESSION_COUNT} charla(s)."

if git diff --quiet -- "$TARGET_FILE"; then
  echo "Sin cambios en ${TARGET_FILE}."
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "changed=false" >> "$GITHUB_OUTPUT"
  fi
  exit 0
fi

# Build a descriptive commit message with the approved speakers and talks
SPEAKER_NAMES="$(jq -r '[.speakers[].fullName] | join(", ")' "$TARGET_FILE")"
SESSION_TITLES="$(jq -r '[.sessions[] | select((.isServiceSession // false) == false) | .title] | join(" | ")' "$TARGET_FILE")"

COMMIT_TITLE="feat(sessionize): actualizar oradores (${SPEAKER_COUNT}) y charlas (${SESSION_COUNT})"
COMMIT_BODY="Sincronización automática desde Sessionize (${SESSIONIZE_ID})."
if [[ -n "$SPEAKER_NAMES" ]]; then
  COMMIT_BODY="${COMMIT_BODY}"$'\n'"Oradores: ${SPEAKER_NAMES}"
fi
if [[ -n "$SESSION_TITLES" ]]; then
  COMMIT_BODY="${COMMIT_BODY}"$'\n'"Charlas: ${SESSION_TITLES}"
fi

echo "Cambios detectados en ${TARGET_FILE}:"
echo "$COMMIT_TITLE"
echo "$COMMIT_BODY"

if [[ "${COMMIT_CHANGES:-true}" == "true" ]]; then
  git config user.name "${GIT_AUTHOR_NAME:-github-actions[bot]}"
  git config user.email "${GIT_AUTHOR_EMAIL:-41898282+github-actions[bot]@users.noreply.github.com}"
  git add "$TARGET_FILE"
  git commit -m "$COMMIT_TITLE" -m "$COMMIT_BODY"

  if [[ "${PUSH_CHANGES:-false}" == "true" ]]; then
    git push origin HEAD:main
  fi
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "changed=true" >> "$GITHUB_OUTPUT"
fi
