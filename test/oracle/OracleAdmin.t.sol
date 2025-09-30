// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";

import {PriceLoomOracle} from "src/oracle/PriceLoomOracle.sol";
import {
    ZeroFeedId,
    FeedExists,
    MinGreaterThanOps,
    TooManyOps,
    ZeroOperator,
    DuplicateOperator,
    BadDecimals,
    BadMinMax,
    MinSubmissionsTooSmall,
    MaxSubmissionsTooLarge,
    MaxGreaterThanOperators,
    TrimUnsupported,
    BoundsInvalid,
    MinPriceTooLow,
    MaxPriceTooHigh,
    DescriptionTooLong,
    NoGating,
    NoFeed,
    DecimalsImmutable
} from "src/oracle/PriceLoomOracle.sol";
import {OracleTypes} from "src/oracle/PriceLoomTypes.sol";

contract OracleAdminTest is Test {
    PriceLoomOracle internal oracle;

    bytes32 internal FEED = keccak256("AR/byte");
    address internal admin;
    address[] internal ops;

    function setUp() public {
        admin = address(this);
        oracle = new PriceLoomOracle(admin);

        // Prepare operators
        ops = new address[](3);
        ops[0] = makeAddr("op1");
        ops[1] = makeAddr("op2");
        ops[2] = makeAddr("op3");
    }

    function test_createFeed_reverts_zeroFeedId() public {
        OracleTypes.FeedConfig memory cfg = _defaultConfig();
        vm.expectRevert(ZeroFeedId.selector);
        oracle.createFeed(bytes32(0), cfg, ops);
    }

    function test_createFeed_reverts_feedExists() public {
        OracleTypes.FeedConfig memory cfg = _defaultConfig();
        oracle.createFeed(FEED, cfg, ops);
        vm.expectRevert(FeedExists.selector);
        oracle.createFeed(FEED, cfg, ops);
    }

    function test_createFeed_reverts_minGreaterThanOps() public {
        OracleTypes.FeedConfig memory cfg = _defaultConfig();
        cfg.minSubmissions = 4;
        vm.expectRevert(MinGreaterThanOps.selector);
        oracle.createFeed(FEED, cfg, ops);
    }

    function test_createFeed_reverts_tooManyOps() public {
        address[] memory tooManyOps = new address[](32);
        for (uint8 i = 0; i < 32; i++) {
            tooManyOps[i] = makeAddr(string(abi.encodePacked("op", i)));
        }
        OracleTypes.FeedConfig memory cfg = _defaultConfig();
        cfg.minSubmissions = 32;
        cfg.maxSubmissions = 32;
        vm.expectRevert(MaxSubmissionsTooLarge.selector);
        oracle.createFeed(FEED, cfg, tooManyOps);
    }

    function test_createFeed_reverts_zeroOperator() public {
        address[] memory opsWithZero = new address[](3);
        opsWithZero[0] = ops[0];
        opsWithZero[1] = address(0);
        opsWithZero[2] = ops[2];
        OracleTypes.FeedConfig memory cfg = _defaultConfig();
        vm.expectRevert(ZeroOperator.selector);
        oracle.createFeed(FEED, cfg, opsWithZero);
    }

    function test_createFeed_reverts_duplicateOperator() public {
        address[] memory opsWithDuplicate = new address[](3);
        opsWithDuplicate[0] = ops[0];
        opsWithDuplicate[1] = ops[0];
        opsWithDuplicate[2] = ops[2];
        OracleTypes.FeedConfig memory cfg = _defaultConfig();
        vm.expectRevert(DuplicateOperator.selector);
        oracle.createFeed(FEED, cfg, opsWithDuplicate);
    }

    function test_createFeed_reverts_badDecimals() public {
        OracleTypes.FeedConfig memory cfg = _defaultConfig();
        cfg.decimals = 19;
        vm.expectRevert(BadDecimals.selector);
        oracle.createFeed(FEED, cfg, ops);
    }

    function test_createFeed_reverts_badMinMax() public {
        OracleTypes.FeedConfig memory cfg = _defaultConfig();
        cfg.minSubmissions = 3; // <= operators.length to avoid MinGreaterThanOps
        cfg.maxSubmissions = 2; // less than minSubmissions
        vm.expectRevert(BadMinMax.selector);
        oracle.createFeed(FEED, cfg, ops);
    }

    function test_createFeed_reverts_minSubmissionsTooSmall() public {
        OracleTypes.FeedConfig memory cfg = _defaultConfig();
        cfg.minSubmissions = 0;
        vm.expectRevert(MinSubmissionsTooSmall.selector);
        oracle.createFeed(FEED, cfg, ops);
    }

    function test_createFeed_reverts_maxSubmissionsTooLarge() public {
        OracleTypes.FeedConfig memory cfg = _defaultConfig();
        cfg.maxSubmissions = 32;
        vm.expectRevert(MaxSubmissionsTooLarge.selector);
        oracle.createFeed(FEED, cfg, ops);
    }

    function test_createFeed_reverts_maxGreaterThanOperators() public {
        OracleTypes.FeedConfig memory cfg = _defaultConfig();
        cfg.maxSubmissions = 4;
        vm.expectRevert(MaxGreaterThanOperators.selector);
        oracle.createFeed(FEED, cfg, ops);
    }

    function test_createFeed_reverts_trimUnsupported() public {
        OracleTypes.FeedConfig memory cfg = _defaultConfig();
        cfg.trim = 1;
        vm.expectRevert(TrimUnsupported.selector);
        oracle.createFeed(FEED, cfg, ops);
    }

    function test_createFeed_reverts_boundsInvalid() public {
        OracleTypes.FeedConfig memory cfg = _defaultConfig();
        cfg.minPrice = 100;
        cfg.maxPrice = 99;
        vm.expectRevert(BoundsInvalid.selector);
        oracle.createFeed(FEED, cfg, ops);
    }

    function test_createFeed_reverts_minPriceTooLow() public {
        OracleTypes.FeedConfig memory cfg = _defaultConfig();
        cfg.minPrice = type(int256).min;
        vm.expectRevert(MinPriceTooLow.selector);
        oracle.createFeed(FEED, cfg, ops);
    }

    function test_createFeed_reverts_maxPriceTooHigh() public {
        OracleTypes.FeedConfig memory cfg = _defaultConfig();
        cfg.maxPrice = type(int256).max;
        vm.expectRevert(MaxPriceTooHigh.selector);
        oracle.createFeed(FEED, cfg, ops);
    }

    function test_createFeed_reverts_descriptionTooLong() public {
        OracleTypes.FeedConfig memory cfg = _defaultConfig();
        cfg.description =
            "a very long description that is more than 100 characters long and should be rejected by the contract and this makes it even longer";
        vm.expectRevert(DescriptionTooLong.selector);
        oracle.createFeed(FEED, cfg, ops);
    }

    function test_createFeed_reverts_noGating() public {
        OracleTypes.FeedConfig memory cfg = _defaultConfig();
        cfg.heartbeatSec = 0;
        cfg.deviationBps = 0;
        vm.expectRevert(NoGating.selector);
        oracle.createFeed(FEED, cfg, ops);
    }

    function test_setFeedConfig_updates_and_invariants() public {
        OracleTypes.FeedConfig memory cfg = _defaultConfig();
        oracle.createFeed(FEED, cfg, ops);

        cfg.heartbeatSec = 7200;
        cfg.deviationBps = 100;
        oracle.setFeedConfig(FEED, cfg);

        OracleTypes.FeedConfig memory newCfg = oracle.getConfig(FEED);
        assertEq(newCfg.heartbeatSec, 7200);
        assertEq(newCfg.deviationBps, 100);
    }

    function test_setFeedConfig_reverts_noFeed() public {
        OracleTypes.FeedConfig memory cfg = _defaultConfig();
        vm.expectRevert(NoFeed.selector);
        oracle.setFeedConfig(FEED, cfg);
    }

    function test_setFeedConfig_reverts_decimalsImmutable() public {
        OracleTypes.FeedConfig memory cfg = _defaultConfig();
        oracle.createFeed(FEED, cfg, ops);

        cfg.decimals = 10;
        vm.expectRevert(DecimalsImmutable.selector);
        oracle.setFeedConfig(FEED, cfg);
    }

    function _defaultConfig() internal pure returns (OracleTypes.FeedConfig memory) {
        return OracleTypes.FeedConfig({
            decimals: 8,
            minSubmissions: 3,
            maxSubmissions: 3,
            trim: 0,
            heartbeatSec: 3600,
            deviationBps: 50,
            timeoutSec: 900,
            minPrice: int256(-1e20),
            maxPrice: int256(1e20),
            description: "AR/byte"
        });
    }
}
