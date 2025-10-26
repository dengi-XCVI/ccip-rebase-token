// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {IRebaseToken} from "./interfaces/IRebaseToken.sol";

contract Vault {
    error Vault__RedeemFailed();

    IRebaseToken immutable private i_rebaseToken;

    event Deposit(address indexed user, uint256 amount);
    event Redeem(address indexed user, uint256 amount);

    constructor(IRebaseToken _rebaseToken) {
        i_rebaseToken = _rebaseToken;
    }

    // To receive and later redistribute rewards ??
    receive() external payable {}

    /**
     * @notice Deposit ETH into the vault and mint rebase tokens
     */
    function deposit() external payable {
        i_rebaseToken.mint(msg.sender, msg.value);
        emit Deposit(msg.sender, msg.value);
    }

    /**
     * @notice Redeem rebase tokens for ETH
     * @param _amount The amount of rebase tokens to redeem
     */
    function redeem(uint256 _amount) external {
        i_rebaseToken.burn(msg.sender, _amount);
        (bool success,) = payable(msg.sender).call{value: _amount}("");
        if (!success) {
            revert Vault__RedeemFailed();
        }
        emit Redeem(msg.sender, _amount);
    }

    /**
     * @return The address of the rebase token
     */ 
    function getRebaseTokenAddress() external view returns (address) {
        return address(i_rebaseToken);
    }
}