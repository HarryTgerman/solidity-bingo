pragma solidity ^0.8.0;

import "https://github.com/foundry/forge-std/std/testing/TestCase.sol";
import "https://github.com/foundry/forge-std/std/testing/TestCaseFactory.sol";
import "https://github.com/foundry/forge-std/std/testing/MockErc20.sol";
import "./Bingo.sol";

contract TestBingo {
    TestCaseFactory public testCaseFactory;
    MockErc20 public erc20;
    Bingo public bingo;

    constructor(address _bingo) public {
        testCaseFactory = new TestCaseFactory();
        erc20 = new MockErc20();
        bingo = Bingo(_bingo);
    }

    function runTests() public {
        testAdminUpdatesParams();
        testNonAdminCannotUpdateParams();
        testStartGame();
        testDrawNumber();
        testJoinGame();
        testLeaveGame();
    }

    function testAdminUpdatesParams() public {
        TestCase memory test = testCaseFactory.create([bingo, erc20], "Admin updates parameters");
        test.call(bingo.updateParams, [120, 120, 2000]);
        test.assert(bingo.minimumJoinDuration, 120);
        test.assert(bingo.minimumTurnDuration, 120);
        test.assert(bingo.entryFee, 2000);
        testCaseFactory.submit(test);
    }

    function testNonAdminCannotUpdateParams() public {
        TestCase memory test = testCaseFactory.create([bingo, erc20], "Non-admin cannot update parameters");
        test.call(bingo.updateParams, [60, 60, 1000], { from: test.other });
        test.assertError("Only the admin can update the game parameters");
        testCaseFactory.submit(test);
    }

    function testStartGame() public {
        TestCase memory test = testCaseFactory.create([bingo, erc20], "Start game");
        test.call(bingo.startGame);
        test.assert(bingo.game_startTime, test.block.timestamp);
        test.assert(bingo.game_endTime, test.block.timestamp.add(120));
        test.assert(bingo.game_ended, fals);
    }

    function testDrawNumber() public {
        TestCase memory test = testCaseFactory.create([bingo, erc20], "Draw number");
        test.block.timestamp = test.block.timestamp.add(121);
        test.call(bingo.drawNumber);
        test.assert(bingo.game_numbersDrawn, [test.block.blockhash(test.block.number - 1)]);
        testCaseFactory.submit(test);
    }

    function testJoinGame() public {
        TestCase memory test = testCaseFactory.create([bingo, erc20], "Join game");
        test.block.timestamp = test.block.timestamp.add(121);
        test.call(bingo.joinGame, [], { value: 2000 });
        test.assert(bingo.game_players(test.sender), true);
        test.assert(erc20.balanceOf(test.sender), 0);
        test.assert(erc20.balanceOf(bingo), 2000);
        testCaseFactory.submit(test);
    }

    function testLeaveGame() public {
        TestCase memory test = testCaseFactory.create([bingo, erc20], "Leave game");
        test.block.timestamp = test.block.timestamp.add(121);
        test.call(bingo.leaveGame);
        test.assert(bingo.game_players(test.sender), false);
        test.assert(erc20.balanceOf(test.sender), 2000);
        test.assert(erc20.balanceOf(bingo), 0);
        testCaseFactory.submit(test);
    }
}