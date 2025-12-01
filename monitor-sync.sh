#!/bin/bash

# Safrochain Validator Monitoring Script
# This script monitors the sync progress of the Safrochain validator node

set -e  # Exit on any error

# Load environment variables from .env file if it exists
if [ -f ".env" ]; then
    source .env
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
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

# Function to check if the safrochain container is running
check_container_running() {
    if ! docker ps --format '{{.Names}}' | grep -q "safrochain-validator"; then
        print_error "Safrochain validator container is not running."
        print_info "Please start the validator with: ./start-validator.sh start"
        exit 1
    fi
}

# Function to get sync status
get_sync_status() {
    docker exec safrochain-validator safrochaind status 2>/dev/null
}

# Function to get network info (peers)
get_network_info() {
    docker exec safrochain-validator safrochaind network-info 2>/dev/null
}

# Function to get peer count
get_peer_count() {
    # Get network info and extract peer count
    docker exec safrochain-validator safrochaind tendermint show-node-id 2>/dev/null
}

# Function to parse sync information
parse_sync_info() {
    local status_json=$1
    
    if [ -z "$status_json" ]; then
        print_error "Failed to get status information"
        return 1
    fi
    
    # Load environment variables from .env file if it exists
    if [ -f ".env" ]; then
        source .env
    fi
    
    # Set default moniker if not set
    SAFROCHAIN_MONIKER=${SAFROCHAIN_MONIKER:-"safrochain-validator"}
    
    # Parse JSON using jq
    local latest_block_height=$(echo $status_json | jq -r '.sync_info.latest_block_height')
    local catching_up=$(echo $status_json | jq -r '.sync_info.catching_up')
    local latest_block_time=$(echo $status_json | jq -r '.sync_info.latest_block_time')
    local node_moniker=$(echo $status_json | jq -r '.node_info.moniker')
    local node_id=$(echo $status_json | jq -r '.node_info.id')
    
    # Get peer count using RPC endpoint
    local peer_count=$(docker exec safrochain-validator curl -s http://localhost:26657/net_info 2>/dev/null | jq -r '.result.n_peers' 2>/dev/null || echo "0")
    
    # Display information
    echo "=========================================="
    echo "    SAFROCHAIN VALIDATOR MONITORING"
    echo "=========================================="
    echo "Node Moniker: $node_moniker"
    echo "Node ID: $node_id"
    echo "Latest Block Height: $latest_block_height"
    echo "Catching Up: $catching_up"
    echo "Connected Peers: $peer_count"
    echo "Latest Block Time: $latest_block_time"
    echo "=========================================="
    
    # Interpret status
    if [ "$catching_up" == "true" ]; then
        print_warning "Node is still syncing with the network"
        print_info "Progress: Block $latest_block_height"
    else
        print_status "Node is fully synced with the network!"
    fi
    
    # Peer connection status
    if [ "$peer_count" -eq 0 ]; then
        print_warning "No peers connected - check network connectivity"
    fi
    
    return 0
}

# Function to continuous monitoring
monitor_continuous() {
    print_info "Starting continuous monitoring (Press Ctrl+C to stop)"
    echo ""
    
    while true; do
        check_container_running
        
        local status_json=$(get_sync_status)
        if [ -n "$status_json" ]; then
            parse_sync_info "$status_json"
        else
            print_error "Failed to retrieve status information"
        fi
        
        echo ""
        sleep 10
    done
}

# Function to show help
show_help() {
    echo "Safrochain Validator Monitoring Script"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  -c, --continuous    Continuous monitoring (updates every 10 seconds)"
    echo "  -h, --help          Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0              Show current sync status"
    echo "  $0 -c           Start continuous monitoring"
    echo ""
    echo "Requirements:"
    echo "  - Docker and docker-compose installed"
    echo "  - Safrochain validator container running"
    echo "  - jq installed for JSON parsing"
}

# Main function
main() {
    # Check prerequisites
    check_docker
    
    # Check if jq is installed
    if ! command -v jq &> /dev/null; then
        print_error "jq is not installed. Please install jq first:"
        echo "  Ubuntu/Debian: sudo apt-get install jq"
        echo "  CentOS/RHEL: sudo yum install jq"
        echo "  macOS: brew install jq"
        exit 1
    fi
    
    # Parse command line arguments
    case "$1" in
        -c|--continuous)
            check_container_running
            monitor_continuous
            ;;
        -h|--help)
            show_help
            ;;
        *)
            # Default behavior: show current status
            check_container_running
            local status_json=$(get_sync_status)
            if [ -n "$status_json" ]; then
                parse_sync_info "$status_json"
            else
                print_error "Failed to retrieve status information"
                exit 1
            fi
            ;;
    esac
}

# Run main function with all arguments
main "$@"