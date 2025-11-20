#!/bin/bash
#Author @zhamrock
###########################################
# Vote Account Withdrawal Script (Cron Safe)
###########################################

set -e  # Exit on error

#------------------------------------------
# ENVIRONMENT FIXES FOR CRON
#------------------------------------------
export TERM=xterm
export NO_COLOR=1
export SOLANA_DISABLE_COLOR=1

# Ensure solana binary path
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$HOME/.local/share/solana/install/active_release/bin:$PATH"

#------------------------------------------
# COLOR SUPPORT (terminal only)
#------------------------------------------
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
else
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    NC=""
fi

#------------------------------------------
# CONFIG
#------------------------------------------
SOLANA_DIR="$HOME/.config/solana"
VOTE_KEYPAIR="vote.json"
WITHDRAW_KEYPAIR="withdraw.json"
IDENTITY_KEYPAIR="identity.json"
TARGET_WALLET="73DAYvoeXnohwte9Z5jo2zxknyQFi8iXUbDXGMJzXCWc"
VOTE_ACCOUNT_RESERVE=0.5  # SOL to leave in vote account

LOG_DIR="$HOME/.config/solana/logs"
LOG_FILE="$LOG_DIR/vote_withdrawal_$(date +%Y%m).log"
HISTORY_FILE="$LOG_DIR/withdrawal_history.csv"

mkdir -p "$LOG_DIR"

if [ ! -f "$HISTORY_FILE" ]; then
    echo "timestamp,vote_balance_before,withdraw_amount,vote_balance_after,target_balance_after,status,error_message" > "$HISTORY_FILE"
fi

#------------------------------------------
# LOG FUNCTIONS
#------------------------------------------
log_to_file() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    log_to_file "[INFO] $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    log_to_file "[SUCCESS] $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    log_to_file "[ERROR] $1"
}

#------------------------------------------
# VALIDATION
#------------------------------------------
validate_keypair() {
    local path="$1"
    local name="$2"

    if [ ! -f "$path" ]; then
        log_error "$name not found at: $path"
        return 1
    fi

    if ! solana-keygen verify "$path" &>/dev/null; then
        log_error "$name is not a valid keypair: $path"
        return 1
    fi

    log_success "$name validated"
    return 0
}

validate_address() {
    local addr="$1"
    local name="$2"

    if [ -z "$addr" ]; then
        log_error "$name address is empty"
        return 1
    fi

    if [ ${#addr} -lt 32 ] || [ ${#addr} -gt 44 ]; then
        log_error "$name address invalid length: $addr"
        return 1
    fi

    log_success "$name address validated"
}

check_balance() {
    solana balance "$1" 2>/dev/null | awk '{print $1}'
}

check_network_connection() {
    log_info "Checking network..."

    if ! solana cluster-version &>/dev/null; then
        log_error "Cannot connect to network"
        solana config get | tee -a "$LOG_FILE"
        return 1
    fi

    log_success "Connected to Solana"
}

log_withdrawal_history() {
    echo "$1,$2,$3,$4,$5,$6,\"$7\"" >> "$HISTORY_FILE"
}

###########################################
# MAIN EXECUTION START
###########################################

RUN_TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
ERROR_MESSAGE=""

log_info "========================================="
log_info "Starting withdrawal session"
log_info "========================================="
log_info "Log: $LOG_FILE"
log_info "History: $HISTORY_FILE"

#------------------------------------------
# CHANGE DIRECTORY
#------------------------------------------
if ! cd "$SOLANA_DIR"; then
    ERROR_MESSAGE="Cannot access directory: $SOLANA_DIR"
    log_error "$ERROR_MESSAGE"
    log_withdrawal_history "$RUN_TIMESTAMP" "0" "0" "0" "0" "FAILED" "$ERROR_MESSAGE"
    exit 1
fi

#------------------------------------------
# NETWORK CHECK
#------------------------------------------
if ! check_network_connection; then
    ERROR_MESSAGE="Network unavailable"
    log_withdrawal_history "$RUN_TIMESTAMP" "0" "0" "0" "0" "FAILED" "$ERROR_MESSAGE"
    exit 1
fi

# Validate target address
validate_address "$TARGET_WALLET" "Target wallet" || exit 1

#------------------------------------------
# INITIAL BALANCES
#------------------------------------------
VOTE_ACCOUNT=$(solana-keygen pubkey "$VOTE_KEYPAIR")
VOTE_BALANCE_INITIAL=$(check_balance "$VOTE_KEYPAIR")
WITHDRAW_BALANCE=$(check_balance "$WITHDRAW_KEYPAIR")
TARGET_BALANCE=$(check_balance "$TARGET_WALLET")

log_info "Vote Account: $VOTE_ACCOUNT"
log_info "Vote Balance: $VOTE_BALANCE_INITIAL SOL"

# Must have balance above reserve
if (( $(echo "$VOTE_BALANCE_INITIAL <= $VOTE_ACCOUNT_RESERVE" | bc -l) )); then
    ERROR_MESSAGE="Insufficient vote account balance"
    log_error "$ERROR_MESSAGE"
    exit 1
fi

WITHDRAW_AMOUNT=$(echo "$VOTE_BALANCE_INITIAL - $VOTE_ACCOUNT_RESERVE" | bc)

log_info "Will withdraw: $WITHDRAW_AMOUNT SOL"
log_info "Leaving reserve: $VOTE_ACCOUNT_RESERVE SOL"

#------------------------------------------
# WITHDRAW FROM VOTE
#------------------------------------------
log_info "Withdrawing from vote account..."

if ! solana withdraw-from-vote-account "$VOTE_KEYPAIR" "$WITHDRAW_KEYPAIR" "$WITHDRAW_AMOUNT" --authorized-withdrawer "$WITHDRAW_KEYPAIR" 2>&1 | tee -a "$LOG_FILE"; then
    ERROR_MESSAGE="Withdraw from vote failed"
    log_error "$ERROR_MESSAGE"
    exit 1
fi

sleep 2

#------------------------------------------
# TRANSFER TO TARGET WALLET
#------------------------------------------
ORIGINAL_KEYPAIR=$(solana config get | grep "Keypair Path" | awk '{print $3}')
solana config set -k "$WITHDRAW_KEYPAIR" > /dev/null

WITHDRAW_BALANCE=$(check_balance "$WITHDRAW_KEYPAIR")
TRANSFER_AMOUNT=$(echo "$WITHDRAW_BALANCE - 0.001" | bc)

if (( $(echo "$TRANSFER_AMOUNT <= 0" | bc -l) )); then
    ERROR_MESSAGE="Insufficient withdraw account balance"
    log_error "$ERROR_MESSAGE"
    solana config set -k "$ORIGINAL_KEYPAIR" > /dev/null
    exit 1
fi

log_info "Transferring $TRANSFER_AMOUNT SOL..."

if ! solana transfer "$TARGET_WALLET" "$TRANSFER_AMOUNT" --allow-unfunded-recipient 2>&1 | tee -a "$LOG_FILE"; then
    ERROR_MESSAGE="Transfer failed"
    log_error "$ERROR_MESSAGE"
    solana config set -k "$ORIGINAL_KEYPAIR" > /dev/null
    exit 1
fi

solana config set -k "$ORIGINAL_KEYPAIR" > /dev/null

sleep 2

#------------------------------------------
# FINAL BALANCES
#------------------------------------------
VOTE_BALANCE=$(check_balance "$VOTE_KEYPAIR")
WITHDRAW_BALANCE=$(check_balance "$WITHDRAW_KEYPAIR")
TARGET_BALANCE=$(check_balance "$TARGET_WALLET")

log_success "Withdrawal Complete"
log_info "Vote Before: $VOTE_BALANCE_INITIAL"
log_info "Withdrawn: $WITHDRAW_AMOUNT"
log_info "Vote After:  $VOTE_BALANCE"
log_info "Target After: $TARGET_BALANCE"

log_withdrawal_history "$RUN_TIMESTAMP" "$VOTE_BALANCE_INITIAL" "$WITHDRAW_AMOUNT" "$VOTE_BALANCE" "$TARGET_BALANCE" "SUCCESS" ""
log_info "========================================="
log_info "Session complete"
log_info "========================================="
