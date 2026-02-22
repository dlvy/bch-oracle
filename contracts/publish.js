#!/usr/bin/env node
// Publish oracle result on-chain
// Called by the Gleam service via Node.js bridge

const { Contract, ElectrumNetworkProvider, SignatureTemplate } = require('cashscript');
const fs = require('fs');
const path = require('path');

require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

async function publishResult(taskId, timestamp, result) {
  // Load contract artifact
  const artifactPath = path.join(__dirname, 'artifacts', 'oracle.json');
  if (!fs.existsSync(artifactPath)) {
    throw new Error('Contract artifact not found. Run: npm run compile');
  }
  const artifact = JSON.parse(fs.readFileSync(artifactPath, 'utf8'));
  
  // Load contract info for this task
  const contractInfoPath = path.join(__dirname, 'artifacts', `contract-${taskId}.json`);
  if (!fs.existsSync(contractInfoPath)) {
    throw new Error(`Contract not deployed for task ${taskId}. Run: node deploy.js ${taskId}`);
  }
  const contractInfo = JSON.parse(fs.readFileSync(contractInfoPath, 'utf8'));
  
  // Get oracle private key
  const oracleWIF = process.env.BCH_ORACLE_WIF;
  if (!oracleWIF) {
    throw new Error('BCH_ORACLE_WIF not set in .env');
  }
  
  const { PrivateKey } = require('cashscript');
  const privateKey = PrivateKey.fromWIF(oracleWIF);
  const publicKey = privateKey.toPublicKey();
  
  // Network provider
  const network = process.env.BCH_NETWORK || 'chipnet';
  const provider = new ElectrumNetworkProvider(network);
  
  // Instantiate contract
  const contract = new Contract(
    artifact,
    [publicKey, BigInt(taskId)],
    { provider }
  );
  
  // Verify contract address matches
  if (contract.address !== contractInfo.address) {
    throw new Error('Contract address mismatch');
  }
  
  // Encode result as bytes
  const resultBytes = Buffer.from(result, 'utf8');
  
  // Build and send transaction
  const tx = await contract.functions
    .publishResult(
      new SignatureTemplate(privateKey),
      BigInt(timestamp),
      resultBytes
    )
    .to(contract.address, 1000n) // Send dust back to contract for next publish
    .withHardcodedFee(1000n)
    .send();
  
  console.log(JSON.stringify({
    success: true,
    txid: tx.txid,
    taskId,
    timestamp,
    result,
    explorerUrl: `https://chipnet.chaingraph.cash/tx/${tx.txid}`
  }));
  
  return {
    txid: tx.txid,
    taskId,
    timestamp,
    result
  };
}

// CLI usage
if (require.main === module) {
  const args = process.argv.slice(2);
  if (args.length !== 3) {
    console.error('Usage: node publish.js <task_id> <timestamp> <result>');
    process.exit(1);
  }
  
  const [taskId, timestamp, result] = args;
  
  publishResult(parseInt(taskId), parseInt(timestamp), result)
    .then(() => process.exit(0))
    .catch(err => {
      console.error(JSON.stringify({
        success: false,
        error: err.message
      }));
      process.exit(1);
    });
}

module.exports = { publishResult };
