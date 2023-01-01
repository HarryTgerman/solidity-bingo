// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {Bingo} from "../src/Bingo.sol";
import {MockERC20} from "./Mock/MockERC20.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";

contract TestBingo is Test {
    MockERC20 public erc20;
    Bingo public bingo;

    address playerOne = address(0x0000000000000000000000000000000000000001);
    address playerTwo = address(0x0000000000000000000000000000000000000002);
    address playerThree = address(0x0000000000000000000000000000000000000003);
    address playerFour = address(0x0000000000000000000000000000000000000004);
    address playerFive = address(0x0000000000000000000000000000000000000005);

    // Parameters
    uint32 public minimumJoinDuration;
    uint32 public minimumTurnDuration;
    uint128 public entryFee;

    function setUp() public {
        // start at block 100 to prevent arithmetic underflow
        vm.roll(100);
        erc20 = new MockERC20("Test", "TST");
        bingo = new Bingo(address(erc20));
        // minimumJoinDuration of 3 days;
        // minimumTurnDuration of 10 minutes;
        // entryFee of 10 tokens;
        minimumJoinDuration = 259200;
        minimumTurnDuration = 600;
        entryFee = 1 ether;
        bingo.updateParams(minimumJoinDuration, minimumTurnDuration, entryFee);

        // Mint 100 tokens for each player
        erc20.mint(playerOne, 100 ether);
        erc20.mint(playerTwo, 100 ether);
        erc20.mint(playerThree, 100 ether);
        erc20.mint(playerFour, 100 ether);
        erc20.mint(playerFive, 100 ether);

        // Approve 100 tokens for each player
        vm.startPrank(playerOne);
        erc20.approve(address(bingo), 100 ether);
        vm.stopPrank();
        vm.startPrank(playerTwo);
        erc20.approve(address(bingo), 100 ether);
        vm.stopPrank();
        vm.startPrank(playerThree);
        erc20.approve(address(bingo), 100 ether);
        vm.stopPrank();
        vm.startPrank(playerFour);
        erc20.approve(address(bingo), 100 ether);
        vm.stopPrank();
        vm.startPrank(playerFive);
        erc20.approve(address(bingo), 100 ether);
        vm.stopPrank();
    }

    function testAdminUpdatesParams() public {
        bingo.updateParams(120, 10, 1 ether);
        assertEq(bingo.minimumJoinDuration(), 120);
        assertEq(bingo.minimumTurnDuration(), 10);
        assertEq(bingo.entryFee(), 1 ether);
    }

    function testNonAdminCannotUpdateParams() public {
        vm.startPrank(playerOne);
        vm.expectRevert(abi.encodeWithSignature("NotAdmin()"));
        bingo.updateParams(120, 10, 1 ether);
        vm.stopPrank();
    }

    function testStartGame() public {
        bingo.startGame();

        (
            uint64 startTime,
            uint64 endTime,
            uint64 lastDrawTime,
            bool ended,
            uint256 pot,
            address winner,
            uint8[] memory numbersDrawn
        ) = bingo.getGame(1);

        assertEq(uint256(startTime), block.timestamp);
        assertEq(uint256(endTime), block.timestamp + minimumJoinDuration);
        assertEq(lastDrawTime, 0);
        assertEq(pot, 0);
        assertEq(winner, address(0));
        assertEq(numbersDrawn.length, 0);
        assert(ended == false);
    }

    function testDrawNumber() public {
        helperStartGame();

        vm.expectRevert(abi.encodeWithSignature("GameDoesNotExist()"));
        bingo.drawNumber(10);

        uint32 gameId = bingo.CurrentGame();
        vm.expectRevert(
            abi.encodeWithSignature("MinimumJoinDurationNotPassed()")
        );
        bingo.drawNumber(gameId);

        vm.warp(block.timestamp + minimumJoinDuration + 1);
        bingo.drawNumber(gameId);
        assertEq(bingo.getNumbersDrawn(1).length, 1);

        vm.expectRevert(
            abi.encodeWithSignature("MinimumTurnDurationNotPassed()")
        );
        bingo.drawNumber(gameId);

        vm.warp(
            block.timestamp + minimumJoinDuration + 1 + minimumTurnDuration
        );
        bingo.drawNumber(gameId);
        assertEq(bingo.getNumbersDrawn(1).length, 2);

        vm.warp(
            block.timestamp + minimumJoinDuration + 1 + minimumTurnDuration * 2
        );
        bingo.drawNumber(gameId);
        assertEq(bingo.getNumbersDrawn(1).length, 3);
    }

    function testJoinGame() public {
        uint256 playerOneBalance = erc20.balanceOf(playerOne);
        helperStartGameSingle();
        bool playerOneJoined = bingo.getPlayerInGame(1, playerOne);
        assert(playerOneJoined);
        uint256 playerOneBalanceAfter = erc20.balanceOf(playerOne);
        assertEq(playerOneBalanceAfter, playerOneBalance - entryFee);
        assertEq(erc20.balanceOf(address(bingo)), entryFee);
        uint8[25] memory playerOneBoard = bingo.getPlayerBoard(1, playerOne);
        assertEq(playerOneBoard.length, 25);
        assertEq(playerOneBoard[12], 0);
    }

    function testLeaveGame() public {
        uint256 playerOneBalance = erc20.balanceOf(playerOne);
        helperStartGameSingle();
        vm.startPrank(playerOne);
        // revert if game does not exist
        vm.expectRevert(abi.encodeWithSignature("GameDoesNotExist()"));
        bingo.leaveGame(10);
        // revert if player is not in game
        bingo.startGame();
        vm.expectRevert(abi.encodeWithSignature("NotPlayer()"));
        bingo.leaveGame(2);
        // revert if game has started
        vm.warp(block.timestamp + minimumJoinDuration + 2);
        vm.expectRevert(abi.encodeWithSignature("GameHasStarted()"));
        bingo.leaveGame(1);

        // warp back to before game started
        // tests starts at timestamp 0
        vm.warp(1);
        bingo.leaveGame(1);
        bool playerOneJoined = bingo.getPlayerInGame(1, playerOne);
        assert(playerOneJoined == false);

        uint256 playerOneBalanceAfter = erc20.balanceOf(playerOne);
        assertEq(playerOneBalanceAfter, playerOneBalance);
        assertEq(erc20.balanceOf(address(bingo)), 0);

        vm.stopPrank();
    }

    function testCheckBoard() public {
        helperStartGameSingle();
        // revert if game does not exist
        vm.expectRevert(abi.encodeWithSignature("GameDoesNotExist()"));
        bingo.checkBoard(10, playerOne);
        // revert if player is not in game
        bingo.startGame();
        vm.expectRevert(abi.encodeWithSignature("NotPlayer()"));
        bingo.checkBoard(2, playerOne);
        // revert if game has not started
        vm.expectRevert(
            abi.encodeWithSignature("MinimumJoinDurationNotPassed()")
        );
        bingo.checkBoard(1, playerOne);

        // revert if no numbers have been drawn
        vm.warp(block.timestamp + minimumJoinDuration + 1);
        vm.expectRevert(abi.encodeWithSignature("NoNumbersDrawn()"));
        bingo.checkBoard(1, playerOne);
        vm.warp(block.timestamp - minimumJoinDuration - 1);
        // revert if not enough numbers have been drawn
        helperDrawNumbers(1, 1);
        vm.expectRevert(abi.encodeWithSignature("NotEnoughNumbersDrawn()"));
        bingo.checkBoard(1, playerOne);

        helperDrawNumbers(1, 5);
        bingo.checkBoard(1, playerOne);

        // draw numbers until player one wins
        (, , , , , address winner, ) = bingo.getGame(1);
        uint256 j = 0;
        // vm.roll(123141);
        // vm.roll(2321);
        vm.roll(2343);

        while (winner != playerOne && j < 300) {
            vm.warp(block.timestamp + minimumTurnDuration);
            vm.roll(block.number + 1);

            bingo.drawNumber(1);
            bingo.checkBoard(1, playerOne);
            (, , , , , address winnerTemp, ) = bingo.getGame(1);

            if (winnerTemp == playerOne) {
                winner = winnerTemp;
            }
            j++;
        }

        // helperDrawNumbers(1, 300);
        // bingo.checkBoard(1, playerOne);
        uint8[25] memory playerOneBoard = bingo.getPlayerBoard(1, playerOne);

        // user --vvvv to see full array of player and drawn numbers
        uint8[] memory numbers = bingo.getNumbersDrawn(1);
        console.log("numbers drawn", numbers.length);

        // check if playerOne is winner
        assertEq(winner, playerOne);
    }

    function helperStartGameSingle() internal {
        bingo.startGame();
        vm.startPrank(playerOne);
        uint32 gameId = bingo.CurrentGame();
        bingo.joinGame(gameId);
        vm.stopPrank();
    }

    function helperStartGame() internal {
        bingo.startGame();
        vm.startPrank(playerOne);
        bingo.joinGame(1);
        vm.stopPrank();
        vm.startPrank(playerTwo);
        bingo.joinGame(1);
        vm.stopPrank();
        vm.startPrank(playerThree);
        bingo.joinGame(1);
        vm.stopPrank();
        vm.startPrank(playerFour);
        bingo.joinGame(1);
        vm.stopPrank();
        vm.startPrank(playerFive);
        bingo.joinGame(1);
        vm.stopPrank();
    }

    function helperDrawNumbers(uint32 gameId, uint256 numberOfDraws) internal {
        vm.warp(block.timestamp + minimumJoinDuration + 1);
        for (uint256 i = 0; i < numberOfDraws; i++) {
            vm.warp(block.timestamp + minimumTurnDuration);
            vm.roll(block.number + 1);
            bingo.drawNumber(gameId);
        }
    }
}
