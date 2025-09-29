// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {OracleTypes} from "src/oracle/PriceLoomTypes.sol";

interface IOracleAdmin {
    function createFeed(bytes32 feedId, OracleTypes.FeedConfig calldata cfg, address[] calldata operators) external;

    function setFeedConfig(bytes32 feedId, OracleTypes.FeedConfig calldata cfg) external;

    function addOperator(bytes32 feedId, address op) external;

    function removeOperator(bytes32 feedId, address op) external;

    function pause() external;

    function unpause() external;
}
