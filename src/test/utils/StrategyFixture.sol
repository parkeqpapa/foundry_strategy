// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.12;
pragma abicoder v2;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ExtendedTest } from "./ExtendedTest.sol";
import { Vm } from "forge-std/Vm.sol";
import { IVault } from "../../interfaces/Vault.sol";

// NOTE: if the name of the strat or file changes this needs to be updated
import { Strategy } from "../../Strategy.sol";

// Artifact paths for deploying from the deps folder, assumes that the command is run from
// the project root.
string constant vaultArtifact = "artifacts/Vault.json";

// Base fixture deploying Vault
contract StrategyFixture is ExtendedTest {
    using SafeERC20 for IERC20;

    IVault public vault;
    Strategy public strategy;
    IERC20 public weth;
    IERC20 public want;

    mapping(string => address) public tokenAddrs;
    mapping(string => uint256) public tokenPrices;

    address public gov = 0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52;
    address public user = address(1);
    address public whale = address(2);
    address public rewards = address(3);
    address public guardian = address(4);
    address public management = address(5);
    address public strategist = address(6);
    address public keeper = address(7);

    uint256 public minFuzzAmt;
    // @dev maximum amount of want tokens deposited based on @maxDollarNotional
    uint256 public maxFuzzAmt;
    // @dev maximum dollar amount of tokens to be deposited
    uint256 public maxDollarNotional = 250_000;
    // @dev maximum dollar amount of tokens for single large amount
    uint256 public bigDollarNotional = 100_000;
    // @dev used for non-fuzz tests to test large amounts
    uint256 public bigAmount;
    // Used for integer approximation
    uint256 public constant DELTA = 10 ** 1;

    function setUp() public virtual {
        _setTokenPrices();
        _setTokenAddrs();

        // Choose a token from the tokenAddrs mapping, see _setTokenAddrs for options
        string memory token = "USDC";
        weth = IERC20(tokenAddrs["WETH"]);
        want = IERC20(tokenAddrs[token]);

        (address _vault, address _strategy) = deployVaultAndStrategy(
            address(want),
            gov,
            rewards,
            "",
            "",
            guardian,
            management,
            keeper,
            strategist
        );
        vault = IVault(_vault);
        strategy = Strategy(_strategy);

        minFuzzAmt = 10 ** vault.decimals() * 10000; // USDC 6 decimals
        maxFuzzAmt =
            uint256(maxDollarNotional / tokenPrices[token]) *
            10 ** vault.decimals();
        bigAmount =
            uint256(bigDollarNotional / tokenPrices[token]) *
            10 ** vault.decimals();

        // add more labels to make your traces readable
        vm.label(address(vault), "Vault");
        vm.label(address(strategy), "Strategy");
        vm.label(address(want), "Want");
        vm.label(gov, "Gov");
        vm.label(user, "User");
        vm.label(whale, "Whale");
        vm.label(rewards, "Rewards");
        vm.label(guardian, "Guardian");
        vm.label(management, "Management");
        vm.label(strategist, "Strategist");
        vm.label(keeper, "Keeper");

        // do here additional setup
    }

    // Deploys a vault
    function deployVault(
        address _token,
        address _gov,
        address _rewards,
        string memory _name,
        string memory _symbol,
        address _guardian,
        address _management
    ) public returns (address) {
        vm.prank(_gov);
        address _vaultAddress = deployCode(vaultArtifact);
        IVault _vault = IVault(_vaultAddress);

        vm.prank(_gov);
        _vault.initialize(
            _token,
            _gov,
            _rewards,
            _name,
            _symbol,
            _guardian,
            _management
        );

        vm.prank(_gov);
        _vault.setDepositLimit(type(uint256).max);

        return address(_vault);
    }

    // Deploys a strategy
    function deployStrategy(address _vault) public returns (address) {
        Strategy _strategy = new Strategy(_vault);

        return address(_strategy);
    }

    // Deploys a vault and strategy attached to vault
    function deployVaultAndStrategy(
        address _token,
        address _gov,
        address _rewards,
        string memory _name,
        string memory _symbol,
        address _guardian,
        address _management,
        address _keeper,
        address _strategist
    ) public returns (address _vaultAddr, address _strategyAddr) {
        _vaultAddr = deployVault(
            _token,
            _gov,
            _rewards,
            _name,
            _symbol,
            _guardian,
            _management
        );
        IVault _vault = IVault(_vaultAddr);

        vm.prank(_strategist);
        _strategyAddr = deployStrategy(_vaultAddr);
        Strategy _strategy = Strategy(_strategyAddr);

        vm.prank(_strategist);
        _strategy.setKeeper(_keeper);

        vm.prank(_gov);
        _vault.addStrategy(_strategyAddr, 10_000, 0, type(uint256).max, 1_000);

        return (address(_vault), address(_strategy));
    }

    function _setTokenAddrs() internal {
        tokenAddrs["WBTC"] = 0x68f180fcCe6836688e9084f035309E29Bf0A2095;
        tokenAddrs["WETH"] = 0x4200000000000000000000000000000000000006;
        tokenAddrs["LINK"] = 0x350a791Bfc2C21F9Ed5d10980Dad2e2638ffa7f6;
        tokenAddrs["USDT"] = 0x94b008aA00579c1307B0EF2c499aD98a8ce58e58;
        tokenAddrs["DAI"] = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;
        tokenAddrs["USDC"] = 0x7F5c764cBc14f9669B88837ca1490cCa17c31607;
    }

    function _setTokenPrices() internal {
        tokenPrices["WBTC"] = 26_400;
        tokenPrices["WETH"] = 1_800;
        tokenPrices["LINK"] = 6;
        tokenPrices["USDT"] = 1;
        tokenPrices["USDC"] = 1;
        tokenPrices["DAI"] = 1;
    }
}
