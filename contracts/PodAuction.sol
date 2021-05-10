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
contract PriviPodAuction is Ownable, Pausable, ReentrancyGuard {
    /*** Struct & Enum ***/

    enum AuctionState { INITIATED, CLAIMED, WITHDRAWED }

    struct Auction {
        address creator;
        uint256 creatorSharePercent;
        uint256 sharingSharePercent;
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

    // The max creator share percent
    uint256 public maxCreatorSharePercent;

    // The max sharing share percent
    uint256 public maxSharingSharePercent;

    // The min protocol fee percent
    uint256 public minProtocolFeePercent;

    // The max protocol fee percent
    uint256 public maxProtocolFeePercent;

    // Counter for new auction ids.
    uint256 public nextAuctionId;

    // Address where the x% of bid deposit goes
    address public claimingPool;

    // The auction objects identifiable by their unsigned integer ids.
    mapping(uint256 => Auction) private auctions;

    // AuctionId => Address => SharingShare
    mapping(uint256 => mapping(address => uint256)) sharingShares;

    /*** Events ***/

    event SetClaimingPool(address indexed pool);
    event VerifyArtist(uint256 indexed auctionId, address indexed artist);
    event SharedPod(uint256 indexed auctionId, uint256 length, uint256 sharesPerUser);
    event CreatePodAuction(
        address indexed creator,
        address indexed tokenAddress,
        uint256 creatorSharePercent,
        uint256 sharingSharePercent,
        uint256 startTime,
        uint256 bidEndTime,
        uint256 claimEndTime,
        uint256 feePercent
    );
    event Bid(uint256 indexed auctionId, address indexed depositor, uint256 amount);
    event WithdrawBid(uint256 indexed auctionId, address indexed depositor, uint256 amount);
    event ClaimFund(uint256 indexed auctionId, address indexed artist, uint256 claimedFund);
    event ClaimSharingShare(uint256 indexed auctionId, address indexed user, uint256 sharingShare);

    /*** Modifiers ***/

    // Throws if the provided id does not point to a valid auction.
    modifier auctionExists(uint256 auctionId) {
        require(auctions[auctionId].isEntity, "auction does not exist");
        _;
    }

    // Throws if the block.timestamp is before the start time or after bidding end time
    modifier duringBid(uint256 auctionId) {
        require(
            block.timestamp >= auctions[auctionId].startTime && block.timestamp < auctions[auctionId].bidEndTime,
            "invalid time to bid"
        );
        _;
    }

    // Throws if the block.timestamp is before the biding end time(claiming start time) or after claiming end time
    modifier duringClaim(uint256 auctionId) {
        require(
            block.timestamp >= auctions[auctionId].bidEndTime && block.timestamp < auctions[auctionId].claimEndTime,
            "invalid time to claim"
        );
        _;
    }

    /*** Contract Logic Starts Here */

    constructor(address _claimingPool) {
        nextAuctionId = 1;
        maxCreatorSharePercent = onePercent * 25;
        maxSharingSharePercent = onePercent * 15;
        minProtocolFeePercent = onePercent / 5;
        maxProtocolFeePercent = onePercent * 10;
        _setClaimingPool(_claimingPool);
    }

    /*** Owner Functions ***/

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Owner function: Set the claiming pool address where the fee get accumulated
     *
     * @param _claimingPool address of claim pool
     */
    function setClaimingPool(address _claimingPool) external onlyOwner {
        _setClaimingPool(_claimingPool);
    }

    /**
     * @dev Owner function: Set the ranges of creator share, sharing share, fee percent
     *
     * @param _maxCreatorSharePercent the max percent of creator share
     * @param _maxSharingSharePercent the max percent of sharing share
     * @param _minProtocolFeePercent the min percent of fee
     * @param _maxProtocolFeePercent the max percent of fee
     */
    function setSharesAndProtocolFeePercent(
        uint256 _maxCreatorSharePercent,
        uint256 _maxSharingSharePercent,
        uint256 _minProtocolFeePercent,
        uint256 _maxProtocolFeePercent
    ) external onlyOwner {
        require(
            _maxCreatorSharePercent + _maxSharingSharePercent + _maxProtocolFeePercent < hundredPercent,
            "the sum should be less than one hundred percent"
        );

        maxCreatorSharePercent = _maxCreatorSharePercent;
        maxSharingSharePercent = _maxSharingSharePercent;
        minProtocolFeePercent = _minProtocolFeePercent;
        maxProtocolFeePercent = _maxProtocolFeePercent;
    }

    /**
     * @dev Owner function: Set the address of artist who can claim fund during the claming period
     *
     * @param auctionId The identifier of auction
     * @param artist The address of verified artist
     */
    function verifyArtist(uint256 auctionId, address artist) external onlyOwner auctionExists(auctionId) {
        require(artist != address(0x0), "invalid artist address");
        auctions[auctionId].verifiedArtist = artist;
        emit VerifyArtist(auctionId, artist);
    }

    /**
     * @dev Owner function: Share the sharingShare of the auction to the list of users
     *
     * @param auctionId The identifier of auction
     * @param users The list of addresses to get sharing shares
     */
    function sharedPod(uint256 auctionId, address[] calldata users) external onlyOwner auctionExists(auctionId) {
        require(users.length > 0, "empty user list");
        require(auctions[auctionId].sharingSharePercent > 0, "sharing share is zero");
        require(block.timestamp > auctions[auctionId].bidEndTime, "invalid time");

        (, uint256 lastRemaining) =
            _calculateFeeAndRemaining(auctions[auctionId].lastHighDeposit, auctions[auctionId].feePercent);

        uint256 sharesPerUser =
            (lastRemaining * auctions[auctionId].sharingSharePercent) / hundredPercent / users.length;

        for (uint256 i = 0; i < users.length; i++) {
            sharingShares[auctionId][users[i]] = sharesPerUser;
        }

        emit SharedPod(auctionId, users.length, sharesPerUser);
    }

    /*** View Functions ***/

    /**
     * @dev Returns the all properties of the auction
     *
     * @param auctionId The identifier of auction
     */
    function getAuction(uint256 auctionId)
        public
        view
        auctionExists(auctionId)
        returns (
            address creator,
            uint256 creatorSharePercent,
            uint256 sharingSharePercent,
            uint256 startTime,
            uint256 bidEndTime,
            uint256 claimEndTime,
            uint256 feePercent,
            uint256 lastHighDeposit,
            address depositor,
            address tokenAddress,
            address verifiedArtist,
            AuctionState state
        )
    {
        creator = auctions[auctionId].creator;
        creatorSharePercent = auctions[auctionId].creatorSharePercent;
        sharingSharePercent = auctions[auctionId].sharingSharePercent;
        startTime = auctions[auctionId].startTime;
        bidEndTime = auctions[auctionId].bidEndTime;
        claimEndTime = auctions[auctionId].claimEndTime;
        feePercent = auctions[auctionId].feePercent;
        lastHighDeposit = auctions[auctionId].lastHighDeposit;
        depositor = auctions[auctionId].depositor;
        tokenAddress = auctions[auctionId].tokenAddress;
        verifiedArtist = auctions[auctionId].verifiedArtist;
        state = auctions[auctionId].state;
    }

    /**
     * @dev Returns the sharing share of the user
     * Note that this could be wrong unless the owner called the sharedPod function
     *
     * @param auctionId The identifier of auction
     * @param user The address of user
     */
    function getSharingShare(uint256 auctionId, address user) public view auctionExists(auctionId) returns (uint256) {
        return sharingShares[auctionId][user];
    }

    /**
     * @dev Returns the claimable fund of by an aritist
     * Note that this could be wrong during the bidding period
     *
     * @param auctionId The identifier of auction
     */
    function getClaimableFund(uint256 auctionId) public view auctionExists(auctionId) returns (uint256 claimableFund) {
        (claimableFund, ) = _calculateClaimableFundAndShares(auctionId);
    }

    /*** Public Effects & Interactions Functions ***/

    /**
     * @dev Create a new auction
     *
     * @param creatorSharePercent The fund share for the auction creator
     * @param sharingSharePercent The fund share for users who shared the auction
     * @param startTime The unix timestamp for when the auction starts.
     * @param bidEndTime The unix timestamp for when the bid ends.
     * @param claimEndTime The unix timestamp for when the claim ends.
     * @param feePercent The portion of bid deposit charged as fee.
     * @param tokenAddress The ERC20 token to use as auction currency.
     * @return The uint256 id of the newly created auction.
     */
    function createPodAuction(
        uint256 creatorSharePercent,
        uint256 sharingSharePercent,
        uint256 startTime,
        uint256 bidEndTime,
        uint256 claimEndTime,
        uint256 feePercent,
        address tokenAddress
    ) external whenNotPaused returns (uint256) {
        require(creatorSharePercent <= maxCreatorSharePercent, "invalid creator share");
        require(sharingSharePercent <= maxSharingSharePercent, "invalid sharing share");
        require(startTime >= block.timestamp, "start time before block.timestamp");
        require(bidEndTime > startTime, "bid end time before the start time");
        require(claimEndTime > bidEndTime, "claim end time before the bid end time");
        require(feePercent >= onePercent / 5 && feePercent <= onePercent * 10, "invalid fee value");

        uint256 auctionId = nextAuctionId;
        auctions[auctionId] = Auction({
            creator: _msgSender(),
            creatorSharePercent: creatorSharePercent,
            sharingSharePercent: sharingSharePercent,
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

        emit CreatePodAuction(
            _msgSender(),
            tokenAddress,
            creatorSharePercent,
            sharingSharePercent,
            startTime,
            bidEndTime,
            claimEndTime,
            feePercent
        );
        return nextAuctionId;
    }

    /**
     * @dev Bid to an auction
     * Notice that if the new deposit amount is less than the highest deposit so far, then it reverts.
     * If the new deposit is higher than last high deposit, then auto pay back to the last depositer.
     *
     * @param auctionId The identifier of auction
     * @param deposit The amount of token to deposit
     * @return Returns true is success
     */
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

        if (lastDepositor != address(0x0)) {
            require(IERC20(auction.tokenAddress).transfer(lastDepositor, lastRemaining), "token transfer failure");
        }

        require(IERC20(auction.tokenAddress).transfer(claimingPool, fee), "token transfer failure");

        emit Bid(auctionId, _msgSender(), deposit);
        return true;
    }

    /**
     * @dev Withdraw the bid
     * Notice that if the bidder only can withdraw the his bid after claming period is ended
     * and the artist didn't claimed the fund
     *
     * @param auctionId The identifier of auction
     * @return The withdrawed amount
     */
    function withdrawBid(uint256 auctionId)
        external
        whenNotPaused
        nonReentrant
        auctionExists(auctionId)
        returns (uint256)
    {
        Auction storage auction = auctions[auctionId];
        require(block.timestamp > auction.claimEndTime, "invalid time to withdraw");
        require(auction.depositor == _msgSender(), "invalid address to withdraw");
        require(auction.state == AuctionState.INITIATED, "invalid auction state to withdraw");

        (, uint256 lastRemaining) = _calculateFeeAndRemaining(auction.lastHighDeposit, auction.feePercent);

        auction.state = AuctionState.WITHDRAWED;

        require(IERC20(auction.tokenAddress).transfer(auction.depositor, lastRemaining), "token transfer failure");

        emit WithdrawBid(auctionId, _msgSender(), lastRemaining);
        return lastRemaining;
    }

    /**
     * @dev Claim the fund by the verified artist
     * The artist who is already verified artist can only claimed the fund during the claming period.
     * Notice that it also transfer the creatorShare to the auction creator.
     *
     * @param auctionId The identifier of auction
     * @return The fund amounts withdrawed to the artist and creator
     */
    function claimFunds(uint256 auctionId)
        external
        whenNotPaused
        nonReentrant
        auctionExists(auctionId)
        duringClaim(auctionId)
        returns (uint256, uint256)
    {
        Auction storage auction = auctions[auctionId];
        require(auction.verifiedArtist == _msgSender(), "invalid address to claim");
        require(auction.state == AuctionState.INITIATED, "invalid auction state to claim");

        (uint256 claimableFund, uint256 creatorShare) = _calculateClaimableFundAndShares(auctionId);

        auction.state = AuctionState.CLAIMED;

        require(IERC20(auction.tokenAddress).transfer(auction.creator, creatorShare), "token transfer failure");

        require(IERC20(auction.tokenAddress).transfer(auction.verifiedArtist, claimableFund), "token transfer failure");

        emit ClaimFund(auctionId, auction.verifiedArtist, claimableFund);
        return (claimableFund, creatorShare);
    }

    function claimSharingShare(uint256 auctionId)
        external
        whenNotPaused
        nonReentrant
        auctionExists(auctionId)
        returns (uint256)
    {
        uint256 sharingShare = sharingShares[auctionId][_msgSender()];
        require(sharingShares[auctionId][_msgSender()] > 0, "no shares to claim");

        sharingShares[auctionId][_msgSender()] = 0;

        require(
            IERC20(auctions[auctionId].tokenAddress).transfer(_msgSender(), sharingShare),
            "token transfer failure"
        );

        emit ClaimSharingShare(auctionId, _msgSender(), sharingShare);
        return sharingShare;
    }

    /*** Internal Functions ***/

    function _calculateClaimableFundAndShares(uint256 auctionId) internal view returns (uint256, uint256) {
        (, uint256 lastRemaining) =
            _calculateFeeAndRemaining(auctions[auctionId].lastHighDeposit, auctions[auctionId].feePercent);
        uint256 creatorShare = (lastRemaining * auctions[auctionId].creatorSharePercent) / hundredPercent;
        uint256 sharingShare = (lastRemaining * auctions[auctionId].sharingSharePercent) / hundredPercent;
        uint256 claimable = lastRemaining - creatorShare - sharingShare;
        return (claimable, creatorShare);
    }

    function _calculateFeeAndRemaining(uint256 deposit, uint256 feePercent)
        internal
        pure
        returns (uint256 fee, uint256 remaining)
    {
        fee = (deposit * feePercent) / hundredPercent;
        remaining = deposit - fee;
    }

    function _setClaimingPool(address _claimingPool) internal {
        claimingPool = _claimingPool;
        emit SetClaimingPool(_claimingPool);
    }
}
