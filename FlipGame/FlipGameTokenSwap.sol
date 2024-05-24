// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

// Open Zeppelin libraries for controlling upgradability and access.
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

contract FlipGameTokenSwap is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IERC20Upgradeable public token;
    address public tokenDistributor; // wallet distribute tokens to user when play game
    mapping(address => bool) public adminLists;
    mapping(string => SwapData) public swapDatas;

    ///@dev swap limit
    uint256 public swapDelay;
    uint256 public maxSwapAmount;
    mapping(address => uint256) public lastGSwap;
    mapping(string => bool) public invalidTx;

    uint256 public maxFlipBetAmount;
    uint256 public minFlipBetAmount;
    uint256 public feeFlipPlay; //5= 5%

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

        swapDelay = 5; // 5s
        maxSwapAmount = 0;
        feeFlipPlay = 5;
        maxFlipBetAmount = 100000000000000000000000; //100k
        minFlipBetAmount = 100000000000000000000; // 100
    }

    ///@dev required by the OZ UUPS module
    function _authorizeUpgrade(address) internal override onlyOwner {}

    /** ==================== EVENT ============================ */
    event RoleEvent(string role, address user, bool status);

    event resultFlip(
        string internalTx,
        address user,
        uint256 amount,
        uint256 FlipGame
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
        uint256 minFlipBetAmount_,
        uint256 maxFlipBetAmount_
    ) external onlyAdmins {
        minFlipBetAmount = minFlipBetAmount_;
        maxFlipBetAmount = maxFlipBetAmount_;
        emit RoleEvent("set_Limit_Bet_Amount", address(token), true);
    }

    function setSwapDelay(uint256 swapDelay_) external onlyAdmins {
        swapDelay = swapDelay_;
    }

    function setFeePlayAmount(uint256 feeFlipPlay_) external onlyAdmins {
        feeFlipPlay = feeFlipPlay_;
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

    function getMessageHash(
        string memory _internalTx,
        address receiver_,
        uint256 amount_
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_internalTx, receiver_, amount_));
    }

    /**
     *play flip game
     */
    function playFlipGame(
        string memory internalTx_,
        address receiver_,
        uint256 amount_,
        uint8 optionGame_
    )
        external
        nonReentrant
        validTx(internalTx_)
        swapDataNotExisted(internalTx_)
    {
        require(amount_ <= maxFlipBetAmount, "Transfer amount exceeds max Bet");
        require(amount_ >= minFlipBetAmount, "Transfer amount below min Bet");
        _validateSwapData(receiver_, amount_);
        require(amount_ > 0, "playgame: Amount is zero");
        require(
            token.balanceOf(tokenDistributor) >= amount_,
            "playgame: Transfer amount exceeds balance"
        );
        require(
            token.allowance(tokenDistributor, address(this)) >= amount_,
            "playgame: Transfer amount exceeds allowance"
        );

        //transfer token from user to distributor
        token.safeTransferFrom(msg.sender, tokenDistributor, amount_);

        //random hash and refund
        bytes32 FlipGame = keccak256(
            abi.encodePacked(internalTx_, receiver_, amount_)
        );
        uint256 amoutWin_ = 0;
        if (uint(FlipGame) % 2 == optionGame_) {
            amoutWin_ = (amount_ * (200 - feeFlipPlay)) / 100;
            token.safeTransferFrom(tokenDistributor, receiver_, amoutWin_);
        }
        swapDatas[internalTx_] = SwapData(
            msg.sender,
            0,
            amount_,
            block.timestamp
        );
        // emit event
        emit resultFlip(internalTx_, msg.sender, amount_, uint(FlipGame));
        emit playgameDataUser(msg.sender, amount_, amoutWin_, block.timestamp);
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
