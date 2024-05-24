// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

// Open Zeppelin libraries for controlling upgradability and access.
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

contract LUCKYCRABTokenSwap is
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
    uint8[] public data;
    uint8[] public bonus;
    uint8[][] public result;
    uint256 public _defaultJackpot;
    uint256 public _Jackpotbalance;
    uint256 public maxLUCKYCRABBetAmount;
    uint256 public minLUCKYCRABBetAmount;
    uint256 public feeLUCKYCRABPlay; //5
    uint256 public feeLUCKYCRABJackpot; //2
    struct SwapData {
        address user;
        uint256 amountIn;
        uint256 amountOut;
        uint256 swapTime;
    }

    ///@dev no constructor in upgradable contracts. Instead we have initializers
    function initialize(IERC20Upgradeable token_) public initializer {
        ///@dev as there is no constructor, we need to initialise the OwnableUpgradeable explicitly
        __Ownable_init();

        token = token_;
        tokenDistributor = msg.sender;
        adminLists[msg.sender] = true;

        feeLUCKYCRABPlay = 5;
        feeLUCKYCRABJackpot = 2;
        swapDelay = 1;
        maxSwapAmount = 0;

        maxLUCKYCRABBetAmount = 100000000000000000000000; //100k
        minLUCKYCRABBetAmount = 100000000000000000000; // 100
        data = [
            1,
            3,
            4,
            5,
            6,
            7,
            8,
            9,
            10,
            9,
            9,
            9,
            8,
            8,
            7,
            3,
            4,
            5,
            10,
            8,
            8,
            9
        ];
        bonus = [3, 4, 5, 10, 10, 10, 10, 10, 10, 10];
        _defaultJackpot = 100000000000000000000000; //100k
        _Jackpotbalance = _defaultJackpot;
        result = [
            [1, 4, 7],
            [1, 4, 8],
            [1, 4, 9],
            [1, 5, 7],
            [1, 5, 8],
            [1, 5, 9],
            [1, 6, 7],
            [1, 6, 8],
            [1, 6, 9],
            [2, 4, 7],
            [2, 4, 8],
            [2, 4, 9],
            [2, 5, 7],
            [2, 5, 8],
            [2, 5, 9],
            [2, 6, 7],
            [2, 6, 8],
            [2, 6, 9],
            [3, 4, 7],
            [3, 4, 8],
            [3, 4, 9],
            [3, 5, 7],
            [3, 5, 8],
            [3, 5, 9],
            [3, 6, 7],
            [3, 6, 8],
            [3, 6, 9]
        ];
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
        uint256 LUCKYCRAB,
        bytes userSignature
    );

    event CancelEvent(
        string internalTx,
        address user,
        uint256 amount,
        bytes signature
    );

    event CancelWithAuthorityEvent(string[] internalTx);

    event resultLUCKYCRAB(
        address user,
        uint8[] mtx,
        uint256 amount,
        uint8 IsJackpot,
        uint256 TotalPrizeValue,
        uint256 playTime
    );

    event playgameDataUser(
        address user,
        uint256 amount,
        uint256 TotalPrizeValue,
        uint256 playTime
    );

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

    function setLimitBetAmount(
        uint256 minLUCKYCRABBetAmount_,
        uint256 maxLUCKYCRABBetAmount_
    ) external onlyAdmins {
        minLUCKYCRABBetAmount = minLUCKYCRABBetAmount_;
        maxLUCKYCRABBetAmount = maxLUCKYCRABBetAmount_;
        emit RoleEvent("set_Limit_Bet_Amount", address(token), true);
    }

    function setSwapDelay(uint256 swapDelay_) external onlyAdmins {
        swapDelay = swapDelay_;
    }

    function setJackpotmoney(
        uint256 defaultJackpotbalance
    ) external onlyAdmins {
        _defaultJackpot = defaultJackpotbalance;
        _Jackpotbalance = _defaultJackpot;
        emit RoleEvent("set_Jackpotmoney", address(token), true);
    }

    function setFeeLUCKYCRAB(
        uint256 feeLUCKYCRABPlay_,
        uint256 feeLUCKYCRABJackpot_
    ) external onlyAdmins {
        feeLUCKYCRABPlay = feeLUCKYCRABPlay_;
        feeLUCKYCRABJackpot = feeLUCKYCRABJackpot_;
        emit RoleEvent("set_FeeLUCKYCRAB", address(token), true);
    }

    function setMaxSwapAmount(uint256 maxSwapAmount_) external onlyAdmins {
        maxSwapAmount = maxSwapAmount_;
    }

    function setBirdData(uint8[] memory data_) external onlyAdmins {
        data = data_;
    }

    function setBonusData(uint8[] memory bonusData_) external onlyAdmins {
        bonus = bonusData_;
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

    /**
     *get user signature
     */
    function getMessageHash(
        string memory _internalTx,
        address receiver_,
        uint256 amount_
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_internalTx, receiver_, amount_));
    }

    // bird game
    function getRandomHash(
        uint256 timestamp,
        uint256 amount,
        address msgsender,
        string memory internalTx
    ) public view returns (uint8[] memory) {
        uint8[] memory rdBirdArray = new uint8[](15);

        uint8 indexBird0to8 = 0;
        while (true) {
            bytes32 hash1 = keccak256(
                abi.encodePacked(
                    internalTx,
                    amount,
                    msgsender,
                    timestamp,
                    indexBird0to8
                )
            );

            for (uint8 i = 0; i < 32; i++) {
                uint8 index_val = uint8(hash1[i]) % 32;
                if (index_val < data.length) {
                    rdBirdArray[indexBird0to8] = data[index_val];
                    indexBird0to8++;
                }
                if (indexBird0to8 == 9) break;
            }
            if (indexBird0to8 == 9) break;
        }

        uint8 indexBird8to15 = 9;
        while (true) {
            bytes32 hash2 = keccak256(
                abi.encodePacked(
                    internalTx,
                    amount,
                    msgsender,
                    timestamp,
                    indexBird8to15
                )
            );

            for (uint8 i = 0; i < 32; i++) {
                uint8 index_val = uint8(hash2[i]) % 8;
                if (index_val < bonus.length) {
                    rdBirdArray[indexBird8to15] = bonus[index_val];
                    indexBird8to15++;
                }
                if (indexBird8to15 == 15) break;
            }
            if (indexBird8to15 == 15) break;
        }
        return rdBirdArray;
    }

    function getBonusRate(uint8 type_) internal pure returns (uint8) {
        uint8 rate = 1;
        if (type_ == 3) rate = 3;
        else if (type_ == 4) rate = 5;
        else if (type_ == 5) rate = 10;
        else if (type_ == 10) rate = 1;
        return rate;
    }

    function get_results(
        uint8 g0,
        uint8 g1,
        uint8 g2
    ) internal pure returns (uint8) {
        uint8 result_ = 0;
        if (g0 == g1 && g0 == g2) {
            result_ = g0;
        } else if (g0 == 1 || g1 == 1 || g2 == 1) {
            if (g0 != 1 && g0 != 6) {
                if (g1 == 1) {
                    g1 = g0;
                }
                if (g2 == 1) {
                    g2 = g0;
                }
            } else if (g1 != 1 && g1 != 6) {
                if (g0 == 1) {
                    g0 = g1;
                }
                if (g2 == 1) {
                    g2 = g1;
                }
            } else if (g2 != 1 && g2 != 6) {
                if (g0 == 1) {
                    g0 = g2;
                }
                if (g1 == 1) {
                    g1 = g2;
                }
            }
            if (g0 == g1 && g0 == g2) {
                result_ = g0;
            }
        }
        return result_;
    }

    function playLUCKYCRAB(
        string memory internalTx_,
        address receiver_,
        uint256 bet
    )
        external
        nonReentrant
        validTx(internalTx_)
        swapDataNotExisted(internalTx_)
    {
        require(
            bet <= maxLUCKYCRABBetAmount,
            "Transfer amount exceeds max Bet"
        );
        require(bet >= minLUCKYCRABBetAmount, "Transfer amount below min Bet");
        _validateSwapData(receiver_, bet);
        require(
            token.allowance(tokenDistributor, address(this)) >= bet,
            "playLUCKYCRAB: Transfer amount exceeds allowance"
        );

        //transfer token from user to distributor
        token.safeTransferFrom(msg.sender, tokenDistributor, bet);
        _Jackpotbalance += (bet * feeLUCKYCRABJackpot) / 100;

        uint8 IsJackPot = 0;
        uint256 TotalPrizeValue = 0;
        uint8[] memory rdBirdArray_;
        address msgsender = msg.sender;
        rdBirdArray_ = getRandomHash(
            block.timestamp,
            bet,
            msgsender,
            internalTx_
        );

        for (uint y = 0; y < result.length; y++) {
            uint8[] memory row = result[y];
            uint8 g0 = rdBirdArray_[row[0] - 1];
            uint8 g1 = rdBirdArray_[row[1] - 1];
            uint8 g2 = rdBirdArray_[row[2] - 1];

            uint8 val = get_results(g0, g1, g2);
            uint256 prize = 0;
            if (val > 0) {
                if (val < 6) {
                    continue;
                } else {
                    if (val == 6) {
                        if (rdBirdArray_[10] == 5 && rdBirdArray_[13] == 5) {
                            IsJackPot = 1;
                            continue;
                        }
                        prize = bet * 5;
                    }
                    if (val == 7) {
                        prize = bet;
                    }
                    if (val == 8) {
                        prize = (bet * 35) / 100;
                    }
                    if (val == 9) {
                        prize = (bet * 10) / 100;
                    }
                    uint8 a = getBonusRate(rdBirdArray_[10]);
                    if (a != 1) {
                        prize = prize * a * getBonusRate(rdBirdArray_[13]);
                    }
                }
            }
            TotalPrizeValue += prize;
        }

        if (IsJackPot == 1) {
            TotalPrizeValue = TotalPrizeValue + _Jackpotbalance;
            _Jackpotbalance = _defaultJackpot;
        }
        uint256 fee = 0;
        if (TotalPrizeValue > 0) {
            fee = (TotalPrizeValue * feeLUCKYCRABPlay) / 100;
        }
        TotalPrizeValue = (TotalPrizeValue - fee);

        //check results and refund
        if (TotalPrizeValue > 0)
            token.safeTransferFrom(
                tokenDistributor,
                receiver_,
                TotalPrizeValue
            );

        emit resultLUCKYCRAB(
            msgsender,
            rdBirdArray_,
            bet,
            IsJackPot,
            TotalPrizeValue,
            block.timestamp
        );

        emit playgameDataUser(
            msg.sender,
            bet,
            TotalPrizeValue,
            block.timestamp
        );
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

    function blockTime() external view returns (uint256) {
        return block.timestamp;
    }
}
