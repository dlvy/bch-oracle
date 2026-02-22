#!/bin/bash
# Example: Create a BCH price oracle that publishes on-chain

set -e

API_URL="http://localhost:8080"

echo "=== BCH Price Oracle Example ==="
echo ""

# 1. Create the task
echo "1. Creating BCH price oracle task..."
TASK_RESPONSE=$(curl -s -X POST "$API_URL/tasks" \
  -H 'Content-Type: application/json' \
  -d '{
    "name": "BCH/USD Price Oracle",
    "source_url": "https://api.coinbase.com/v2/prices/BCH-USD/spot",
    "prompt": "This is the Coinbase API response:\n{content}\n\nExtract the BCH price in USD. Reply with ONLY the number, no currency symbols.",
    "parse_rule": "price",
    "interval_seconds": 300
  }')

TASK_ID=$(echo "$TASK_RESPONSE" | grep -o '"id":[0-9]*' | cut -d':' -f2)
echo "✓ Task created with ID: $TASK_ID"
echo ""

# 2. Deploy the contract
echo "2. Deploying BCH smart contract for task $TASK_ID..."
curl -s -X POST "$API_URL/tasks/$TASK_ID/deploy-contract" | grep -o '"message":"[^"]*"'
echo ""
sleep 2

# 3. Run the task immediately
echo "3. Running task to get first result..."
curl -s -X POST "$API_URL/tasks/$TASK_ID/run" | grep -o '"message":"[^"]*"'
echo ""
sleep 5

# 4. Check results
echo "4. Fetching results..."
curl -s "$API_URL/tasks/$TASK_ID/results" | python3 -m json.tool
echo ""

echo "=== Setup Complete ==="
echo ""
echo "Your BCH price oracle is now running!"
echo "- Task ID: $TASK_ID"
echo "- Interval: Every 5 minutes"
echo "- View results: curl $API_URL/tasks/$TASK_ID/results"
echo ""
echo "If BCH_PUBLISH_ENABLED=true, results are being published on-chain."
echo "Check the contract at: contracts/artifacts/contract-$TASK_ID.json"
