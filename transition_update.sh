#!/bin/bash

# Function to read input with a default value
read_input() {
  local prompt=$1
  local default=$2
  local result
  read -p "$prompt [$default]: " result
  echo "${result:-$default}"
}

# Set environment variables with user input
PRIMARY_SERVER_IP=$(read_input "Enter the IP address of the primary server" "")
PRIMARY_SSH_USER=$(read_input "Enter the username for the primary server" "ubuntu")
SECONDARY_SERVER_IP=$(read_input "Enter the IP address of the secondary server" "")
SECONDARY_SSH_USER=$(read_input "Enter the username for the secondary server" "admin")
PRIMARY_LEDGER_DIR=$(read_input "Enter the full path to the ledger directory on the primary server" "/mnt/data/solana/ledger")
SECONDARY_LEDGER_DIR=$(read_input "Enter the full path to the ledger directory on the secondary server" "/mnt/data/solana/ledger")
PRIMARY_SOLANA_BIN="/home/$PRIMARY_SSH_USER/.local/share/solana/install/active_release/bin/solana"
SECONDARY_SOLANA_BIN="/home/$SECONDARY_SSH_USER/.local/share/solana/install/active_release/bin/solana"
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to check command success
check_command() {
  if [ $? -ne 0 ]; then
    echo -e "${RED}Error: $1 failed.${NC}"
    exit 1
  fi
}

# Function to check for "Ready to restart"
check_ready_for_restart() {
  local server_ip=$1
  local ssh_user=$2
  local solana_bin=$3
  echo -e "${YELLOW}Checking restart readiness on $server_ip...${NC}"
  local restart_output=$(ssh -o StrictHostKeyChecking=no $ssh_user@$server_ip "export PATH=/home/$ssh_user/.local/share/solana/install/active_release/bin:\$PATH && $solana_bin-validator -l $PRIMARY_LEDGER_DIR wait-for-restart-window --min-idle-time 3 --skip-new-snapshot-check")
  echo "$restart_output"

  if [[ $restart_output == *"Ready to restart"* ]]; then
    echo -e "${GREEN}Server $server_ip is ready to restart.${NC}"
  else
    echo -e "${RED}Server $server_ip is not ready to restart. Aborting.${NC}"
    exit 1
  fi
}

# Function to generate SSH key if not present
generate_ssh_key() {
  local ssh_user=$1
  local server_ip=$2
  ssh -o StrictHostKeyChecking=no $ssh_user@$server_ip "test -f ~/.ssh/id_rsa || ssh-keygen -t rsa -b 2048 -N '' -f ~/.ssh/id_rsa"
}

# Function to check and fix SSH connection
fix_ssh_connection() {
  local primary_user=$1
  local primary_ip=$2
  local secondary_user=$3
  local secondary_ip=$4

  ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=5 $primary_user@$primary_ip "ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=5 $secondary_user@$secondary_ip exit"
  if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Unable to establish SSH connection from $primary_ip to $secondary_ip. Attempting to fix...${NC}"

    # Remove old key if it exists
    ssh -o StrictHostKeyChecking=no $primary_user@$primary_ip "ssh-keygen -R $secondary_ip"

    # Get the public key from the primary server
    local public_key=$(ssh -o StrictHostKeyChecking=no $primary_user@$primary_ip "cat ~/.ssh/id_rsa.pub")

    # Add the public key to the secondary server's authorized_keys
    ssh -o StrictHostKeyChecking=no $primary_user@$primary_ip "echo '$public_key' | ssh -o StrictHostKeyChecking=no $secondary_user@$secondary_ip 'mkdir -p ~/.ssh && touch ~/.ssh/authorized_keys && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys && echo \"$public_key\" >> ~/.ssh/authorized_keys'"

    # Verify the connection again
    ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=5 $primary_user@$primary_ip "ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=5 $secondary_user@$secondary_ip exit"
    if [ $? -ne 0 ]; then
      echo -e "${RED}Failed to establish SSH connection from $primary_ip to $secondary_ip after attempting to fix. Aborting.${NC}"
      exit 1
    fi
  fi
}

# Function to check catchup status
check_catchup() {
  local server_ip=$1
  local ssh_user=$2
  local solana_bin=$3
  echo -e "${YELLOW}Checking catchup status on $server_ip...${NC}"
  local catchup_output=$(ssh -o StrictHostKeyChecking=no $ssh_user@$server_ip "export PATH=/home/$ssh_user/.local/share/solana/install/active_release/bin:\$PATH && $solana_bin catchup --our-localhost")
  echo "$catchup_output"

  if [[ $catchup_output == *"has caught up"* ]]; then
    echo -e "${GREEN}Identity on $server_ip has caught up.${NC}"
  else
    echo -e "${RED}Identity on $server_ip has not caught up. Aborting.${NC}"
    exit 1
  fi
}

# Function to check SSH connection
check_ssh_connection() {
  local ssh_user=$1
  local server_ip=$2
  ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=5 $ssh_user@$server_ip "exit"
  if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Unable to establish SSH connection to $server_ip.${NC}"
    exit 1
  fi
}

# Generate SSH keys if not present on both servers
generate_ssh_key $PRIMARY_SSH_USER $PRIMARY_SERVER_IP
generate_ssh_key $SECONDARY_SSH_USER $SECONDARY_SERVER_IP

# Check and fix SSH connection from primary to secondary server
fix_ssh_connection $PRIMARY_SSH_USER $PRIMARY_SERVER_IP $SECONDARY_SSH_USER $SECONDARY_SERVER_IP

# Check SSH connection
check_ssh_connection $PRIMARY_SSH_USER $PRIMARY_SERVER_IP
check_ssh_connection $SECONDARY_SSH_USER $SECONDARY_SERVER_IP

# Check catchup status on both servers
check_catchup $PRIMARY_SERVER_IP $PRIMARY_SSH_USER $PRIMARY_SOLANA_BIN
check_catchup $SECONDARY_SERVER_IP $SECONDARY_SSH_USER $SECONDARY_SOLANA_BIN

# Check restart readiness on the primary server
check_ready_for_restart $PRIMARY_SERVER_IP $PRIMARY_SSH_USER $PRIMARY_SOLANA_BIN

# Commands for the primary server
echo -e "${YELLOW}Transitioning the primary server to the inactive identity...${NC}"
ssh -o StrictHostKeyChecking=no $PRIMARY_SSH_USER@$PRIMARY_SERVER_IP "export PATH=/home/$PRIMARY_SSH_USER/.local/share/solana/install/active_release/bin:\$PATH && $PRIMARY_SOLANA_BIN-validator -l $PRIMARY_LEDGER_DIR set-identity /home/$PRIMARY_SSH_USER/solana/primary-unstaked-identity.json"
check_command "set-identity (primary)"

ssh -o StrictHostKeyChecking=no $PRIMARY_SSH_USER@$PRIMARY_SERVER_IP "scp $PRIMARY_LEDGER_DIR/tower-* $SECONDARY_SSH_USER@$SECONDARY_SERVER_IP:/home/$SECONDARY_SSH_USER/solana/"
check_command "scp tower files from primary to secondary"

ssh -o StrictHostKeyChecking=no $PRIMARY_SSH_USER@$PRIMARY_SERVER_IP "ln -sf /home/$PRIMARY_SSH_USER/solana/primary-unstaked-identity.json /home/$PRIMARY_SSH_USER/solana/primary-identity.json"
check_command "update symlink on primary"

# Commands for the secondary server
echo -e "${YELLOW}Transitioning the secondary server to the active identity...${NC}"
ssh -o StrictHostKeyChecking=no $SECONDARY_SSH_USER@$SECONDARY_SERVER_IP "mv /home/$SECONDARY_SSH_USER/solana/tower-* $SECONDARY_LEDGER_DIR/"
check_command "move tower files to secondary ledger"

ssh -o StrictHostKeyChecking=no $SECONDARY_SSH_USER@$SECONDARY_SERVER_IP "export PATH=/home/$SECONDARY_SSH_USER/.local/share/solana/install/active_release/bin:\$PATH && $SECONDARY_SOLANA_BIN-validator -l $SECONDARY_LEDGER_DIR set-identity --require-tower /home/$SECONDARY_SSH_USER/solana/staked-identity.json"
if [ $? -ne 0 ]; then
  echo -e "${YELLOW}Retrying without --require-tower...${NC}"
  ssh -o StrictHostKeyChecking=no $SECONDARY_SSH_USER@$SECONDARY_SERVER_IP "export PATH=/home/$SECONDARY_SSH_USER/.local/share/solana/install/active_release/bin:\$PATH && $SECONDARY_SOLANA_BIN-validator -l $SECONDARY_LEDGER_DIR set-identity /home/$SECONDARY_SSH_USER/solana/staked-identity.json"
  check_command "set-identity (secondary) without --require-tower"
else
  check_command "set-identity (secondary)"
fi

# Sleep for 10 seconds to allow the secondary server to catch up
echo -e "${YELLOW}Waiting for 10 seconds before checking the validator status...${NC}"
sleep 10

# Check the status of the validators
echo -e "${YELLOW}Checking the validator status...${NC}"
VALIDATOR_ADDRESS=$(ssh -o StrictHostKeyChecking=no $SECONDARY_SSH_USER@$SECONDARY_SERVER_IP "export PATH=/home/$SECONDARY_SSH_USER/.local/share/solana/install/active_release/bin:\$PATH && solana address")
SLOTS_BEHIND=$(ssh -o StrictHostKeyChecking=no $SECONDARY_SSH_USER@$SECONDARY_SERVER_IP "export PATH=/home/$SECONDARY_SSH_USER/.local/share/solana/install/active_release/bin:\$PATH && solana validators | grep $VALIDATOR_ADDRESS | awk '{print \$6 \" \" \$8}'")
echo "Validator lag: $SLOTS_BEHIND"

# Evaluate the lag
IFS=' ' read -r -a array <<< "$SLOTS_BEHIND"
if [[ ${array[0]} -lt -3 || ${array[1]} -lt -3 ]]; then
    echo -e "${RED}Problem: Validator lag is above normal.${NC}"
else
    echo -e "${GREEN}All good, the lag is within acceptable limits.${NC}"
fi

echo -e "${GREEN}Transition completed. Please check the validator status.${NC}"