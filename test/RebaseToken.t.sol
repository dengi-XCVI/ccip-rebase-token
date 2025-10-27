// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";

contract RebaseTokenTest is Test {
    RebaseToken rebaseToken;
    Vault vault;
    address public owner = makeAddr("owner");
    address public user = makeAddr("user");

    function setUp() public {
        vm.startPrank(owner);
        rebaseToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        rebaseToken.grantMintAndBurnRole(address(vault));
        // Adding to vault for rewards
        (bool success, ) = payable(address(vault)).call{value: 1e18}("");
        vm.stopPrank();
    }

    function testDepositLinear(uint256 amount) public {
        vm.startPrank(user);
        amount = bound(amount, 1e5, type(uint96).max);
         vm.deal(user, amount);
        // 1. Deposit
        vault.deposit{value:amount}();
        // 2. Check rebase token balance
        uint256 startingBalance = rebaseToken.balanceOf(user);
        console.log("Starting Balance:", startingBalance);
        assertEq(startingBalance, amount);
        // 3. warp tme and check interest accrued
        vm.warp(block.timestamp + 1 hours);
        uint256 newBalance = rebaseToken.balanceOf(user);
        assertGt(newBalance, startingBalance);
        console.log("New Balance after 1 hour:", newBalance);
        uint256 interestAccrued = newBalance - startingBalance;
        console.log("Interest Accrued after 1 hour:", interestAccrued);
        // 4. warp again and check interst again
        vm.warp(block.timestamp + 1 hours);
        uint256 latestBalance = rebaseToken.balanceOf(user);
        assertGt(latestBalance, newBalance);
        console.log("Latest Balance after 2 hours:", latestBalance);
        uint256 latestInterestAccrued = latestBalance - newBalance;
        console.log("Interest Accrued after 2 hours:", latestInterestAccrued);
        // 5. Check if intrest is linear and balances 
        assertApproxEqAbs(latestInterestAccrued, interestAccrued,1);


    }
}
