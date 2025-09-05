# WheelX Contracts

Core Solidity contracts for the WheelX cross-chain swap, providing secure token approval and multicall functionality.

## Overview

This repository contains three main contracts:

1. **ApprovalProxy.sol** - A proxy contract that handles token approvals and facilitates multicall operations
2. **Multicall3Router.sol** - A router contract that integrates with Multicall3 for batch operations and Permit2 for gas-efficient approvals
3. **WheelxReceiver.sol** - A receiver contract for handling deposits and forwarding calls

## Installation

```bash
# Install dependencies
yarn install

# Build contracts
forge build

# Run tests
forge test
```

## Deployments

The contracts are deployed to multiple blockchain networks with deterministic addresses.

### Addresses

* `ApprovalProxy`:  `0x7eC9672678509a574F6305F112a7E3703845a98b`.
* `Multicall3Router`:  `0x6222f99443A0d75bd96d40F2904606f60f37cdc2`.
* `WheelxReceiver`:  `0xB10F9Ec04A66b69E3831e1e5b1E6B9D41081B6CC`.

Supported chains include:

### Mainnets

- **Ethereum Mainnet** - `mainnet`
- **Optimism** - `optimism`  
- **Arbitrum** - `arbitrum`
- **Base** - `base`
- **Unichain** - `unichain`
- **BNB Smart Chain** - `bnb_smart_chain`
- **opBNB**
- **Polygon** - `polygon`
- **Linea**
- **ZKSync**
- **Mode**
- **Lisk**
- **Celo**
- **Zora**
- **Katana**
- **Bob**
- **Taiko**
- **Scroll**
- **HEMI**
- **XLayer**
- **HyperEVM**
- **Abstract**

## Security

### Audits
- **ABDK Audit** - Comprehensive security review completed
- Audit reports available in `/audits/` directory

## License

MIT License - See LICENSE file for details.