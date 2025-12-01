#!/bin/bash

# Safrochain Validator Startup Script
# This script initializes and starts a Safrochain validator node using Docker

set -e  # Exit on any error

# Load environment variables from .env file if it exists
if [ -f ".env" ]; then
    source .env
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default ports for Safrochain
SAFROCHAIN_P2P_PORT_DEFAULT=26656
SAFROCHAIN_RPC_PORT_DEFAULT=26657
SAFROCHAIN_API_PORT_DEFAULT=1317
SAFROCHAIN_GRPC_PORT_DEFAULT=9090

# Function to print colored output
print_status() {
    echo -e "${GREEN}[STATUS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if docker is installed
check_docker() {
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        print_error "docker-compose is not installed. Please install docker-compose first."
        exit 1
    fi
}

# Function to check if a port is available
is_port_available() {
    local port=$1
    # Use ss to check if port is available (fallback to netstat if ss is not available)
    if command -v ss &> /dev/null; then
        if ! ss -tuln | grep -q ":$port "; then
            return 0  # Port is available
        else
            return 1  # Port is in use
        fi
    elif command -v netstat &> /dev/null; then
        if ! netstat -tuln | grep -q ":$port "; then
            return 0  # Port is available
        else
            return 1  # Port is in use
        fi
    else
        # If neither ss nor netstat is available, try to bind to the port
        if command -v nc &> /dev/null; then
            if nc -z localhost $port 2>/dev/null; then
                return 1  # Port is in use
            else
                return 0  # Port is available
            fi
        else
            print_warning "Neither ss, netstat, nor nc is available. Assuming port $port is available."
            return 0  # Assume port is available
        fi
    fi
}

# Function to find available port starting from a base port
find_available_port() {
    local base_port=$1
    local port=$base_port
    
    while ! is_port_available $port; do
        port=$((port + 1))
        
        # Safety check to avoid infinite loop
        if [ $port -gt $((base_port + 100)) ]; then
            print_error "Could not find available port after 100 attempts"
            exit 1
        fi
    done
    
    echo $port
}

# Function to update .env file with new port values
update_env_file() {
    local p2p_port=$1
    local rpc_port=$2
    local api_port=$3
    local grpc_port=$4
    
    # Generic function to update or add a variable in .env
    update_env_variable() {
        local var_name=$1
        local var_value=$2
        
        if grep -q "^${var_name}=" .env 2>/dev/null; then
            sed -i "s/^${var_name}=.*/${var_name}=${var_value}/" .env
        else
            echo "${var_name}=${var_value}" >> .env
        fi
    }
    
    if [ -f ".env" ]; then
        # Update or add port variables while preserving other variables
        update_env_variable "SAFROCHAIN_P2P_PORT" "$p2p_port"
        update_env_variable "SAFROCHAIN_RPC_PORT" "$rpc_port"
        update_env_variable "SAFROCHAIN_API_PORT" "$api_port"
        update_env_variable "SAFROCHAIN_GRPC_PORT" "$grpc_port"
        
        print_status "Updated .env file with new port values"
    else
        # Create .env file with the found ports
        echo "SAFROCHAIN_P2P_PORT=$p2p_port" > .env
        echo "SAFROCHAIN_RPC_PORT=$rpc_port" >> .env
        echo "SAFROCHAIN_API_PORT=$api_port" >> .env
        echo "SAFROCHAIN_GRPC_PORT=$grpc_port" >> .env
        print_status "Created .env file with port values"
    fi
}

# Function to stop and remove existing safrochain container
cleanup_existing_container() {
    print_status "Checking for existing safrochain container..."
    if docker ps -a --format '{{.Names}}' | grep -q "safrochain-validator"; then
        print_status "Stopping existing safrochain container..."
        docker stop safrochain-validator >/dev/null 2>&1
        print_status "Removing existing safrochain container..."
        docker rm safrochain-validator >/dev/null 2>&1
    fi
}

# Generic function to check and set a port
check_and_set_port() {
    local port_var_name=$1
    local default_port=$2
    local env_port_value=${!port_var_name}
    
    # Check if default port is available and not already assigned
    if is_port_available $default_port; then
        # Check if this port is already assigned to another service
        local port_already_assigned=false
        case $port_var_name in
            "SAFROCHAIN_P2P_PORT")
                if [ -n "$SAFROCHAIN_RPC_PORT" ] && [ "$default_port" -eq "$SAFROCHAIN_RPC_PORT" ]; then
                    port_already_assigned=true
                elif [ -n "$SAFROCHAIN_API_PORT" ] && [ "$default_port" -eq "$SAFROCHAIN_API_PORT" ]; then
                    port_already_assigned=true
                elif [ -n "$SAFROCHAIN_GRPC_PORT" ] && [ "$default_port" -eq "$SAFROCHAIN_GRPC_PORT" ]; then
                    port_already_assigned=true
                fi
                ;;
            "SAFROCHAIN_RPC_PORT")
                if [ -n "$SAFROCHAIN_P2P_PORT" ] && [ "$default_port" -eq "$SAFROCHAIN_P2P_PORT" ]; then
                    port_already_assigned=true
                elif [ -n "$SAFROCHAIN_API_PORT" ] && [ "$default_port" -eq "$SAFROCHAIN_API_PORT" ]; then
                    port_already_assigned=true
                elif [ -n "$SAFROCHAIN_GRPC_PORT" ] && [ "$default_port" -eq "$SAFROCHAIN_GRPC_PORT" ]; then
                    port_already_assigned=true
                fi
                ;;
            "SAFROCHAIN_API_PORT")
                if [ -n "$SAFROCHAIN_P2P_PORT" ] && [ "$default_port" -eq "$SAFROCHAIN_P2P_PORT" ]; then
                    port_already_assigned=true
                elif [ -n "$SAFROCHAIN_RPC_PORT" ] && [ "$default_port" -eq "$SAFROCHAIN_RPC_PORT" ]; then
                    port_already_assigned=true
                elif [ -n "$SAFROCHAIN_GRPC_PORT" ] && [ "$default_port" -eq "$SAFROCHAIN_GRPC_PORT" ]; then
                    port_already_assigned=true
                fi
                ;;
            "SAFROCHAIN_GRPC_PORT")
                if [ -n "$SAFROCHAIN_P2P_PORT" ] && [ "$default_port" -eq "$SAFROCHAIN_P2P_PORT" ]; then
                    port_already_assigned=true
                elif [ -n "$SAFROCHAIN_RPC_PORT" ] && [ "$default_port" -eq "$SAFROCHAIN_RPC_PORT" ]; then
                    port_already_assigned=true
                elif [ -n "$SAFROCHAIN_API_PORT" ] && [ "$default_port" -eq "$SAFROCHAIN_API_PORT" ]; then
                    port_already_assigned=true
                fi
                ;;
        esac
        
        if [ "$port_already_assigned" = false ]; then
            eval "$port_var_name=\$default_port"
            print_status "Using Safrochain default $port_var_name: ${!port_var_name}"
            return
        fi
    fi
    
    # Check if port from .env is available and not already assigned
    if [ -n "$env_port_value" ] && is_port_available $env_port_value; then
        # Check if this port is already assigned to another service
        local port_already_assigned=false
        case $port_var_name in
            "SAFROCHAIN_P2P_PORT")
                if [ -n "$SAFROCHAIN_RPC_PORT" ] && [ "$env_port_value" -eq "$SAFROCHAIN_RPC_PORT" ]; then
                    port_already_assigned=true
                elif [ -n "$SAFROCHAIN_API_PORT" ] && [ "$env_port_value" -eq "$SAFROCHAIN_API_PORT" ]; then
                    port_already_assigned=true
                elif [ -n "$SAFROCHAIN_GRPC_PORT" ] && [ "$env_port_value" -eq "$SAFROCHAIN_GRPC_PORT" ]; then
                    port_already_assigned=true
                fi
                ;;
            "SAFROCHAIN_RPC_PORT")
                if [ -n "$SAFROCHAIN_P2P_PORT" ] && [ "$env_port_value" -eq "$SAFROCHAIN_P2P_PORT" ]; then
                    port_already_assigned=true
                elif [ -n "$SAFROCHAIN_API_PORT" ] && [ "$env_port_value" -eq "$SAFROCHAIN_API_PORT" ]; then
                    port_already_assigned=true
                elif [ -n "$SAFROCHAIN_GRPC_PORT" ] && [ "$env_port_value" -eq "$SAFROCHAIN_GRPC_PORT" ]; then
                    port_already_assigned=true
                fi
                ;;
            "SAFROCHAIN_API_PORT")
                if [ -n "$SAFROCHAIN_P2P_PORT" ] && [ "$env_port_value" -eq "$SAFROCHAIN_P2P_PORT" ]; then
                    port_already_assigned=true
                elif [ -n "$SAFROCHAIN_RPC_PORT" ] && [ "$env_port_value" -eq "$SAFROCHAIN_RPC_PORT" ]; then
                    port_already_assigned=true
                elif [ -n "$SAFROCHAIN_GRPC_PORT" ] && [ "$env_port_value" -eq "$SAFROCHAIN_GRPC_PORT" ]; then
                    port_already_assigned=true
                fi
                ;;
            "SAFROCHAIN_GRPC_PORT")
                if [ -n "$SAFROCHAIN_P2P_PORT" ] && [ "$env_port_value" -eq "$SAFROCHAIN_P2P_PORT" ]; then
                    port_already_assigned=true
                elif [ -n "$SAFROCHAIN_RPC_PORT" ] && [ "$env_port_value" -eq "$SAFROCHAIN_RPC_PORT" ]; then
                    port_already_assigned=true
                elif [ -n "$SAFROCHAIN_API_PORT" ] && [ "$env_port_value" -eq "$SAFROCHAIN_API_PORT" ]; then
                    port_already_assigned=true
                fi
                ;;
        esac
        
        if [ "$port_already_assigned" = false ]; then
            eval "$port_var_name=\$env_port_value"
            print_status "Using $port_var_name from .env: ${!port_var_name}"
            return
        fi
    fi
    
    # If port from .env is not available or already assigned, find alternative
    if [ -n "$env_port_value" ]; then
        print_warning "Port $env_port_value from .env is not available or already assigned, finding alternative..."
    fi
    
    # Find available port, starting from default port
    local found_port=$(find_available_port $default_port)
    
    # Make sure the found port is not already assigned
    case $port_var_name in
        "SAFROCHAIN_P2P_PORT")
            while ([ -n "$SAFROCHAIN_RPC_PORT" ] && [ "$found_port" -eq "$SAFROCHAIN_RPC_PORT" ]) || \
                  ([ -n "$SAFROCHAIN_API_PORT" ] && [ "$found_port" -eq "$SAFROCHAIN_API_PORT" ]) || \
                  ([ -n "$SAFROCHAIN_GRPC_PORT" ] && [ "$found_port" -eq "$SAFROCHAIN_GRPC_PORT" ]); do
                found_port=$((found_port + 1))
                found_port=$(find_available_port $found_port)
            done
            ;;
        "SAFROCHAIN_RPC_PORT")
            while ([ -n "$SAFROCHAIN_P2P_PORT" ] && [ "$found_port" -eq "$SAFROCHAIN_P2P_PORT" ]) || \
                  ([ -n "$SAFROCHAIN_API_PORT" ] && [ "$found_port" -eq "$SAFROCHAIN_API_PORT" ]) || \
                  ([ -n "$SAFROCHAIN_GRPC_PORT" ] && [ "$found_port" -eq "$SAFROCHAIN_GRPC_PORT" ]); do
                found_port=$((found_port + 1))
                found_port=$(find_available_port $found_port)
            done
            ;;
        "SAFROCHAIN_API_PORT")
            while ([ -n "$SAFROCHAIN_P2P_PORT" ] && [ "$found_port" -eq "$SAFROCHAIN_P2P_PORT" ]) || \
                  ([ -n "$SAFROCHAIN_RPC_PORT" ] && [ "$found_port" -eq "$SAFROCHAIN_RPC_PORT" ]) || \
                  ([ -n "$SAFROCHAIN_GRPC_PORT" ] && [ "$found_port" -eq "$SAFROCHAIN_GRPC_PORT" ]); do
                found_port=$((found_port + 1))
                found_port=$(find_available_port $found_port)
            done
            ;;
        "SAFROCHAIN_GRPC_PORT")
            while ([ -n "$SAFROCHAIN_P2P_PORT" ] && [ "$found_port" -eq "$SAFROCHAIN_P2P_PORT" ]) || \
                  ([ -n "$SAFROCHAIN_RPC_PORT" ] && [ "$found_port" -eq "$SAFROCHAIN_RPC_PORT" ]) || \
                  ([ -n "$SAFROCHAIN_API_PORT" ] && [ "$found_port" -eq "$SAFROCHAIN_API_PORT" ]); do
                found_port=$((found_port + 1))
                found_port=$(find_available_port $found_port)
            done
            ;;
    esac
    
    eval "$port_var_name=\$found_port"
    print_status "Using $port_var_name: ${!port_var_name}"
}

# Function to check if Safrochain default ports are available, otherwise find alternatives
check_and_set_ports() {
    # First, try Safrochain default ports
    print_status "Checking Safrochain default ports..."
    
    # Load environment variables from .env file if it exists
    if [ -f ".env" ]; then
        print_status "Loading environment variables from .env file..."
        source .env
    fi
    
    # IMPORTANT: Cleanup existing container BEFORE checking ports
    cleanup_existing_container
    
    # Small delay to ensure container is fully stopped and ports are released
    sleep 2
    
    # Check each port using the generic function, but ensure they are unique
    check_and_set_port "SAFROCHAIN_P2P_PORT" $SAFROCHAIN_P2P_PORT_DEFAULT
    
    # For RPC port, make sure it's different from P2P port
    local rpc_base_port=$SAFROCHAIN_RPC_PORT_DEFAULT
    # If RPC default port is the same as P2P port or conflicts with existing P2P port, adjust it
    if [ "$rpc_base_port" -eq "$SAFROCHAIN_P2P_PORT_DEFAULT" ] || \
       ([ -n "$SAFROCHAIN_P2P_PORT" ] && [ "$rpc_base_port" -eq "$SAFROCHAIN_P2P_PORT" ]); then
        # Start from P2P port + 1 or default RPC port + 1, whichever is higher
        if [ -n "$SAFROCHAIN_P2P_PORT" ]; then
            rpc_base_port=$((SAFROCHAIN_P2P_PORT + 1))
        else
            rpc_base_port=$((SAFROCHAIN_RPC_PORT_DEFAULT + 1))
        fi
    fi
    check_and_set_port "SAFROCHAIN_RPC_PORT" $rpc_base_port
    
    # For API port, make sure it's different from P2P and RPC ports
    local api_base_port=$SAFROCHAIN_API_PORT_DEFAULT
    check_and_set_port "SAFROCHAIN_API_PORT" $api_base_port
    
    # For gRPC port, make sure it's different from other ports
    local grpc_base_port=$SAFROCHAIN_GRPC_PORT_DEFAULT
    check_and_set_port "SAFROCHAIN_GRPC_PORT" $grpc_base_port
}

# Function to update docker-compose.yml with the found ports
update_docker_compose() {
    print_status "Updating docker-compose.yml with found ports..."
    
    # We don't need to update the docker-compose.yml file since it already uses environment variables
    # The ports will be used directly from the environment variables
    print_status "docker-compose.yml already configured to use environment variables"
}

# Function to initialize the node
init_node() {
    local moniker=${1:-"safrochain-validator"}
    
    print_status "Initializing Safrochain node with moniker: $moniker"
    
    # Create data directory if it doesn't exist
    mkdir -p data
    
    # Check if node is already initialized
    if [ -f "data/config/genesis.json" ]; then
        print_warning "Node already initialized. Skipping initialization."
        return
    fi
    
    # Initialize the node
    docker run --rm -v $(pwd)/data:/data safrochain/safrochaind:local init $moniker --chain-id safro-testnet-1 --home /data
    
    print_status "Node initialized successfully"
}

# Function to configure the node
configure_node() {
    print_status "Configuring node settings"
    
    # Download genesis file
    print_status "Downloading genesis file"
    curl -L https://genesis.safrochain.com/testnet/genesis.json -o data/config/genesis.json
    
    # Configure seeds
    docker run --rm -v $(pwd)/data:/data alpine sh -c "
        sed -i 's/seeds = \"\"/seeds = \"2242a526e7841e7e8a551aabc4614e6cd612e7fb@88.99.211.113:26656\"/g' /data/config/config.toml
        sed -i 's/persistent_peers = \"\"/persistent_peers = \"2242a526e7841e7e8a551aabc4614e6cd612e7fb@88.99.211.113:26656\"/g' /data/config/config.toml
        sed -i 's/minimum-gas-prices = \"\"/minimum-gas-prices = \"0.001usaf\"/g' /data/config/app.toml
    "
    
    print_status "Node configured successfully"
}

# Function to create a wallet
create_wallet() {
    local wallet_name=${1:-"validator-wallet"}
    
    print_status "Creating wallet: $wallet_name"
    
    # Check if wallet already exists
    if [ -f "data/keyring-test/$wallet_name.info" ]; then
        print_warning "Wallet $wallet_name already exists. Skipping creation."
        return
    fi
    
    # Create wallet
    echo "Creating wallet. Please save the mnemonic phrase securely:"
    docker run --rm -v $(pwd)/data:/data safrochain/safrochaind:local keys add $wallet_name --home /data --keyring-backend test
    
    # Show wallet address
    print_status "Wallet address:"
    docker run --rm -v $(pwd)/data:/data safrochain/safrochaind:local keys show $wallet_name --address --home /data --keyring-backend test
    
    print_status "Wallet created successfully. Please backup your mnemonic phrase!"
}

# Function to import wallet from mnemonic
import_wallet_from_mnemonic() {
    local wallet_name=${1:-"validator-wallet"}
    
    print_status "Importing wallet from mnemonic: $wallet_name"
    
    echo "Enter your mnemonic phrase (24 words):"
    read -s mnemonic
    
    if [ -z "$mnemonic" ]; then
        print_error "Mnemonic phrase cannot be empty"
        exit 1
    fi
    
    # Import wallet
    echo "$mnemonic" | docker run --rm -i -v $(pwd)/data:/data safrochain/safrochaind:local keys add $wallet_name --home /data --keyring-backend test --recover
    
    # Show wallet address
    print_status "Wallet imported. Address:"
    docker run --rm -v $(pwd)/data:/data safrochain/safrochaind:local keys show $wallet_name --address --home /data --keyring-backend test
    
    print_status "Wallet imported successfully"
}

# Function to import wallet from private key
import_wallet_from_private_key() {
    local wallet_name=${1:-"validator-wallet"}
    
    print_status "Importing wallet from private key: $wallet_name"
    
    echo "Enter your private key (hex format):"
    read -s private_key
    
    if [ -z "$private_key" ]; then
        print_error "Private key cannot be empty"
        exit 1
    fi
    
    # Import wallet using private key
    echo "$private_key" | docker run --rm -i -v $(pwd)/data:/data safrochain/safrochaind:local keys unsafe-import-eth-key $wallet_name --home /data --keyring-backend test
    
    # Show wallet address
    print_status "Wallet imported. Address:"
    docker run --rm -v $(pwd)/data:/data safrochain/safrochaind:local keys show $wallet_name --address --home /data --keyring-backend test
    
    print_status "Wallet imported successfully"
}

# Function to register as validator
register_validator() {
    local wallet_name=${1:-"validator-wallet"}
    local moniker=${2:-"safrochain-validator"}
    
    print_status "Registering as validator with wallet: $wallet_name and moniker: $moniker"
    
    # Create validator.json file with the correct format
    cat > validator.json << EOF
{
  "pubkey": {"@type":"/cosmos.crypto.ed25519.PubKey","key":"$(docker run --rm -v $(pwd)/data:/data safrochain/safrochaind:local tendermint show-validator --home /data | jq -r '.key')"},
  "amount": "1000000usaf",
  "moniker": "$moniker",
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
    
    # Copy validator.json to the container
    docker cp validator.json safrochain-validator:/data/validator.json
    
    # Create the validator
    docker exec safrochain-validator safrochaind tx staking create-validator /data/validator.json \
        --from=$wallet_name \
        --chain-id=safro-testnet-1 \
        --gas=200000 \
        --gas-prices="0.075usaf" \
        --home /data \
        --keyring-backend test \
        -y
    
    print_status "Validator registration transaction submitted"
}

# Function to start the node
start_node() {
    print_status "Starting Safrochain validator node"
    
    # Load environment variables from .env file if it exists
    if [ -f ".env" ]; then
        source .env
    fi
    
    # If moniker is not set, ask the user for it
    if [ -z "$SAFROCHAIN_MONIKER" ]; then
        echo -n "Enter your validator moniker (or press Enter for default 'safrochain-validator'): "
        read user_moniker
        if [ -n "$user_moniker" ]; then
            SAFROCHAIN_MONIKER="$user_moniker"
        else
            SAFROCHAIN_MONIKER="safrochain-validator"
        fi
        
        # Save the moniker to .env file
        echo "SAFROCHAIN_MONIKER=$SAFROCHAIN_MONIKER" >> .env
    fi
    
    # Update the moniker in config.toml
    docker run --rm -v $(pwd)/data:/data alpine sh -c "sed -i 's/moniker = \".*\"/moniker = \"'$SAFROCHAIN_MONIKER'\"/g' /data/config/config.toml"
    
    # Check and set ports before starting
    check_and_set_ports
    
    # Update docker-compose with the found ports
    update_docker_compose
    
    # Update .env file with the final port values
    update_env_file $SAFROCHAIN_P2P_PORT $SAFROCHAIN_RPC_PORT $SAFROCHAIN_API_PORT $SAFROCHAIN_GRPC_PORT
    
    # Export the ports as environment variables
    export SAFROCHAIN_P2P_PORT
    export SAFROCHAIN_RPC_PORT
    export SAFROCHAIN_API_PORT
    export SAFROCHAIN_GRPC_PORT
    export SAFROCHAIN_MONIKER
    
    # Start the node using docker-compose
    print_status "Starting Safrochain..."
    docker-compose up -d
    
    # Check if the container started successfully
    if [ $? -eq 0 ]; then
        # Wait a moment for the container to start
        sleep 2
        
        print_status "Safrochain validator node started successfully!"
        print_status "Moniker: $SAFROCHAIN_MONIKER"
        print_status "P2P Port: $SAFROCHAIN_P2P_PORT"
        print_status "RPC Port: $SAFROCHAIN_RPC_PORT"
        print_status "API Port: $SAFROCHAIN_API_PORT"
        print_status "gRPC Port: $SAFROCHAIN_GRPC_PORT"
        
        # Show live logs
        print_status "Showing Safrochain logs (Press Ctrl+C to exit)..."
        docker logs -f safrochain-validator
    else
        print_error "Failed to start Safrochain validator node"
        exit 1
    fi
}

# Function to check sync status
check_sync_status() {
    print_status "Checking sync status"
    
    docker exec -it safrochain-validator safrochaind status
}

# Function to check wallet balance
check_balance() {
    local wallet_name=${1:-"validator-wallet"}
    
    print_status "Checking wallet balance for: $wallet_name"
    
    wallet_address=$(docker run --rm -v $(pwd)/data:/data safrochain/safrochaind:local keys show $wallet_name --address --home /data --keyring-backend test)
    
    # Use the container name to connect to the RPC
    docker run --rm -v $(pwd)/data:/data --network container:safrochain-validator safrochain/safrochaind:local query bank balances $wallet_address --home /data
}

# Function to stop the node
stop_node() {
    print_status "Stopping Safrochain validator node"
    
    docker-compose down
}

# Function to request tokens from faucet
request_faucet_tokens() {
    local wallet_name=${1:-"validator-wallet"}
    
    print_status "Requesting tokens from faucet for wallet: $wallet_name"
    
    wallet_address=$(docker run --rm -v $(pwd)/data:/data safrochain/safrochaind:local keys show $wallet_name --address --home /data --keyring-backend test)
    
    print_status "Wallet address: $wallet_address"
    print_status "Please visit https://faucet.safrochain.com and enter this address to request tokens"
    print_status "Alternatively, you can use the command:"
    echo "curl -X POST https://faucet.testnet.safrochain.com/request -d '{\"address\":\"$wallet_address\"}'"
}

# Function to edit an existing validator
edit_validator() {
    local wallet_name=${1:-"validator-wallet"}
    local moniker=${2:-"safrochain-validator"}
    
    print_status "Editing validator with wallet: $wallet_name and new moniker: $moniker"
    
    # Edit the validator
    docker exec safrochain-validator safrochaind tx staking edit-validator \
        --new-moniker="$moniker" \
        --details="Safrochain Validator" \
        --from=$wallet_name \
        --chain-id=safro-testnet-1 \
        --gas=100000 \
        --gas-prices="0.075usaf" \
        --home /data \
        --keyring-backend test \
        -y
    
    print_status "Validator edit transaction submitted"
}

# Function to check validator status
check_validator_status() {
    local wallet_name=${1:-"validator-wallet"}
    
    print_status "Checking validator status for wallet: $wallet_name"
    
    # Get validator address
    validator_addr=$(docker exec safrochain-validator safrochaind keys show $wallet_name --bech val --address --home /data --keyring-backend test)
    
    # Check validator status
    docker exec safrochain-validator safrochaind query staking validator $validator_addr --home /data
}

# Function to show help
show_help() {
    echo "Safrochain Validator Setup Script"
    echo ""
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  init [moniker]                     Initialize the node with optional moniker"
    echo "  configure                          Configure the node with genesis file and seeds"
    echo "  create-wallet [name]               Create a new wallet with optional name"
    echo "  import-mnemonic [name]             Import wallet from mnemonic phrase"
    echo "  import-private-key [name]          Import wallet from private key"
    echo "  start                              Start the validator node"
    echo "  register-validator [wallet] [name]  Register as validator with wallet and moniker"
    echo "  edit-validator [wallet] [name]     Edit existing validator with new moniker"
    echo "  validator-status [wallet]          Check validator status"
    echo "  faucet [wallet]                    Request tokens from faucet"
    echo "  status                             Check sync status"
    echo "  balance [wallet]                   Check wallet balance"
    echo "  stop                               Stop the validator node"
    echo "  help                               Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 init my-validator"
    echo "  $0 create-wallet my-wallet"
    echo "  $0 register-validator my-wallet my-validator"
    echo "  $0 edit-validator my-wallet new-validator-name"
    echo "  $0 faucet validator-wallet"
}

# Main function
main() {
    # Check prerequisites silently
    check_docker >/dev/null 2>&1
    
    # Load environment variables from .env file if it exists
    if [ -f ".env" ]; then
        source .env
    fi
    
    # Parse command line arguments
    case "$1" in
        init)
            init_node "$2"
            ;;
        configure)
            configure_node
            ;;
        create-wallet)
            create_wallet "$2"
            ;;
        import-mnemonic)
            import_wallet_from_mnemonic "$2"
            ;;
        import-private-key)
            import_wallet_from_private_key "$2"
            ;;
        start)
            start_node
            ;;
        register-validator)
            register_validator "$2" "$3"
            ;;
        edit-validator)
            edit_validator "$2" "$3"
            ;;
        validator-status)
            check_validator_status "$2"
            ;;
        faucet)
            request_faucet_tokens "$2"
            ;;
        status)
            check_sync_status
            ;;
        balance)
            check_balance "$2"
            ;;
        stop)
            stop_node
            ;;
        help|"")
            show_help
            ;;
        *)
            print_error "Unknown command: $1"
            show_help
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"