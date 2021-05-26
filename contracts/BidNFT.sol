// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./libraries/EnumerableMap.sol";
import "./interfaces/IBidNFT.sol";

/**
 * @title Bid NFT
 * @author 0xlook
 */
contract BidNFT is IBidNFT, ERC721Holder, Ownable, Pausable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address;
    using EnumerableMap for EnumerableMap.UintToUintMap;
    using EnumerableSet for EnumerableSet.UintSet;

    struct AskEntry {
        uint256 tokenId;
        uint256 price;
    }

    struct BidEntry {
        address bidder;
        uint256 price;
    }

    struct UserBidEntry {
        uint256 tokenId;
        uint256 price;
    }

    IERC721 public nft;
    IERC20 public quoteErc20;
    address public feeAddr;
    uint256 public feePercent;
    EnumerableMap.UintToUintMap private _asksMap;
    mapping(uint256 => address) private _tokenSellers;
    mapping(address => EnumerableSet.UintSet) private _userSellingTokens;
    mapping(uint256 => BidEntry[]) private _tokenBids;
    mapping(address => EnumerableMap.UintToUintMap) private _userBids;

    event Trade(address indexed seller, address indexed buyer, uint256 indexed tokenId, uint256 price, uint256 fee);
    event Ask(address indexed seller, uint256 indexed tokenId, uint256 price);
    event CancelSellToken(address indexed seller, uint256 indexed tokenId);
    event FeeAddressTransferred(address indexed previousOwner, address indexed newOwner);
    event SetFeePercent(address indexed seller, uint256 oldFeePercent, uint256 newFeePercent);
    event Bid(address indexed bidder, uint256 indexed tokenId, uint256 price);
    event CancelBidToken(address indexed bidder, uint256 indexed tokenId);

    constructor(
        address _nftAddress,
        address _quoteErc20Address,
        address _feeAddr,
        uint256 _feePercent
    ) public {
        require(_nftAddress != address(0) && _nftAddress != address(this));
        require(_quoteErc20Address != address(0) && _quoteErc20Address != address(this));
        nft = IERC721(_nftAddress);
        quoteErc20 = IERC20(_quoteErc20Address);
        feeAddr = _feeAddr;
        feePercent = _feePercent;
        emit FeeAddressTransferred(address(0), feeAddr);
        emit SetFeePercent(_msgSender(), 0, feePercent);
    }

    function buyToken(uint256 _tokenId) public override whenNotPaused {
        buyTokenTo(_tokenId, _msgSender());
    }

    function buyTokenTo(uint256 _tokenId, address _to) public override whenNotPaused {
        require(_msgSender() != address(0) && _msgSender() != address(this), "Wrong msg sender");
        require(_asksMap.contains(_tokenId), "Token not in sell book");
        require(!_userBids[_msgSender()].contains(_tokenId), "You must cancel your bid first");
        nft.safeTransferFrom(address(this), _to, _tokenId);
        uint256 price = _asksMap.get(_tokenId);
        uint256 feeAmount = price.mul(feePercent).div(100);
        if (feeAmount != 0) {
            quoteErc20.safeTransferFrom(_msgSender(), feeAddr, feeAmount);
        }
        quoteErc20.safeTransferFrom(_msgSender(), _tokenSellers[_tokenId], price.sub(feeAmount));
        _asksMap.remove(_tokenId);
        _userSellingTokens[_tokenSellers[_tokenId]].remove(_tokenId);
        emit Trade(_tokenSellers[_tokenId], _to, _tokenId, price, feeAmount);
        delete _tokenSellers[_tokenId];
    }

    function setCurrentPrice(uint256 _tokenId, uint256 _price) public override whenNotPaused {
        require(_userSellingTokens[_msgSender()].contains(_tokenId), "Only Seller can update price");
        require(_price != 0, "Price must be granter than zero");
        _asksMap.set(_tokenId, _price);
        emit Ask(_msgSender(), _tokenId, _price);
    }

    function readyToSellToken(uint256 _tokenId, uint256 _price) public override whenNotPaused {
        readyToSellTokenTo(_tokenId, _price, address(_msgSender()));
    }

    function readyToSellTokenTo(
        uint256 _tokenId,
        uint256 _price,
        address _to
    ) public override whenNotPaused {
        require(_msgSender() == nft.ownerOf(_tokenId), "Only Token Owner can sell token");
        require(_price != 0, "Price must be granter than zero");
        nft.safeTransferFrom(address(_msgSender()), address(this), _tokenId);
        _asksMap.set(_tokenId, _price);
        _tokenSellers[_tokenId] = _to;
        _userSellingTokens[_to].add(_tokenId);
        emit Ask(_to, _tokenId, _price);
    }

    function cancelSellToken(uint256 _tokenId) public override whenNotPaused {
        require(_userSellingTokens[_msgSender()].contains(_tokenId), "Only Seller can cancel sell token");
        nft.safeTransferFrom(address(this), _msgSender(), _tokenId);
        _asksMap.remove(_tokenId);
        _userSellingTokens[_tokenSellers[_tokenId]].remove(_tokenId);
        delete _tokenSellers[_tokenId];
        emit CancelSellToken(_msgSender(), _tokenId);
    }

    function getAskLength() public view returns (uint256) {
        return _asksMap.length();
    }

    function getAsks() public view returns (AskEntry[] memory) {
        AskEntry[] memory asks = new AskEntry[](_asksMap.length());
        for (uint256 i = 0; i < _asksMap.length(); ++i) {
            (uint256 tokenId, uint256 price) = _asksMap.at(i);
            asks[i] = AskEntry({ tokenId: tokenId, price: price });
        }
        return asks;
    }

    function getAsksDesc() public view returns (AskEntry[] memory) {
        AskEntry[] memory asks = new AskEntry[](_asksMap.length());
        if (_asksMap.length() > 0) {
            for (uint256 i = _asksMap.length() - 1; i > 0; --i) {
                (uint256 tokenId, uint256 price) = _asksMap.at(i);
                asks[_asksMap.length() - 1 - i] = AskEntry({ tokenId: tokenId, price: price });
            }
            (uint256 tokenId, uint256 price) = _asksMap.at(0);
            asks[_asksMap.length() - 1] = AskEntry({ tokenId: tokenId, price: price });
        }
        return asks;
    }

    function getAsksByPage(uint256 page, uint256 size) public view returns (AskEntry[] memory) {
        if (_asksMap.length() > 0) {
            uint256 from = page == 0 ? 0 : (page - 1) * size;
            uint256 to = Math.min((page == 0 ? 1 : page) * size, _asksMap.length());
            AskEntry[] memory asks = new AskEntry[]((to - from));
            for (uint256 i = 0; from < to; ++i) {
                (uint256 tokenId, uint256 price) = _asksMap.at(from);
                asks[i] = AskEntry({ tokenId: tokenId, price: price });
                ++from;
            }
            return asks;
        } else {
            return new AskEntry[](0);
        }
    }

    function getAsksByPageDesc(uint256 page, uint256 size) public view returns (AskEntry[] memory) {
        if (_asksMap.length() > 0) {
            uint256 from = _asksMap.length() - 1 - (page == 0 ? 0 : (page - 1) * size);
            uint256 to = _asksMap.length() - 1 - Math.min((page == 0 ? 1 : page) * size - 1, _asksMap.length() - 1);
            uint256 resultSize = from - to + 1;
            AskEntry[] memory asks = new AskEntry[](resultSize);
            if (to == 0) {
                for (uint256 i = 0; from > to; ++i) {
                    (uint256 tokenId, uint256 price) = _asksMap.at(from);
                    asks[i] = AskEntry({ tokenId: tokenId, price: price });
                    --from;
                }
                (uint256 tokenId, uint256 price) = _asksMap.at(0);
                asks[resultSize - 1] = AskEntry({ tokenId: tokenId, price: price });
            } else {
                for (uint256 i = 0; from >= to; ++i) {
                    (uint256 tokenId, uint256 price) = _asksMap.at(from);
                    asks[i] = AskEntry({ tokenId: tokenId, price: price });
                    --from;
                }
            }
            return asks;
        }
        return new AskEntry[](0);
    }

    function getAsksByUser(address user) public view returns (AskEntry[] memory) {
        AskEntry[] memory asks = new AskEntry[](_userSellingTokens[user].length());
        for (uint256 i = 0; i < _userSellingTokens[user].length(); ++i) {
            uint256 tokenId = _userSellingTokens[user].at(i);
            uint256 price = _asksMap.get(tokenId);
            asks[i] = AskEntry({ tokenId: tokenId, price: price });
        }
        return asks;
    }

    function getAsksByUserDesc(address user) public view returns (AskEntry[] memory) {
        AskEntry[] memory asks = new AskEntry[](_userSellingTokens[user].length());
        if (_userSellingTokens[user].length() > 0) {
            for (uint256 i = _userSellingTokens[user].length() - 1; i > 0; --i) {
                uint256 tokenId = _userSellingTokens[user].at(i);
                uint256 price = _asksMap.get(tokenId);
                asks[_userSellingTokens[user].length() - 1 - i] = AskEntry({ tokenId: tokenId, price: price });
            }
            uint256 tokenId = _userSellingTokens[user].at(0);
            uint256 price = _asksMap.get(tokenId);
            asks[_userSellingTokens[user].length() - 1] = AskEntry({ tokenId: tokenId, price: price });
        }
        return asks;
    }

    function pause() public onlyOwner whenNotPaused {
        _pause();
    }

    function unpause() public onlyOwner whenPaused {
        _unpause();
    }

    function transferFeeAddress(address _feeAddr) public {
        require(_msgSender() == feeAddr, "FORBIDDEN");
        feeAddr = _feeAddr;
        emit FeeAddressTransferred(_msgSender(), feeAddr);
    }

    function setFeePercent(uint256 _feePercent) public onlyOwner {
        require(feePercent != _feePercent, "Not need update");
        emit SetFeePercent(_msgSender(), feePercent, _feePercent);
        feePercent = _feePercent;
    }

    function bidToken(uint256 _tokenId, uint256 _price) public override whenNotPaused {
        require(_msgSender() != address(0) && _msgSender() != address(this), "Wrong msg sender");
        require(_price != 0, "Price must be granter than zero");
        require(_asksMap.contains(_tokenId), "Token not in sell book");
        address _seller = _tokenSellers[_tokenId];
        address _to = address(_msgSender());
        require(_seller != _to, "Owner cannot bid");
        require(!_userBids[_to].contains(_tokenId), "Bidder already exists");
        quoteErc20.safeTransferFrom(address(_msgSender()), address(this), _price);
        _userBids[_to].set(_tokenId, _price);
        _tokenBids[_tokenId].push(BidEntry({ bidder: _to, price: _price }));
        emit Bid(_msgSender(), _tokenId, _price);
    }

    function updateBidPrice(uint256 _tokenId, uint256 _price) public override whenNotPaused {
        require(_userBids[_msgSender()].contains(_tokenId), "Only Bidder can update the bid price");
        require(_price != 0, "Price must be granter than zero");
        address _to = address(_msgSender()); // find  bid and the index
        (BidEntry memory bidEntry, uint256 _index) = getBidByTokenIdAndAddress(_tokenId, _to);
        require(bidEntry.price != 0, "Bidder does not exist");
        require(bidEntry.price != _price, "The bid price cannot be the same");
        if (_price > bidEntry.price) {
            quoteErc20.safeTransferFrom(address(_msgSender()), address(this), _price - bidEntry.price);
        } else {
            quoteErc20.transfer(_to, bidEntry.price - _price);
        }
        _userBids[_to].set(_tokenId, _price);
        _tokenBids[_tokenId][_index] = BidEntry({ bidder: _to, price: _price });
        emit Bid(_msgSender(), _tokenId, _price);
    }

    function getBidByTokenIdAndAddress(uint256 _tokenId, address _address)
        private
        view
        returns (BidEntry memory, uint256)
    {
        // find the index of the bid
        BidEntry[] memory bidEntries = _tokenBids[_tokenId];
        uint256 len = bidEntries.length;
        uint256 _index;
        BidEntry memory bidEntry;
        for (uint256 i = 0; i < len; i++) {
            if (_address == bidEntries[i].bidder) {
                _index = i;
                bidEntry = BidEntry({ bidder: bidEntries[i].bidder, price: bidEntries[i].price });
                break;
            }
        }
        return (bidEntry, _index);
    }

    function delBidByTokenIdAndIndex(uint256 _tokenId, uint256 _index) private {
        _userBids[_tokenBids[_tokenId][_index].bidder].remove(_tokenId);
        // delete the bid
        uint256 len = _tokenBids[_tokenId].length;
        for (uint256 i = _index; i < len - 1; i++) {
            _tokenBids[_tokenId][i] = _tokenBids[_tokenId][i + 1];
        }
        _tokenBids[_tokenId].pop();
    }

    function sellTokenTo(uint256 _tokenId, address _to) public override whenNotPaused {
        require(_asksMap.contains(_tokenId), "Token not in sell book");
        address _seller = _tokenSellers[_tokenId];
        address _owner = address(_msgSender());
        require(_seller == _owner, "Only owner can sell token");
        // find  bid and the index
        (BidEntry memory bidEntry, uint256 _index) = getBidByTokenIdAndAddress(_tokenId, _to);
        require(bidEntry.price != 0, "Bidder does not exist");
        // transfer token to bidder
        nft.safeTransferFrom(address(this), _to, _tokenId);
        uint256 price = bidEntry.price;
        uint256 feeAmount = price.mul(feePercent).div(100);
        if (feeAmount != 0) {
            quoteErc20.transfer(feeAddr, feeAmount);
        }
        quoteErc20.transfer(_seller, price.sub(feeAmount));
        _asksMap.remove(_tokenId);
        _userSellingTokens[_tokenSellers[_tokenId]].remove(_tokenId);
        delBidByTokenIdAndIndex(_tokenId, _index);
        emit Trade(_tokenSellers[_tokenId], _to, _tokenId, price, feeAmount);
        delete _tokenSellers[_tokenId];
    }

    function cancelBidToken(uint256 _tokenId) public override whenNotPaused {
        require(_userBids[_msgSender()].contains(_tokenId), "Only Bidder can cancel the bid");
        address _address = address(_msgSender());
        // find  bid and the index
        (BidEntry memory bidEntry, uint256 _index) = getBidByTokenIdAndAddress(_tokenId, _address);
        require(bidEntry.price != 0, "Bidder does not exist");
        quoteErc20.transfer(_address, bidEntry.price);
        delBidByTokenIdAndIndex(_tokenId, _index);
        emit CancelBidToken(_msgSender(), _tokenId);
    }

    function getBidsLength(uint256 _tokenId) public view returns (uint256) {
        return _tokenBids[_tokenId].length;
    }

    function getBids(uint256 _tokenId) public view returns (BidEntry[] memory) {
        return _tokenBids[_tokenId];
    }

    function getUserBids(address user) public view returns (UserBidEntry[] memory) {
        uint256 len = _userBids[user].length();
        UserBidEntry[] memory bids = new UserBidEntry[](len);
        for (uint256 i = 0; i < len; i++) {
            (uint256 tokenId, uint256 price) = _userBids[user].at(i);
            bids[i] = UserBidEntry({ tokenId: tokenId, price: price });
        }
        return bids;
    }
}
