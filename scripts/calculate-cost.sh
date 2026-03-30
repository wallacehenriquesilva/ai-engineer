#!/bin/bash
# calculate-cost.sh — Calcula custo e tokens da sessão Claude Code atual
# Uso: source scripts/calculate-cost.sh

SESSION_FILE=$(ls -t ~/.claude/projects/**/*.jsonl 2>/dev/null | head -1)

if [ -z "$SESSION_FILE" ] || [ ! -f "$SESSION_FILE" ]; then
  echo "COST=N/A INPUT=0 CACHE_WRITE=0 CACHE_READ=0 OUTPUT=0"; exit 0
fi

TOKENS=$(jq -r 'select(.type == "assistant" and .message.usage != null) | .message.usage' \
  "$SESSION_FILE" 2>/dev/null | jq -s '{
  input:       (map(.input_tokens // 0) | add // 0),
  cache_write: (map(.cache_creation_input_tokens // 0) | add // 0),
  cache_read:  (map(.cache_read_input_tokens // 0) | add // 0),
  output:      (map(.output_tokens // 0) | add // 0)
}' 2>/dev/null)

[ -z "$TOKENS" ] || [ "$TOKENS" = "null" ] && \
  echo "COST=N/A INPUT=0 CACHE_WRITE=0 CACHE_READ=0 OUTPUT=0" && exit 0

INPUT=$(echo "$TOKENS" | jq '.input // 0')
CACHE_WRITE=$(echo "$TOKENS" | jq '.cache_write // 0')
CACHE_READ=$(echo "$TOKENS" | jq '.cache_read // 0')
OUTPUT=$(echo "$TOKENS" | jq '.output // 0')

COST=$(jq -r '
  select(.type == "assistant" and .message.usage != null) |
  .message.usage as $u |
  (if .message.model then .message.model else "" end) as $model |
  (if ($model | test("opus")) then
    (($u.input_tokens // 0) * 0.000005 +
     ($u.cache_creation_input_tokens // 0) * 0.000003750 +
     ($u.cache_read_input_tokens // 0) * 0.0000003 +
     ($u.output_tokens // 0) * 0.000025)
  else
    (($u.input_tokens // 0) * 0.000003 +
     ($u.cache_creation_input_tokens // 0) * 0.000003750 +
     ($u.cache_read_input_tokens // 0) * 0.0000003 +
     ($u.output_tokens // 0) * 0.000015)
  end)
' "$SESSION_FILE" 2>/dev/null | awk '{sum += $1} END {printf "%.4f", sum}')

COST=${COST:-"N/A"}
echo "COST=$COST INPUT=$INPUT CACHE_WRITE=$CACHE_WRITE CACHE_READ=$CACHE_READ OUTPUT=$OUTPUT"
