// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {ConditionalTokens} from "../src/ConditionalTokens.sol";

contract ConditionalTokensTest is Test {

    
    ConditionalTokens public conditional_token;
    address public oracle = 0x375C11FD30FdC95e10aAD66bdcE590E1bccc6aFA;
    uint outcome_slots = 3;
    bytes32 question_id = keccak256(abi.encodePacked(block.timestamp, block.number, oracle));

    event ConditionPreparation(
        bytes32 indexed conditionId,
        address indexed oracle,
        bytes32 indexed questionId,
        uint outcomeSlotCount
    );

    function setUp() public {
        conditional_token = new ConditionalTokens();
    }

    // Prepare condition
    function testCreateQuestion() public {


        vm.expectEmit(false, true, true, false);
        emit ConditionPreparation("dasd", oracle,question_id, outcome_slots);
        conditional_token.prepareCondition(oracle,question_id, outcome_slots);

    }

    function testConditionCreated() public view {

        bytes32 conditionId = conditional_token.getConditionId(oracle,question_id, outcome_slots); 
        bytes32 actualConditionId = 0xb67aabb69fda6d449b5378d12326215c590d72ff09b2dc4b8088d9e52c54af5d;
        assertEq(conditionId, actualConditionId);

    }

}
