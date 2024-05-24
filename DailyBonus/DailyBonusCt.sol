// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DailyBonusCt is Ownable {
    IERC20 public EFIToken;
    address public EFiPoolAddress;
    mapping(address => bool) public adminLists;
    mapping(address => uint256) public lastClaimTime;
    uint256 public claimedDurationTime;
    uint256[] public gefih_rw;
    uint256[] public gol_rw;

    constructor(address EFIToken_) {
        EFIToken = IERC20(EFIToken_); //efi token
        EFiPoolAddress = address(0xAc968A3F4AB6ec40f3b721Ef0fBb066CFC058103); //efi pool
        adminLists[msg.sender] = true;
        claimedDurationTime = 86400; //1days =86400
        gefih_rw = [
            100,
            200,
            300,
            400,
            500,
            600,
            700,
            800,
            900,
            1000,
            1100,
            1200
        ];
        gol_rw = [
            300,
            600,
            900,
            1200,
            1500,
            1800,
            2100,
            2400,
            2700,
            3000,
            3300,
            3600
        ];
    }

    /** ==================== EVENT ============================ */
    event RoleEvent(string role, address user, bool status);
    event resultDailyBonus(
        address user,
        uint256 lastTimeClaimed,
        string hashNumber,
        uint256 goldwin,
        uint256 efihwin
    );

    /** ==================== CONFIG ========================= */
    function setAdmin(address user_, bool status_) external onlyOwner {
        adminLists[user_] = status_;
    }

    function setEfiData(uint256[] memory gefih_rw_) external onlyAdmins {
        gefih_rw = gefih_rw_;
    }

    function setGoldData(uint256[] memory gol_rw_) external onlyAdmins {
        gol_rw = gol_rw_;
    }

    function setExchangeToken(IERC20 EFIToken_) external onlyAdmins {
        EFIToken = EFIToken_;
        emit RoleEvent("set_exchange_token", msg.sender, true);
    }

    function setTokenPool(address EFiPoolAddress_) external onlyAdmins {
        EFiPoolAddress = EFiPoolAddress_;
        emit RoleEvent("set_token_pool", msg.sender, true);
    }

    modifier onlyAdmins() {
        require(
            adminLists[msg.sender] == true || msg.sender == owner(),
            "Authorization: Require admin role"
        );
        _;
    }

    function setTimeDuration(uint256 time_) external onlyAdmins {
        claimedDurationTime = time_;
    }

    /** ========================== MAIN FUNCTIONS ========================= */
    function claimDailyBonus(string memory internalTx) external {
        uint256 curTime = block.timestamp;
        require(
            curTime - lastClaimTime[msg.sender] > claimedDurationTime,
            "Not enough time to claim"
        );
        bytes32 hashNumber = keccak256(
            abi.encodePacked(internalTx, msg.sender, curTime)
        );
        uint256 res = uint(hashNumber) % 1000;

        lastClaimTime[msg.sender] = curTime;

        //check result and receive token
        uint256 rw_level = 99;
        uint256 gold = 0;
        uint256 efih = 0;

        if (0 <= res && res < 5) rw_level = 11;

        if (5 <= res && res <= 9) rw_level = 10;
        if (10 <= res && res < 20) rw_level = 9;
        if (20 <= res && res < 40) rw_level = 8;
        if (40 <= res && res < 70) rw_level = 7;
        if (70 <= res && res < 110) rw_level = 6;
        if (110 <= res && res < 160) rw_level = 5;

        if (160 <= res && res < 220) rw_level = 4;

        if (220 <= res && res < 280) rw_level = 3;

        if (280 <= res && res < 380) rw_level = 2;

        if (380 <= res && res < 600) rw_level = 1;

        if (600 <= res && res < 1000) rw_level = 0;

        if (rw_level < 99) {
            gold = gol_rw[rw_level];
            efih = gefih_rw[rw_level];
        }

        EFIToken.transferFrom(EFiPoolAddress, msg.sender, efih * 1e18);

        emit resultDailyBonus(
            msg.sender,
            curTime,
            Strings.toString(uint(hashNumber)),
            gold,
            efih
        );
    }
}
