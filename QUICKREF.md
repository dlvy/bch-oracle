# BCH Oracle Quick Reference

## Setup Commands

```bash
# One-line setup
make setup && cp .env.example .env

# Start service
make run

# Run tests
make test
```

## API Endpoints

```bash
# Create task
curl -X POST http://localhost:8080/tasks \
  -H 'Content-Type: application/json' \
  -d '{"name":"BCH Price","source_url":"https://api.coinbase.com/v2/prices/BCH-USD/spot","prompt":"Extract price from: {content}","parse_rule":"price","interval_seconds":300}'

# List tasks
curl http://localhost:8080/tasks

# Get task
curl http://localhost:8080/tasks/1

# Run task now
curl -X POST http://localhost:8080/tasks/1/run

# Get results
curl http://localhost:8080/tasks/1/results

# Deploy contract
curl -X POST http://localhost:8080/tasks/1/deploy-contract

# Activate/deactivate
curl -X PUT http://localhost:8080/tasks/1/activate
curl -X PUT http://localhost:8080/tasks/1/deactivate

# Delete task
curl -X DELETE http://localhost:8080/tasks/1
```

## Parse Rules

| Rule | Description | Example Input | Example Output |
|------|-------------|---------------|----------------|
| `yes_no` | Extract YES/NO | "The answer is YES" | "yes" |
| `numeric` | Extract number | "Price is 42.5" | "42.5" |
| `price` | Extract price | "$1,234.56" | "1234.56" |
| `raw` | Return as-is | "Any text" | "Any text" |

## Contract Commands

```bash
# Setup contracts
cd contracts && ./setup.sh

# Generate wallet
node -e "const {PrivateKey} = require('cashscript'); console.log(PrivateKey.generate().toWIF())"

# Deploy contract
node deploy.js 1

# Publish result manually
node publish.js 1 1708617600 "yes"

# Read on-chain results
node read-onchain.js 1
```

## Environment Variables

```bash
# Required
LLM_API_KEY=sk-...

# Optional
PORT=8080
DB_PATH=./oracle.db
LLM_BASE_URL=https://api.openai.com/v1
LLM_MODEL=gpt-4o-mini

# BCH (optional)
BCH_PUBLISH_ENABLED=true
BCH_NETWORK=chipnet
BCH_ORACLE_WIF=your_wif_here
```

## Common Tasks

### Create a Price Oracle
```bash
curl -X POST http://localhost:8080/tasks \
  -H 'Content-Type: application/json' \
  -d '{
    "name": "BCH/USD",
    "source_url": "https://api.coinbase.com/v2/prices/BCH-USD/spot",
    "prompt": "Extract BCH price from: {content}",
    "parse_rule": "price",
    "interval_seconds": 300
  }'
```

### Create a Prediction Market
```bash
curl -X POST http://localhost:8080/tasks \
  -H 'Content-Type: application/json' \
  -d '{
    "name": "BCH > $500?",
    "source_url": "https://api.coinbase.com/v2/prices/BCH-USD/spot",
    "prompt": "Is BCH above $500? Answer YES or NO based on: {content}",
    "parse_rule": "yes_no",
    "interval_seconds": 3600
  }'
```

### Enable On-Chain Publishing
```bash
# 1. Generate wallet
cd contracts
node -e "const {PrivateKey} = require('cashscript'); const pk = PrivateKey.generate(); console.log('WIF:', pk.toWIF())"

# 2. Add to .env
echo "BCH_ORACLE_WIF=your_wif_here" >> ../.env
echo "BCH_PUBLISH_ENABLED=true" >> ../.env

# 3. Fund wallet (chipnet faucet)
# Visit: https://tbch.googol.cash/

# 4. Deploy contract
node deploy.js 1

# 5. Restart service
cd .. && make run
```

## Troubleshooting

### Service won't start
```bash
# Check .env exists
ls -la .env

# Check LLM_API_KEY is set
grep LLM_API_KEY .env

# Check port is free
lsof -i :8080
```

### Task not running
```bash
# Check if active
curl http://localhost:8080/tasks/1 | grep active

# Activate it
curl -X PUT http://localhost:8080/tasks/1/activate

# Trigger manually
curl -X POST http://localhost:8080/tasks/1/run
```

### On-chain publish failing
```bash
# Check contract deployed
ls contracts/artifacts/contract-1.json

# Check wallet funded
# (Use block explorer with your address)

# Check BCH_ORACLE_WIF set
grep BCH_ORACLE_WIF .env

# Check BCH_PUBLISH_ENABLED
grep BCH_PUBLISH_ENABLED .env
```

### LLM errors
```bash
# Check API key
curl https://api.openai.com/v1/models \
  -H "Authorization: Bearer $LLM_API_KEY"

# Check base URL
grep LLM_BASE_URL .env

# Check model name
grep LLM_MODEL .env
```

## File Locations

```
oracle/
├── src/oracle/          # Gleam source
│   ├── bch.gleam       # BCH integration
│   ├── db.gleam        # Database
│   ├── llm.gleam       # LLM client
│   ├── parser.gleam    # Response parsing
│   ├── router.gleam    # HTTP API
│   └── worker.gleam    # Task execution
├── contracts/           # Smart contracts
│   ├── oracle.cash     # CashScript contract
│   ├── deploy.js       # Deploy script
│   ├── publish.js      # Publish script
│   └── artifacts/      # Compiled contracts
├── examples/            # Example scripts
├── .env                # Configuration
├── oracle.db           # SQLite database
└── Makefile            # Build commands
```

## Useful Queries

### Get latest result for each task
```bash
curl http://localhost:8080/results
```

### Get task history
```bash
curl http://localhost:8080/tasks/1/results
```

### Check service health
```bash
curl http://localhost:8080/health
```

## Database Queries

```bash
# Open database
sqlite3 oracle.db

# List tasks
SELECT id, name, active, interval_seconds FROM tasks;

# List recent results
SELECT task_id, parsed_value, executed_at FROM results ORDER BY id DESC LIMIT 10;

# Task success rate
SELECT 
  task_id,
  COUNT(*) as total,
  SUM(success) as successful,
  ROUND(100.0 * SUM(success) / COUNT(*), 2) as success_rate
FROM results
GROUP BY task_id;
```

## Logs

```bash
# Service logs (stdout)
gleam run

# Watch logs
gleam run | tee oracle.log

# Filter logs
gleam run | grep "\[worker\]"
gleam run | grep "\[bch\]"
```

## Performance Tips

1. **Adjust intervals** - Don't poll too frequently
2. **Use caching** - Cache LLM responses if data doesn't change
3. **Batch operations** - Group multiple tasks
4. **Monitor costs** - Track LLM API usage
5. **Optimize prompts** - Shorter prompts = faster responses

## Security Checklist

- [ ] `.env` not in git
- [ ] `BCH_ORACLE_WIF` kept secret
- [ ] API behind reverse proxy (production)
- [ ] Rate limiting enabled (production)
- [ ] Database backups configured
- [ ] Logs monitored
- [ ] Contract addresses documented
- [ ] Wallet funded but not over-funded

## Cost Estimates

### LLM Costs (OpenAI gpt-4o-mini)
- ~$0.0001 per task execution
- Hourly task: ~$0.0024/day = $0.88/year
- 5-minute task: ~$0.029/day = $10.50/year

### BCH Costs
- ~0.00001 BCH per publish (~$0.004 at $400/BCH)
- Hourly publish: ~$0.096/day = $35/year
- 5-minute publish: ~$1.15/day = $420/year

### Total (hourly updates)
- ~$36/year per task

## Resources

- [Gleam Docs](https://gleam.run/)
- [CashScript Docs](https://cashscript.org/)
- [Bitcoin Cash](https://bitcoincash.org/)
- [Chipnet Faucet](https://tbch.googol.cash/)
- [Chipnet Explorer](https://chipnet.chaingraph.cash/)

## Support

- Check `README.md` for detailed docs
- Check `ARCHITECTURE.md` for system design
- Check `IMPLEMENTATION.md` for implementation details
- Check `contracts/README.md` for contract docs
