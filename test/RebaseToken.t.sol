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
        RebaseToken rbt = new RebaseToken();
        Vault vlt = new Vault(IRebaseToken(address(rbt)));
        rbt.grantMintAndBurnRole(address(vlt));
        (bool success, ) = payable(address(vlt)).call{value: 1e18}("");
        vm.stopPrank();
    }
}
