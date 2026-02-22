#!/usr/bin/env node
// Deploy oracle contracts and output contract addresses
// Usage: node deploy.js <task_id>

const { Contract, ElectrumNetworkProvider, SignatureTemplate } = require('cashscript');
const { compileFile } = require('cashc');
const fs = require('fs');
const path = require('path');

require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

async function deploy(taskId) {
  // Compile contract
  const artifact = compileFile(path.join(__dirname, 'oracle.cash'));
  
  // Get oracle private key from env
  const oracleWIF = process.env.BCH_ORACLE_WIF;
  if (!oracleWIF) {
    throw new Error('BCH_ORACLE_WIF not set in .env');
  }
  
  // Derive public key from WIF
  const { PrivateKey } = require('cashscript');
  const privateKey = PrivateKey.fromWIF(oracleWIF);
  const publicKey = privateKey.toPublicKey();
  
  // Network provider (mainnet or chipnet)
  const network = process.env.BCH_NETWORK || 'chipnet';
  const provider = new ElectrumNetworkProvider(network);
  
  // Instantiate contract
  const contract = new Contract(
    artifact,
    [publicKey, BigInt(taskId)],
    { provider }
  );
  
  console.log(`Oracle contract for task ${taskId}:`);
  console.log(`Address: ${contract.address}`);
  console.log(`Token address: ${contract.tokenAddress}`);
  
  // Save contract info
  const contractInfo = {
    taskId,
    address: contract.address,
    tokenAddress: contract.tokenAddress,
    publicKey: publicKey.toString(),
    network,
    deployedAt: new Date().toISOString()
  };
  
  const outputPath = path.join(__dirname, 'artifacts', `contract-${taskId}.json`);
  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  fs.writeFileSync(outputPath, JSON.stringify(contractInfo, null, 2));
  
  console.log(`Contract info saved to ${outputPath}`);
  
  return contractInfo;
}

// CLI usage
if (require.main === module) {
  const taskId = parseInt(process.argv[2]);
  if (!taskId) {
    console.error('Usage: node deploy.js <task_id>');
    process.exit(1);
  }
  
  deploy(taskId)
    .then(() => process.exit(0))
    .catch(err => {
      console.error('Deployment failed:', err);
      process.exit(1);
    });
}

module.exports = { deploy };
