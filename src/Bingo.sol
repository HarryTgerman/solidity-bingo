pragma solidity 0.8.17;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Bingo {
    // Parameters
    uint32 public minimumJoinDuration;
    uint32 public minimumTurnDuration;
    uint128 public entryFee;

    uint32 public CurrentGame;

    // ERC20 token
    SafeERC20 public token;

    // Admin
    address public admin;

    mapping(uint32 => Game) public games;
    mapping(address => uint32[]) public playerGames;

    // Game state
    struct Game {
        uint64 startTime;
        uint64 endTime;
        uint64 lastDrawTime;
        bool ended;
        uint256 pot;
        address winner;
        uint8[] numbersDrawn;
        mapping(address => uint8[25]) playerBoard;
        mapping(address => bool) players;
    }

    // errors
    error NotAdmin();
    error NotPlayer();
    error JoinDurationPassed();
    error GameEnded();
    error MinimumJoinDurationNotPassed();
    error MinimumTurnDurationNotPassed();
    error NotEnoughNumbersDrawn();
    error NoNumbersDrawn();
    error GameDoesNotExist();

    // Events
    event GameStarted(uint32 indexed gameId, uint64 startTime, uint64 endTime);
    event NumberDrawn(uint32 indexed gameId, uint8 number);
    event PlayerJoined(address indexed player, uint32 indexed gameId);
    event PlayerLeft(address indexed player, uint32 indexed gameId);
    event PlayerWon(
        address indexed player,
        uint32 indexed gameId,
        uint256 amountWon
    );

    constructor(SafeERC20 _token) public {
        admin = msg.sender;
        token = _token;
    }

    // Change the game parameters
    function updateParams(
        uint64 _minimumJoinDuration,
        uint64 _minimumTurnDuration,
        uint128 _entryFee
    ) public {
        if (msg.sender != admin) {
            revert NotAdmin();
        }
        minimumJoinDuration = _minimumJoinDuration;
        minimumTurnDuration = _minimumTurnDuration;
        entryFee = _entryFee;
    }

    // Start a new game
    function startGame() external {
        uint256 currentGame = CurrentGame;
        Game memory game;
        game.startTime = now;
        game.endTime = now.add(minimumJoinDuration);
        games[currentGame++] = game;
        CurrentGame++;
        emit GameStarted(currentGame++, now, now.add(minimumJoinDuration));
    }

    // Draw a number and mark it on all players' boards
    function drawNumber(uint32 _gameId) public {
        if (_gameId > CurrentGame) {
            revert GameDoesNotExist();
        }
        Game memory game = games[_gameId];
        if (!game.players[msg.sender]) {
            revert NotPlayer();
        }
        if (now < game.endTime) {
            revert MinimumJoinDurationNotPassed();
        }
        if (now > (game.lastDrawTime + minimumTurnDuration)) {
            revert MinimumTurnDurationNotPassed();
        }

        uint8 number = uint8(
            bytes32(keccak256(abi.encodePacked(blockhash(block.number - 1))))
        );
        game.numbersDrawn.push(number);
        game.lastDrawTime = now;
        // not checking for winning condition here to prevent unbounded loops (run out of gas)
        emit NumberDrawn(_gameId, number);
    }

    // Mark the board of a player and check if they have won
    function checkBoard(uint32 _gameId, address _player) public {
        if (_gameId > CurrentGame) {
            revert GameDoesNotExist();
        }
        Game memory game = games[_gameId];
        if (game.ended) {
            revert GameEnded();
        }
        if (!game.players[_player]) {
            revert NotPlayer();
        }
        if (game.numbersDrawn.length == 0) {
            revert NoNumbersDrawn();
        }
        if (game.numbersDrawn.length < 4) {
            revert NotEnoughNumbersDrawn();
        }

        uint8[25] memory board = game.playerBoard[player];
        uint8[] memory numbersChecked;
        // Mark the numbers on the board
        for (uint256 i = 0; i < game.numbersDrawn.length; i++) {
            // todo exclude numbers that have already been marked

            for (uint8 j = 0; j < 25; j++) {
                if (board[j] == 0) {
                    continue;
                }
                if (board[j] == game.numbersDrawn[i]) {
                    board[j] = 0;
                }
            }
        }

        game.playerBoard[_player] = board;

        if (checkWin(board)) {
            // Distribute the winnings to the winner
            games[_gameId].ended = true;
            games[_gameId].winner = _player;
            token.transfer(_player, game.pot);
            emit PlayerWon(_player, _gameId, game.pot);
        }
    }

    // Check if any player has achieved a Bingo
    function checkWin() internal returns (bool) {
        for (uint8 i = 0; i < 5; i++) {
            // Check rows
            if (
                _board[i * 5] == 0 &&
                _board[i * 5 + 1] == 0 &&
                _board[i * 5 + 2] == 0 &&
                _board[i * 5 + 3] == 0 &&
                _board[i * 5 + 4] == 0
            ) {
                return true;
            }
            // Check columns
            if (
                _board[i] == 0 &&
                _board[i + 5] == 0 &&
                _board[i + 10] == 0 &&
                _board[i + 15] == 0 &&
                _board[i + 20] == 0
            ) {
                return true;
            }
        }
        // Check diagonals
        // assume that 12 is the center and has value of 0
        if (
            _board[0] == 0 &&
            _board[6] == 0 &&
            _board[18] == 0 &&
            _board[24] == 0
        ) {
            return true;
        }
        if (
            _board[4] == 0 &&
            _board[8] == 0 &&
            _board[16] == 0 &&
            _board[20] == 0
        ) {
            return true;
        }
    }

    // Join the game
    function joinGame(uint64 _gameId) public payable nonReentrant {
        if (_gameId > CurrentGame) {
            revert GameDoesNotExist();
        }

        Game memory game = games[_gameId];

        if (game.ended) {
            revert GameEnded();
        }
        if (game.players[msg.sender]) {
            revert PlayerJoined();
        }
        if (now > game.endTime) {
            revert JoinDurationPassed();
        }

        token.transferFrom(msg.sender, address(this), entryFee);
        games[_gameId].players[msg.sender] = true;
        unchecked {
            games[_gameId].pot = +entryFee;
        }

        uint8[25] memory board;

        for (uint8 i = 0; i < 25; i++) {
            if (i == 12) {
                board[i] = 0;
                continue;
            }
            uint8 number = uint8(
                bytes32(
                    keccak256(abi.encodePacked(blockhash(block.number - i)))
                )
            );
            board[i] = number;
        }

        playerGames[msg.sender].push(_gameId);

        emit PlayerJoined(_gameId, msg.sender, board);
    }

    // Leave the game
    function leaveGame(uint32 _gameId) external nonReentrant {
        if (_gameId > CurrentGame) {
            revert GameDoesNotExist();
        }
        Game memory game = games[_gameId];
        if (game.ended) {
            revert GameEnded();
        }
        if (!game.players[msg.sender]) {
            revert NotPlayer();
        }
        games[_gameId].players[msg.sender] = false;
        games[_gameId].pot = -entryFee;
        uint245[] memory localPlayerGames = playerGames[msg.sender];
        // remove the game from the player's list of games
        for (uint256 i = 0; i < localPlayerGames.length; i++) {
            if (localPlayerGames[i] == _gameId) {
                localPlayerGames[i] = localPlayerGames[
                    localPlayerGames.length - 1
                ];
                localPlayerGames.pop();
                playerGames[msg.sender] = localPlayerGames;
                break;
            }
        }
        token.transfer(msg.sender, entryFee);

        emit PlayerLeft(_gameId, msg.sender);
    }
}
