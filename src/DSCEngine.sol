// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.20;

import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {AggregatorV3Interface} from "lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title DSCEngine
 * @author Lydia Ahenkorah
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain
 * a 1 token == $1 peg
 * This StableCoin has the Properties:
 * -Exogenous Collateral
 * -Dollar Pegged
 * _algoritmically Stable
 *
 * It is similar to DAI if DAI had no governace,
 * no fee and was backed by WETH and WBTC
 *
 * DSC should always be overcollateralized. At no point, should the value
 * of collateral <= the $ backed value of the DSC.
 *
 * @notice This contract is the Core of the DSC System.It handles all the logic for mining
 * and redeeming DSC, as well as depositing & withdrawing collateral.
 * @notice This contract is very Lossely based on the MakerDAO DSS (DAI) system.
 */

contract DSCEngine is ReentrancyGuard {
    //////////////
    // Errors  //
    /////////////
    error DSCEngine__MustBeMoreThanZero();
    error DSCEngine__TokenAddressAndDataFeedAddressMustbeTheSame();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__HealthFactorIsBelowMinimum();
    error DSCEngine__MintFailed();
    error DSCEngine__BreaksHealthFactor();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();

    /////////////////////
    // State Variables  //
    /////////////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 110; //this means a 10% bonus

    mapping(address user => mapping(address token => uint256 amount))
        private s_collateralDeposited;
    mapping(address user => uint256 amountDscToMint) private s_DSCMinted;
    mapping(address token => address dataFeed) private s_dataFeed; //token datafeed(priceFeed)

    DecentralizedStableCoin private immutable i_dsc;
    address[] private s_collateralToken;

    //////////////
    // Event     //
    /////////////

    event collateralDeposited(
        address indexed user,
        address indexed token,
        uint256 amount
    );

    event CollateralRedeemed(
        address indexed redeemFrom,
        address indexed redeemTo,
        address indexed token,
        uint256 amount
    );

    //////////////
    // Modifiers//
    /////////////

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__MustBeMoreThanZero();
        }
        _;
    }
    modifier isAllowedToken(address token) {
        if (s_dataFeed[token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    //////////////
    // Functions//
    /////////////

    constructor(
        address[] memory tokenAddresses,
        address[] memory dataFeedAddresses,
        address dscAddress
    ) {
        //USD dataFeed
        if (tokenAddresses.length != dataFeedAddresses.length) {
            revert DSCEngine__TokenAddressAndDataFeedAddressMustbeTheSame();
        }
        //eth/usd, btc/eth etc
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_dataFeed[tokenAddresses[i]] = dataFeedAddresses[i];
            s_collateralToken.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    ///////////////////////
    // External Functions//
    //////////////////////

    /**
     *
     * @param tokenCollateralAddress The address of the token to deposite as collateral
     * @param amountCollateral The amount of collateral to deposite
     * @param amountDscToMint The amount of decentralized StableCoin to mint
     * @notice this function will deposit your collateral and mint DSC in one transaction
     */
    function depositCollateralAndMintDSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /**
     *follows CEI (check effect interaction)
     * @param tokenCollateralAddress:  The address of the token to deposit as collateral
     * @param amountCollateral : The amount of collateral to deposit
     */
    function depositCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][
            tokenCollateralAddress
        ] += amountCollateral;
        emit collateralDeposited(
            msg.sender,
            tokenCollateralAddress,
            amountCollateral
        );
        bool success = IERC20(tokenCollateralAddress).transferFrom(
            msg.sender,
            address(this),
            amountCollateral
        );
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     *
     * @param tokenCollateral The Address of the token to redeem
     * @param amountCollateral The amount Of collateral to redeem
     * @param amountDscToBurn amount of DSC you wan to burn
     * this function bruns DSC and redeems Collateral in one Transaction
     */
    function redeemCollateralForDsc(
        address tokenCollateral,
        uint256 amountCollateral,
        uint256 amountDscToBurn
    ) external {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateral, amountCollateral);
        //redeemcoolateral checks
    }

    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) public moreThanZero(amountCollateral) nonReentrant {
        _redeemCollateral(
            tokenCollateralAddress,
            amountCollateral,
            msg.sender,
            msg.sender
        );
    }

    /**
     * @notice follows CEI
     * @param amountDscToMint  the amount of decentralized stableCoin to mint
     * @notice they must have more collateral value than the minimal threshold
     */
    function mintDsc(
        uint256 amountDscToMint
    ) public moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;

        // If they minted too much ($150 DSC, $100 ETH)
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDsc(uint256 amount) public moreThanZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender); // might not need this
    }

    //$75 backing 50 DSC
    //liquidator take 75 backing and burns off the 50 DSC
    // if someone is almost undercollateralized we will pay someone to liquidate them

    /**
     *
     * @param collateral the address of the collateral t liquiadete from the user
     * @param user  the user who has broken the health factor
     * @param debtToCover The amount of DSC to burn from the user to improve health factor
     * @notice you can partially liquidate a user
     * @notice You will get a liquidation bonus for taking the users funds
     * @notice This function assumes the protocol wi;; be roughly 200% overcollateralized in order for this to work
     * @notice A known bug would be if the protocol were 100% or less collateralzed, then we wouldnt be able to incentive the liquidators
     *for example if the price ofthe colllateral plummeted before anyone coulb be liquidated
     follows CEI: Cecks, effect, Interaction
     */
    function liquidate(
        address collateral,
        address user,
        uint256 debtToCover
    ) external moreThanZero(debtToCover) nonReentrant {
        uint256 startingUserHealthfactor = _healthFactor(user);

        if (startingUserHealthfactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }

        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(
            collateral,
            debtToCover
        );

        uint256 bonusCollateral = (tokenAmountFromDebtCovered *
            LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;

        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered +
            bonusCollateral;

        _redeemCollateral(
            collateral,
            totalCollateralToRedeem,
            user,
            msg.sender
        );

        //We Need to burn DSC
        _burnDsc(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor < startingUserHealthfactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /// //////////////////////////////////
    // Private & internal Functions& view//
    //////////////////////////////////////

    /**
     * low-level internal functions,
     * do not call it unless function calling it is checking for health factors broken
     */

    function _burnDsc(
        uint256 amountDscToBurn,
        address onBehalfOf,
        address dscFrom
    ) private {
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(
            dscFrom,
            address(this),
            amountDscToBurn
        );

        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }

    function _redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        address from,
        address to
    ) private {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(
            from,
            to,
            tokenCollateralAddress,
            amountCollateral
        );
        bool success = IERC20(tokenCollateralAddress).transfer(
            to,
            amountCollateral
        );
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _getAccountInformation(
        address user
    )
        private
        view
        returns (uint256 totalDSCMinted, uint256 collateralValueInUsd)
    {
        totalDSCMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    /**
     * How close to liquidation a user is
     *  if user goes below 1, they can get liquidated
     */

    function _healthFactor(address user) private view returns (uint256) {
        (
            uint256 totalDscMinted,
            uint256 collateralValueInUsd
        ) = _getAccountInformation(user);
        if (totalDscMinted == 0) {
            revert DSCEngine__MustBeMoreThanZero();
        }

        uint256 collateralAdjustedForThreshold = (collateralValueInUsd *
            LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
        // return (collateralValueInUsd / totalDscMintd ); //(100/ $50) overcollateral
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        //cheacks health factor (do they have enough collateral)
        //revert if they dont
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorIsBelowMinimum();
        }
    }

    /// //////////////////////////////////
    // public & external view Functions//
    //////////////////////////////////////

    /////////////////
    // Getter Functions //
    /////////////////

    /**
     * @notice Get the amount of collateral deposited by a specific user for a specific token
     * @param user The address of the user
     * @param token The address of the collateral token
     * @return The amount of collateral deposited by the user for the specified token
     */
    function getCollateralDeposited(
        address user,
        address token
    ) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    /**
     * @notice Get the total amount of DSC minted by a specific user
     * @param user The address of the user
     * @return The amount of DSC minted by the user
     */
    function getDSCMinted(address user) external view returns (uint256) {
        return s_DSCMinted[user];
    }

    /**
     * @notice Get the total collateral value in USD for a specific user
     * @param user The address of the user
     * @return The total collateral value in USD for the specified user
     */
    function getTotalCollateralValueInUsd(
        address user
    ) external view returns (uint256) {
        return getAccountCollateralValue(user);
    }

    /**
     * @notice Get the health factor for a specific user
     * @param user The address of the user
     * @return The health factor of the specified user
     */
    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    /**
     * @notice Get the price feed address for a specific collateral token
     * @param token The address of the collateral token
     * @return The address of the price feed associated with the specified token
     */
    function getPriceFeedAddress(
        address token
    ) external view returns (address) {
        return s_dataFeed[token];
    }

    /**
     * @notice Get the list of supported collateral tokens
     * @return The array of supported collateral token addresses
     */
    function getSupportedCollateralTokens()
        external
        view
        returns (address[] memory)
    {
        return s_collateralToken;
    }

    function getTokenAmountFromUsd(
        address token,
        uint256 usdAmountInWei
    ) public view returns (uint256) {
        AggregatorV3Interface dataFeed = AggregatorV3Interface(
            s_dataFeed[token]
        );
        (, int256 price, , , ) = dataFeed.latestRoundData();
        require(price > 0, "Invalid price");
        return
            (usdAmountInWei * PRECISION) /
            (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getAccountCollateralValue(
        address user
    ) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralToken.length; i++) {
            address token = s_collateralToken[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdvalue(token, amount);
        }

        return totalCollateralValueInUsd;
    }

    function getUsdvalue(
        address token,
        uint256 amount
    ) public view returns (uint256) {
        AggregatorV3Interface dataFeed = AggregatorV3Interface(
            s_dataFeed[token]
        );
        (, int256 price, , , ) = dataFeed.latestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION * amount) /
            PRECISION);
    }

    function getAccountInformation(
        address user
    )
        external
        view
        returns (uint256 totalDSCMinted, uint256 collateralValueInUsd)
    {
        (totalDSCMinted, collateralValueInUsd) = _getAccountInformation(user);
    }

    function getCollateralBalanceOfUser(
        address user,
        address token
    ) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getCollateralTokenPriceFeed(
        address token
    ) external view returns (address) {
        return s_dataFeeds[token];
    }
}
