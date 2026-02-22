# BCH Oracle Smart Contracts

CashScript contracts for publishing oracle results on Bitcoin Cash blockchain.

## Quick Start

```bash
# Install and compile
./setup.sh

# Generate wallet
node -e "const {PrivateKey} = require('cashscript'); const pk = PrivateKey.generate(); console.log('WIF:', pk.toWIF()); console.log('Address:', pk.toPublicKey().toAddress('testnet').toString())"

# Deploy contract for task 1
node deploy.js 1

# Publish a result manually
node publish.js 1 1708617600 "yes"
```

## Contract: oracle.cash

The oracle contract allows an authorized oracle (identified by public key) to publish results on-chain.

### Constructor Parameters

- `oraclePubkey` - Public key of the authorized oracle
- `taskId` - The oracle task ID this contract serves

### Functions

#### publishResult(sig, timestamp, result)

Publishes a new oracle result on-chain.

- `sig` - Oracle's signature
- `timestamp` - Unix timestamp of the result
- `result` - The parsed oracle value (as bytes)

Creates an OP_RETURN output with format:
```
OP_RETURN <ORCL> <task_id> <timestamp> <result>
```

Where:
- `ORCL` = Protocol identifier (0x4f52434c)
- `task_id` = 4 bytes (big-endian)
- `timestamp` = 8 bytes (big-endian)
- `result` = Variable length UTF-8 encoded string

#### withdraw(sig)

Allows the oracle to withdraw funds from the contract for maintenance.

## Scripts

### deploy.js

Deploys a new contract instance for a specific task.

```bash
node deploy.js <task_id>
```

Outputs:
- Contract address
- Token address
- Saves contract info to `artifacts/contract-<task_id>.json`

### publish.js

Publishes an oracle result on-chain.

```bash
node publish.js <task_id> <timestamp> <result>
```

Example:
```bash
node publish.js 1 1708617600 "yes"
node publish.js 2 1708617600 "42100.50"
```

Returns JSON:
```json
{
  "success": true,
  "txid": "abc123...",
  "taskId": 1,
  "timestamp": 1708617600,
  "result": "yes",
  "explorerUrl": "https://chipnet.chaingraph.cash/tx/abc123..."
}
```

## Integration with Gleam Service

The Gleam service calls these scripts via `src/oracle/bch.gleam`:

1. When a task is created, optionally deploy a contract:
   ```bash
   curl -X POST http://localhost:8080/tasks/1/deploy-contract
   ```

2. When `BCH_PUBLISH_ENABLED=true`, successful task results are automatically published on-chain

3. The `worker.gleam` module calls `bch.publish_result()` which spawns `publish.js`

## Reading Results

Query the blockchain for OP_RETURN outputs from your contract address:

### Using Chaingraph (GraphQL)

```graphql
query {
  transaction(where: {
    outputs: {
      locking_bytecode: {_like: "6a044f52434c%"}
    }
  }) {
    hash
    outputs {
      locking_bytecode
    }
  }
}
```

### Using Block Explorer

Visit: https://chipnet.chaingraph.cash/address/<your_contract_address>

Look for transactions with OP_RETURN outputs.

### Decoding OP_RETURN

The OP_RETURN format is:
```
6a                    OP_RETURN
04 4f52434c          Push 4 bytes "ORCL"
04 <task_id>         Push 4 bytes task ID
08 <timestamp>       Push 8 bytes timestamp
<len> <result>       Push result bytes
```

Example decoder:
```javascript
function decodeOracleOpReturn(hex) {
  const buf = Buffer.from(hex, 'hex');
  let pos = 0;
  
  // Skip OP_RETURN (0x6a)
  pos += 1;
  
  // Read protocol ID
  const protocolLen = buf[pos++];
  const protocol = buf.slice(pos, pos + protocolLen).toString('ascii');
  pos += protocolLen;
  
  // Read task ID
  const taskIdLen = buf[pos++];
  const taskId = buf.readUInt32BE(pos);
  pos += taskIdLen;
  
  // Read timestamp
  const timestampLen = buf[pos++];
  const timestamp = Number(buf.readBigUInt64BE(pos));
  pos += timestampLen;
  
  // Read result
  const resultLen = buf[pos++];
  const result = buf.slice(pos, pos + resultLen).toString('utf8');
  
  return { protocol, taskId, timestamp, result };
}
```

## Network Configuration

### Chipnet (Testnet)

- Network: `chipnet`
- Faucet: https://tbch.googol.cash/
- Explorer: https://chipnet.chaingraph.cash/

### Mainnet

- Network: `mainnet`
- Explorer: https://blockchair.com/bitcoin-cash

## Cost Analysis

Each on-chain publish costs approximately:
- Transaction fee: ~1000 satoshis (0.00001 BCH)
- OP_RETURN data: Free (up to 223 bytes)
- Contract dust: 1000 satoshis (recycled)

For a task running every hour:
- Daily cost: ~0.00024 BCH
- Monthly cost: ~0.0072 BCH
- Yearly cost: ~0.0876 BCH (~$35 at $400/BCH)

## Security Considerations

1. **Private Key Security**: Keep `BCH_ORACLE_WIF` secure. Anyone with this key can publish fake results.

2. **Contract Immutability**: Once deployed, contracts cannot be upgraded. Deploy new contracts for changes.

3. **Result Validation**: Consumers should verify:
   - Transaction is signed by the oracle's key
   - OP_RETURN format is correct
   - Timestamp is reasonable
   - Task ID matches expected contract

4. **Replay Protection**: Timestamps prevent replay attacks. Consumers should reject old timestamps.

## Troubleshooting

### "Contract not deployed"

Run: `node deploy.js <task_id>`

### "Insufficient funds"

Fund your oracle wallet with BCH from a faucet or exchange.

### "Invalid signature"

Verify `BCH_ORACLE_WIF` matches the public key used during deployment.

### "Network error"

Check your internet connection and Electrum server availability.
