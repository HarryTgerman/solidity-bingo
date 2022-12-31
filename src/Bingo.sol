pragma solidity 0.8.17;

import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";

contract Bingo is ReentrancyGuard {
    using SafeERC20 for IERC20;
    // Parameters
    uint32 public minimumJoinDuration;
    uint32 public minimumTurnDuration;
    uint128 public entryFee;

    uint32 public CurrentGame;

    // ERC20 token
    IERC20 public token;

    // Admin
    address public admin;

    mapping(uint32 => Game) public games;
    mapping(bytes32 => uint8[25]) playerBoard;
    mapping(bytes32 => bool) players;
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
    }

    // errors
    error NotAdmin();
    error NotPlayer();
    error JoinDurationPassed();
    error GameEnded();
    error GameHasStarted();
    error MinimumJoinDurationNotPassed();
    error MinimumTurnDurationNotPassed();
    error NotEnoughNumbersDrawn();
    error NoNumbersDrawn();
    error GameDoesNotExist();
    error PlayerAlreadyJoined();

    // Events
    event GameStarted(uint32 indexed gameId, uint256 startTime, uint64 endTime);
    event NumberDrawn(uint32 indexed gameId, uint8 number);
    event PlayerJoined(
        address indexed player,
        uint32 indexed gameId,
        uint8[25] board
    );
    event PlayerLeft(address indexed player, uint32 indexed gameId);
    event PlayerWon(
        address indexed player,
        uint32 indexed gameId,
        uint256 amountWon
    );

    constructor(address _token) public {
        admin = msg.sender;
        token = IERC20(_token);
    }

    // get game info
    function getGame(uint32 _gameId)
        public
        view
        returns (
            uint64 startTime,
            uint64 endTime,
            uint64 lastDrawTime,
            bool ended,
            uint256 pot,
            address winner,
            uint8[] memory numbersDrawn
        )
    {
        Game storage game = games[_gameId];
        return (
            game.startTime,
            game.endTime,
            game.lastDrawTime,
            game.ended,
            game.pot,
            game.winner,
            game.numbersDrawn
        );
    }

    //get player board
    function getPlayerBoard(uint32 _gameId, address _player)
        public
        view
        returns (uint8[25] memory)
    {
        bytes32 playerGameId = hashPlayerGameId(_gameId, _player);
        return playerBoard[playerGameId];
    }

    // get if player in game
    function getPlayerInGame(uint32 _gameId, address _player)
        public
        view
        returns (bool)
    {
        bytes32 playerGameId = hashPlayerGameId(_gameId, _player);
        return players[playerGameId];
    }

    // get numbers drawn in a game
    function getNumbersDrawn(uint32 _gameId)
        public
        view
        returns (uint8[] memory)
    {
        Game storage game = games[_gameId];
        return game.numbersDrawn;
    }

    // get player winnings in all games
    function getPlayerWinnings(address _player)
        public
        view
        returns (uint256 winnings)
    {
        uint32[] memory playerGamesArray = playerGames[_player];
        for (uint256 i = 0; i < playerGamesArray.length; i++) {
            uint32 gameId = playerGamesArray[i];
            Game storage game = games[gameId];
            if (game.winner == _player) {
                winnings += game.pot;
            }
        }
    }

    // Change the game parameters
    function updateParams(
        uint32 _minimumJoinDuration,
        uint32 _minimumTurnDuration,
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
        uint32 currentGame = CurrentGame;
        Game storage game = games[currentGame + 1];
        game.startTime = uint64(block.timestamp);
        game.endTime = uint64(block.timestamp) + minimumJoinDuration;
        CurrentGame++;
        emit GameStarted(
            currentGame++,
            uint64(block.timestamp),
            uint64(block.timestamp) + minimumJoinDuration
        );
    }

    // Draw a number and mark it on all players' boards
    function drawNumber(uint32 _gameId) public {
        if (_gameId > CurrentGame) {
            revert GameDoesNotExist();
        }
        Game storage game = games[_gameId];
        if (game.ended) {
            revert GameEnded();
        }
        if (block.timestamp < uint256(game.endTime)) {
            revert MinimumJoinDurationNotPassed();
        }
        if (
            block.timestamp < uint256((game.lastDrawTime + minimumTurnDuration))
        ) {
            revert MinimumTurnDurationNotPassed();
        }

        uint8 number = uint8(
            uint256(
                bytes32(
                    keccak256(abi.encodePacked(blockhash(block.number - 1)))
                )
            )
        );
        game.numbersDrawn.push(number);
        game.lastDrawTime = uint64(block.timestamp);
        // not checking for winning condition here to prevent unbounded loops (run out of gas)
        emit NumberDrawn(_gameId, number);
    }

    // Mark the board of a player and check if they have won
    function checkBoard(uint32 _gameId, address _player) public nonReentrant {
        if (_gameId > CurrentGame) {
            revert GameDoesNotExist();
        }
        Game memory game = games[_gameId];
        bytes32 playerGameId = hashPlayerGameId(_gameId, _player);

        if (game.ended) {
            revert GameEnded();
        }
        if (!players[playerGameId]) {
            revert NotPlayer();
        }
        if (block.timestamp < uint256(game.endTime)) {
            revert MinimumJoinDurationNotPassed();
        }
        if (game.numbersDrawn.length == 0) {
            revert NoNumbersDrawn();
        }
        if (game.numbersDrawn.length < 4) {
            revert NotEnoughNumbersDrawn();
        }

        uint8[25] memory board = playerBoard[playerGameId];
        // Mark the numbers on the board
        for (uint256 i = 0; i < game.numbersDrawn.length; i++) {
            // todo exclude numbers that have already been marked

            for (uint256 j = 0; j < 25; j++) {
                if (board[j] == 0) {
                    continue;
                }
                if (board[j] == game.numbersDrawn[i]) {
                    board[j] = 0;
                }
            }
        }

        playerBoard[playerGameId] = board;

        if (checkWin(board)) {
            // Distribute the winnings to the winner
            games[_gameId].ended = true;
            games[_gameId].winner = _player;
            token.transfer(_player, game.pot);
            emit PlayerWon(_player, _gameId, game.pot);
        }
    }

    //  0  1  2  3  4
    //  5  6  7  8  9
    // 10 11 12 13 14
    // 15 16 17 18 19
    // 20 21 22 23 24

    // Check if any player has achieved a Bingo
    function checkWin(uint8[25] memory _board) internal pure returns (bool) {
        for (uint256 i = 0; i < 5; i++) {
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
        return false;
    }

    // Join the game
    function joinGame(uint32 _gameId) public payable nonReentrant {
        if (_gameId > CurrentGame) {
            revert GameDoesNotExist();
        }

        Game memory game = games[_gameId];
        bytes32 playerGameId = hashPlayerGameId(_gameId, msg.sender);

        if (game.ended) {
            revert GameEnded();
        }
        if (players[playerGameId]) {
            revert PlayerAlreadyJoined();
        }
        if (block.timestamp > game.endTime) {
            revert JoinDurationPassed();
        }

        token.transferFrom(msg.sender, address(this), entryFee);

        players[playerGameId] = true;
        games[_gameId].pot += entryFee;

        uint8[25] memory board;

        uint256 random = uint256(
            bytes32(keccak256(abi.encodePacked(blockhash(block.number - 1))))
        );

        for (uint256 i = 0; i < 25; i++) {
            if (i == 12) {
                board[i] = 0;
                continue;
            }
            uint8 number = uint8(random >> (i * 8));
            if (number == 0) {
                // 0 is not a valid number
                number = 88;
            }
            board[i] = number;
        }

        playerBoard[playerGameId] = board;

        playerGames[msg.sender].push(_gameId);

        emit PlayerJoined(msg.sender, _gameId, board);
    }

    // Leave the game
    function leaveGame(uint32 _gameId) external nonReentrant {
        if (_gameId > CurrentGame) {
            revert GameDoesNotExist();
        }
        Game memory game = games[_gameId];
        bytes32 playerGameId = hashPlayerGameId(_gameId, msg.sender);

        if (!players[playerGameId]) {
            revert NotPlayer();
        }
        if (game.endTime < uint64(block.timestamp)) {
            revert GameHasStarted();
        }

        players[playerGameId] = false;
        games[_gameId].pot -= entryFee;
        uint32[] memory localPlayerGames = playerGames[msg.sender];
        // remove the game from the player's list of games
        for (uint256 i = 0; i < localPlayerGames.length; i++) {
            if (localPlayerGames[i] == _gameId) {
                playerGames[msg.sender][i] = playerGames[msg.sender][
                    localPlayerGames.length - 1
                ];
                playerGames[msg.sender].pop();
                break;
            }
        }
        token.transfer(msg.sender, entryFee);

        emit PlayerLeft(msg.sender, _gameId);
    }

    // hash player game id
    function hashPlayerGameId(uint32 _gameId, address _player)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(_gameId, _player));
    }
}
