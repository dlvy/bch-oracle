# BCH Oracle — Prediction Market Oracle Service

A **Gleam** service that:
1. Manages _oracle tasks_ via a REST API
2. Periodically fetches a URL, calls an LLM with a custom prompt, parses the response, and stores the result in SQLite
3. **Writes results on-chain to Bitcoin Cash blockchain** 🎯

Perfect for prediction markets, DeFi, and any application requiring trustless external data.

## ✨ Features

- 🔄 **Scheduled Tasks** - OTP processes run tasks on configurable intervals
- 🤖 **LLM Integration** - OpenAI-compatible API for intelligent data processing
- 📊 **Smart Parsing** - Four parsing strategies (yes/no, numeric, price, raw)
- 💾 **SQLite Storage** - Persistent result history
- ⛓️ **On-Chain Publishing** - Automatic BCH blockchain integration
- 🔐 **Trustless** - Verifiable, immutable results
- 🚀 **Production Ready** - Error handling, logging, tests

## 📚 Documentation

- **[Summary](SUMMARY.md)** - Implementation complete overview ⭐
- **[Quick Reference](QUICKREF.md)** - Commands and API cheat sheet
- **[Project Structure](PROJECT-STRUCTURE.md)** - File organization
- **[Architecture](ARCHITECTURE.md)** - System design and diagrams
- **[Implementation](IMPLEMENTATION.md)** - What was built and how it works
- **[Contract Docs](contracts/README.md)** - Smart contract details
- **[Changelog](CHANGELOG.md)** - Version history and updates

## Quick Start

### Using Make (recommended)

```bash
# One-command setup
make setup

# Configure
cp .env.example .env
# Edit .env with your LLM_API_KEY and optionally BCH_ORACLE_WIF

# Run
make run

# Test
make test
```

### Manual Setup

```bash
# 1. Install Gleam dependencies
gleam deps download

# 2. Set up contracts
cd contracts
./setup.sh
cd ..

# 3. Configure environment
cp .env.example .env
# Edit .env with your LLM_API_KEY and optionally BCH_ORACLE_WIF

# 4. Run the service
export $(cat .env | xargs)
gleam run

# 5. Test it
./test-integration.sh
```

The service starts at **http://localhost:8080**.

## Examples

Ready-to-run examples are in the `examples/` directory:

```bash
# BCH price oracle with on-chain publishing
./examples/bch-price-oracle.sh

# Prediction market: "Will BCH reach $500?"
./examples/prediction-market.sh
```

## API Reference

### Tasks

| Method | Path | Description |
|--------|------|-------------|
| `GET`    | `/tasks`                   | List all tasks |
| `POST`   | `/tasks`                   | Create a task |
| `GET`    | `/tasks/:id`               | Get task by ID |
| `DELETE` | `/tasks/:id`               | Delete task |
| `PUT`    | `/tasks/:id/activate`      | Enable task |
| `PUT`    | `/tasks/:id/deactivate`    | Disable task |
| `POST`   | `/tasks/:id/run`           | Trigger task immediately (async) |
| `POST`   | `/tasks/:id/deploy-contract` | Deploy BCH contract for task |
| `GET`    | `/tasks/:id/results`       | Last 20 results for task |
| `GET`    | `/results`                 | Last 50 results across all tasks |
| `GET`    | `/health`                  | Health check |

### Create a Task (POST /tasks)

```json
{
  "name": "BCH Price above $400?",
  "source_url": "https://coinmarketcap.com/currencies/bitcoin-cash/",
  "prompt": "Based on this page content:\n{content}\n\nIs the current BCH price above $400? Answer YES or NO only.",
  "parse_rule": "yes_no",
  "interval_seconds": 3600
}
```

**`parse_rule` options:**

| Value | Description |
|-------|-------------|
| `yes_no` | Extracts YES or NO from the LLM response |
| `numeric` | Extracts the first number from the response |
| `price` | Strips currency symbols then extracts a number |
| `raw` | Returns the full trimmed LLM response |

**`{content}`** in the prompt is replaced with the first 4,000 characters of the fetched `source_url`.

### Example: Create a BCH price oracle

```bash
curl -X POST http://localhost:8080/tasks \
  -H 'Content-Type: application/json' \
  -d '{
    "name": "BCH/USD price",
    "source_url": "https://api.coinbase.com/v2/prices/BCH-USD/spot",
    "prompt": "This is the Coinbase spot price API response:\n{content}\n\nWhat is the BCH price in USD? Reply with just the number.",
    "parse_rule": "price",
    "interval_seconds": 300
  }'
```

```bash
# Deploy contract for on-chain publishing
curl -X POST http://localhost:8080/tasks/1/deploy-contract

# Trigger immediately
curl -X POST http://localhost:8080/tasks/1/run

# Check results
curl http://localhost:8080/tasks/1/results

# Read on-chain results
cd contracts
node read-onchain.js 1
```

## Configuration

| Env Var | Default | Description |
|---------|---------|-------------|
| `PORT` | `8080` | HTTP port |
| `DB_PATH` | `./oracle.db` | SQLite file path |
| `LLM_BASE_URL` | `https://api.openai.com/v1` | OpenAI-compatible API base URL |
| `LLM_API_KEY` | — | API key |
| `LLM_MODEL` | `gpt-4o-mini` | Model name |
| `BCH_PUBLISH_ENABLED` | `false` | Enable on-chain publishing |
| `BCH_NETWORK` | `chipnet` | BCH network (mainnet/chipnet) |
| `BCH_ORACLE_WIF` | — | Oracle wallet private key (WIF format) |

## Architecture

```
oracle.gleam         ← entry point (start server + boot schedulers)
src/oracle/
  types.gleam        ← OracleTask, OracleResult, ParseRule
  db.gleam           ← SQLite CRUD via sqlight
  llm.gleam          ← LLM client (OpenAI-compatible REST)
  parser.gleam       ← Parse LLM responses (yes_no, numeric, price, raw)
  worker.gleam       ← Execute tasks + per-task OTP scheduler loops
  router.gleam       ← Wisp HTTP request router
  encoding.gleam     ← JSON encode helpers
  bch.gleam          ← Bitcoin Cash on-chain publishing
  ffi.gleam          ← Erlang FFI helpers
contracts/
  oracle.cash        ← CashScript smart contract
  deploy.js          ← Deploy contracts for tasks
  publish.js         ← Publish results on-chain
```

Each task runs in its own **OTP process** that loops: _run → sleep(interval) → run → …_

When `BCH_PUBLISH_ENABLED=true`, successful results are automatically published on-chain via the CashScript contract.

## On-chain Writing (Bitcoin Cash)

The oracle can publish results on-chain to Bitcoin Cash using CashScript smart contracts. Each task gets its own contract that stores results in OP_RETURN outputs.

### Setup

1. Install Node.js dependencies and compile contracts:
```bash
cd contracts
./setup.sh
```

2. Generate an oracle wallet:
```bash
node -e "const {PrivateKey} = require('cashscript'); console.log('WIF:', PrivateKey.generate().toWIF())"
```

3. Add to your `.env`:
```bash
BCH_PUBLISH_ENABLED=true
BCH_NETWORK=chipnet  # or mainnet
BCH_ORACLE_WIF=your_private_key_here
```

4. Fund your wallet with BCH:
   - Chipnet faucet: https://tbch.googol.cash/
   - Mainnet: Send BCH to your wallet address

### Deploy a Contract

Each task needs its own contract deployed:

```bash
# Via API
curl -X POST http://localhost:8080/tasks/1/deploy-contract

# Or directly
cd contracts
node deploy.js 1
```

This creates a contract at a unique address for task #1. The contract info is saved to `contracts/artifacts/contract-1.json`.

### How It Works

1. When a task runs successfully, the worker automatically publishes the `parsed_value` on-chain (if `BCH_PUBLISH_ENABLED=true`)
2. The result is stored in an OP_RETURN output with format:
   ```
   OP_RETURN <ORCL> <task_id> <timestamp> <result>
   ```
3. Anyone can read the blockchain to verify oracle results
4. The contract requires the oracle's signature to publish

### Contract Structure

The CashScript contract (`contracts/oracle.cash`) has two functions:

- `publishResult(sig, timestamp, result)` - Publish a new oracle value
- `withdraw(sig)` - Reclaim dust for maintenance

### API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/tasks/:id/deploy-contract` | Deploy BCH contract for task |

### Reading Results On-Chain

Results are published as OP_RETURN outputs. You can query them using:

- Block explorers: https://chipnet.chaingraph.cash/
- Electrum servers
- BCH full node RPC
- Chaingraph GraphQL API

Look for transactions from your contract address with OP_RETURN outputs starting with `4f52434c` (hex for "ORCL").

### Cost

Each on-chain publish costs ~1000 satoshis (0.00001 BCH) in fees. The contract maintains a small balance for continuous operation.
