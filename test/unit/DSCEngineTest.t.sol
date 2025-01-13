// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {AggregatorV3Interface} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    address wbtc;

    address public USER = makeAddr("user");
    address public LIQUIDATOR = makeAddr("liquidator");

    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    uint256 public constant ETH_AMOUNT = 15 ether;
    uint256 public constant EXPECTED_USD_VALUE = 30000 ether;
    uint256 public constant USD_AMOUNT = 100 ether;
    uint256 public constant EXPECTED_WETH_AMOUNT = 0.05 ether;
    uint256 public constant MIN_HEALTH_FACTOR = 1;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, ) = config
            .activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
        ERC20Mock(weth).mint(LIQUIDATOR, STARTING_ERC20_BALANCE);
    }

    ///////////////
    //Price Test//
    /////////////
    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testGetUsdvalue() public view {
        uint256 ethAmount = 15e18;
        //15e18 *2000 = 30000e18

        uint256 expectedUsd = 30000e18;

        uint256 actualUsd = dsce.getUsdvalue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;

        //2000Eth ,100
        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = dsce.getTokenAmountFromUsd(weth, usdAmount);
        assertEq(expectedWeth, actualWeth);
    }

    ///////////////////////////
    //depositeCollateral Test//
    //////////////////////////

    function testRevertIfCollateralIsZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        dsce.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock(
            "RAN",
            "RAN",
            USER,
            AMOUNT_COLLATERAL
        );

        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dsce.depositCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testCanDepositeCollateralAndGetAccountInfo() public depositedCollateral{
        (uint256 totalDSCMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);

        uint256 expectedTotalDscMinted = 0;
        uint256 expectedCollateralValueInUsd = dsce.getTokenAmountFromUsd(weth,collateralValueInUsd );
        assertEq(totalDSCMinted, expectedTotalDscMinted);
        assertEq(collateralValueInUsd, expectedCollateralValueInUsd);

    }


    ///////////////////////////
    //CONSTRUCTOR  Test////////
    //////////////////////////
    address[] public tokenAddresses;
    address[] public dataFeedAddresses;

    function testREvertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        dataFeedAddresses.push(ethUsdPriceFeed);
        dataFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(
            DSCEngine
                .DSCEngine__TokenAddressAndDataFeedAddressMustbeTheSame
                .selector
        );

        new DSCEngine(tokenAddresses, dataFeedAddresses, address(dsc));
    }
    

    ///////////////
    //Minting DSC Tests//
    /////////////
    function testRevertsIfMintAmountIsZero() public depositedCollateral {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        dsce.mintDsc(0);
        vm.stopPrank();
    }

    function testRevertIfHealthFactorIsBroken() public depositedCollateral {
        vm.startPrank(USER);
        uint256 overMintAmount = 30_000 ether; // Exceeding collateral value
        vm.expectRevert(
            DSCEngine.DSCEngine__HealthFactorIsBelowMinimum.selector
        );
        dsce.mintDsc(overMintAmount);
        vm.stopPrank();
    }

    function testSuccessfulMint() public depositedCollateral {
        vm.startPrank(USER);
        uint256 mintAmount = USD_AMOUNT;
        dsce.mintDsc(mintAmount);

        uint256 dscMinted = dsce.getDSCMinted(USER);
        assertEq(dscMinted, mintAmount);
        vm.stopPrank();
    }

    ///////////////
    //Redeeming Collateral Tests//
    /////////////
    function testRevertsIfRedeemAmountIsZero() public depositedCollateral {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);
        dsce.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertIfRedeemExceedsDeposited() public depositedCollateral {
        vm.startPrank(USER);
        uint256 excessRedeemAmount = AMOUNT_COLLATERAL + 1;
        vm.expectRevert();
        dsce.redeemCollateral(weth, excessRedeemAmount);
        vm.stopPrank();
    }

    function testSuccessfulCollateralRedemption() public depositedCollateral {
        vm.startPrank(USER);
        uint256 redeemAmount = 5 ether;
        dsce.redeemCollateral(weth, redeemAmount);

        uint256 remainingCollateral = dsce.getCollateralDeposited(USER, weth);
        assertEq(remainingCollateral, AMOUNT_COLLATERAL - redeemAmount);
        vm.stopPrank();
    }

    ///////////////
    //Liquidation Tests//
    /////////////
    function testRevertIfHealthFactorIsOkForLiquidation()
        public
        depositedCollateral
    {
        vm.startPrank(LIQUIDATOR);
        vm.expectRevert(DSCEngine.DSCEngine__MustBeMoreThanZero.selector);

        dsce.liquidate(weth, USER, USD_AMOUNT);
        vm.stopPrank();
    }

    ///////////////
    //Health Factor Tests//
    /////////////
    function testHealthFactorAfterMint() public depositedCollateral {
        vm.startPrank(USER);
        uint256 mintAmount = USD_AMOUNT;
        dsce.mintDsc(mintAmount);
        vm.stopPrank();

        uint256 healthFactor = dsce.getHealthFactor(USER);
        assert(healthFactor > MIN_HEALTH_FACTOR);
    }

    function testHealthFactorBelowMinimum() public depositedCollateral {
        vm.startPrank(USER);

        // Expect the minting to revert because it would cause the health factor to drop below the minimum
        vm.expectRevert(
            DSCEngine.DSCEngine__HealthFactorIsBelowMinimum.selector
        );

        // Attempt to over-mint DSC, expecting it to fail
        uint256 overMintAmount = 30_000 ether;
        dsce.mintDsc(overMintAmount);
        vm.stopPrank();
    }
}
