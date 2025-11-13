#!/bin/bash

###########################################
# Vote Account Withdrawal Script
# Safely withdraws funds from vote account
###########################################

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SOLANA_DIR="$HOME/.config/solana"
VOTE_KEYPAIR="vote.json"
WITHDRAW_KEYPAIR="withdraw.json"
IDENTITY_KEYPAIR="identity.json"
TARGET_WALLET="73DAYvoeXnohwte9Z5jo2zxknyQFi8iXUbDXGMJzXCWc"
VOTE_ACCOUNT_RESERVE=0.5  # SOL to leave in vote account

# Logging configuration
LOG_DIR="$HOME/.config/solana/logs"
LOG_FILE="$LOG_DIR/vote_withdrawal_$(date +%Y%m).log"
HISTORY_FILE="$LOG_DIR/withdrawal_history.csv"

# Create log directory if it doesn't exist
mkdir -p "$LOG_DIR"

# Initialize history file with headers if it doesn't exist
if [ ! -f "$HISTORY_FILE" ]; then
    echo "timestamp,vote_balance_before,withdraw_amount,vote_balance_after,target_balance_after,status,error_message" > "$HISTORY_FILE"
fi

# Logging functions
log_to_file() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" >> "$LOG_FILE"
}

log_info() {
    local msg="$1"
    echo -e "${BLUE}[INFO]${NC} $msg"
    log_to_file "[INFO] $msg"
}

log_success() {
    local msg="$1"
    echo -e "${GREEN}[SUCCESS]${NC} $msg"
    log_to_file "[SUCCESS] $msg"
}

log_warning() {
    local msg="$1"
    echo -e "${YELLOW}[WARNING]${NC} $msg"
    log_to_file "[WARNING] $msg"
}

log_error() {
    local msg="$1"
    echo -e "${RED}[ERROR]${NC} $msg"
    log_to_file "[ERROR] $msg"
}

# Validation functions
validate_keypair() {
    local keypair_path="$1"
    local keypair_name="$2"
    
    if [ ! -f "$keypair_path" ]; then
        log_error "$keypair_name not found at: $keypair_path"
        return 1
    fi
    
    if [ ! -r "$keypair_path" ]; then
        log_error "$keypair_name is not readable: $keypair_path"
        return 1
    fi
    
    # Validate keypair format
    if ! solana-keygen verify "$keypair_path" &>/dev/null; then
        log_error "$keypair_name is not a valid Solana keypair: $keypair_path"
        return 1
    fi
    
    log_success "$keypair_name validated"
    return 0
}

validate_address() {
    local address="$1"
    local name="$2"
    
    if [ -z "$address" ]; then
        log_error "$name address is empty"
        return 1
    fi
    
    # Basic length check for Solana address (32-44 characters)
    if [ ${#address} -lt 32 ] || [ ${#address} -gt 44 ]; then
        log_error "$name address has invalid length: $address"
        return 1
    fi
    
    log_success "$name address validated"
    return 0
}

check_balance() {
    local keypair="$1"
    local balance=$(solana balance "$keypair" 2>/dev/null | awk '{print $1}')
    
    if [ -z "$balance" ]; then
        echo "0"
    else
        echo "$balance"
    fi
}

check_network_connection() {
    log_info "Checking network connection..."
    
    if ! solana cluster-version &>/dev/null; then
        log_error "Cannot connect to Solana network. Check your RPC endpoint."
        log_info "Current config:"
        solana config get | tee -a "$LOG_FILE"
        return 1
    fi
    
    log_success "Connected to Solana network"
    local cluster=$(solana config get | grep "RPC URL" | awk '{print $3}')
    log_info "Cluster: $cluster"
    return 0
}

log_withdrawal_history() {
    local timestamp="$1"
    local vote_before="$2"
    local withdraw_amt="$3"
    local vote_after="$4"
    local target_after="$5"
    local status="$6"
    local error_msg="$7"
    
    echo "$timestamp,$vote_before,$withdraw_amt,$vote_after,$target_after,$status,\"$error_msg\"" >> "$HISTORY_FILE"
}

###########################################
# Main Script
###########################################

# Start timestamp for this run
RUN_TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
ERROR_MESSAGE=""

clear
echo "========================================="
echo "  Vote Account Withdrawal Script"
echo "  $(date)"
echo "========================================="
echo ""

log_info "========================================="
log_info "Starting new withdrawal session"
log_info "Log file: $LOG_FILE"
log_info "History file: $HISTORY_FILE"
log_info "========================================="

# Change to Solana directory
log_info "Changing to Solana directory: $SOLANA_DIR"
if ! cd "$SOLANA_DIR" 2>/dev/null; then
    ERROR_MESSAGE="Cannot access directory: $SOLANA_DIR"
    log_error "$ERROR_MESSAGE"
    log_withdrawal_history "$RUN_TIMESTAMP" "0" "0" "0" "0" "FAILED" "$ERROR_MESSAGE"
    exit 1
fi

# Check network connection
if ! check_network_connection; then
    ERROR_MESSAGE="Network connection failed"
    log_withdrawal_history "$RUN_TIMESTAMP" "0" "0" "0" "0" "FAILED" "$ERROR_MESSAGE"
    exit 1
fi

echo ""
echo "========================================="
echo "  VALIDATION CHECKS"
echo "========================================="

# Validate target wallet address
if ! validate_address "$TARGET_WALLET" "Target wallet"; then
    ERROR_MESSAGE="Target wallet address validation failed"
    log_withdrawal_history "$RUN_TIMESTAMP" "0" "0" "0" "0" "FAILED" "$ERROR_MESSAGE"
    exit 1
fi

echo ""
echo "========================================="
echo "  INITIAL BALANCES"
echo "========================================="

# Get vote account public key
VOTE_ACCOUNT=$(solana-keygen pubkey "$VOTE_KEYPAIR")
log_info "Vote Account: $VOTE_ACCOUNT"

# Display initial balances
VOTE_BALANCE=$(check_balance "$VOTE_KEYPAIR")
WITHDRAW_BALANCE=$(check_balance "$WITHDRAW_KEYPAIR")
TARGET_BALANCE=$(check_balance "$TARGET_WALLET")

printf "%-20s: %s SOL\n" "Vote Account" "$VOTE_BALANCE"
printf "%-20s: %s SOL\n" "Withdraw Account" "$WITHDRAW_BALANCE"
printf "%-20s: %s SOL\n" "Target Wallet" "$TARGET_BALANCE"

# Validate vote account has sufficient balance
if (( $(echo "$VOTE_BALANCE <= $VOTE_ACCOUNT_RESERVE" | bc -l) )); then
    ERROR_MESSAGE="Vote account balance ($VOTE_BALANCE SOL) is not enough to withdraw. Minimum required: $VOTE_ACCOUNT_RESERVE SOL"
    log_error "$ERROR_MESSAGE"
    log_withdrawal_history "$RUN_TIMESTAMP" "$VOTE_BALANCE" "0" "$VOTE_BALANCE" "$TARGET_BALANCE" "FAILED" "$ERROR_MESSAGE"
    exit 1
fi

# Calculate withdrawal amount
WITHDRAW_AMOUNT=$(echo "$VOTE_BALANCE - $VOTE_ACCOUNT_RESERVE" | bc)

if (( $(echo "$WITHDRAW_AMOUNT <= 0" | bc -l) )); then
    ERROR_MESSAGE="Calculated withdrawal amount is zero or negative: $WITHDRAW_AMOUNT SOL"
    log_error "$ERROR_MESSAGE"
    log_withdrawal_history "$RUN_TIMESTAMP" "$VOTE_BALANCE" "0" "$VOTE_BALANCE" "$TARGET_BALANCE" "FAILED" "$ERROR_MESSAGE"
    exit 1
fi

echo ""
echo "========================================="
echo "  WITHDRAWAL PLAN"
echo "========================================="
log_info "Amount to withdraw: $WITHDRAW_AMOUNT SOL"
log_info "Reserve in vote account: $VOTE_ACCOUNT_RESERVE SOL"
log_info "Proceeding with automatic withdrawal..."
echo ""
echo "========================================="
echo "  STEP 1: Withdraw from Vote Account"
echo "========================================="

log_info "Withdrawing $WITHDRAW_AMOUNT SOL from vote account..."

if solana withdraw-from-vote-account "$VOTE_KEYPAIR" "$WITHDRAW_KEYPAIR" "$WITHDRAW_AMOUNT" \
    --authorized-withdrawer "$WITHDRAW_KEYPAIR" 2>&1 | tee -a "$LOG_FILE"; then
    log_success "Withdrawal from vote account completed"
else
    ERROR_MESSAGE="Failed to withdraw from vote account"
    log_error "$ERROR_MESSAGE"
    log_withdrawal_history "$RUN_TIMESTAMP" "$VOTE_BALANCE" "$WITHDRAW_AMOUNT" "$VOTE_BALANCE" "$TARGET_BALANCE" "FAILED" "$ERROR_MESSAGE"
    exit 1
fi

# Wait for confirmation
sleep 2

echo ""
echo "========================================="
echo "  INTERMEDIATE BALANCES"
echo "========================================="

VOTE_BALANCE=$(check_balance "$VOTE_KEYPAIR")
WITHDRAW_BALANCE=$(check_balance "$WITHDRAW_KEYPAIR")

printf "%-20s: %s SOL\n" "Vote Account" "$VOTE_BALANCE"
printf "%-20s: %s SOL\n" "Withdraw Account" "$WITHDRAW_BALANCE"

echo ""
echo "========================================="
echo "  STEP 2: Transfer to Target Wallet"
echo "========================================="

# Save current keypair
ORIGINAL_KEYPAIR=$(solana config get | grep "Keypair Path" | awk '{print $3}')
log_info "Original keypair: $ORIGINAL_KEYPAIR"

# Set withdraw keypair as source
log_info "Setting withdraw keypair as source..."
solana config set -k "$WITHDRAW_KEYPAIR" > /dev/null

# Calculate transfer amount (leave some for transaction fees)
TRANSFER_AMOUNT=$(echo "$WITHDRAW_BALANCE - 0.001" | bc)

if (( $(echo "$TRANSFER_AMOUNT <= 0" | bc -l) )); then
    ERROR_MESSAGE="Insufficient balance in withdraw account for transfer"
    log_error "$ERROR_MESSAGE"
    log_withdrawal_history "$RUN_TIMESTAMP" "$VOTE_BALANCE" "$WITHDRAW_AMOUNT" "$VOTE_BALANCE" "$TARGET_BALANCE" "FAILED" "$ERROR_MESSAGE"
    solana config set -k "$ORIGINAL_KEYPAIR" > /dev/null
    exit 1
fi

log_info "Transferring $TRANSFER_AMOUNT SOL to target wallet..."

if solana transfer "$TARGET_WALLET" "$TRANSFER_AMOUNT" --allow-unfunded-recipient 2>&1 | tee -a "$LOG_FILE"; then
    log_success "Transfer to target wallet completed"
else
    ERROR_MESSAGE="Failed to transfer to target wallet"
    log_error "$ERROR_MESSAGE"
    log_withdrawal_history "$RUN_TIMESTAMP" "$VOTE_BALANCE" "$WITHDRAW_AMOUNT" "$VOTE_BALANCE" "$TARGET_BALANCE" "FAILED" "$ERROR_MESSAGE"
    solana config set -k "$ORIGINAL_KEYPAIR" > /dev/null
    exit 1
fi

# Restore original keypair
log_info "Restoring original keypair configuration..."
solana config set -k "$ORIGINAL_KEYPAIR" > /dev/null

# Wait for confirmation
sleep 2

echo ""
echo "========================================="
echo "  FINAL BALANCES"
echo "========================================="

VOTE_BALANCE=$(check_balance "$VOTE_KEYPAIR")
WITHDRAW_BALANCE=$(check_balance "$WITHDRAW_KEYPAIR")
TARGET_BALANCE=$(check_balance "$TARGET_WALLET")

printf "%-20s: %s SOL\n" "Vote Account" "$VOTE_BALANCE"
printf "%-20s: %s SOL\n" "Withdraw Account" "$WITHDRAW_BALANCE"
printf "%-20s: %s SOL\n" "Target Wallet" "$TARGET_BALANCE"

# Log to history file
log_withdrawal_history "$RUN_TIMESTAMP" "$VOTE_BALANCE" "$WITHDRAW_AMOUNT" "$VOTE_BALANCE" "$TARGET_BALANCE" "SUCCESS" ""

echo ""
echo "========================================="
echo -e "${GREEN}  ✓ WITHDRAWAL COMPLETED SUCCESSFULLY${NC}"
echo "========================================="
echo ""

log_info "Withdrawal Summary:"
log_info "  Vote Balance Before: $VOTE_BALANCE SOL"
log_info "  Amount Withdrawn: $WITHDRAW_AMOUNT SOL"
log_info "  Final Vote Balance: $VOTE_BALANCE SOL"
log_info "  Final Target Balance: $TARGET_BALANCE SOL"
log_info "Script completed at $(date)"
log_info "========================================="
