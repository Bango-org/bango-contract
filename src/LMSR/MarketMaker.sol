// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.20;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SignedSafeMath } from "../../lib/util-contracts/contracts/SignedSafeMath.sol";
// import { ERC1155TokenReceiver } from "../ERC1155/ERC1155TokenReceiver.sol";
import { Fixed192x64Math } from "../../lib/util-contracts/contracts/Fixed192x64Math.sol";

import { CTHelpers } from "../CTHelpers.sol";
import { ConditionalTokens } from "../ConditionalTokens.sol";
import { Whitelist } from "./Whitelist.sol";
import "@openzeppelin/contracts/token/ERC1155//IERC1155Receiver.sol";


contract MarketMaker is Ownable, IERC1155Receiver {
    using SignedSafeMath for int;
    using Math for uint;

    
    /*
     *  Constants
     */
    uint constant ONE = 0x10000000000000000;
    int constant EXP_LIMIT = 3394200909562557497344;


    /*
     *  Constants
     */    
    uint64 public constant FEE_RANGE = 10**18;

    /*
     *  Events
     */
    event AMMCreated(uint initialFunding);
    event AMMPaused();
    event AMMResumed();
    event AMMClosed();
    event AMMFundingChanged(int fundingChange);
    event AMMFeeChanged(uint64 newFee);
    event AMMFeeWithdrawal(uint fees);
    event AMMOutcomeTokenTrade(address indexed transactor, int[] outcomeTokenAmounts, int outcomeTokenNetCost, uint marketFees);
    
    /*
     *  Storage
     */
    ConditionalTokens public pmSystem;
    IERC20 public collateralToken;
    bytes32[] public conditionIds;
    uint public atomicOutcomeSlotCount;
    uint64 public fee;
    uint public funding;
    Stage public stage;
    Whitelist public whitelist;

    uint[] outcomeSlotCounts;
    bytes32[][] collectionIds;
    uint[] positionIds;

    enum Stage {
        Running,
        Paused,
        Closed
    }

    /*
     *  Modifiers
     */
    modifier atStage(Stage _stage) {
        // Contract has to be in given stage
        require(stage == _stage);
        _;
    }

    modifier onlyWhitelisted() {
        require(
            whitelist == Whitelist(address(0)) || whitelist.isWhitelisted(msg.sender),
            "only whitelisted users may call this function"
        );
        _;
    }

    constructor(
        
    ) Ownable(msg.sender) IERC1155Receiver() {
        emit AMMCreated(0);
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId || 
               interfaceId == type(IERC165).interfaceId;
    }

    function sumExpOffset(int log2N, int[] memory otExpNums, uint8 outcomeIndex, Fixed192x64Math.EstimationMode estimationMode)
        private
        view
        returns (uint sum, int offset, uint outcomeExpTerm)
    {
        // Naive calculation of this causes an overflow
        // since anything above a bit over 133*ONE supplied to exp will explode
        // as exp(133) just about fits into 192 bits of whole number data.

        // The choice of this offset is subject to another limit:
        // computing the inner sum successfully.
        // Since the index is 8 bits, there has to be 8 bits of headroom for
        // each summand, meaning q/b - offset <= exponential_limit,
        // where that limit can be found with `mp.floor(mp.log((2**248 - 1) / ONE) * ONE)`
        // That is what EXP_LIMIT is set to: it is about 127.5

        // finally, if the distribution looks like [BIG, tiny, tiny...], using a
        // BIG offset will cause the tiny quantities to go really negative
        // causing the associated exponentials to vanish.

        require(log2N >= 0 && int(funding) >= 0);
        offset = Fixed192x64Math.max(otExpNums);
        offset = offset * (log2N) / int(funding);
        offset = offset - (EXP_LIMIT);
        uint term;
        for (uint8 i = 0; i < otExpNums.length; i++) {
            term = Fixed192x64Math.pow2((otExpNums[i] * log2N / int256(funding)) - offset, estimationMode);
            if (i == outcomeIndex)
                outcomeExpTerm = term;
            sum = sum - term;
        }
    }

    function calcNetCost(int[] memory outcomeTokenAmounts)
        public
        view
        returns (int netCost)
    {
        require(outcomeTokenAmounts.length == atomicOutcomeSlotCount);

        int[] memory otExpNums = new int[](atomicOutcomeSlotCount);
        for (uint i = 0; i < atomicOutcomeSlotCount; i++) {
            int balance = int(pmSystem.balanceOf(address(this), generateAtomicPositionId(i)));
            require(balance >= 0);
            otExpNums[i] = outcomeTokenAmounts[i] - balance;
        }

        int log2N = Fixed192x64Math.binaryLog(atomicOutcomeSlotCount * ONE, Fixed192x64Math.EstimationMode.UpperBound);

        (uint sum, int offset, ) = sumExpOffset(log2N, otExpNums, 0, Fixed192x64Math.EstimationMode.UpperBound);
        netCost = Fixed192x64Math.binaryLog(sum, Fixed192x64Math.EstimationMode.UpperBound);
        netCost = netCost + offset;
        netCost = ((netCost * int256(ONE)) / log2N) * int256(funding);


        // Integer division for negative numbers already uses ceiling,
        // so only check boundary condition for positive numbers
        if(netCost <= 0 || netCost / int(ONE) * int(ONE) == netCost) {
            netCost /= int(ONE);
        } else {
            netCost = netCost / int(ONE) + 1;
        }

        return netCost;
    }

    /// @dev Allows to fund the market with collateral tokens converting them into outcome tokens
    /// Note for the future: should combine splitPosition and mergePositions into one function, as code duplication causes things like this to happen.
    function changeFunding(int fundingChange)
        public
        onlyOwner
        atStage(Stage.Paused)
    {
        require(fundingChange != 0, "funding change must be non-zero");
        // Either add or subtract funding based off whether the fundingChange parameter is negative or positive
        if (fundingChange > 0) {
            require(collateralToken.transferFrom(msg.sender, address(this), uint(fundingChange)) && collateralToken.approve(address(pmSystem), uint(fundingChange)));
            splitPositionThroughAllConditions(uint(fundingChange));
            funding = funding + uint(fundingChange);
            emit AMMFundingChanged(fundingChange);
        }
        if (fundingChange < 0) {
            mergePositionsThroughAllConditions(uint(-fundingChange));
            funding = funding - uint(-fundingChange);
            require(collateralToken.transfer(owner(), uint(-fundingChange)));
            emit AMMFundingChanged(fundingChange);
        }
    }

    function pause() public onlyOwner atStage(Stage.Running) {
        stage = Stage.Paused;
        emit AMMPaused();
    }
    
    function resume() public onlyOwner atStage(Stage.Paused) {
        stage = Stage.Running;
        emit AMMResumed();
    }

    function changeFee(uint64 _fee) public onlyOwner atStage(Stage.Paused) {
        fee = _fee;
        emit AMMFeeChanged(fee);
    }

    /// @dev Allows market owner to close the markets by transferring all remaining outcome tokens to the owner
    function close()
        public
        onlyOwner
    {
        require(stage == Stage.Running || stage == Stage.Paused, "This Market has already been closed");
        for (uint i = 0; i < atomicOutcomeSlotCount; i++) {
            uint positionId = generateAtomicPositionId(i);
            pmSystem.safeTransferFrom(address(this), owner(), positionId, pmSystem.balanceOf(address(this), positionId), "");
        }
        stage = Stage.Closed;
        emit AMMClosed();
    }

    function withdrawFees()
        public
        onlyOwner
        returns (uint fees)
    {
        fees = collateralToken.balanceOf(address(this));
        // Transfer fees
        require(collateralToken.transfer(owner(), fees));
        emit AMMFeeWithdrawal(fees);
    }


    function trade(int[] memory outcomeTokenAmounts, int collateralLimit)
        public
        atStage(Stage.Running)
        onlyWhitelisted
        returns (int netCost)
    {
        require(outcomeTokenAmounts.length == atomicOutcomeSlotCount);

        // Calculate net cost for executing trade
        int outcomeTokenNetCost = calcNetCost(outcomeTokenAmounts);
        int fees;
        if(outcomeTokenNetCost < 0)
            fees = int(calcMarketFee(uint(-outcomeTokenNetCost)));
        else
            fees = int(calcMarketFee(uint(outcomeTokenNetCost)));

        require(fees >= 0);
        netCost = outcomeTokenNetCost.add(fees);

        require(
            (collateralLimit != 0 && netCost <= collateralLimit) ||
            collateralLimit == 0
        );

        if(outcomeTokenNetCost > 0) {
            require(
                collateralToken.transferFrom(msg.sender, address(this), uint(netCost)) &&
                collateralToken.approve(address(pmSystem), uint(outcomeTokenNetCost))
            );

            splitPositionThroughAllConditions(uint(outcomeTokenNetCost));
        }

        bool touched = false;
        uint[] memory transferAmounts = new uint[](atomicOutcomeSlotCount);
        for (uint i = 0; i < atomicOutcomeSlotCount; i++) {
            if(outcomeTokenAmounts[i] < 0) {
                touched = true;
                // This is safe since
                // 0x8000000000000000000000000000000000000000000000000000000000000000 ==
                // uint(-int(-0x8000000000000000000000000000000000000000000000000000000000000000))
                transferAmounts[i] = uint(-outcomeTokenAmounts[i]);
            }
        }
        if(touched) pmSystem.safeBatchTransferFrom(msg.sender, address(this), positionIds, transferAmounts, "");

        if(outcomeTokenNetCost < 0) {
            mergePositionsThroughAllConditions(uint(-outcomeTokenNetCost));
        }

        emit AMMOutcomeTokenTrade(msg.sender, outcomeTokenAmounts, outcomeTokenNetCost, uint(fees));

        touched = false;
        for (uint i = 0; i < atomicOutcomeSlotCount; i++) {
            if(outcomeTokenAmounts[i] > 0) {
                touched = true;
                transferAmounts[i] = uint(outcomeTokenAmounts[i]);
            } else {
                transferAmounts[i] = 0;
            }
        }
        if(touched) pmSystem.safeBatchTransferFrom(address(this), msg.sender, positionIds, transferAmounts, "");

        if(netCost < 0) {
            require(collateralToken.transfer(msg.sender, uint(-netCost)));
        }
    }

    /// @dev Calculates fee to be paid to market maker
    /// @param outcomeTokenCost Cost for buying outcome tokens
    /// @return Fee for trade
    function calcMarketFee(uint outcomeTokenCost)
        public
        view
        returns (uint)
    {
        return outcomeTokenCost * fee / FEE_RANGE;
    }

    function onERC1155Received(address operator, address /*from*/, uint256 /*id*/, uint256 /*value*/, bytes calldata /*data*/) external view returns(bytes4) {
        if (operator == address(this)) {
            return this.onERC1155Received.selector;
        }
        return 0x0;
    }

    function onERC1155BatchReceived(address _operator, address /*from*/, uint256[] calldata /*ids*/, uint256[] calldata /*values*/, bytes calldata /*data*/) external view returns(bytes4) {
        if (_operator == address(this)) {
            return this.onERC1155BatchReceived.selector;
        }
        return 0x0;
    }

    function generateBasicPartition(uint outcomeSlotCount)
        private
        pure
        returns (uint[] memory partition)
    {
        partition = new uint[](outcomeSlotCount);
        for(uint i = 0; i < outcomeSlotCount; i++) {
            partition[i] = 1 << i;
        }
    }

    function generateAtomicPositionId(uint i)
        internal
        view
        returns (uint)
    {
        return positionIds[i];
    }

    function splitPositionThroughAllConditions(uint amount)
        private
    {
        for(uint i = conditionIds.length - 1; int(i) >= 0; i--) {
            uint[] memory partition = generateBasicPartition(outcomeSlotCounts[i]);
            for(uint j = 0; j < collectionIds[i].length; j++) {
                pmSystem.splitPosition(collateralToken, collectionIds[i][j], conditionIds[i], partition, amount);
            }
        }
    }

    function mergePositionsThroughAllConditions(uint amount)
        private
    {
        for(uint i = 0; i < conditionIds.length; i++) {
            uint[] memory partition = generateBasicPartition(outcomeSlotCounts[i]);
            for(uint j = 0; j < collectionIds[i].length; j++) {
                pmSystem.mergePositions(collateralToken, collectionIds[i][j], conditionIds[i], partition, amount);
            }
        }
    }
}