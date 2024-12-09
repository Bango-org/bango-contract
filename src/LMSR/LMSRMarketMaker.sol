// // SPDX-License-Identifier: GPL-3.0

// pragma solidity ^0.8.20;

// import "@openzeppelin/contracts/utils/math/Math.sol";
// import { Fixed192x64Math } from "../../lib/util-contracts/contracts/Fixed192x64Math.sol";
// import { MarketMaker } from "./MarketMaker.sol";


// contract LMSRMarketMaker is MarketMaker {
//     using Math for uint;
    
//     /*
//      *  Constants
//      */
//     uint constant ONE = 0x10000000000000000;
//     int constant EXP_LIMIT = 3394200909562557497344;

//     function calcNetCost(int[] memory outcomeTokenAmounts)
//         public
//         override
//         view
//         returns (int netCost)
//     {
//         require(outcomeTokenAmounts.length == atomicOutcomeSlotCount);

//         int[] memory otExpNums = new int[](atomicOutcomeSlotCount);
//         for (uint i = 0; i < atomicOutcomeSlotCount; i++) {
//             int balance = int(pmSystem.balanceOf(address(this), generateAtomicPositionId(i)));
//             require(balance >= 0);
//             otExpNums[i] = outcomeTokenAmounts[i] - balance;
//         }

//         int log2N = Fixed192x64Math.binaryLog(atomicOutcomeSlotCount * ONE, Fixed192x64Math.EstimationMode.UpperBound);

//         (uint sum, int offset, ) = sumExpOffset(log2N, otExpNums, 0, Fixed192x64Math.EstimationMode.UpperBound);
//         netCost = Fixed192x64Math.binaryLog(sum, Fixed192x64Math.EstimationMode.UpperBound);
//         netCost = netCost + offset;
//         netCost = ((netCost * int256(ONE)) / log2N) * int256(funding);


//         // Integer division for negative numbers already uses ceiling,
//         // so only check boundary condition for positive numbers
//         if(netCost <= 0 || netCost / int(ONE) * int(ONE) == netCost) {
//             netCost /= int(ONE);
//         } else {
//             netCost = netCost / int(ONE) + 1;
//         }

//         return netCost;
//     }
    

//     function calcMarginalPrice(uint8 outcomeTokenIndex)
//         public
//         view
//         returns (uint price)
//     {
//         int[] memory negOutcomeTokenBalances = new int[](atomicOutcomeSlotCount);
//         for (uint i = 0; i < atomicOutcomeSlotCount; i++) {
//             int negBalance = -int(pmSystem.balanceOf(address(this), generateAtomicPositionId(i)));
//             require(negBalance <= 0);
//             negOutcomeTokenBalances[i] = negBalance;
//         }

//         int log2N = Fixed192x64Math.binaryLog(negOutcomeTokenBalances.length * ONE, Fixed192x64Math.EstimationMode.Midpoint);
//         // The price function is exp(quantities[i]/b) / sum(exp(q/b) for q in quantities)
//         // To avoid overflow, calculate with
//         // exp(quantities[i]/b - offset) / sum(exp(q/b - offset) for q in quantities)
//         (uint sum, , uint outcomeExpTerm) = sumExpOffset(log2N, negOutcomeTokenBalances, outcomeTokenIndex, Fixed192x64Math.EstimationMode.Midpoint);
//         return outcomeExpTerm / (sum / ONE);
//     }


//     function sumExpOffset(int log2N, int[] memory otExpNums, uint8 outcomeIndex, Fixed192x64Math.EstimationMode estimationMode)
//         private
//         view
//         returns (uint sum, int offset, uint outcomeExpTerm)
//     {
//         // Naive calculation of this causes an overflow
//         // since anything above a bit over 133*ONE supplied to exp will explode
//         // as exp(133) just about fits into 192 bits of whole number data.

//         // The choice of this offset is subject to another limit:
//         // computing the inner sum successfully.
//         // Since the index is 8 bits, there has to be 8 bits of headroom for
//         // each summand, meaning q/b - offset <= exponential_limit,
//         // where that limit can be found with `mp.floor(mp.log((2**248 - 1) / ONE) * ONE)`
//         // That is what EXP_LIMIT is set to: it is about 127.5

//         // finally, if the distribution looks like [BIG, tiny, tiny...], using a
//         // BIG offset will cause the tiny quantities to go really negative
//         // causing the associated exponentials to vanish.

//         require(log2N >= 0 && int(funding) >= 0);
//         offset = Fixed192x64Math.max(otExpNums);
//         offset = offset * (log2N) / int(funding);
//         offset = offset - (EXP_LIMIT);
//         uint term;
//         for (uint8 i = 0; i < otExpNums.length; i++) {
//             term = Fixed192x64Math.pow2((otExpNums[i] * log2N / int256(funding)) - offset, estimationMode);
//             if (i == outcomeIndex)
//                 outcomeExpTerm = term;
//             sum = sum - term;
//         }
//     }
// }