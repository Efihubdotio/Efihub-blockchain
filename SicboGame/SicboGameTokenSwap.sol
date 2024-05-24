// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

// Open Zeppelin libraries for controlling upgradability and access.
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract SicboGameTokenSwap is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IERC20Upgradeable public token;
    address public tokenDistributor; // wallet distribute tokens to user when user play game
    mapping(address => bool) public adminLists;
    mapping(string => SwapData) public swapDatas;

    ///@dev swap limit
    uint256 public swapDelay;
    uint256 public maxSwapAmount;
    mapping(address => uint256) public lastGSwap;
    mapping(string => bool) public invalidTx;

    struct SwapData {
        address user;
        uint256 amountIn;
        uint256 amountOut;
        uint256 swapTime;
    }

    uint16 public BIG_RATE;
    uint16 public PAIR_RATE;
    uint16 public TRIPLE_RATE;
    uint16 public TRIPLE_ANY_RATE;
    uint16 public EVEN_RATE;
    uint16 public TWO_DICE_RATE;
    uint8[] public SCORE_RATE;
    uint8[] public MATCH_DICE_RATE;
    uint256 public maxSicboBetAmount;
    uint256 public minSicboBetAmount;
    enum SicboConstant {
        BIG,
        SMALL,
        PAIR,
        TRIPLE_ANY,
        TRIPLE,
        SCORE,
        MATCH_DICE,
        EVEN,
        ODD,
        TWO_DICE
    }

    ///@dev no constructor in upgradable contracts. Instead we have initializers
    function initialize(IERC20Upgradeable token_) public initializer {
        ///@dev as there is no constructor, we need to initialise the OwnableUpgradeable explicitly
        __Ownable_init();

        token = token_;
        tokenDistributor = msg.sender;
        adminLists[msg.sender] = true;

        maxSicboBetAmount = 100000000000000000000000; //100k
        minSicboBetAmount = 100000000000000000000; // 100
        swapDelay = 1; // 5s
        maxSwapAmount = 0;
        BIG_RATE = 198;
        PAIR_RATE = 11;
        TRIPLE_RATE = 181;
        TRIPLE_ANY_RATE = 31;
        EVEN_RATE = 198;
        TWO_DICE_RATE = 6;
        SCORE_RATE = [
            0,
            0,
            0,
            0,
            61,
            31,
            18,
            13,
            9,
            7,
            7,
            7,
            7,
            9,
            13,
            18,
            31,
            61
        ];
        MATCH_DICE_RATE = [0, 2, 3, 4];
    }

    ///@dev required by the OZ UUPS module
    function _authorizeUpgrade(address) internal override onlyOwner {}

    /** ==================== EVENT ============================ */
    event RoleEvent(string role, address user, bool status);

    // token => point
    event SwapEvent(
        string internalTx,
        address user,
        uint256 amount,
        uint256 SicboGame,
        bytes userSignature
    );

    event CancelEvent(
        string internalTx,
        address user,
        uint256 amount,
        bytes signature
    );

    event playgameDataUser(
        address user,
        uint256 amount,
        uint256 TotalPrizeValue,
        uint256 playTime
    );

    event CancelWithAuthorityEvent(string[] internalTx);

    event resultSicbo(
        uint8[] resultSicbo,
        address player,
        uint256 amount,
        uint256 TotalPrizeValue
    );

    /** ==================== CONFIG ========================= */
    function setAdmin(address user_, bool status_) external onlyOwner {
        adminLists[user_] = status_;
        emit RoleEvent("set_admin", user_, status_);
    }

    function setRateValue(
        uint16 BIG_RATE_,
        uint16 PAIR_RATE_,
        uint16 TRIPLE_RATE_,
        uint16 TRIPLE_ANY_RATE_,
        uint16 EVEN_RATE_,
        uint16 TWO_DICE_RATE_,
        uint8[] memory SCORE_RATE_,
        uint8[] memory MATCH_DICE_RATE_
    ) external onlyOwner {
        BIG_RATE = BIG_RATE_;
        PAIR_RATE_ = PAIR_RATE_;
        TRIPLE_RATE = TRIPLE_RATE_;
        TRIPLE_ANY_RATE = TRIPLE_ANY_RATE_;
        EVEN_RATE = EVEN_RATE_;
        TWO_DICE_RATE = TWO_DICE_RATE_;
        SCORE_RATE = SCORE_RATE_;
        MATCH_DICE_RATE = MATCH_DICE_RATE_;
        emit RoleEvent("setRateValue", msg.sender, true);
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

    function setLimitBetAmount(
        uint256 minSicboBetAmount_,
        uint256 maxSicboBetAmount_
    ) external onlyAdmins {
        minSicboBetAmount = minSicboBetAmount_;
        maxSicboBetAmount = maxSicboBetAmount_;
        emit RoleEvent("set_Limit_Bet_Amount", address(token), true);
    }

    function setExchangeToken(IERC20Upgradeable token_) external onlyAdmins {
        token = token_;
        emit RoleEvent("set_exchange_token", address(token), true);
    }

    function setSwapDelay(uint256 swapDelay_) external onlyAdmins {
        swapDelay = swapDelay_;
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

    // Sicbo game
    function getRandomHash(
        uint256 timestamp,
        uint256 amount,
        address msgsender,
        string memory internalTx
    ) internal pure returns (uint8[] memory) {
        uint8[] memory Sicboarray = new uint8[](3);

        uint8 indexSicbo0to3 = 0;
        while (true) {
            bytes32 hash1 = keccak256(
                abi.encodePacked(
                    internalTx,
                    amount,
                    msgsender,
                    timestamp,
                    indexSicbo0to3
                )
            );

            for (uint8 i = 0; i < 32; i++) {
                uint8 index_val = uint8(hash1[i]) % 8;
                if (index_val < 6) {
                    Sicboarray[indexSicbo0to3] = index_val + 1;
                    indexSicbo0to3++;
                }
                if (indexSicbo0to3 == 3) break;
            }
            if (indexSicbo0to3 == 3) break;
        }

        return Sicboarray;
    }

    event Logss(string log__, uint256 number_);

    function playSicboGame(
        string memory internalTx_,
        address receiver_,
        uint256[][] memory betList
    ) external nonReentrant {
        uint256 sumBetList = 0;
        for (uint8 i = 0; i < 10; i++) {
            for (uint8 j = 0; j < betList[i].length; j++) {
                sumBetList += betList[i][j];
            }
        }
        //send monney
        _validateSwapData(receiver_, sumBetList);
        require(
            sumBetList <= maxSicboBetAmount,
            "Transfer amount exceeds max Bet"
        );
        require(
            sumBetList >= minSicboBetAmount,
            "Transfer amount below min Bet"
        );
        require(sumBetList > 0, "playSicboGame: Amount is zero");
        require(
            token.balanceOf(tokenDistributor) >= sumBetList * 2,
            "playSicboGame: Transfer amount exceeds balance"
        );
        require(
            token.allowance(tokenDistributor, address(this)) >= sumBetList,
            "playSicboGame: Transfer amount exceeds allowance"
        );

        //transfer token from user to distributor
        token.safeTransferFrom(msg.sender, tokenDistributor, sumBetList);

        uint256 totalReward = 0;
        uint8[] memory d = getRandomHash(
            block.timestamp,
            sumBetList,
            receiver_,
            internalTx_
        );
        uint256 sum = d[0] + d[1] + d[2];
        if (betList[0][0] > 0 && sum >= 11) {
            //Win big
            totalReward += (betList[0][0] * BIG_RATE) / 100;
        }

        if (betList[1][0] > 0 && sum < 11) {
            //Win small
            totalReward += (betList[1][0] * BIG_RATE) / 100;
        }

        uint8 WIN_PAIR;
        if (d[0] == d[1]) {
            WIN_PAIR = d[0];
        } else if (d[0] == d[2]) {
            WIN_PAIR = d[2];
        } else if (d[1] == d[2]) {
            WIN_PAIR = d[1];
        }

        for (uint8 j = 1; j <= 6; j++) {
            uint256 betValue = betList[2][j];
            if (betValue <= 0) continue;
            if (WIN_PAIR == j) totalReward += betList[2][j] * PAIR_RATE;
        }

        uint8 WIN_TRIPLE;

        if (d[0] == d[1] && d[0] == d[2]) {
            WIN_TRIPLE = d[0];
        }

        if (WIN_TRIPLE > 0 && betList[3][0] > 0)
            totalReward += betList[3][0] * TRIPLE_ANY_RATE;

        for (uint8 j = 1; j <= 6; j++) {
            uint256 betValue = betList[4][j];
            if (betValue <= 0) continue;
            if (WIN_TRIPLE == j) totalReward += betList[4][j] * TRIPLE_RATE;
        }

        for (uint8 j = 4; j <= 17; j++) {
            if (betList[5][j] <= 0) continue;
            if (sum == j) totalReward += betList[5][j] * SCORE_RATE[j];
        }

        for (uint8 j = 1; j <= 6; j++) {
            if (betList[6][j] <= 0) continue;

            uint8 matchCnt = 0;
            if (d[0] == j) matchCnt++;
            if (d[1] == j) matchCnt++;
            if (d[2] == j) matchCnt++;

            if (matchCnt > 0) {
                totalReward += betList[6][j] * MATCH_DICE_RATE[matchCnt];
            }
        }
        //Win even
        if (sum % 2 == 0 && betList[7][0] > 0)
            totalReward += (betList[7][0] * EVEN_RATE) / 100;

        //win odd
        if (sum % 2 != 0 && betList[8][0] > 0)
            totalReward += (betList[8][0] * EVEN_RATE) / 100;
        string[15] memory TWO_DICE = [
            "12",
            "13",
            "14",
            "15",
            "16",
            "23",
            "24",
            "25",
            "26",
            "34",
            "35",
            "36",
            "45",
            "46",
            "56"
        ];

        for (uint8 j = 0; j < 15; j++) {
            if (betList[9][j] <= 0) continue;

            string memory s = string(
                abi.encodePacked(Strings.toString(d[0]), Strings.toString(d[1]))
            );

            if (
                keccak256(abi.encodePacked(s)) ==
                keccak256(abi.encodePacked(TWO_DICE[j]))
            ) {
                totalReward += betList[9][j] * TWO_DICE_RATE;
                continue;
            }
            s = string(
                abi.encodePacked(Strings.toString(d[1]), Strings.toString(d[0]))
            );
            if (
                keccak256(abi.encodePacked(s)) ==
                keccak256(abi.encodePacked(TWO_DICE[j]))
            ) {
                totalReward += betList[9][j] * TWO_DICE_RATE;
                continue;
            }
            s = string(
                abi.encodePacked(Strings.toString(d[0]), Strings.toString(d[2]))
            );
            if (
                keccak256(abi.encodePacked(s)) ==
                keccak256(abi.encodePacked(TWO_DICE[j]))
            ) {
                totalReward += betList[9][j] * TWO_DICE_RATE;
                continue;
            }
            s = string(
                abi.encodePacked(Strings.toString(d[2]), Strings.toString(d[0]))
            );

            if (
                keccak256(abi.encodePacked(s)) ==
                keccak256(abi.encodePacked(TWO_DICE[j]))
            ) {
                totalReward += betList[9][j] * TWO_DICE_RATE;
                continue;
            }
            s = string(
                abi.encodePacked(Strings.toString(d[1]), Strings.toString(d[2]))
            );
            if (
                keccak256(abi.encodePacked(s)) ==
                keccak256(abi.encodePacked(TWO_DICE[j]))
            ) {
                totalReward += betList[9][j] * TWO_DICE_RATE;
                continue;
            }
            s = string(
                abi.encodePacked(Strings.toString(d[2]), Strings.toString(d[1]))
            );
            if (
                keccak256(abi.encodePacked(s)) ==
                keccak256(abi.encodePacked(TWO_DICE[j]))
            ) {
                totalReward += betList[9][j] * TWO_DICE_RATE;
                continue;
            }
        }
        //check results and refund
        if (totalReward > 0)
            token.safeTransferFrom(tokenDistributor, receiver_, totalReward);

        emit resultSicbo(d, receiver_, sumBetList, totalReward);
        emit playgameDataUser(
            msg.sender,
            sumBetList,
            totalReward,
            block.timestamp
        );
    }

    /** ========================== MAIN FUNCTIONS ========================= */
    modifier validTx(string memory internalTx_) {
        require(!invalidTx[internalTx_], "Tx state: Cancelled");
        _;
    }

    function _validateSwapData(address receiver_, uint256 amount_) private {
        // Check delay
        require(
            block.timestamp >= (lastGSwap[receiver_] + swapDelay),
            "playgame: Not to swap time yet"
        );
        //Check max limit
        if (maxSwapAmount != 0) {
            require(
                amount_ <= maxSwapAmount,
                "playgame: Swap amount exceed max limit"
            );
        }

        //update last swap time
        lastGSwap[receiver_] = block.timestamp;
    }

    modifier swapDataNotExisted(string memory internalTx_) {
        require(
            swapDatas[internalTx_].swapTime == 0,
            "Tx state: Swap data existed"
        );
        _;
    }

    function blockTime() external view returns (uint256) {
        return block.timestamp;
    }
}
