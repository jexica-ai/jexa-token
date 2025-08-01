// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {JEXAVestingNFT} from "../../contracts/JEXAVestingNFT.sol";

contract JEXAVestingNFT_Test is Test {
    ERC20Mock jexa;
    JEXAVestingNFT vest;

    address admin = address(0xA11);
    address alice = address(0xB00);
    address bob = address(0xC00);

    uint256 constant ONE_M = 1_000_000 ether;

    function setUp() public {
        // Set current time to May 15, 2025 (realistic timestamp)
        vm.warp(1_747_526_400); // May 15, 2025 00:00:00 UTC

        jexa = new ERC20Mock("Jexica AI", "JEXA");
        jexa.mint(admin, ONE_M);
        vest = new JEXAVestingNFT(address(jexa));

        vm.prank(admin);

        jexa.approve(address(vest), type(uint256).max);
    }

   /* ─────────────── constructor / mint validation ─────────────── */
   function testConstructorRevertsZeroAddress() public {
       vm.expectRevert(JEXAVestingNFT.ZeroAddress.selector);
       new JEXAVestingNFT(address(0));
   }

   function testMintZeroAmountReverts() public {
       vm.prank(admin);
       vm.expectRevert(JEXAVestingNFT.InvalidAmount.selector);
       vest.mintVesting(uint64(block.timestamp + 1 days), 1 days, 0);
   }

   function testMintZeroDurationReverts() public {
       vm.prank(admin);
       vm.expectRevert(JEXAVestingNFT.InvalidDuration.selector);
       vest.mintVesting(uint64(block.timestamp + 1 days), 0, 1 ether);
   }

   function testMintInsufficientBalanceReverts() public {
       address poor = address(0xD00);
       vm.startPrank(poor);
       jexa.approve(address(vest), 1 ether);
       vm.expectRevert();
       vest.mintVesting(uint64(block.timestamp + 1 days), 1 days, 1 ether);
       vm.stopPrank();
   }

    /* ─────────────── mint / release ─────────────── */

    function testMintAndRelease() public {
        uint64 start = uint64(block.timestamp + 1 days);
        uint64 dur = 30 days;
        uint256 amount = 1_000 ether;

        // mint
        vm.prank(admin);
        uint256 id = vest.mintVesting(start, dur, amount);

        // rewind to midpoint
        vm.warp(start + dur / 2);

        uint256 balBefore = jexa.balanceOf(admin);

        // release half
        vm.prank(admin);
        vest.release(id);

        assertEq(jexa.balanceOf(admin) - balBefore, amount / 2);

        // fast-forward to end
        vm.warp(start + dur + 1);

        // final release burns NFT
        vm.prank(admin);
        vest.release(id);

        // NFT must not exist
        vm.expectRevert();
        vest.ownerOf(id);
    }

    /* ─────────────── splitByDates ─────────────── */

    function testSplitByDates_DustSpread3Slices() public {
        uint64 start = uint64(block.timestamp + 1 days);
        uint64 dur = 10 days;
        uint256 amt = 99 ether + 1 wei; // deliberately non-divisible into 3 equal slices

        vm.prank(admin);
        uint256 id = vest.mintVesting(start, dur, amt);

        // timestamps: three equal slices; total dust = 1
        uint64[] memory ts = new uint64[](4);
        ts[0] = start + 2 days;
        ts[1] = start + 5 days;
        ts[2] = start + 8 days;
        ts[3] = start + 11 days;

        vm.prank(admin);
        uint256[] memory ids = vest.splitByDates(id, ts);

        assertEq(ids.length, 3);

        // slice 1 length = 3d, slice 2 = 3d, slice 3 = 3d
        uint256 a1 = vest.vestingInfo(ids[0]).amount;
        uint256 a2 = vest.vestingInfo(ids[1]).amount;
        uint256 a3 = vest.vestingInfo(ids[2]).amount;
        assertEq(a1 + a2 + a3, 99 ether + 1 wei);
        assertEq(a1, 33 ether);
        assertEq(a2, 33 ether);
        assertEq(a3, 33 ether + 1 wei);
    }

    function testSplitByDates_DustSpread4Slices() public {
        uint64 start = uint64(block.timestamp + 1 days);
        uint64 dur = 10 days;
        uint256 amt = 100 ether + 2 wei; // deliberately non-divisible into 4 equal slices

        vm.prank(admin);
        uint256 id = vest.mintVesting(start, dur, amt);

        // timestamps: four equal slices; total dust = 2
        uint64[] memory ts = new uint64[](5);
        ts[0] = start + 2 days;
        ts[1] = start + 4 days;
        ts[2] = start + 6 days;
        ts[3] = start + 8 days;
        ts[4] = start + 10 days; // last one is after end

        vm.prank(admin);
        uint256[] memory ids = vest.splitByDates(id, ts);

        assertEq(ids.length, 4);

        // slice 1 length = 2d, slice 2 = 2d, slice 3 = 2d, slice 4 = 2d
        uint256 a1 = vest.vestingInfo(ids[0]).amount;
        uint256 a2 = vest.vestingInfo(ids[1]).amount;
        uint256 a3 = vest.vestingInfo(ids[2]).amount;
        uint256 a4 = vest.vestingInfo(ids[3]).amount;
        assertEq(a1 + a2 + a3 + a4, 100 ether + 2 wei);
        assertEq(a1, 25 ether);
        assertEq(a2, 25 ether);
        assertEq(a3, 25 ether + 1 wei);
        assertEq(a4, 25 ether + 1 wei);
    }

    /* ─────────────── splitByAmounts ─────────────── */

    function testSplitByAmounts_PreVestingOnly() public {
        uint64 start = uint64(block.timestamp + 5 days);
        uint64 dur = 10 days;
        uint256 amt = 1_000 ether;

        vm.prank(admin);
        uint256 id = vest.mintVesting(start, dur, amt);

        uint256[] memory parts = new uint256[](2);
        parts[0] = 600 ether;
        parts[1] = 400 ether;

        vm.prank(admin);
        uint256[] memory ids = vest.splitByAmounts(id, parts);

        assertEq(ids.length, 2);
        uint256 a0 = vest.vestingInfo(ids[0]).amount;
        uint256 a1 = vest.vestingInfo(ids[1]).amount;
        assertEq(a0, parts[0]);
        assertEq(a1, parts[1]);

        // After vesting has started it must revert
        vm.warp(start + 1);
        vm.expectRevert();
        vest.splitByAmounts(ids[0], parts);
    }

    /* ─────────────── splitByShares  ─────────────── */

    function testSplitByShares_MidVesting() public {
        uint64 start = uint64(block.timestamp); // start now
        uint64 dur = 10 days;
        uint256 amt = 1_000 ether;

        vm.prank(admin);
        uint256 id = vest.mintVesting(start, dur, amt);

        // move 2 days, release vested (200)
        uint64 newStart = start + 2 days;
        vm.warp(newStart); // warp to start + 2 days
        
        vm.prank(admin);
        vest.release(id);

        uint32[] memory shares = new uint32[](3);
        shares[0] = 1;
        shares[1] = 1;
        shares[2] = 2;

        vm.prank(admin);
        uint256[] memory ids = vest.splitByShares(id, shares);
        assertEq(ids.length, 3);

        // each NFT must have the *same* new start = now, same end
        for (uint256 i; i < ids.length; ++i) {
            JEXAVestingNFT.VestingPosition memory p = vest.vestingInfo(ids[i]);
            uint64 s = p.startTime;
            uint64 d = p.duration;
            uint256 r = p.released;
            assertEq(s, newStart);
            assertEq(s + d, start + dur); // end unchanged
            assertEq(r, 0);
        }
        // shares: 1+1+2 → 800 remaining -> 200/200/400
        uint256 a0 = vest.vestingInfo(ids[0]).amount;
        uint256 a1 = vest.vestingInfo(ids[1]).amount;
        uint256 a2 = vest.vestingInfo(ids[2]).amount;
        assertEq(a0, 200 ether);
        assertEq(a1, 200 ether);
        assertEq(a2, 400 ether);
    }
}
