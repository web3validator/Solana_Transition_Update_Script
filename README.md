# Solana Validator Identity Transition Script

This script allows you to transition a staked Solana validator from one machine to another with minimal downtime. It automates the process of transferring the validator's identity and vote accounts between two servers.

## Prerequisites

1. **Solana CLI**: Ensure that the Solana CLI is installed on both the primary and secondary servers.
2. **SSH Access**: You must have SSH access to both servers with the necessary permissions to execute commands and transfer files.
3. **Configured Ledger Directories**: The ledger directories must be configured and accessible on both servers.
4. **Running Solana Instances**: Both servers should already be running Solana with the appropriate configurations.

primary server1
```sh
--identity /home/$username/solana/primary-identity.json \
--vote-account /home/$username/solana/vote-account-keypair.json \
--authorized-voter /home/$username/solana/staked-identity.json \
```
secondary server2
```sh
--identity /home/$username/solana/secondary-identity.json \
--vote-account /home/$username/solana/vote-account-keypair.json \
--authorized-voter /home/$username/solana/staked-identity.json \

```

**Note**: The script assumes that all operations are performed from a non-root user as recommended by the official Solana documentation.

## Setup

1. **Clone the repository**:

    ```sh
    curl
    ```

2. **Make the script executable**:

    ```sh
    chmod +x transition_update.sh
    ```

## Usage

1. **Run the transition script**:

    ```sh
    ./transition_update.sh
    ```

2. **Follow the prompts**:
    - Enter the IP address of the primary server.
    - Enter the username for the primary server.
    - Enter the IP address of the secondary server.
    - Enter the username for the secondary server.
    - Enter the full path to the ledger directory on the primary server (e.g., `/mnt/data/solana/ledger`).
    - Enter the full path to the ledger directory on the secondary server (e.g., `/mnt/data/solana/ledger`).

## Script Workflow

1. **Generate SSH Keys**: The script generates SSH keys on both servers if they do not already exist.
2. **Fix SSH Connection**: The script ensures that the primary server can connect to the secondary server via SSH.
3. **Check Catchup Status**: The script verifies that both servers have caught up with the blockchain.
4. **Check Restart Readiness**: The script checks if the primary server is ready for a restart.
5. **Transition Primary Server**: The script transitions the primary server to an unstaked identity.
6. **Transfer Tower Files**: The script transfers the tower files from the primary server to the secondary server.
7. **Transition Secondary Server**: The script transitions the secondary server to the staked identity.
8. **Check Validator Status**: The script checks the validator status and prints the lag.

## Example Output

```sh
$ ./transition_update.sh
Enter the IP address of the primary server: 
Enter the username for the primary server: 
Enter the IP address of the secondary server: 
Enter the username for the secondary server: 
Enter the full path to the ledger directory on the primary server (e.g., /mnt/data/solana/ledger): 
Enter the full path to the ledger directory on the secondary server (e.g., /mnt/data/solana/ledger): 

Checking catchup status on primary server...
Identity on primary server has caught up.
Checking catchup status on secondary server...
Identity on secondary server has caught up.
Checking restart readiness on primary server...
Server primary server is ready to restart.
Transitioning the primary server to the inactive identity...
Transitioning the secondary server to the active identity...
Waiting for 10 seconds before checking the validator status...
Checking the validator status...
Validator lag: -1 -3
All good, the lag is within acceptable limits.
Transition completed. Please check the validator status.
