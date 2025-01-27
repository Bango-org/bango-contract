// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/ConditionalTokens.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock USDT for testing
contract MockUSDT is ERC20 {
    constructor() ERC20("Mock USDT", "USDT") {
        _mint(msg.sender, 10000 * 10**18); // Mint 10,000 USDT
    }
}

contract WeatherMarketScript is Script {
    ConditionalTokens public conditionalTokens;
    MockUSDT public usdt;
    
    // Market parameters
    address public oracle;
    uint256 public oraclePrivateKey;
    bytes32 public questionId;
    uint public outcomeSlotCount = 4; // Rain, Cloudy, Sunny, Smogy
    bytes32 public conditionId;
    
    // Index sets for outcomes (in binary)
    uint public constant RAIN = 1;    // 0001
    uint public constant CLOUDY = 2;  // 0010
    uint public constant SUNNY = 4;   // 0100
    uint public constant SMOGY = 8;   // 1000

    function setUp() public {
        uint256 deployerPrivateKey = vm.envUint("DEV_PRIVATE_KEY");
        oraclePrivateKey = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
        oracle = vm.addr(oraclePrivateKey);

        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy contracts
        conditionalTokens = new ConditionalTokens();
        usdt = new MockUSDT();
        
        // Setup market parameters
        questionId = keccak256("What will be the weather tomorrow in pune?");
        
        // Calculate condition ID
        conditionId = conditionalTokens.getConditionId(oracle, questionId, outcomeSlotCount);
        
        vm.stopBroadcast();
    }

    function run() public {
        // First part - Market setup and betting
        uint256 deployerPrivateKey = vm.envUint("DEV_PRIVATE_KEY");
        uint256 smogBettorKey = 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a;
        address deployer = vm.addr(deployerPrivateKey);
        address smogAddr = vm.addr(smogBettorKey);

        vm.startBroadcast(deployerPrivateKey);
    
        // Step 1: Create the market by preparing the condition
        console.log("Creating weather prediction market...");
        conditionalTokens.prepareCondition(oracle, questionId, outcomeSlotCount);
        console.log("Market created with condition ID:", vm.toString(conditionId));
        
        // Step 2: Initial bet - Split 100 USDT across all outcomes
        uint256 betAmount = 1000 * 10**18;
        usdt.approve(address(conditionalTokens), betAmount);

        // Print final USDT balance
        uint256 finalBalance = usdt.balanceOf(deployer);
        console.log("Final USDT balance:", finalBalance / 10**18);


        usdt.transfer(smogAddr, betAmount+10000);

        
        // Create partition for all outcomes
        uint[] memory allOutcomes = new uint[](3);
        // allOutcomes[0] = 0;
        // allOutcomes[1] = CLOUDY;
        // allOutcomes[2] = 0;
        allOutcomes[0] = SMOGY;
        allOutcomes[1] = RAIN;
        allOutcomes[2] = 6;

        console.log("Placing initial bet across all outcomes...");
        conditionalTokens.splitPosition(
            IERC20(address(usdt)),
            bytes32(0), // Empty parent collection
            conditionId,
            allOutcomes,
            betAmount
        );
        console.log("Initial positions created");
        
        // Step 3: Later, decide to merge all positions into RAIN
        // console.log("Merging all positions into RAIN outcome...");
        // uint[] memory rainOnly = new uint[](1);
        // rainOnly[0] = RAIN;

        // conditionalTokens.mergePositions(
        //     IERC20(address(usdt)),
        //     bytes32(0),
        //     conditionId,
        //     allOutcomes,
        //     betAmount
        // );
        // console.log("All positions merged to RAIN");
        
        vm.stopBroadcast();

        vm.startBroadcast(smogBettorKey);


        uint[] memory smogPartition = new uint[](2);
        smogPartition[0] = SMOGY;    // Smog
        smogPartition[1] = 7;    

        usdt.approve(address(conditionalTokens), betAmount);

        // Print final USDT balance
        finalBalance = usdt.balanceOf(smogAddr);
        console.log("SMOG USDT balance:", finalBalance / 10**18);
        
        conditionalTokens.splitPosition(
            IERC20(address(usdt)),
            bytes32(0),
            conditionId,
            smogPartition,
            betAmount
        );

        vm.stopBroadcast();


        // Second part - Oracle reporting
        vm.startBroadcast(oraclePrivateKey);

        // Step 4: Oracle reports the outcome
        uint[] memory payouts = new uint[](4);
        payouts[0] = 1; // 100% for Rain
        payouts[1] = 0; // 0% for Cloudy
        payouts[2] = 0; // 0% for Sunny
        payouts[3] = 0; // 0% for Smogy
        conditionalTokens.reportPayouts(questionId, payouts);
        console.log("Oracle reported: It rained!");
        
        vm.stopBroadcast();

        // Third part - Redemption
        vm.startBroadcast(deployerPrivateKey);
        
        console.log("Oracle Addr: ", oracle);

        // Step 5: Redeem winning position
        console.log("Redeeming winning position...");
        uint[] memory redeemOutcomes = new uint[](1);
        redeemOutcomes[0] = RAIN;
        
        conditionalTokens.redeemPositions(
            IERC20(address(usdt)),
            bytes32(0),
            conditionId,
            redeemOutcomes
        );
        console.log("Position redeemed successfully!");
        
        // Print final USDT balance
        finalBalance = usdt.balanceOf(deployer);
        console.log("Final USDT balance:", finalBalance / 10**18);

        // Print final USDT balance
        finalBalance = usdt.balanceOf(smogAddr);
        console.log("SMOG USDT balance:", finalBalance / 10**18);
        
        vm.stopBroadcast();
    }
}