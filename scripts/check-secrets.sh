#!/bin/bash
# Escáner de secretos pre-publicación: cero tolerancia.
# Se ejecuta en CI antes de empaquetar. Sale 1 si encuentra algo.
set -Eeuo pipefail
cd "$(dirname "$0")/.."

PATTERNS='sk-[A-Za-z0-9]{16,}|sk-ant-[A-Za-z0-9]|xai-[A-Za-z0-9]{16,}|ghp_[A-Za-z0-9]{20,}|gho_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}|BEGIN (RSA|EC|OPENSSH) PRIVATE KEY|(_API_KEY|apikey|api_key)["'"'"' ]*[:=]["'"'"' ]?[A-Za-z0-9_-]{16,}'

# Fuentes, docs, scripts y skills. Sin binarios ni imágenes.
FILES=$(find . -type f \
    \( -name "*.swift" -o -name "*.md" -o -name "*.sh" -o -name "*.json" \
       -o -name "*.yml" -o -name "*.plist" -o -name "*.py" \) \
    -not -path "./.build/*" -not -path "./.git/*" -not -path "./dist/*" \
    -not -path "./.swiftpm/*" 2>/dev/null)

HITS=$(grep -InE "$PATTERNS" $FILES 2>/dev/null || true)
if [ -n "$HITS" ]; then
    echo "✗ POSIBLES SECRETOS EN EL REPO:"
    echo "$HITS"
    exit 1
fi
echo "✓ Escáner de secretos limpio ($(echo "$FILES" | wc -l | tr -d ' ') archivos revisados)."
