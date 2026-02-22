#!/bin/bash
# Setup script for BCH oracle contracts

set -e

echo "Setting up BCH Oracle contracts..."

# Install Node.js dependencies
echo "Installing Node.js dependencies..."
cd "$(dirname "$0")"
npm install

# Compile contracts
echo "Compiling CashScript contracts..."
npm run compile

echo ""
echo "✓ Setup complete!"
echo ""
echo "Next steps:"
echo "1. Generate a wallet: node -e \"const {PrivateKey} = require('cashscript'); console.log('WIF:', PrivateKey.generate().toWIF())\""
echo "2. Add BCH_ORACLE_WIF to your .env file"
echo "3. Fund the wallet with some BCH (chipnet faucet: https://tbch.googol.cash/)"
echo "4. Deploy a contract: node deploy.js <task_id>"
echo "5. Enable publishing: Set BCH_PUBLISH_ENABLED=true in .env"
