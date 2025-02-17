// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ConditionalTokens } from "../ConditionalTokens.sol";
import { CTHelpers } from "../CTHelpers.sol";
import { ConstructedCloneFactory } from "./ConstructedCloneFactory.sol";
import { LMSRMarketMaker } from "./LMSRMarketMaker.sol";
import { Whitelist } from "./Whitelist.sol";

contract LMSRMarketMakerData {
    address internal _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);


    bytes4 internal constant _INTERFACE_ID_ERC165 = 0x01ffc9a7;
    mapping(bytes4 => bool) internal _supportedInterfaces;


    uint64 constant FEE_RANGE = 10**18;
    event AMMCreated(uint initialFunding);
    ConditionalTokens internal pmSystem;
    IERC20 internal collateralToken;
    bytes32[] internal conditionIds;
    uint internal atomicOutcomeSlotCount;
    uint64 internal fee;
    uint internal funding;
    Stage internal stage;
    Whitelist internal whitelist;

    uint[] internal outcomeSlotCounts;
    bytes32[][] internal collectionIds;
    uint[] internal positionIds;

    enum Stage {
        Running,
        Paused,
        Closed
    }
}

contract LMSRMarketMakerFactory is ConstructedCloneFactory, LMSRMarketMakerData {
    event LMSRMarketMakerCreation(address indexed creator, LMSRMarketMaker lmsrMarketMaker, ConditionalTokens pmSystem, IERC20 collateralToken, bytes32[] conditionIds, uint64 fee, uint funding);

    LMSRMarketMaker public implementationMaster;

    constructor() {
        implementationMaster = new LMSRMarketMaker();
    }

    function cloneConstructor(bytes calldata consData) override external {
        (
            ConditionalTokens _pmSystem,
            IERC20 _collateralToken,
            bytes32[] memory _conditionIds,
            uint64 _fee,
            Whitelist _whitelist
        ) = abi.decode(consData, (ConditionalTokens, IERC20, bytes32[], uint64, Whitelist));

        _owner = msg.sender;
        emit OwnershipTransferred(address(0), _owner);

        _supportedInterfaces[_INTERFACE_ID_ERC165] = true;

        // Validate inputs
        require(address(_pmSystem) != address(0) && _fee < FEE_RANGE);
        pmSystem = _pmSystem;
        collateralToken = _collateralToken;
        conditionIds = _conditionIds;
        fee = _fee;
        whitelist = _whitelist;

        atomicOutcomeSlotCount = 1;
        outcomeSlotCounts = new uint[](conditionIds.length);
        for (uint i = 0; i < conditionIds.length; i++) {
            uint outcomeSlotCount = pmSystem.getOutcomeSlotCount(conditionIds[i]);
            atomicOutcomeSlotCount *= outcomeSlotCount;
            outcomeSlotCounts[i] = outcomeSlotCount;
        }
        require(atomicOutcomeSlotCount > 1, "conditions must be valid");

        collectionIds = new bytes32[][](conditionIds.length);
        _recordCollectionIDsForAllConditions(conditionIds.length, bytes32(0));

        stage = Stage.Paused;
        emit AMMCreated(funding);
    }

    function _recordCollectionIDsForAllConditions(uint conditionsLeft, bytes32 parentCollectionId) private {
        if(conditionsLeft == 0) {
            positionIds.push(CTHelpers.getPositionId(collateralToken, parentCollectionId));
            return;
        }

        conditionsLeft--;

        uint outcomeSlotCount = outcomeSlotCounts[conditionsLeft];

        collectionIds[conditionsLeft].push(parentCollectionId);
        for(uint i = 0; i < outcomeSlotCount; i++) {
            _recordCollectionIDsForAllConditions(
                conditionsLeft,
                CTHelpers.getCollectionId(
                    parentCollectionId,
                    conditionIds[conditionsLeft],
                    1 << i
                )
            );
        }
    }

    function createLMSRMarketMaker(ConditionalTokens pmSystem, IERC20 collateralToken, bytes32[] calldata conditionIds, uint64 fee, Whitelist whitelist, uint funding)
        external
        returns (LMSRMarketMaker lmsrMarketMaker)
    {
        lmsrMarketMaker = LMSRMarketMaker(createClone(address(implementationMaster), abi.encode(pmSystem, collateralToken, conditionIds, fee, whitelist)));
        collateralToken.transferFrom(msg.sender, address(this), funding);
        collateralToken.approve(address(lmsrMarketMaker), funding);
        lmsrMarketMaker.changeFunding(int(funding));
        lmsrMarketMaker.resume();
        lmsrMarketMaker.transferOwnership(msg.sender);
        emit LMSRMarketMakerCreation(msg.sender, lmsrMarketMaker, pmSystem, collateralToken, conditionIds, fee, funding);
    }
}