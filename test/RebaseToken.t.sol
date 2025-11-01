// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";
import {Ownable} from "@openzeppelin-contracts/access/Ownable.sol";
import {IAccessControl} from "@openzeppelin-contracts/access/IAccessControl.sol";
import {AccessControl} from "@openzeppelin-contracts/access/AccessControl.sol";

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
        (bool success,) = payable(address(vault)).call{value: 1e18}("");
        vm.stopPrank();
    }

    function addRewardAmount(uint256 rewardAmount) public {
        bool success;
        (success,) = payable(address(vault)).call{value: rewardAmount}("");
        require(success, "Failed to add reward amount");
    }

    function testDepositLinear(uint256 amount) public {
        vm.startPrank(user);
        amount = bound(amount, 1e5, type(uint96).max);
        vm.deal(user, amount);
        // 1. Deposit
        vault.deposit{value: amount}();
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
        assertApproxEqAbs(latestInterestAccrued, interestAccrued, 1);
    }

    function testRedeemStraightAway(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);
        vm.startPrank(user);
        vm.deal(user, amount);
        // 1. Deposit
        vault.deposit{value: amount}();
        assertEq(rebaseToken.balanceOf(user), amount);
        vault.redeem(amount);
        assertEq(rebaseToken.balanceOf(user), 0);
        assertEq(user.balance, amount);
        vm.stopPrank();
    }

    function testRedeemAfterSomeTime(uint256 amount, uint256 time) public {
        time = bound(time, 1000, type(uint32).max);
        amount = bound(amount, 1e5, type(uint32).max);

        vm.deal(user, amount);
        vm.prank(user);
        // 1. Deposit
        vault.deposit{value: amount}();
        assertEq(rebaseToken.balanceOf(user), amount);
        // 2. Warp time
        vm.warp(block.timestamp + time);
        uint256 newBalance = rebaseToken.balanceOf(user);
        assertGt(newBalance, amount);
        console.log("Balance after 2 hours:", newBalance);
        // 3. Redeem
        vm.deal(owner, newBalance - amount);
        vm.prank(owner);
        addRewardAmount(newBalance - amount);
        vm.prank(user);
        vault.redeem(type(uint256).max);
        assertEq(rebaseToken.balanceOf(user), 0);
        console.log("ETH Balance after redeem:", user.balance);
        assertEq(user.balance, newBalance);
    }

    function testTransfer(uint256 amount, uint256 amountToSend) public {
        amount = bound(amount, 1e5 + 1e5, type(uint32).max);
        amountToSend = bound(amountToSend, 1e5, amount - 1e5);

        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();

        address recipient = makeAddr("recipient");
        uint256 userStartingBalance = rebaseToken.balanceOf(user);
        uint256 recipientStartingBalance = rebaseToken.balanceOf(recipient);

        assertEq(userStartingBalance, amount);
        assertEq(recipientStartingBalance, 0);

        vm.prank(owner);
        rebaseToken.setInterestRate(4e10);

        vm.prank(user);
        rebaseToken.transfer(recipient, amountToSend);
        uint256 userBalanceAfterTransfer = rebaseToken.balanceOf(user);
        uint256 recipientBalanceAfterTransfer = rebaseToken.balanceOf(recipient);
        assertEq(userBalanceAfterTransfer, userStartingBalance - amountToSend);
        assertEq(recipientBalanceAfterTransfer, recipientStartingBalance + amountToSend);

        // Check interest rates
        uint256 userInterestRate = rebaseToken.getUserInterestRate(user);
        uint256 recipientInterestRate = rebaseToken.getUserInterestRate(recipient);
        assertEq(userInterestRate, 5e10);
        assertEq(recipientInterestRate, 4e10);
    }

    function testCanNotSetInterestRateIfNotOwner(uint256 newInterestRate) public {
        vm.prank(user);
        vm.expectPartialRevert(Ownable.OwnableUnauthorizedAccount.selector);
        rebaseToken.setInterestRate(newInterestRate);
    }

    function testInterestRateCanOnlyDecrease(uint256 newInterestRate) public {
        uint256 initialInterestRate = rebaseToken.getInterestRate();
        newInterestRate = bound(newInterestRate, initialInterestRate, type(uint256).max);
        vm.prank(owner);
        vm.expectPartialRevert(RebaseToken.RebaseToken__InterestRateCanOnlyDecrease.selector);
        rebaseToken.setInterestRate(newInterestRate); // Current is 5e10
    }

    function testCanNotMintAndBurnIfNotOwner(uint256 amount) public {
        vm.prank(user);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        rebaseToken.mint(user, amount,rebaseToken.getInterestRate());

        vm.prank(user);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        rebaseToken.burn(user, amount);
    }

    function testGetPrincipalBalance(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);
        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();

        vm.warp(block.timestamp + 1 days);
        uint256 principalBalance = rebaseToken.principalBalanceOf(user);
        assertEq(principalBalance, amount);
    }

    function testGetRebaseTokenAddress() public {
        address rebaseTokenAddress = vault.getRebaseTokenAddress();
        assertEq(rebaseTokenAddress, address(rebaseToken));
    }
}
