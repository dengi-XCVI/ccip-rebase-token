// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {RebaseTokenPool} from "../src/RebaseTokenPool.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";
import {Test, console} from "forge-std/Test.sol";
import {CCIPLocalSimulatorFork} from "@chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";

contract CrossChainTest is Test {
    RebaseToken rebaseToken;
    RebaseTokenPool rebaseTokenPool;
    Vault vault;
    address public owner = makeAddr("owner");
    address public user = makeAddr("user");

    uint256 ethSepoliaFork;
    uint256 arbSepoliaFork;

    function setUp() public {
        ethSepoliaFork = vm.createSelectFork("eth-sepolia");
        arbSepoliaFork = vm.createFork("arb-sepolia");
    }
}