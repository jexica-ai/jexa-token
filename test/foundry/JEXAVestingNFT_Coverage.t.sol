// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {JEXAVestingNFT} from "../../contracts/JEXAVestingNFT.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// @title Additional coverage tests for JEXAVestingNFT
/// @notice Focuses on branches that were not hit by the happy-path suite: view helpers,
///         `setEndDate`, and various custom-error reverts.
contract JEXAVestingNFT_Coverage is Test {
    ERC20Mock jexa;
    JEXAVestingNFT vest;

    address internal admin = address(0xA11);
    uint256 internal constant SUPPLY = 2_000_000 ether;

    function setUp() public {
        // Fix the block timestamp for deterministic math
        vm.warp(1_747_526_400); // 2025-05-15 00:00:00 UTC

        jexa = new ERC20Mock("Jexica AI", "JEXA");
        jexa.mint(admin, SUPPLY);
        vest = new JEXAVestingNFT(address(jexa));

        vm.prank(admin);
        jexa.approve(address(vest), type(uint256).max);
    }

    /*──────────────────────── tokenURI / _baseURI ───────────────────────*/

    function testTokenURI_MatchesBase() public {
        uint64 start = uint64(block.timestamp + 1 days);
        uint64 dur = 30 days;
        uint256 amount = 100 ether;

        vm.prank(admin);
        uint256 id = vest.mintVesting(start, dur, amount);

        string memory expected = string.concat("https://vesting.jexica.ai/api/nft-metadata/", Strings.toString(id));
        assertEq(vest.tokenURI(id), expected, "tokenURI must match hard-coded base URI scheme");
    }

    /*──────────────────────── setEndDate ────────────────────────────────*/

    function testSetEndDate_ReleasesAndExtends() public {
        uint64 start = uint64(block.timestamp); // start now
        uint64 dur = 10 days;
        uint256 amt = 1_000 ether;

        vm.prank(admin);
        uint256 id = vest.mintVesting(start, dur, amt);

        // Move half-way through vesting so 50% is claimable
        vm.warp(start + dur / 2);
        uint256 balBefore = jexa.balanceOf(admin);

        uint64 newEnd = start + dur + 5 days; // extend by 5 days
        vm.prank(admin);
        vest.setEndDate(id, newEnd);

        // 1. Half of the tokens must have been released to owner
        assertEq(jexa.balanceOf(admin) - balBefore, amt / 2);

        // 2. New duration stored
        JEXAVestingNFT.VestingPosition memory vp = vest.vestingInfo(id);
        assertEq(vp.duration, newEnd - start);
    }

    function testSetEndDate_TooEarlyReverts() public {
        uint64 start = uint64(block.timestamp + 1 days);
        uint64 dur = 8 days;

        vm.prank(admin);
        uint256 id = vest.mintVesting(start, dur, 50 ether);

        // newEnd earlier than original end
        uint64 tooEarly = start + dur - 1;
        vm.prank(admin);
        vm.expectRevert(JEXAVestingNFT.NewEndTooEarly.selector);
        vest.setEndDate(id, tooEarly);
    }

    /*──────────────────────── splitByDates reverts ──────────────────────*/

    function testSplitByDates_DuplicateTimestampReverts() public {
        uint64 start = uint64(block.timestamp + 2 days);
        uint64 dur = 10 days;

        vm.prank(admin);
        uint256 id = vest.mintVesting(start, dur, 100 ether);

        uint64[] memory ts = new uint64[](2);
        ts[0] = start + 3 days;
        ts[1] = start + 3 days; // duplicate → not strictly increasing

        vm.prank(admin);
        vm.expectRevert(JEXAVestingNFT.InvalidTimestamps.selector);
        vest.splitByDates(id, ts);
    }

    /*──────────────────────── splitByAmounts reverts ────────────────────*/

    function testSplitByAmounts_BadSumReverts() public {
        uint64 start = uint64(block.timestamp + 5 days);
        uint64 dur = 30 days;
        uint256 amt = 100 ether;

        vm.prank(admin);
        uint256 id = vest.mintVesting(start, dur, amt);

        uint256[] memory parts = new uint256[](2);
        parts[0] = 60 ether;
        parts[1] = 30 ether; // sum 90, should be 100

        vm.prank(admin);
        vm.expectRevert(JEXAVestingNFT.InvalidAmounts.selector);
        vest.splitByAmounts(id, parts);
    }

    /*──────────────────────── release reverts ───────────────────────────*/

    function testRelease_NothingToReleaseReverts() public {
        uint64 start = uint64(block.timestamp + 7 days); // vesting starts in future
        uint64 dur = 14 days;
        uint256 amt = 500 ether;

        vm.prank(admin);
        uint256 id = vest.mintVesting(start, dur, amt);

        // No tokens vested yet -> expect revert
        vm.prank(admin);
        vm.expectRevert(JEXAVestingNFT.NothingToRelease.selector);
        vest.release(id);
    }

    /*──────────────────────── vestedAmount branches ─────────────────────*/

    function testVestedAmount_BeforeAndAfter() public {
        uint64 start = uint64(block.timestamp + 1 days);
        uint64 dur = 5 days;
        uint256 amt = 100 ether;

        vm.prank(admin);
        uint256 id = vest.mintVesting(start, dur, amt);

        // Before vesting start
        assertEq(vest.vestedAmount(id), 0);

        // After vesting end
        vm.warp(start + dur + 1);
        assertEq(vest.vestedAmount(id), amt);
    }

    /*──────────────────────── mint reverts ─────────────────────────────*/

    function testMintVesting_ZeroDurationReverts() public {
        vm.prank(admin);
        vm.expectRevert(JEXAVestingNFT.InvalidDuration.selector);
        vest.mintVesting(uint64(block.timestamp + 1 days), 0, 1 ether);
    }

    function testMintVesting_ZeroAmountReverts() public {
        vm.prank(admin);
        vm.expectRevert(JEXAVestingNFT.InvalidAmount.selector);
        vest.mintVesting(uint64(block.timestamp + 1 days), 1 days, 0);
    }

    /*──────────────────────── splitByShares reverts ────────────────────*/

    function testSplitByShares_LengthAndZeroShareReverts() public {
        uint64 start = uint64(block.timestamp + 1 days);
        uint64 dur = 10 days;

        vm.prank(admin);
        uint256 id = vest.mintVesting(start, dur, 10 ether);

        // length < 2
        uint32[] memory one = new uint32[](1);
        one[0] = 1;
        vm.prank(admin);
        vm.expectRevert(JEXAVestingNFT.InvalidAmounts.selector);
        vest.splitByShares(id, one);

        // zero share value
        uint32[] memory bad = new uint32[](2);
        bad[0] = 0;
        bad[1] = 1;
        vm.prank(admin);
        vm.expectRevert(JEXAVestingNFT.InvalidAmounts.selector);
        vest.splitByShares(id, bad);
    }

    /*──────────────────────── splitByAmounts length reverts ────────────*/

    function testSplitByAmounts_LengthReverts() public {
        uint64 start = uint64(block.timestamp + 2 days);
        uint64 dur = 15 days;

        vm.prank(admin);
        uint256 id = vest.mintVesting(start, dur, 20 ether);

        uint256[] memory one = new uint256[](1);
        one[0] = 5 ether;
        vm.prank(admin);
        vm.expectRevert(JEXAVestingNFT.InvalidAmounts.selector);
        vest.splitByAmounts(id, one);
    }

    /*──────────────────────── splitByDates additional reverts ──────────*/

    function testSplitByDates_FlowReverts() public {
        uint64 start = uint64(block.timestamp + 3 days);
        uint64 dur = 8 days;
        uint256 amt = 40 ether;

        vm.prank(admin);
        uint256 id = vest.mintVesting(start, dur, amt);

        // too few timestamps
        uint64[] memory one = new uint64[](1);
        one[0] = start + 1 days;
        vm.prank(admin);
        vm.expectRevert(JEXAVestingNFT.InvalidTimestamps.selector);
        vest.splitByDates(id, one);

        // scheduleStart earlier than minStart
        uint64[] memory early = new uint64[](2);
        early[0] = start - 1;
        early[1] = start + dur;
        vm.prank(admin);
        vm.expectRevert(JEXAVestingNFT.InvalidTimestamps.selector);
        vest.splitByDates(id, early);

        // last timestamp earlier than original end
        uint64[] memory endEarly = new uint64[](2);
        endEarly[0] = start + 1 days;
        endEarly[1] = start + dur - 1;
        vm.prank(admin);
        vm.expectRevert(JEXAVestingNFT.InvalidTimestamps.selector);
        vest.splitByDates(id, endEarly);
    }

    /*──────────────────────── vestedAmount mid-branch ──────────────────*/

    function testVestedAmount_MidwayLinear() public {
        uint64 start = uint64(block.timestamp + 1 days);
        uint64 dur = 4 days;
        uint256 amt = 80 ether;

        vm.prank(admin);
        uint256 id = vest.mintVesting(start, dur, amt);

        vm.warp(start + dur / 2);
        assertEq(vest.vestedAmount(id), amt / 2);
    }

    /*──────────────────────── add-on tests ─────────────────────────*/

    /*──────────────────────── unauthorized mutations ─────────────────────────*/
    function testUnauthorizedMutationsRevert() public {
        uint64 start = uint64(block.timestamp + 1 days);
        uint64 dur = 10 days;
        uint256 amt = 100 ether;
        vm.prank(admin);
        uint256 id = vest.mintVesting(start, dur, amt);
        address rogue = address(0xB0B);

        // release
        vm.prank(rogue);
        vm.expectRevert(JEXAVestingNFT.OnlyOwner.selector);
        vest.release(id);

        // split by dates
        uint64[] memory ts = new uint64[](2);
        ts[0] = start + 1 days;
        ts[1] = start + dur;
        vm.prank(rogue);
        vm.expectRevert(JEXAVestingNFT.OnlyOwner.selector);
        vest.splitByDates(id, ts);

        // split by shares
        uint32[] memory shares = new uint32[](2);
        shares[0] = 1;
        shares[1] = 1;
        vm.prank(rogue);
        vm.expectRevert(JEXAVestingNFT.OnlyOwner.selector);
        vest.splitByShares(id, shares);

        // split by amounts
        uint256[] memory parts = new uint256[](2);
        parts[0] = 50 ether;
        parts[1] = 50 ether;
        vm.prank(rogue);
        vm.expectRevert(JEXAVestingNFT.OnlyOwner.selector);
        vest.splitByAmounts(id, parts);
    }

    /*──────────────────────── public view functions ─────────────────────────*/
    function testPublicViewAccess() public {
        uint64 start = uint64(block.timestamp + 1 days);
        uint64 dur = 5 days;
        uint256 amt = 50 ether;
        vm.prank(admin);
        uint256 id = vest.mintVesting(start, dur, amt);
        address rogue = address(0xB0B);

        // view vesting info publicly
        JEXAVestingNFT.VestingPosition memory p = vest.vestingInfo(id);
        assertEq(p.startTime, start);
        assertEq(p.duration, dur);
        assertEq(p.amount, amt);
        assertEq(p.released, 0);

        // view vested and claimable amounts
        assertEq(vest.vestedAmount(id), 0);
        assertEq(vest.claimable(id), 0);

        // view tokenURI
        string memory uri = vest.tokenURI(id);
        assertTrue(bytes(uri).length > 0);
    }

    /// @notice Sentinel `_USE_CURRENT_TIMESTAMP` allows splitting after vesting has started
    function testSplitByDates_WithSentinelAfterStarted() public {
        // Set up a vesting that started 1 day ago, duration 2 days
        uint64 start = uint64(block.timestamp - 1 days);
        uint64 dur = 2 days;
        uint256 amt = 100 ether;
        vm.prank(admin);
        uint256 id = vest.mintVesting(start, dur, amt);

        // Admin should receive the already vested amount (50 ether)
        uint256 balBefore = jexa.balanceOf(admin);

        uint64[] memory ts = new uint64[](2);
        ts[0] = uint64(1438226773); // sentinel = Ethereum genesis
        ts[1] = start + dur;       // original end

        vm.prank(admin);
        uint256[] memory ids = vest.splitByDates(id, ts);
        assertEq(ids.length, 1);
        assertEq(jexa.balanceOf(admin) - balBefore, 50 ether);

        JEXAVestingNFT.VestingPosition memory p = vest.vestingInfo(ids[0]);
        assertEq(p.startTime, uint64(block.timestamp));
        assertEq(p.duration, 1 days);
        assertEq(p.amount, 50 ether);
    }

    /*──────────────────────── edge-case splits ─────────────────────────*/
    function testSplitByDates_NothingToSplitReverts() public {
        uint64 start = uint64(block.timestamp - 2 days);
        uint64 dur = 1 days;
        vm.prank(admin);
        uint256 id = vest.mintVesting(start, dur, 10 ether);
        // all tokens vested
        vm.warp(start + dur + 1);
        uint64[] memory ts = new uint64[](2);
        ts[0] = uint64(block.timestamp);
        ts[1] = uint64(block.timestamp + 1 days);
        vm.prank(admin);
        vm.expectRevert(JEXAVestingNFT.NothingToSplit.selector);
        vest.splitByDates(id, ts);
    }

    function testSplitByShares_NothingToSplitReverts() public {
        uint64 start = uint64(block.timestamp - 2 days);
        uint64 dur = 1 days;
        vm.prank(admin);
        uint256 id = vest.mintVesting(start, dur, 40 ether);
        vm.warp(start + dur + 1);
        uint32[] memory shares = new uint32[](2);
        shares[0] = 1;
        shares[1] = 1;
        vm.prank(admin);
        vm.expectRevert(JEXAVestingNFT.NothingToSplit.selector);
        vest.splitByShares(id, shares);
    }

    function testSplitByAmounts_NothingToSplitReverts() public {
        uint64 start = uint64(block.timestamp - 2 days);
        uint64 dur = 1 days;
        vm.prank(admin);
        uint256 id = vest.mintVesting(start, dur, 30 ether);
        vm.warp(start + dur + 1);
        uint256[] memory parts = new uint256[](2);
        parts[0] = 15 ether;
        parts[1] = 15 ether;
        vm.prank(admin);
        vm.expectRevert(JEXAVestingNFT.NothingToSplit.selector);
        vest.splitByAmounts(id, parts);
    }

    function testSplitByAmounts_AfterStartedReverts() public {
        uint64 start = uint64(block.timestamp - 1 days);
        uint64 dur = 3 days;
        vm.prank(admin);
        uint256 id = vest.mintVesting(start, dur, 20 ether);
        uint256[] memory parts = new uint256[](2);
        parts[0] = 10 ether;
        parts[1] = 10 ether;
        vm.prank(admin);
        vm.expectRevert(JEXAVestingNFT.InvalidTimestamps.selector);
        vest.splitByAmounts(id, parts);
    }
}
