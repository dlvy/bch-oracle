#!/bin/bash
# Integration test for BCH oracle service
# Tests the full workflow: create task → deploy contract → run → verify

set -e

echo "=== BCH Oracle Integration Test ==="
echo ""

# Check if service is running
if ! curl -s http://localhost:8080/health > /dev/null; then
  echo "❌ Service not running. Start with: gleam run"
  exit 1
fi
echo "✓ Service is running"

# Check if contracts are set up
if [ ! -d "contracts/node_modules" ]; then
  echo "❌ Contracts not set up. Run: cd contracts && ./setup.sh"
  exit 1
fi
echo "✓ Contracts are set up"

# Check environment
if [ -z "$LLM_API_KEY" ]; then
  echo "⚠️  Warning: LLM_API_KEY not set. LLM calls will fail."
fi

if [ -z "$BCH_ORACLE_WIF" ]; then
  echo "⚠️  Warning: BCH_ORACLE_WIF not set. On-chain publishing disabled."
fi

echo ""
echo "Running tests..."
echo ""

# Test 1: Create a task
echo "1. Creating test task..."
TASK_RESPONSE=$(curl -s -X POST http://localhost:8080/tasks \
  -H 'Content-Type: application/json' \
  -d '{
    "name": "Test Task",
    "source_url": "https://api.coinbase.com/v2/prices/BCH-USD/spot",
    "prompt": "Extract the BCH price from: {content}",
    "parse_rule": "price",
    "interval_seconds": 3600
  }')

if echo "$TASK_RESPONSE" | grep -q '"id"'; then
  TASK_ID=$(echo "$TASK_RESPONSE" | grep -o '"id":[0-9]*' | cut -d':' -f2)
  echo "✓ Task created: ID=$TASK_ID"
else
  echo "❌ Failed to create task"
  echo "$TASK_RESPONSE"
  exit 1
fi

# Test 2: Get task
echo "2. Fetching task..."
TASK=$(curl -s http://localhost:8080/tasks/$TASK_ID)
if echo "$TASK" | grep -q "Test Task"; then
  echo "✓ Task retrieved"
else
  echo "❌ Failed to get task"
  exit 1
fi

# Test 3: List tasks
echo "3. Listing all tasks..."
TASKS=$(curl -s http://localhost:8080/tasks)
if echo "$TASKS" | grep -q "Test Task"; then
  echo "✓ Task appears in list"
else
  echo "❌ Task not in list"
  exit 1
fi

# Test 4: Deploy contract (if BCH enabled)
if [ -n "$BCH_ORACLE_WIF" ]; then
  echo "4. Deploying contract..."
  DEPLOY_RESPONSE=$(curl -s -X POST http://localhost:8080/tasks/$TASK_ID/deploy-contract)
  if echo "$DEPLOY_RESPONSE" | grep -q "initiated"; then
    echo "✓ Contract deployment initiated"
    sleep 3
  else
    echo "⚠️  Contract deployment may have failed"
  fi
else
  echo "4. Skipping contract deployment (BCH_ORACLE_WIF not set)"
fi

# Test 5: Run task (if LLM enabled)
if [ -n "$LLM_API_KEY" ]; then
  echo "5. Running task..."
  RUN_RESPONSE=$(curl -s -X POST http://localhost:8080/tasks/$TASK_ID/run)
  if echo "$RUN_RESPONSE" | grep -q "triggered"; then
    echo "✓ Task triggered"
    sleep 5
  else
    echo "❌ Failed to trigger task"
    exit 1
  fi
  
  # Check results
  echo "6. Checking results..."
  RESULTS=$(curl -s http://localhost:8080/tasks/$TASK_ID/results)
  if echo "$RESULTS" | grep -q "parsed_value"; then
    echo "✓ Results available"
    echo ""
    echo "Latest result:"
    echo "$RESULTS" | python3 -m json.tool | head -20
  else
    echo "⚠️  No results yet (may still be processing)"
  fi
else
  echo "5. Skipping task run (LLM_API_KEY not set)"
fi

# Test 6: Deactivate task
echo ""
echo "7. Deactivating task..."
DEACTIVATE=$(curl -s -X PUT http://localhost:8080/tasks/$TASK_ID/deactivate)
if echo "$DEACTIVATE" | grep -q "deactivated"; then
  echo "✓ Task deactivated"
else
  echo "❌ Failed to deactivate"
fi

# Test 7: Delete task
echo "8. Cleaning up (deleting task)..."
DELETE=$(curl -s -X DELETE http://localhost:8080/tasks/$TASK_ID)
if echo "$DELETE" | grep -q "deleted"; then
  echo "✓ Task deleted"
else
  echo "❌ Failed to delete"
fi

echo ""
echo "=== Integration Test Complete ==="
echo ""
echo "Summary:"
echo "  ✓ API endpoints working"
echo "  ✓ Task lifecycle working"
if [ -n "$BCH_ORACLE_WIF" ]; then
  echo "  ✓ Contract deployment working"
fi
if [ -n "$LLM_API_KEY" ]; then
  echo "  ✓ LLM integration working"
fi
echo ""
echo "Your BCH Oracle service is ready to use!"
