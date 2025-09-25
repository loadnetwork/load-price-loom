// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {EfficientHashLib as EHash} from "@solady-utils/EfficientHashLib.sol";

library PriceSubmissionHash {
    struct PriceSubmission {
        bytes32 feedId;
        uint80 roundId;
        int256 answer;
        uint256 validUntil;
    }

    bytes32 internal constant PRICE_SUBMISSION_TYPEHASH =
        keccak256(
            "PriceSubmission(bytes32 feedId,uint80 roundId,int256 answer,uint256 validUntil)"
        );

    function structHash(
        PriceSubmission memory sub
    ) internal pure returns (bytes32) {
        // Allocate a buffer for 5 words: typehash + 4 fields
        bytes32[] memory buf = EHash.malloc(5);

        // Fill the 32-byte slots in the same order as abi.encode(...)
        EHash.set(buf, 0, PRICE_SUBMISSION_TYPEHASH);
        EHash.set(buf, 1, sub.feedId); // already bytes32
        EHash.set(buf, 2, bytes32(uint256(sub.roundId))); // widen to uint256, then bytes32
        EHash.set(buf, 3, bytes32(uint256(sub.answer))); // two's complement representation
        EHash.set(buf, 4, bytes32(sub.validUntil));

        // keccak256(concat(buf))
        return EHash.hash(buf);
    }
}
