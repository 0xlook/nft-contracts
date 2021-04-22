// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Privi Pod Auction
 * @author 0xlook
 */
contract PodAuction is Ownable, Pausable, ReentrancyGuard {
    /*** Struct & Enum ***/

    enum AuctionState { INITIATED, CLAIMED, WITHDRAWED }

    struct Auction {
        address creator;
        uint256 creatorShare;
        uint256 sharingShare;
        uint256 startTime;
        uint256 bidEndTime;
        uint256 claimEndTime;
        uint256 feePercent;
        uint256 lastHighDeposit;
        address depositor;
        address tokenAddress;
        address verifiedArtist;
        AuctionState state;
        bool isEntity;
    }

    /*** Storage Properties ***/

    // In Exp terms, 1e18 is 1, or 100%
    uint256 private constant hundredPercent = 1e18;

    // In Exp terms, 1e16 is 0.01, or 1%
    uint256 private constant onePercent = 1e16;

    // Counter for new auction ids.
    uint256 public nextAuctionId;

    address public claimingPool;

    // The auction objects identifiable by their unsigned integer ids.
    mapping(uint256 => Auction) private auctions;

    /*** Events ***/

    event CreatePodAuction(
        address indexed creator,
        address indexed tokenAddress,
        uint256 creatorShare,
        uint256 sharingShare,
        uint256 startTime,
        uint256 bidEndTime,
        uint256 claimEndTime,
        uint256 feePercent
    );
    event Bid(uint256 indexed auctionId, address indexed depositor, uint256 deposit);
    event WithdrawBid(uint256 indexed auctionId, address indexed depositor, uint256 deposit);
    event ClaimFund(uint256 indexed auctionId, address indexed artist, uint256 claimedFund);

    /*** Modifiers ***/

    // Throws if the provided id does not point to a valid auction.
    modifier auctionExists(uint256 auctionId) {
        require(auctions[auctionId].isEntity, "auction does not exist");
        _;
    }

    modifier duringBid(uint256 auctionId) {
        require(
            block.timestamp >= auctions[auctionId].startTime && block.timestamp < auctions[auctionId].bidEndTime,
            "invalid time to bid"
        );
        _;
    }

    modifier duringClaim(uint256 auctionId) {
        require(
            block.timestamp >= auctions[auctionId].bidEndTime && block.timestamp < auctions[auctionId].claimEndTime,
            "invalid time to claim"
        );
        _;
    }

    /*** Contract Logic Starts Here */

    constructor() {
        nextAuctionId = 1;
    }

    /*** Owner Functions ***/

    function pause() external onlyOwner {
        _pause();
    }

    function setClaimingPool(address _claimingPool) external onlyOwner {
        claimingPool = _claimingPool;
    }

    function verifyArtist(uint256 auctionId, address _artist) external onlyOwner auctionExists(auctionId) {
        require(_artist != address(0x0), "invalid artist address");
        Auction storage auction = auctions[auctionId];
        auction.verifiedArtist = _artist;
    }

    function sharePod(uint256 auctionId) external onlyOwner auctionExists(auctionId) duringBid(auctionId) {}

    /*** View Functions ***/

    /*** Public Effects & Interactions Functions ***/

    function createPodAuction(
        uint256 creatorShare,
        uint256 sharingShare,
        uint256 startTime,
        uint256 bidEndTime,
        uint256 claimEndTime,
        uint256 feePercent,
        address tokenAddress
    ) external whenNotPaused returns (uint256) {
        require(creatorShare > 0, "creator share is zero");
        require(sharingShare > 0, "sharing share is zero");
        require(startTime >= block.timestamp, "start time before block.timestamp");
        require(bidEndTime > startTime, "bid end time before the start time");
        require(claimEndTime > bidEndTime, "claim end time before the bid end time");
        require(feePercent >= onePercent / 5 && feePercent < onePercent * 10, "invalid fee value");

        uint256 auctionId = nextAuctionId;
        auctions[auctionId] = Auction({
            creator: _msgSender(),
            creatorShare: creatorShare,
            sharingShare: sharingShare,
            startTime: startTime,
            bidEndTime: bidEndTime,
            claimEndTime: claimEndTime,
            feePercent: feePercent,
            lastHighDeposit: 0,
            tokenAddress: tokenAddress,
            depositor: address(0x0),
            verifiedArtist: address(0x0),
            state: AuctionState.INITIATED,
            isEntity: true
        });

        nextAuctionId = nextAuctionId + 1;
        return nextAuctionId;
    }

    function bid(uint256 auctionId, uint256 deposit)
        external
        whenNotPaused
        nonReentrant
        auctionExists(auctionId)
        duringBid(auctionId)
        returns (bool)
    {
        Auction storage auction = auctions[auctionId];
        require(auction.depositor != _msgSender(), "user has a bid");
        require(auction.lastHighDeposit < deposit, "deposit is lower than the high deposit");
        require(claimingPool != address(0x0), "invalid claiming pool address");

        (, uint256 lastRemaining) = _calculateFeeAndRemaining(auction.lastHighDeposit, auction.feePercent);
        (uint256 fee, ) = _calculateFeeAndRemaining(deposit, auction.feePercent);

        address lastDepositor = auction.depositor;

        auction.depositor = _msgSender();
        auction.lastHighDeposit = deposit;

        require(
            IERC20(auction.tokenAddress).transferFrom(msg.sender, address(this), deposit),
            "token transfer failure"
        );

        require(IERC20(auction.tokenAddress).transfer(lastDepositor, lastRemaining), "token transfer failure");

        require(IERC20(auction.tokenAddress).transfer(claimingPool, fee), "token transfer failure");

        return true;
    }

    function withdrawBid(uint256 auctionId)
        external
        whenNotPaused
        nonReentrant
        auctionExists(auctionId)
        returns (bool)
    {
        Auction storage auction = auctions[auctionId];
        require(block.timestamp > auction.claimEndTime, "invalid time to withdraw");
        require(auction.depositor == _msgSender(), "invalid address to withdraw");
        require(auction.state == AuctionState.INITIATED, "invalid auction state to withdraw");

        (, uint256 lastRemaining) = _calculateFeeAndRemaining(auction.lastHighDeposit, auction.feePercent);

        auction.state = AuctionState.WITHDRAWED;

        require(IERC20(auction.tokenAddress).transfer(auction.depositor, lastRemaining), "token transfer failure");

        return true;
    }

    function claimFunds(uint256 auctionId)
        external
        whenNotPaused
        nonReentrant
        auctionExists(auctionId)
        duringClaim(auctionId)
        returns (bool)
    {
        Auction storage auction = auctions[auctionId];
        require(auction.verifiedArtist == _msgSender(), "invalid address to claim");
        require(auction.state == AuctionState.INITIATED, "invalid auction state to claim");

        auction.state = AuctionState.CLAIMED;

        return true;
    }

    /*** Internal Functions ***/

    function _calculateFeeAndRemaining(uint256 deposit, uint256 feePercent)
        internal
        pure
        returns (uint256 fee, uint256 remaining)
    {
        fee = (deposit * feePercent) / hundredPercent;
        remaining = deposit - fee;
    }
}
