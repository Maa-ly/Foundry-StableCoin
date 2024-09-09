# DSCEngine - Decentralized Algorithmic Stablecoin

**Author**: Lydia Ahenkorah  
**Project Status**: Development In Progress  

## Overview

The DSCEngine contract is designed to create a decentralized, algorithmically stable cryptocurrency that maintains a 1:1 peg with the US dollar. 
The system uses exogenous collateral to ensure the stability of the token, while minimizing complexity and avoiding governance or fees. 
It draws inspiration from the MakerDAO DSS (DAI) system but differs in key areas such as governance and collateral types.

## Features

- **Exogenous Collateral**: The stablecoin is backed by external assets such as WETH and WBTC.
- **Dollar Pegged**: 1 token is designed to always equal $1.
- **Algorithmically Stable**: The system uses algorithms to ensure stability without relying on governance.
- **Overcollateralized**: At no point should the value of the collateral be less than or equal to the dollar value of the stablecoin (DSC).
- This ensures that the stablecoin remains fully backed.

## Similarities and Differences to DAI

This system is similar to DAI in that it uses overcollateralization and aims to maintain a stable $1 peg. However, unlike DAI, the DSCEngine:

- Has no governance.
- Has no fees.
- Is exclusively backed by WETH and WBTC.

## Functionality

- **Mining and Redeeming DSC**: The DSCEngine contract handles the issuance (minting) and redemption (burning) of DSC tokens.
- **Collateral Management**: Users can deposit and withdraw collateral, with strict rules ensuring that the system remains overcollateralized at all times.

## Current Status

This project is still under active development, and additional testing and library integrations are required before it can be deployed for public use. 
While the core structure of the contract is in place, several critical components, including stability mechanisms and collateral handling, are still being refined.

