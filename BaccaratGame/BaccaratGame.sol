// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

// Open Zeppelin libraries for controlling upgradability and access.
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

contract BaccaratGame is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IERC20Upgradeable public token;
    address public tokenDistributor;
    mapping(address => bool) public adminLists;
    mapping(string => SwapData) public swapDatas;

    ///@dev swap limit,
    uint256 public swapDelay;
    uint256 public maxSwapAmount;
    mapping(address => uint256) public lastGSwap;
    mapping(string => bool) public invalidTx;

    //bacarat game data
    uint8[] public cards;
    int8[] public playerCards;
    int8[] public dealerCards;
    int8 public sumCardPlayer;
    int8 public sumCardDealer;

    uint256 public reward;
    uint8 public result_win;
    uint256 public maxBaccaratBetAmount;
    uint256 public minBaccaratBetAmount;

    //index game const
    uint8 public constant BANKER = 1;
    uint8 public constant PLAYER = 0;
    uint8 public constant TIE = 2;
    uint8 public constant PP = 3;
    uint8 public constant BP = 4;

    struct SwapData {
        address user;
        uint256 amountIn;
        uint256 amountOut;
        uint256 swapTime;
    }

    event resultBaccarat(
        uint8 result_win_,
        uint8 result_playerPair_,
        uint8 result_bankerPair_,
        int8[] playerCards_,
        int8[] dealerCards_,
        uint256 reward_,
        int8 sumCardPlayer_,
        int8 sumCardDealer_
    );

    event playgameDataUser(
        address user,
        uint256 amount,
        uint256 TotalPrizeValue,
        uint256 playTime
    );

    ///@dev no constructor in upgradable contracts. Instead we have initializers
    function initialize(IERC20Upgradeable token_) public initializer {
        ///@dev as there is no constructor, we need to initialise the OwnableUpgradeable explicitly
        __Ownable_init();
        token = token_;
        tokenDistributor = msg.sender;
        adminLists[msg.sender] = true;
        swapDelay = 1; // 1s
        maxSwapAmount = 0;
        reward = 0;
        result_win = 0;
        maxBaccaratBetAmount = 100000000000000000000000; //100k
        minBaccaratBetAmount = 100000000000000000000; // 100
    }

    ///@dev required by the OZ UUPS module
    function _authorizeUpgrade(address) internal override onlyOwner {}

    /** ==================== EVENT ============================ */
    event RoleEvent(string role, address user, bool status);

    event SwapEvent(
        string internalTx,
        address user,
        uint256 amount,
        uint256 BaccaratGame,
        bytes userSignature
    );

    event CancelEvent(
        string internalTx,
        address user,
        uint256 amount,
        bytes signature
    );

    event CancelWithAuthorityEvent(string[] internalTx);

    /** ==================== CONFIG ========================= */
    function setAdmin(address user_, bool status_) external onlyOwner {
        adminLists[user_] = status_;
        emit RoleEvent("set_admin", user_, status_);
    }

    modifier onlyAdmins() {
        require(
            adminLists[msg.sender] == true || msg.sender == owner(),
            "Authorization: Require admin role"
        );
        _;
    }

    function setTokenDistributor(address user_) external onlyAdmins {
        tokenDistributor = user_;
        emit RoleEvent("set_token_distributor", user_, true);
    }

    function setExchangeToken(IERC20Upgradeable token_) external onlyAdmins {
        token = token_;
        emit RoleEvent("set_exchange_token", address(token), true);
    }

    function setSwapDelay(uint256 swapDelay_) external onlyAdmins {
        swapDelay = swapDelay_;
    }

    function setLimitBetAmount(
        uint256 maxBaccaratBetAmount_,
        uint256 minBaccaratBetAmount_
    ) external onlyAdmins {
        maxBaccaratBetAmount = maxBaccaratBetAmount_;
        minBaccaratBetAmount = minBaccaratBetAmount_;
        emit RoleEvent("set_Limit_Bet_Amount", address(token), true);
    }

    function setMaxSwapAmount(uint256 maxSwapAmount_) external onlyAdmins {
        maxSwapAmount = maxSwapAmount_;
    }

    function cancelTxWithAuthority(
        string[] memory internalTxs_
    ) external onlyAdmins {
        for (uint256 i = 0; i < internalTxs_.length; i++) {
            invalidTx[internalTxs_[i]] = true;
        }
        emit CancelWithAuthorityEvent(internalTxs_);
    }

    /** ========================== MAIN FUNCTIONS ========================= */
    modifier validTx(string memory internalTx_) {
        require(!invalidTx[internalTx_], "Tx state: Cancelled");
        _;
    }

    modifier swapDataNotExisted(string memory internalTx_) {
        require(
            swapDatas[internalTx_].swapTime == 0,
            "Tx state: Swap data existed"
        );
        _;
    }

    function indexOf(
        uint8[] memory arr,
        uint8 searchFor
    ) internal pure returns (int8) {
        for (uint8 j = 0; j < arr.length; j++) {
            if (arr[j] == searchFor) {
                return int8(j);
            }
        }
        return -1;
    }

    function getGameCardsFromHash(
        string memory internalTx,
        uint256 amount_
    ) private {
        delete cards;
        while (true) {
            bytes32 hash = keccak256(
                abi.encodePacked(internalTx, amount_, block.timestamp)
            );

            uint8[] memory hash64 = new uint8[](64);
            for (uint8 y = 0; y < 32; y++) {
                uint8 b = uint8(hash[y]);
                uint8 hi = b / 16;
                uint8 lo = b - 16 * hi;
                hash64[y * 2] = hi;
                hash64[y * 2 + 1] = lo;
            }

            uint8 i = 0;
            while (i < hash64.length - 1) {
                uint8 rank = hash64[i];

                if (rank < 13) {
                    uint8 suit = hash64[i + 1] % 4;
                    rank = rank + suit * 13;
                    if (indexOf(cards, rank) < 0) {
                        cards.push(rank);
                        i += 2;
                    } else {
                        i += 1;
                    }
                } else {
                    i += 1;
                }

                if (cards.length == 6) {
                    break;
                }
            }

            if (cards.length == 6) break;
        }
    }

    function getCardRank(int8 playercard) private pure returns (int8 result_) {
        int8 b = playercard % 13;
        if (b > 10) return 0;
        else return b;
    }

    function playBaccaratGame(
        string memory internalTx_,
        address receiver_,
        uint256[] memory bet
    )
        external
        nonReentrant
        validTx(internalTx_)
        swapDataNotExisted(internalTx_)
    {
        //play game condition
        require(bet.length == 5, "playBaccaratGame: Wrong size of bet");
        uint256 sumBet = bet[0] + bet[1] + bet[2] + bet[3] + bet[4];

        require(
            sumBet <= maxBaccaratBetAmount,
            "Transfer amount exceeds max Bet"
        );
        require(
            sumBet >= minBaccaratBetAmount,
            "Transfer amount below min Bet"
        );
        getGameCardsFromHash(internalTx_, sumBet);
        _validateSwapData(receiver_, sumBet);
        require(
            token.balanceOf(tokenDistributor) >= sumBet * 2,
            "playBirdGame: Transfer amount exceeds balance"
        );
        require(
            token.allowance(tokenDistributor, address(this)) >= sumBet,
            "playBirdGame: Transfer amount exceeds allowance"
        );
        uint8 result_playerPair = 0;
        uint8 result_bankerPair = 0;
        reward = 0;
        result_win = 0;

        //transfer token from user to distributor
        token.safeTransferFrom(msg.sender, tokenDistributor, sumBet);

        playerCards = [-1, -1, -1];
        dealerCards = [-1, -1, -1];
        sumCardPlayer = -1;
        sumCardDealer = -1;

        //Pick card round
        playerCards[0] = int8(cards[0]);
        playerCards[1] = int8(cards[1]);
        sumCardPlayer =
            (getCardRank(playerCards[0]) + getCardRank(playerCards[1])) %
            10;

        dealerCards[0] = int8(cards[2]);
        dealerCards[1] = int8(cards[3]);
        sumCardDealer =
            (getCardRank(dealerCards[0]) + getCardRank(dealerCards[1])) %
            10;
        //Give card round
        bool exit = false;
        int8 c1 = -1;
        int8 c2 = -1;
        int8 c1_rank = -1;
        int8 c2_rank = -1;

        if (
            sumCardDealer == 8 ||
            sumCardDealer == 9 ||
            sumCardPlayer == 8 ||
            sumCardPlayer == 9
        ) {
            exit = true;
        } else {
            if (sumCardPlayer <= 5) {
                c1 = int8(cards[4]);
                playerCards[2] = c1;
                c1_rank = getCardRank(c1);
                sumCardPlayer = (c1_rank + sumCardPlayer) % 10;
            }

            if (sumCardDealer < 3) {
                c2 = int8(cards[5]);
                dealerCards[2] = c2;
                c2_rank = getCardRank(c2);
                sumCardDealer = (c2_rank + sumCardDealer) % 10;
            } else if (sumCardDealer == 3) {
                if ((c1 != -1 && c1_rank != 8) || c1 == -1) {
                    c2 = int8(cards[5]);
                    dealerCards[2] = c2;
                    c2_rank = getCardRank(c2);
                    sumCardDealer = (c2_rank + sumCardDealer) % 10;
                }
            } else if (sumCardDealer == 4) {
                if (
                    (c1 != -1 &&
                        c1_rank != 0 &&
                        c1_rank != 1 &&
                        c1_rank != 8 &&
                        c1_rank != 9) || c1 == -1
                ) {
                    c2 = int8(cards[5]);
                    dealerCards[2] = c2;
                    c2_rank = getCardRank(c2);
                    sumCardDealer = (c2_rank + sumCardDealer) % 10;
                }
            } else if (sumCardDealer == 5) {
                if (
                    (c1 != -1 &&
                        (c1_rank == 4 ||
                            c1_rank == 5 ||
                            c1_rank == 6 ||
                            c1_rank == 7)) || c1 == -1
                ) {
                    c2 = int8(cards[5]);
                    dealerCards[2] = c2;
                    c2_rank = getCardRank(c2);
                    sumCardDealer = (c2_rank + sumCardDealer) % 10;
                }
            } else if (sumCardDealer == 6) {
                if (c1 != -1 && (c1_rank == 6 || c1_rank == 7)) {
                    c2 = int8(cards[5]);
                    dealerCards[2] = c2;
                    c2_rank = getCardRank(c2);
                    sumCardDealer = (c2_rank + sumCardDealer) % 10;
                }
            }
        }

        uint256 totalReward = 0;
        if (sumCardDealer == sumCardPlayer) {
            result_win = TIE;
            totalReward += bet[TIE] * 10;
        } else if (sumCardDealer < sumCardPlayer) {
            result_win = PLAYER;
            totalReward += bet[PLAYER] * 2;
        } else {
            result_win = BANKER;
            totalReward += (bet[BANKER] * 195) / 100;
        }

        // check pair
        int8 r1 = playerCards[0] % 13;
        int8 r2 = playerCards[1] % 13;
        int8 r3 = playerCards[2] % 13;

        if (r1 == r2 || r1 == r3 || r2 == r3) {
            result_playerPair = PP;
            totalReward += bet[PP] * 16;
        }

        // -- pair banker
        r1 = dealerCards[0] % 13;
        r2 = dealerCards[1] % 13;
        r3 = dealerCards[2] % 13;

        if (r1 == r2 || r1 == r3 || r2 == r3) {
            result_bankerPair = BP;
            totalReward += bet[BP] * 16;
        }
        reward = (totalReward * 98) / 100;

        //check results and refund
        if (reward > 0)
            token.safeTransferFrom(tokenDistributor, msg.sender, reward);

        emit resultBaccarat(
            result_win,
            result_playerPair,
            result_bankerPair,
            playerCards,
            dealerCards,
            reward,
            sumCardPlayer,
            sumCardDealer
        );
        emit playgameDataUser(msg.sender, sumBet, reward, block.timestamp);
    }

    function _validateSwapData(address receiver_, uint256 amount_) private {
        // Check delay
        require(
            block.timestamp >= (lastGSwap[receiver_] + swapDelay),
            "playgame: Not to swap time yet"
        );

        if (maxSwapAmount != 0) {
            require(
                amount_ <= maxSwapAmount,
                "playgame: Swap amount exceed max limit"
            );
        }
        //update last swap time
        lastGSwap[receiver_] = block.timestamp;
    }

    function blockTime() external view returns (uint256) {
        return block.timestamp;
    }
}
