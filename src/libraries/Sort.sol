// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {LibSort} from "@solady-utils/LibSort.sol";

library Sort {
    function insertionSort(int256[] memory arr) internal pure {
        LibSort.insertionSort(arr);
    }
}
