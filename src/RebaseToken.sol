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
import {Ownable} from "@openzeppelin-contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin-contracts/access/AccessControl.sol";

/**
 * @title Rebase Token
 * @author Dennis Gianassi
 * @notice This is a cross-chain rebase token that incentivises users to deposit into a vault
 * @notice The interest rate in the smart contract can only decrease
 * @notice Each user will have their own interest rate that will be the global interest rate at the moment of deposit
 */
contract RebaseToken is ERC20, Ownable, AccessControl {
    error RebaseToken__InterestRateCanOnlyDecrease(uint256 currentInterestRate, uint256 newInterestRate);

    mapping(address => uint256) private s_userInterestRates;
    mapping(address => uint256) private s_userLastUpdatedTimestamps;
    uint256 private s_interestRate = 5e10; // Rate per second
    uint256 private constant PRECISION_FACTOR = 1e18;
    bytes32 private constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");

    event InterestRateUpdated(uint256 newInterestRate);

    constructor() ERC20("Rebase Token", "RBT") Ownable(msg.sender) {
    }

    function grantMintAndBurnRole(address _account) external onlyOwner {
        _grantRole(MINT_AND_BURN_ROLE, _account);
    }

    /**
     * @notice Sets a new interest rate
     * @dev The interest rate can only decrease
     * @param _newInterestRate The new interest rate
     */
    function setInterestRate(uint256 _newInterestRate) external onlyOwner {
        if(_newInterestRate < s_interestRate) {
            revert RebaseToken__InterestRateCanOnlyDecrease(s_interestRate, _newInterestRate);
        }
        s_interestRate = _newInterestRate;
        emit InterestRateUpdated(_newInterestRate);
    }

    /**
     * @notice Gets the principal balance of the user (the amount of tokens that have currently been minted to the user, not including interest included since last user interaction with the protocol)
     * @param _user The address of the user
     * @return uint256 Principal balance of the user
     */
    function principalBalanceOf(address _user) external view returns (uint256) {
        return super.balanceOf(_user);
    }

    /**
    * @notice Mints tokens to the user when they deposit into the vault
    * @dev Before minting, we need to mint any accrued interest to the user
    * @param _to The address to mint tokens to
    * @param _amount The amount of tokens to mint    
     */
    function mint(address _to, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_to);
        s_userInterestRates[_to] = s_interestRate;
        _mint(_to, _amount); // Inherited from OpenZeppelin ERC20
    }

    /**
     * @notice Burns tokens from the user when they withdraw from the vault
     * @dev Before burning, we need to mint any accrued interest to the user
     * @param _from The address to burn tokens from
     * @param _amount The amount of tokens to burn    
     */
    function burn(address _from, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        // Dealing with dust
        if(_amount == type(uint256).max) {
            _amount = balanceOf(_from);
        }
        _mintAccruedInterest(_from);
        _burn(_from, _amount); // Inherited from OpenZeppelin ERC20
    }

    /**
     * @notice Mints the accrued interest to the user since the latest interaction with the protocol (e.g. burn, mint, transfer)
     * @param _user The address of the user
     */
    function _mintAccruedInterest(address _user) internal {
        // (1) find the current balance of rebase tokens that have been minted to the user -> principal balance
        uint256 previousPrincipalBalance = super.balanceOf(_user);
        // (2) calculate their current balance with interest accrued -> balanceOf
        uint256 currentBalance = balanceOf(_user);
        // (3) calculate the number of tokens to mint that needs to be minted to the user -> (2) - (1)
        uint256 balanceIncrease = currentBalance - previousPrincipalBalance;
        // call _mint to mint the difference to the user
        s_userLastUpdatedTimestamps[_user] = block.timestamp;
        _mint(_user, balanceIncrease);
    }

    /**
     * @notice Calculates the principal balance + interest accumulated since last update
     * @param _user The address of the user
     * @return uint256 Balance of the user including interest accumulated since last update
     */
    function balanceOf(address _user) public view override returns (uint256) {
        // Get the current principal balance => tokens that have actually been minted to the user
        // multiply the balance by the interest that has been accumulated since last update
        return (super.balanceOf(_user) * _calculateUserAccumulatedInterestSinceLastUpdate(_user)) / 1e18;
    }

    /**
     * @notice Transfers tokens from one user to another
     * @dev Before transferring, we need to mint any accrued interest to both users
     * @param _recipient The address of the recipient
     * @param _amount The amount of tokens to transfer
     * @return bool True if the transfer was successful
     */
    function transfer(address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(msg.sender);
        _mintAccruedInterest(_recipient);
        if(_amount == type(uint256).max) {
            _amount = balanceOf(msg.sender);
        }
        if(balanceOf(_recipient) == 0) {
            s_userInterestRates[_recipient] = s_interestRate;
        }
        return super.transfer(_recipient, _amount);
    }

    /**
     * @notice Transfers tokens from one user to another on behalf of the sender
     * @dev Before transferring, we need to mint any accrued interest to both users
     * @param _sender The address of the sender
     * @param _recipient The address of the recipient
     * @param _amount The amount of tokens to transfer
     * @return bool True if the transfer was successful
     */
    function transferFrom(address _sender, address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(_sender);
        _mintAccruedInterest(_recipient);
        if(_amount == type(uint256).max) {
            _amount = balanceOf(_sender);
        }
        if(balanceOf(_recipient) == 0) {
            s_userInterestRates[_recipient] = s_interestRate;
        }
        return super.transferFrom(_sender, _recipient, _amount);
    }

    /**
     * @notice Calculates the accumulated interest since last update for that user
     * @param _user The user to calculate interest for
     * @return linearInterest The accumulated interest since last update for that user
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
     * @param _user The user to get the interest rate for
     * @return uint256 The interest rate of the user
     */
    function getUserInterestRate(address _user) external view returns (uint256) {
        return s_userInterestRates[_user];
    }

    /**
     * @notice Gets the global interest rate currently set for contract, future depositors will have this interest rate
     * @return uint256 The global interest rate
     */
    function getInterestRate() external view returns (uint256) {
        return s_interestRate;
    }

}