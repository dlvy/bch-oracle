#!/usr/bin/env node
// Read oracle results from the blockchain
// Usage: node read-onchain.js <task_id>

const { ElectrumNetworkProvider } = require('cashscript');
const fs = require('fs');
const path = require('path');

require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

async function readResults(taskId) {
  // Load contract info
  const contractInfoPath = path.join(__dirname, 'artifacts', `contract-${taskId}.json`);
  if (!fs.existsSync(contractInfoPath)) {
    throw new Error(`Contract not deployed for task ${taskId}`);
  }
  const contractInfo = JSON.parse(fs.readFileSync(contractInfoPath, 'utf8'));
  
  const network = process.env.BCH_NETWORK || 'chipnet';
  const provider = new ElectrumNetworkProvider(network);
  
  console.log(`Reading on-chain results for task ${taskId}...`);
  console.log(`Contract address: ${contractInfo.address}`);
  console.log(`Network: ${network}`);
  console.log('');
  
  // Get UTXOs (transaction history)
  const utxos = await provider.getUtxos(contractInfo.address);
  
  console.log(`Found ${utxos.length} UTXOs`);
  console.log('');
  
  // Get transaction details for each UTXO
  const results = [];
  for (const utxo of utxos) {
    try {
      const tx = await provider.getRawTransaction(utxo.txid);
      
      // Look for OP_RETURN outputs
      for (const output of tx.vout) {
        if (output.scriptPubKey && output.scriptPubKey.hex) {
          const hex = output.scriptPubKey.hex;
          
          // Check if it starts with OP_RETURN (0x6a) and ORCL protocol
          if (hex.startsWith('6a044f52434c')) {
            const decoded = decodeOracleOpReturn(hex);
            if (decoded.taskId === taskId) {
              results.push({
                txid: utxo.txid,
                ...decoded,
                explorerUrl: network === 'chipnet' 
                  ? `https://chipnet.chaingraph.cash/tx/${utxo.txid}`
                  : `https://blockchair.com/bitcoin-cash/transaction/${utxo.txid}`
              });
            }
          }
        }
      }
    } catch (err) {
      console.error(`Error reading tx ${utxo.txid}:`, err.message);
    }
  }
  
  // Sort by timestamp
  results.sort((a, b) => b.timestamp - a.timestamp);
  
  console.log(`Found ${results.length} on-chain results:\n`);
  
  results.forEach((r, i) => {
    const date = new Date(r.timestamp * 1000).toISOString();
    console.log(`${i + 1}. ${date}`);
    console.log(`   Result: ${r.result}`);
    console.log(`   TX: ${r.txid}`);
    console.log(`   Explorer: ${r.explorerUrl}`);
    console.log('');
  });
  
  return results;
}

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

// CLI usage
if (require.main === module) {
  const taskId = parseInt(process.argv[2]);
  if (!taskId) {
    console.error('Usage: node read-onchain.js <task_id>');
    process.exit(1);
  }
  
  readResults(taskId)
    .then(() => process.exit(0))
    .catch(err => {
      console.error('Error:', err.message);
      process.exit(1);
    });
}

module.exports = { readResults, decodeOracleOpReturn };
