// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

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

import {ERC20} from "@openzeppelin-contracts/token/ERC20/ERC20.sol";

/**
 * @title Rebase Token
 * @author Dennis Gianassi
 * @notice This is a cross-chain rebase token that incentivises users to deposit into a vault
 * @notice The interest rate in the smart contract can only decrease
 * @notice Each user will have their own interest rate that will be the global interest rate at the moment of deposit
 */
contract RebaseToken is ERC20{
    error RebaseToken__InterestRateCanOnlyDecrease(uint256 currentInterestRate, uint256 newInterestRate);

    mapping(address => uint256) private s_userInterestRates;
    mapping(address => uint256) private s_userLastUpdatedTimestamps;
    uint256 private s_interestRate = 5e10; // Rate per second
    uint256 private constant PRECISION_FACTOR = 1e18;

    event InterestRateUpdated(uint256 newInterestRate);

    constructor() ERC20("Rebase Token", "RBT") {
    }

    /**
     * @notice Sets a new interest rate
     * @dev The interest rate can only decrease
     * @param _newInterestRate The new interest rate
     */
    function setInterestRate(uint256 _newInterestRate) external {
        if(_newInterestRate < s_interestRate) {
            revert RebaseToken__InterestRateCanOnlyDecrease(s_interestRate, _newInterestRate);
        }
        s_interestRate = _newInterestRate;
        emit InterestRateUpdated(_newInterestRate);
    }

    /**/
    * @notice Mints tokens to the user when they deposit into the vault
    * @dev Before minting, we need to mint any accrued interest to the user
    * @param _to The address to mint tokens to
    * @param _amount The amount of tokens to mint    
     */
    function mint(address _to, uint256 _amount) external {
        _mintAccruedInterest(_to);
        s_userInterestRates[_to] = s_interestRate;
        _mint(_to, _amount); // Inherited from OpenZeppelin ERC20
    }

    function _mintAccruedInterest(address _user) internal {
        // (1) find the current balance of rebase tokens that have been minted to the user -> principal balance
        // (2) calculate their current balance with interest accrued -> balanceOf
        // (3) calculate the number of tokens to mint that needs to be minted to the user -> (2) - (1)
        // call _mint to mint the difference to the user
        s_userLastUpdatedTimestamps[_user] = block.timestamp;
    }

    /**
     * @notice Calculates the principal balance + interest accumulated since last update
     * @param _user The address of the user
     * @return uint256 Balance of the user including interest accumulated since last update
     */
    function balanceOf(address _user) public view override returns (uint256) {
        // Get the current principal balnce => tokens that have actually been minted to the user
        // multiply the balance by the interest that has been accumulated since last update
        return (super.balanceOf(_user) * _calculateUserAccumulatedInterestSinceLastUpdate(_user)) / 1e18;
    }

    /**
     * @notice Calculates the accumulated interest since last update for that user
     * @param _user The user to calculate interest for
     * @return uint256 The accumulated interest since last update for that user
     */
    function _calculateUserAccumulatedInterestSinceLastUpdate(address _user) internal view returns (uint256 linearInterest) {
        // this is going to be inear growth with time
        // (principal amount) + (principal amount * interest rate * time elapsed)
        // deposit: 10 tokens
        // interest rate: 0.5 tokens per second
        // time elapsed 2 seconds
        // 10 + (10 * 0.5 * 2) tokens = 20 tokens
        uint256 timeElapsed = block.timestamp - s_userLastUpdatedTimestamps[_user];
        uint256 userInterestRate = s_userInterestRates[_user];
        return linearInterest = PRECISION_FACTOR + (userInterestRate * timeElapsed);

    }

    /**
     * @notice Gets the interest rate for that user
     * @param _user 
     * @return uint256 The interest rate of the user
     */
    function getUserInterestRate(address _user) external view returns (uint256) {
        return s_userInterestRates[_user];
    }

}