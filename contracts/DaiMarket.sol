// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title Dai Market Order Book
 * @author 0xlook
 */

contract DaiMarket is Ownable, Pausable {
    using SafeERC20 for IERC20;

    /*** Struct & Enum ***/

    enum Side { BUY, SELL }

    struct Order {
        uint256 amount;
        uint256 price;
        uint256 toFill;
        uint256 updated;
        Side side;
        address token;
        address creator;
    }

    /*** Storage Properties ***/

    // Dai token address.
    address private immutable dai;

    // Counter for new order ids.
    uint256 private nextOrderId;

    // Addresses of whitelist tokens
    address[] public tokenList;

    // The order objects identifiable by their unsigned integer ids.
    mapping(uint256 => Order) private orders;

    // The amount of tokens identifiable by user address and token address
    // UserAddress => tokenAddress => token amount
    mapping(address => mapping(address => uint256)) private tokenBalances;

    // The whiltelist token marker
    mapping(address => bool) private whiteListTokens;

    /*** Events ***/

    event LogWhiteListToken(address indexed token);
    event LogDeposit(address indexed token, address indexed user, uint256 amount);
    event LogWithdraw(address indexed token, address indexed user, uint256 amount);
    event LogCreateOrder(
        uint256 indexed orderId,
        address indexed token,
        address indexed creator,
        uint256 amount,
        uint256 price,
        uint256 createdTime,
        Side side
    );
    event LogUpdateOrder(uint256 indexed orderId, uint256 toFill, uint256 updatedTime);
    event LogFillOrder(
        uint256 indexed orderId,
        address indexed token,
        address indexed user,
        uint256 amount,
        uint256 time
    );
    event LogCancelOrder(uint256 indexed orderId, uint256 time);

    /*** Modifiers ***/

    // Throws if the token is not whitelisted
    modifier onlyWhiteListedToken(address token) {
        require(whiteListTokens[token] == true, "WhiteListed!");
        _;
    }

    // Throws if the token is not whitelisted or not dai
    modifier onlyDaiOrWhiteListedToken(address token) {
        require(token == dai || whiteListTokens[token] == true, "WhiteListed or Dai!");
        _;
    }

    // Throws if the order not created, or fully filled or canceled
    modifier exitsOrder(uint256 orderId) {
        require(orders[orderId].toFill > 0, "Order not exists!");
        _;
    }

    /*** Contract Logic Starts Here */

    constructor(address dai_) {
        dai = dai_;
        nextOrderId = 1;
    }

    /*** Owner Functions ***/

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Owner function: Add new token to the whitelist
     *
     * @param token_ address of token
     */
    function addTokenToWhiteList(address token_) external onlyOwner {
        require(token_ != address(0), "Invalid address!");
        require(token_ != dai, "Dai!");
        require(whiteListTokens[token_] == false, "Duplicated!");
        whiteListTokens[token_] = true;
        tokenList.push(token_);

        emit LogWhiteListToken(token_);
    }

    /*** View Functions ***/

    /**
     * @dev Returns the all properties of the order
     *
     * @param orderId_ The identifier of order
     */
    function getOrder(uint256 orderId_) public view exitsOrder(orderId_) returns (Order memory) {
        return orders[orderId_];
    }

    /**
     * @dev Returns the all whitelist token addressed
     *
     */
    function getTokenWhiteList() public view returns (address[] memory) {
        return tokenList;
    }

    /**
     * @dev Returns true if the token is whitelisted
     *
     * @param token_ The address of token
     */
    function isWhiteListed(address token_) public view returns (bool) {
        return whiteListTokens[token_];
    }

    /**
     * @dev Returns the token balance of user that able to withdraw or create a new order
     *
     * @param user_ The address of user
     * @param token_ The address of token
     */
    function getTokenBalance(address user_, address token_) public view returns (uint256) {
        return tokenBalances[user_][token_];
    }

    /*** Public Effects & Interactions Functions ***/

    /**
     * @dev Deposit token
     *
     * @param token_ The address of token to deposit
     * @param amount_ The amount of token to deposit
     * @return Returns true is success
     */
    function deposit(address token_, uint256 amount_)
        external
        whenNotPaused
        onlyDaiOrWhiteListedToken(token_)
        returns (bool)
    {
        require(amount_ > 0, "Invalid amount!");

        tokenBalances[msg.sender][token_] = tokenBalances[msg.sender][token_] + amount_;

        IERC20(token_).safeTransferFrom(msg.sender, address(this), amount_);

        emit LogDeposit(token_, msg.sender, amount_);

        return true;
    }

    /**
     * @dev Withdraw token
     *
     * @param token_ The address of token to withdraw
     * @param amount_ The amount of token to withdraw
     * @return Returns true is success
     */
    function withdraw(address token_, uint256 amount_)
        external
        whenNotPaused
        onlyDaiOrWhiteListedToken(token_)
        returns (bool)
    {
        require(amount_ > 0, "Invalid amount!");
        require(tokenBalances[msg.sender][token_] >= amount_, "Insufficient balance!");

        tokenBalances[msg.sender][token_] = tokenBalances[msg.sender][token_] - amount_;

        IERC20(token_).safeTransfer(msg.sender, amount_);

        emit LogWithdraw(token_, msg.sender, amount_);

        return true;
    }

    /**
     * @dev Create a new order
     *
     * @param token_ The token address to buy/sell
     * @param amount_ The amount of token to buy/sell
     * @param price_ The price of order in dai
     * @param side_ The Side enum to indentify buy or sell
     * @return The uint256 id of the newly created order
     */
    function createOrder(
        address token_,
        uint256 amount_,
        uint256 price_,
        Side side_
    ) external whenNotPaused onlyWhiteListedToken(token_) returns (uint256) {
        require(amount_ > 0, "Invalid amount!");
        require(price_ > 0, "Invalid price!");

        if (side_ == Side.SELL) {
            uint256 tokenBalance = tokenBalances[msg.sender][token_];
            require(tokenBalance >= amount_, "Insufficient dai balance!");

            tokenBalances[msg.sender][token_] = tokenBalance - amount_;
        } else {
            uint256 daiBalance = tokenBalances[msg.sender][dai];
            require(daiBalance >= amount_ * price_, "Insufficient dai balance!");

            tokenBalances[msg.sender][dai] = daiBalance - amount_ * price_;
        }

        orders[nextOrderId] = Order(amount_, price_, amount_, block.timestamp, side_, token_, msg.sender);

        emit LogCreateOrder(nextOrderId, token_, msg.sender, amount_, price_, block.timestamp, side_);

        nextOrderId++;
        return nextOrderId;
    }

    /**
     * @dev Fill the existing order
     *
     * @param orderId_ The uint256 id of the existing order
     * @param amount_ The amount of token to fill
     * @return Return true if success
     */
    function fillOrder(uint256 orderId_, uint256 amount_) external whenNotPaused exitsOrder(orderId_) returns (bool) {
        Order memory order = orders[orderId_];

        require(order.toFill >= amount_, "Amount is bigger than order!");

        uint256 inDai = amount_ * order.price;
        address token = order.token;

        uint256 traderDaiBalance = tokenBalances[msg.sender][dai];
        uint256 traderTokenBalance = tokenBalances[msg.sender][token];

        if (order.side == Side.SELL) {
            require(traderDaiBalance >= inDai, "Insufficient dai balance!");

            tokenBalances[msg.sender][dai] = traderDaiBalance - inDai;
            tokenBalances[msg.sender][token] = traderTokenBalance + amount_;
            tokenBalances[order.creator][dai] = tokenBalances[order.creator][dai] + inDai;
        } else {
            require(traderTokenBalance >= amount_, "Insufficient token balance!");

            tokenBalances[msg.sender][token] = traderTokenBalance - amount_;
            tokenBalances[msg.sender][dai] = traderDaiBalance + inDai;
            tokenBalances[order.creator][token] = tokenBalances[order.creator][token] + amount_;
        }

        emit LogFillOrder(orderId_, order.token, msg.sender, amount_, block.timestamp);

        if (order.toFill == amount_) {
            delete orders[orderId_];
        } else {
            orders[orderId_].toFill -= amount_;
            emit LogUpdateOrder(orderId_, orders[orderId_].toFill, block.timestamp);
        }

        return true;
    }

    /**
     * @dev Cancel order by creator
     *
     * @param orderId_ The uint256 id of the existing order
     * @return Return true if success
     */
    function cancelOrder(uint256 orderId_) external whenNotPaused exitsOrder(orderId_) returns (bool) {
        Order memory order = orders[orderId_];

        require(order.creator == msg.sender, "Invalid creator!");

        if (order.side == Side.SELL) {
            tokenBalances[msg.sender][order.token] = tokenBalances[msg.sender][order.token] + order.toFill;
        } else {
            tokenBalances[msg.sender][dai] = tokenBalances[msg.sender][dai] + order.toFill * order.price;
        }

        delete orders[orderId_];

        emit LogCancelOrder(orderId_, block.timestamp);

        return true;
    }

    /*** Internal Functions ***/
}
