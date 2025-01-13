// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {IERC20} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {Handler} from "test/fuzz/Handler.t.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {AggregatorV3Interface} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract OpenInvariantTest is StdInvariant, Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address weth;
    address wbtc;
    Handler public handler;

    function setUp() external {
        deployer = new DeployDSC();

        (dsc, dsce, config) = deployer.run();
        (, , weth, wbtc, ) = config.activeNetworkConfig();
        handler = new Handler(dsce, dsc);
        targetContract(address(handler));
    }

    function invariant__protocolMustHaveMoreValueThanTotalSupply() public view {
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dsce));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dsce));

        uint256 wethValue = dsce.getUsdvalue(weth, totalWethDeposited);
        uint256 wbtcValue = dsce.getUsdvalue(wbtc, totalWbtcDeposited);

        console.log("weth value:", wethValue);
        console.log("wbtc value:", wbtcValue);
        console.log("total supply:", totalSupply);
        console.log("Times min called:", handler.timesMintIsCalled());

        assert(wethValue + wethValue >= totalSupply);
    }

    function invariant_gettersShouldNotRevert() public view {
        dsce.getAccountCollateralValue();
        dsce.getAccountInformation();
        dsce.getCollateralBalanceOfUser();
        dsce.getCollateralDeposited();
        dsce.getDSCMinted();
        dsce.getHealthFactor();
        dsce.getPriceFeedAddress();
        dsce.getSupportedCollateralTokens();
        dsce.getTokenAmountFromUsd();
        dsce.getTotalCollateralValueInUsd();
        dsce.getUsdvalue();
    }
}
