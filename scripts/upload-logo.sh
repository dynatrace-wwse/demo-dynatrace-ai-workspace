#!/usr/bin/env bash
# Upload a logo image to Dynatrace Document Store via dtctl exec function.
#
# Uses query-params + FormData content — required for this tenant.
# The two-step approach (JSON POST for metadata, then PUT for content) returns
# 415 on sprint tenants; use this single-POST form instead.
#
# Usage:
#   ./upload-logo.sh <image-file> <doc-id> <description>
#   ./upload-logo.sh sap-abap-logo.png sap-abap-logo "SAP Logo"

set -euo pipefail

FILE="${1:-$(dirname "$0")/sap-abap-logo.png}"
DOC_ID="${2:-sap-abap-logo}"
DESCRIPTION="${3:-Dashboard logo}"

if [[ ! -f "$FILE" ]]; then
  echo "ERROR: Image file not found: $FILE" >&2
  exit 1
fi

MIME_TYPE="image/png"
case "${FILE##*.}" in
  jpg|jpeg) MIME_TYPE="image/jpeg" ;;
  svg)      MIME_TYPE="image/svg+xml" ;;
  webp)     MIME_TYPE="image/webp" ;;
esac

FILENAME=$(basename "$FILE")
BASE64=$(base64 < "$FILE" | tr -d '\n')

TMP_JS=$(mktemp /tmp/dtlogo.XXXXXX.js)
trap 'rm -f "$TMP_JS"' EXIT

cat > "$TMP_JS" << 'JSEOF'
export default async function({ docId, name, description, mimeType, filename, base64 }) {
  const binaryStr = atob(base64);
  const bytes = new Uint8Array(binaryStr.length);
  for (let i = 0; i < binaryStr.length; i++) {
    bytes[i] = binaryStr.charCodeAt(i);
  }
  const blob = new Blob([bytes], { type: mimeType });

  // Check if document already exists
  const metaRes = await fetch(`/platform/document/v1/documents/${docId}/metadata`);

  if (metaRes.ok) {
    // Document exists — update content via PUT
    const meta = await metaRes.json();
    const version = meta.version;
    const formData = new FormData();
    formData.append('content', blob, filename);
    const res = await fetch(
      `/platform/document/v1/documents/${docId}/content?optimistic-locking-version=${version}`,
      { method: 'PUT', body: formData }
    );
    const body = await res.text();
    return { action: 'updated', status: res.status, body };
  }

  // Document does not exist — create with query params + content in one POST.
  // NOTE: JSON-body POST returns 415 on sprint tenants. Use query params instead.
  const params = new URLSearchParams({ id: docId, name, type: 'image', isPrivate: 'false' });
  const formData = new FormData();
  formData.append('content', blob, filename);
  const res = await fetch(`/platform/document/v1/documents?${params}`, {
    method: 'POST',
    body: formData,
  });
  const body = await res.text();
  return { action: res.ok ? 'created' : 'create_failed', status: res.status, body };
}
JSEOF

echo "Uploading $FILE as document '$DOC_ID'..."
dtctl exec function -f "$TMP_JS" \
  --payload "{\"docId\":\"$DOC_ID\",\"name\":\"$DOC_ID\",\"description\":\"$DESCRIPTION\",\"mimeType\":\"$MIME_TYPE\",\"filename\":\"$FILENAME\",\"base64\":\"$BASE64\"}" \
  --plain

echo "defaultSource: /platform/document/v1/documents/$DOC_ID/content"
