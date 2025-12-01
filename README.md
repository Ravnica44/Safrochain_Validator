# Safrochain Validator Setup

This repository contains the necessary files to run a Safrochain validator node using Docker.

## Prerequisites

- Docker
- docker-compose
- curl
- jq

## Key Features

- Automatic port detection to avoid conflicts
- Environment file (.env) for persistent configuration
- Comprehensive management script with all necessary operations
- Support for wallet creation and import (mnemonic/private key)
- Automatic log display after startup

## Setup Instructions

1. **Build the Docker image:**
   ```bash
   docker-compose build
   ```

2. **Initialize the node:**
   ```bash
   mkdir -p data
   docker run --rm -v $(pwd)/data:/data safrochain/safrochaind:local init my-validator --chain-id safro-testnet-1 --home /data
   ```

3. **Configure the genesis file:**
   ```bash
   curl -L https://genesis.safrochain.com/testnet/genesis.json -o data/config/genesis.json
   ```

4. **(Optional) Use a snapshot for faster synchronization:**
   ```bash
   # Download and apply a snapshot from NodeStake (updated every 12 hours)
   SNAP_NAME=$(curl -s https://ss-t.safrochain.nodestake.org/ | egrep -o ">20.*\\.tar.lz4" | tr -d ">")
   curl -o - -L https://ss-t.safrochain.nodestake.org/${SNAP_NAME} | lz4 -c -d - | tar -x -C $HOME/.safrochain
   
   # Or download a snapshot manually
   # curl -L https://file.blocksync.me/safro/snapshot_20251201.tar.lz4 -o snapshot.tar.lz4
   # tar -I lz4 -xf snapshot.tar.lz4 -C data
   
   # After extracting the snapshot, make sure to add the genesis file:
   # curl -L https://genesis.safrochain.com/testnet/genesis.json -o data/config/genesis.json
   ```

5. **Create a wallet or import an existing one:**
   ```bash
   # Create a new wallet
   docker exec -it safrochain-validator safrochaind keys add validator-wallet --home /data --keyring-backend test
   
   # Or import from mnemonic
   # Use the interactive script command:
   ./start-validator.sh import-mnemonic validator-wallet
   
   # Or import from private key
   # Use the interactive script command:
   ./start-validator.sh import-private-key validator-wallet
   ```

6. **Configure seeds and peers:**
   ```bash
   docker run --rm -v $(pwd)/data:/data alpine sh -c "sed -i 's/seeds = \"\"/seeds = \"2242a526e7841e7e8a551aabc4614e6cd612e7fb@88.99.211.113:26656\"/g' /data/config/config.toml && sed -i 's/persistent_peers = \"\"/persistent_peers = \"2242a526e7841e7e8a551aabc4614e6cd612e7fb@88.99.211.113:26656\"/g' /data/config/config.toml && sed -i 's/minimum-gas-prices = \"\"/minimum-gas-prices = \"0.001usaf\"/g' /data/config/app.toml"
   ```

7. **Start the validator node:**
   ```bash
   # Using the management script (recommended - automatically handles port conflicts and shows logs)
   ./start-validator.sh start
   
   # Or using docker-compose directly
   docker-compose up -d
   ```

8. **Get wallet address:**
   ```bash
   docker exec -it safrochain-validator safrochaind keys show validator-wallet --address --home /data --keyring-backend test
   ```

9. **Request test tokens from the faucet:**
   Visit https://faucet.safrochain.com and enter your wallet address to request test tokens.

## Using the Management Script

The [start-validator.sh](start-validator.sh) script provides a convenient way to manage your validator:

```bash
# Initialize node
./start-validator.sh init my-validator

# Configure node
./start-validator.sh configure

# Create wallet
./start-validator.sh create-wallet validator-wallet

# Import wallet from mnemonic
./start-validator.sh import-mnemonic validator-wallet

# Import wallet from private key
./start-validator.sh import-private-key validator-wallet

# Start node (automatically detects and uses available ports, then shows live logs)
./start-validator.sh start

# Check sync status
./start-validator.sh status

# Check wallet balance
./start-validator.sh balance validator-wallet

# Register as validator (after node is synced and you have tokens)
./start-validator.sh register-validator validator-wallet my-validator

# Stop node
./start-validator.sh stop

# Show help
./start-validator.sh help
```

## Monitoring Sync Progress

A dedicated monitoring script [monitor-sync.sh](monitor-sync.sh) is available to track your validator's sync progress:

```bash
# Check current sync status
./monitor-sync.sh

# Continuous monitoring (updates every 10 seconds)
./monitor-sync.sh -c
```

The monitoring script provides:
- Current block height
- Sync status (catching up or fully synced)
- Latest block timestamp
- Number of connected peers
- Node identifier
- Color-coded status indicators

## Automatic Port Management

The script automatically detects port conflicts and uses alternative ports when necessary:
- P2P: 26656 (default) → alternative if occupied
- RPC: 26657 (default) → alternative if occupied
- API: 1317 (default) → alternative if occupied
- gRPC: 9090 (default) → alternative if occupied

Port configuration is stored in `.env` file for persistence.

When starting the node with `./start-validator.sh start`, the script will:
1. Automatically detect and resolve port conflicts
2. Start the Safrochain validator node
3. Display live logs (Press Ctrl+C to exit)

The script implements automatic port detection and conflict resolution.

## Useful Commands

- Check sync status: `docker exec -it safrochain-validator safrochaind status`
- Check wallet balance: `docker exec -it safrochain-validator safrochaind query bank balances [wallet-address] --home /data`
- View logs: `docker-compose logs -f`
- Stop the node: `docker-compose down`

## Directory Structure

- `data/` - Node data and configuration files
- `docker-compose.yml` - Docker configuration
- `Dockerfile` - Docker image definition
- `start-validator.sh` - Management script
- `monitor-sync.sh` - Sync monitoring script
- `.env` - Environment variables (created automatically)

## Current Status

The node is currently syncing with the Safrochain testnet. You can monitor the sync progress with the dedicated monitoring script:

```bash
./monitor-sync.sh
```

Or for continuous monitoring:
```bash
./monitor-sync.sh -c
```

Look for `"catching_up":false` in the output to confirm the node is fully synced.

## Next Steps

Once the node is fully synced and you have received test tokens:

1. Create a validator transaction:
   ```bash
   # Create a validator.json file with your validator details:
   cat > validator.json << EOF
{
  "pubkey": {"@type":"/cosmos.crypto.ed25519.PubKey","key":"YOUR_VALIDATOR_PUBLIC_KEY"},
  "amount": "1000000usaf",
  "moniker": "your-validator-name",
  "identity": "",
  "website": "",
  "security": "",
  "details": "Safrochain Validator",
  "commission-rate": "0.1",
  "commission-max-rate": "0.2",
  "commission-max-change-rate": "0.01",
  "min-self-delegation": "1"
}
EOF
   
   # Copy the validator.json file to the container:
   docker cp validator.json safrochain-validator:/data/validator.json
   
   # Create the validator:
   docker exec -it safrochain-validator safrochaind tx staking create-validator /data/validator.json --from validator-wallet --chain-id safro-testnet-1 --gas 200000 --gas-prices 0.075usaf --home /data --keyring-backend test -y
   ```

2. Or use the management script to register as validator:
   ```bash
   ./start-validator.sh register-validator validator-wallet your-validator-name
   ```

3. To edit an existing validator (change moniker, details, etc.):
   ```bash
   docker exec -it safrochain-validator safrochaind tx staking edit-validator --new-moniker="new-validator-name" --details="Updated Safrochain Validator" --from validator-wallet --chain-id safro-testnet-1 --gas 100000 --gas-prices 0.075usaf --home /data --keyring-backend test -y
   ```

## Validator Management

After registering as a validator, you can manage your validator using the following commands:

- Check your validator status:
  ```bash
  docker exec -it safrochain-validator safrochaind query staking validator $(docker exec safrochain-validator safrochaind keys show validator-wallet --bech val --address --home /data --keyring-backend test) --home /data
  ```

- List all validators:
  ```bash
  docker exec -it safrochain-validator safrochaind query staking validators --home /data
  ```

- Monitor your validator performance:
  ```bash
  ./monitor-sync.sh -c
  ```

## Managing Your Validator Moniker

Your validator's moniker (display name) is configured in the `.env` file:

```bash
SAFROCHAIN_MONIKER=your-validator-name
```

To change your moniker:

1. Edit the `.env` file:
   ```bash
   nano .env
   ```

2. Modify the `SAFROCHAIN_MONIKER` value:
   ```bash
   SAFROCHAIN_MONIKER=my-new-validator-name
   ```

3. Restart your validator node:
   ```bash
   ./start-validator.sh stop
   ./start-validator.sh start
   ```

4. Update your validator's on-chain moniker:
   ```bash
   ./start-validator.sh edit-validator validator-wallet my-new-validator-name
   ```

Note: The moniker in the `.env` file is used when initializing the node. To change it on-chain, you need to use the `edit-validator` command. If no moniker is specified in the `.env` file, you will be prompted to enter one when starting the node.

## Troubleshooting

If you encounter issues during validator registration:

1. **Insufficient fees error**: Increase the gas price multiplier (e.g., from 0.001usaf to 0.075usaf)
2. **Out of gas error**: Increase the gas limit (e.g., from auto to 200000 or higher)
3. **Validator already exists**: Use edit-validator instead of create-validator to modify existing validator settings

## Security Notes

- Store your mnemonic phrase and private keys securely
- Never share your private keys or mnemonic phrases
- Backup your `data/` directory regularly
- The node automatically detects and uses available ports to avoid conflicts

## Wallet Backup

It's crucial to backup your validator wallet to prevent loss of funds:

1. **Mnemonic Phrase**: When you create a wallet, save the 24-word mnemonic phrase in a secure location
2. **Key Files**: The wallet key files are stored in `data/keyring-test/`:
   - `[wallet-name].info` - Wallet information file
   - `[address-hash].address` - Address file
3. **Validator Node Keys**: Critical node key files that must be backed up:
   - `data/config/node_key.json` - Node identity key (required for p2p communication)
   - `data/config/priv_validator_key.json` - Validator private key (required for block signing)
4. **Backup Commands**: Create a backup of all critical files:
   ```bash
   # Export wallet to encrypted format
   docker exec -it safrochain-validator safrochaind keys export validator-wallet --home /data --keyring-backend test
   
   # Or backup the entire keyring directory
   cp -r data/keyring-test/ backup-keyring-test/
   
   # Backup critical node keys
   cp data/config/node_key.json backup-node_key.json
   cp data/config/priv_validator_key.json backup-priv_validator_key.json
   
   # Or backup the entire config directory
   cp -r data/config/ backup-config/
   ```
5. **Restore Commands**: To restore a wallet from mnemonic:
   ```bash
   ./start-validator.sh import-mnemonic validator-wallet
   ```
   
   To restore node keys, copy the backup files back to their original locations:
   ```bash
   cp backup-node_key.json data/config/node_key.json
   cp backup-priv_validator_key.json data/config/priv_validator_key.json
   ```

