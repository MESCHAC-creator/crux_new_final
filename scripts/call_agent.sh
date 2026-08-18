#!/usr/bin/env bash
# Call a CRUX platform agent via Anthropic API
# Usage: ./scripts/call_agent.sh <key> "<prompt>"
# Keys: qa | engineer | designer | architect | orchestrator
# Requires: ANTHROPIC_API_KEY env var

set -e

AGENT_KEY="${1}"
PROMPT="${2}"
AGENTS_FILE="$(dirname "$0")/agents.json"

if [ -z "$ANTHROPIC_API_KEY" ]; then
  echo "ERROR: ANTHROPIC_API_KEY not set" >&2
  echo "  export ANTHROPIC_API_KEY=sk-ant-..." >&2
  exit 1
fi

if [ -z "$AGENT_KEY" ] || [ -z "$PROMPT" ]; then
  echo "Usage: $0 <key> \"<prompt>\"" >&2
  echo "Keys: qa | engineer | designer | architect | orchestrator" >&2
  exit 1
fi

AGENT_ID=$(python3 -c "import json; d=json.load(open('$AGENTS_FILE')); print(d['agents']['$AGENT_KEY']['id'])" 2>/dev/null)
AGENT_NAME=$(python3 -c "import json; d=json.load(open('$AGENTS_FILE')); print(d['agents']['$AGENT_KEY']['name'])" 2>/dev/null)
MODEL=$(python3 -c "import json; d=json.load(open('$AGENTS_FILE')); print(d['model'])")

if [ -z "$AGENT_ID" ]; then
  echo "ERROR: Unknown key '$AGENT_KEY'. Available: qa | engineer | designer | architect | orchestrator" >&2
  exit 1
fi

echo ">>> $AGENT_NAME"
echo ""

PAYLOAD=$(python3 -c "
import json, sys
prompt = '''$PROMPT'''
payload = {
    'model': '$MODEL',
    'agent_id': '$AGENT_ID',
    'max_tokens': 4096,
    'messages': [{'role': 'user', 'content': prompt}]
}
print(json.dumps(payload))
")

curl -s https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d "$PAYLOAD" | python3 -c "
import json, sys
r = json.load(sys.stdin)
if 'content' in r:
    for block in r['content']:
        if block.get('type') == 'text':
            print(block['text'])
elif 'error' in r:
    print('API ERROR:', r['error'].get('message', str(r['error'])), file=sys.stderr)
    sys.exit(1)
else:
    print(json.dumps(r, indent=2))
"
