pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

interface IOracle {
    function getTokenPrice(address token) external view returns (uint, uint);
}

contract Market is Pausable {
    using SafeERC20 for IERC20;

    struct Position {
        uint locked;
        address lockedToken;
        uint borrowed;
        address borrowedToken;
    }

    address public owner;
    address public oracle;
    uint public liquidationThreshold; // in bps
    uint public liquidationBonus; // in bps
    address constant internal WETH = 0xd0A1E359811322d97991E03f863a0C30C2cF029C;
    uint constant internal ONE = 10 ** 18;
    mapping (address => bool) public allowedLockTokens;
    mapping (address => bool) public allowedBorrowTokens;
    mapping (address => uint8) public tokenDecimals;
    mapping (address => Position[]) public positions;

    event CreatePosition(address user, uint pid);
    event Lock(address user, uint pid, address token, uint amount);
    event Unlock(address user, uint pid, address token, uint amount);
    event Borrow(address user, uint pid, address token, uint amount);
    event Repay(address user, uint pid, address token, uint amount);
    event Liquidated(address liquidator, address user, uint pid, address token, uint amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "onlyOwner");
        _;
    }

    constructor(address _oracle) {
        owner = msg.sender;
        oracle = _oracle;
    }

    function getTokenPrice(address token) internal view returns (uint) {
        if (token == address(0) || token == WETH) return ONE;
        (uint price, ) = IOracle(oracle).getTokenPrice(token);
        return price;
    }

    function getHealthFactor(Position storage position) internal view returns (uint) {
        uint lockedTokenPrice = getTokenPrice(position.lockedToken);
        uint borrowedTokenPrice = getTokenPrice(position.borrowedToken);
        uint scaledLocked = position.locked * 10 ** (18 - tokenDecimals[position.lockedToken]);
        uint scaledBorrowed = position.borrowed * 10 ** (18 - tokenDecimals[position.borrowedToken]);
        uint lockedValue = scaledLocked * lockedTokenPrice / ONE;
        uint borrowedValue = scaledBorrowed * borrowedTokenPrice / ONE;
        if (borrowedValue == 0) return ONE;
        uint healthFactor = lockedValue * liquidationThreshold * ONE / (borrowedValue * 10000);
        return healthFactor;
    }

    function getHealthFactor(address user, uint pid) public view returns (uint) {
        require(pid < positions[user].length, "InvalidPID");
        Position storage position = positions[user][pid];
        return getHealthFactor(position);
    }

    function isPositionSafe(Position storage position) internal view returns (bool) {
        uint healthFactor = getHealthFactor(position);
        return healthFactor >= ONE;
    }

    function isPositionSafe(address user, uint pid) public view returns (bool) {
        require(pid < positions[user].length, "InvalidPID");
        Position storage position = positions[user][pid];
        return isPositionSafe(position);
    }

    function createPosition(address lockedToken, address borrowedToken) public whenNotPaused {
        require(allowedLockTokens[lockedToken] && allowedBorrowTokens[borrowedToken], "InvalidToken");
        uint pid = positions[msg.sender].length;
        Position memory position = Position({
            locked: 0,
            lockedToken: lockedToken,
            borrowed: 0,
            borrowedToken: borrowedToken
        });
        positions[msg.sender].push(position);
        emit CreatePosition(msg.sender, pid);
    }

    function lock(uint pid, uint amount) public payable whenNotPaused {
        require(pid < positions[msg.sender].length, "InvalidPID");
        Position storage position = positions[msg.sender][pid];
        position.locked += amount;
        receiveToken(position.lockedToken, amount);
        emit Lock(msg.sender, pid, position.lockedToken, amount);
    }

    function unlock(uint pid, uint amount) public whenNotPaused {
        require(pid < positions[msg.sender].length, "InvalidPID");
        Position storage position = positions[msg.sender][pid];
        position.locked -= amount;
        sendToken(position.lockedToken, amount);
        require(isPositionSafe(position), "UnsafePosition");
        emit Unlock(msg.sender, pid, position.lockedToken, amount);
    }

    function borrow(uint pid, uint amount) public whenNotPaused {
        require(pid < positions[msg.sender].length, "InvalidPID");
        Position storage position = positions[msg.sender][pid];
        position.borrowed += amount;
        sendToken(position.borrowedToken, amount);
        require(isPositionSafe(position), "UnsafePosition");
        emit Borrow(msg.sender, pid, position.borrowedToken, amount);
    }

    function repay(uint pid, uint amount) public payable whenNotPaused {
        require(pid < positions[msg.sender].length, "InvalidPID");
        Position storage position = positions[msg.sender][pid];
        position.borrowed -= amount;
        receiveToken(position.borrowedToken, amount);
        emit Repay(msg.sender, pid, position.borrowedToken, amount);
    }

    function liquidate(address user, uint pid, uint amount) public whenNotPaused {
        require(pid < positions[user].length, "InvalidPID");
        Position storage position = positions[user][pid];
        require(!isPositionSafe(position), "SafePosition");
        uint borrowedTokenPrice = getTokenPrice(position.borrowedToken);
        uint lockedTokenPrice = getTokenPrice(position.lockedToken);
        
        uint scaledAmount = amount * 10 ** (18 - tokenDecimals[position.borrowedToken]);
        uint borrowedValue = scaledAmount * borrowedTokenPrice / ONE;
        uint scaledLiquidated = borrowedValue * (10000 + liquidationBonus) * ONE / (lockedTokenPrice * 10000);
        uint liquidated = scaledLiquidated / 10 ** (18 - tokenDecimals[position.lockedToken]);
        if (liquidated > position.locked) liquidated = position.locked;
        position.borrowed -= amount;
        position.locked -= liquidated;
        
        receiveToken(position.borrowedToken, amount);
        sendToken(position.lockedToken, liquidated);
        emit Liquidated(msg.sender, user, pid, position.lockedToken, liquidated);
    }

    function receiveToken(address token, uint amount) internal {
        if (token == address(0)) {
            require(msg.value >= amount, "NotEnoughFunds");
        } else {
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }
    }

    function sendToken(address token, uint amount) internal {
        if (token == address(0)) {
            (bool success,) = msg.sender.call{value: amount}("");
            require(success, "SendETHError");
        } else {
            IERC20(token).safeTransfer(msg.sender, amount);
        }
    }

    function pause() public onlyOwner {
        _pause();
    }

    function setAllowedLockToken(address token) public onlyOwner {
        allowedLockTokens[token] = true;
    }


    function setAllowedBorrowToken(address token) public onlyOwner {
        allowedBorrowTokens[token] = true;
    }

    function setTokenDecimals(address token, uint8 decimals) public onlyOwner {
        tokenDecimals[token] = decimals;
    }

    function setLiquidationThreshold(uint _liquidationThreshold) public onlyOwner {
        liquidationThreshold = _liquidationThreshold;
    }

    function setLiquidationBonus(uint _liquidationBonus) public onlyOwner {
        liquidationBonus = _liquidationBonus;
    }
}