// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {RebaseTokenPool} from "../src/RebaseTokenPool.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";
import {Test, console} from "forge-std/Test.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";
import {RegistryModuleOwnerCustom} from
    "lib/ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "lib/ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";
import {IERC20} from "lib/ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {TokenPool} from "@ccip/src/v0.8/ccip/pools/TokenPool.sol";
import {RateLimiter} from "@ccip/src/v0.8/ccip/libraries/RateLimiter.sol";
import {Client} from "lib/ccip/contracts/src/v0.8/ccip/libraries/Client.sol";
import {IRouterClient} from "lib/ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";

contract CrossChainTest is Test {
    RebaseToken sepoliaToken;
    RebaseToken arbSepoliaToken;
    RebaseTokenPool sepoliaPool;
    RebaseTokenPool arbSepoliaPool;
    Vault vault;
    address public owner = makeAddr("owner");
    address public user = makeAddr("user");
    uint256 public SEND_VALUE = 1e5;

    uint256 ethSepoliaFork;
    uint256 arbSepoliaFork;

    Register.NetworkDetails sepoliaNetworkDetails;
    Register.NetworkDetails arbSepoliaNetworkDetails;

    CCIPLocalSimulatorFork ccipLocalSimulatorFork;

    function setUp() public {
        ethSepoliaFork = vm.createSelectFork("eth-sepolia");
        arbSepoliaFork = vm.createFork("arb-sepolia");

        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork));

        // Deploy and configure Sepolia token
        sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        vm.startPrank(owner);
        sepoliaToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(sepoliaToken)));
        sepoliaPool = new RebaseTokenPool(
            IERC20(address(sepoliaToken)),
            new address[](0),
            sepoliaNetworkDetails.rmnProxyAddress,
            sepoliaNetworkDetails.routerAddress
        );
        sepoliaToken.grantMintAndBurnRole(address(vault));
        sepoliaToken.grantMintAndBurnRole(address(sepoliaPool));
        RegistryModuleOwnerCustom(sepoliaNetworkDetails.registryModuleOwnerCustomAddress).registerAdminViaOwner(
            address(sepoliaToken)
        );
        TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(sepoliaToken));
        TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress).setPool(
            address(sepoliaToken), address(sepoliaPool)
        );
        vm.stopPrank();

        // Deploy and configure Arbitrum Sepolia token
        vm.selectFork(arbSepoliaFork);
        arbSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        vm.startPrank(owner);
        arbSepoliaToken = new RebaseToken();
        arbSepoliaPool = new RebaseTokenPool(
            IERC20(address(arbSepoliaToken)),
            new address[](0),
            arbSepoliaNetworkDetails.rmnProxyAddress,
            arbSepoliaNetworkDetails.routerAddress
        );
        arbSepoliaToken.grantMintAndBurnRole(address(arbSepoliaPool));
        RegistryModuleOwnerCustom(arbSepoliaNetworkDetails.registryModuleOwnerCustomAddress).registerAdminViaOwner(
            address(arbSepoliaToken)
        );
        TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(arbSepoliaToken));
        TokenAdminRegistry(arbSepoliaNetworkDetails.tokenAdminRegistryAddress).setPool(
            address(arbSepoliaToken), address(arbSepoliaPool)
        );
        vm.stopPrank();

        configurePool(
            ethSepoliaFork,
            address(sepoliaPool),
            arbSepoliaNetworkDetails.chainSelector,
            address(arbSepoliaPool),
            address(arbSepoliaToken)
        );

        configurePool(
            arbSepoliaFork,
            address(arbSepoliaPool),
            sepoliaNetworkDetails.chainSelector,
            address(sepoliaPool),
            address(sepoliaToken)
        );
    }

    function configurePool(
        uint256 fork,
        address localPool,
        uint64 remoteChainSelector,
        address remotePool,
        address remoteTokenAddress
    ) public {
        vm.selectFork(fork);
        vm.prank(owner);
        bytes[] memory remotePoolAddresses = new bytes[](1);
        remotePoolAddresses[0] = abi.encode(remotePool);

        TokenPool.ChainUpdate[] memory chainsToAdd = new TokenPool.ChainUpdate[](1);
        chainsToAdd[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteChainSelector, // Remote chain selector
            remotePoolAddresses: remotePoolAddresses, // Address of the remote pool, ABI encoded in the case of a remote EVM chain.
            remoteTokenAddress: abi.encode(remoteTokenAddress), // Address of the remote token, ABI encoded in the case of a remote EVM chain.
            outboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0}), // Outbound rate limited config, meaning the rate limits for all of the onRamps for the given chain
            inboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0}) // Inbound rate limited config, meaning the rate limits for all of the offRamps for the given chain
        });

        TokenPool(localPool).applyChainUpdates(new uint64[](0), chainsToAdd);
    }

    function bridgeTokens(
    uint256 amountToBridge,
    uint256 localFork,
    uint256 remoteFork,
    Register.NetworkDetails memory localNetworkDetails,
    Register.NetworkDetails memory remoteNetworkDetails,
    RebaseToken localToken,
    RebaseToken remoteToken
) public {
    vm.selectFork(localFork);

    // Build token array
    Client.EVMTokenAmount [] memory tokenAmounts = new Client.EVMTokenAmount[](1);
    tokenAmounts[0] = Client.EVMTokenAmount({
        token: address(localToken),
        amount: amountToBridge
    });

    // Build CCIP message
    Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
        receiver: abi.encode(user),
        data: "",
        tokenAmounts: tokenAmounts,
        feeToken: localNetworkDetails.linkAddress,
        extraArgs: Client._argsToBytes(
            Client.EVMExtraArgsV2({
                gasLimit: 1_000_000, // key fix for local sim
                allowOutOfOrderExecution: false
            })
        )
    });

    // Determine and fund LINK fee
    uint256 fee = IRouterClient(localNetworkDetails.routerAddress)
        .getFee(remoteNetworkDetails.chainSelector, message);

    ccipLocalSimulatorFork.requestLinkFromFaucet(user, fee);

    // Approve LINK fee
    vm.prank(user);
    IERC20(localNetworkDetails.linkAddress).approve(
        localNetworkDetails.routerAddress,
        fee
    );

    // Approve sending token
    vm.prank(user);
    IERC20(address(localToken)).approve(
        localNetworkDetails.routerAddress,
        amountToBridge
    );

    // Track source balance before send
    uint256 balanceBefore = IERC20(address(localToken)).balanceOf(user);

    // Bridge
    vm.prank(user);
    IRouterClient(localNetworkDetails.routerAddress).ccipSend(
        remoteNetworkDetails.chainSelector,
        message
    );

    // Assert token left user wallet
    uint256 balanceAfter = IERC20(address(localToken)).balanceOf(user);
    assertEq(balanceBefore - balanceAfter, amountToBridge);

    // Store interest rate to compare later
    uint256 localRate = localToken.getUserInterestRate(user);

    // Switch to destination
    vm.selectFork(remoteFork);
    vm.warp(block.timestamp + 15 minutes);

    uint256 remoteBefore = IERC20(address(remoteToken)).balanceOf(user);

    // Execute CCIP delivery
    vm.selectFork(localFork);
    ccipLocalSimulatorFork.switchChainAndRouteMessage(remoteFork);

    // Validate mint happened
    uint256 remoteAfter = IERC20(address(remoteToken)).balanceOf(user);
    assertEq(remoteAfter, remoteBefore + amountToBridge);

    // Validate interest continuity
    uint256 remoteRate = remoteToken.getUserInterestRate(user);
    assertEq(remoteRate, localRate);
}


    function testBridgeAllTokens() public {
        vm.selectFork(ethSepoliaFork);
        vm.deal(user, SEND_VALUE);
        vm.prank(user);
        Vault(payable(address(vault))).deposit{value: SEND_VALUE}();
        assertEq(sepoliaToken.balanceOf(user), SEND_VALUE);

        bridgeTokens(
            SEND_VALUE,
            ethSepoliaFork,
            arbSepoliaFork,
            sepoliaNetworkDetails,
            arbSepoliaNetworkDetails,
            sepoliaToken,
            arbSepoliaToken
        );
    }
}
