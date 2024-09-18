// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract NFTAuction is IERC721Receiver, ReentrancyGuard, Ownable {
    using SafeMath for uint256;

    struct Auction {
        address seller;
        address highestBidder;
        uint256 highestBid;
        uint256 startPrice;
        uint256 endTime;
        uint256 minIncrement;
        bool active;
        mapping(address => uint256) bids;
    }

    IERC721 public nftContract;
    uint256 public auctionCount;
    mapping(uint256 => Auction> public auctions;
    mapping(address => uint256> public pendingReturns;
    uint256 public contractBalance;

    event AuctionStarted(uint256 auctionId, address seller, uint256 startPrice, uint256 endTime, uint256 minIncrement);
    event NewBid(uint256 auctionId, address bidder, uint256 amount);
    event AuctionEnded(uint256 auctionId, address winner, uint256 amount);
    event FundsWithdrawn(address indexed user, uint256 amount);

    constructor(address _nftContract) {
        nftContract = IERC721(_nftContract);
    }

    function startAuction(uint256 _tokenId, uint256 _startPrice, uint256 _duration, uint256 _minIncrement) external payable nonReentrant {
        require(nftContract.ownerOf(_tokenId) == msg.sender, "You must own the NFT");

        uint256 fee = _startPrice.mul(2).div(100);
        require(msg.value == fee, "Must send 2% of start price as fee");
        contractBalance = contractBalance.add(fee);

        auctionCount++;
        Auction storage auction = auctions[auctionCount];
        auction.seller = msg.sender;
        auction.startPrice = _startPrice;
        auction.endTime = block.timestamp.add(_duration);
        auction.minIncrement = _minIncrement;
        auction.active = true;

        nftContract.safeTransferFrom(msg.sender, address(this), _tokenId);

        emit AuctionStarted(auctionCount, msg.sender, _startPrice, auction.endTime, _minIncrement);
    }

    function bid(uint256 _auctionId) external payable nonReentrant {
        Auction storage auction = auctions[_auctionId];
        require(auction.active, "Auction not active");

        require(msg.value > 0, "Bid must be greater than zero");

        uint256 newBid = auction.bids[msg.sender].add(msg.value);
        require(newBid >= auction.startPrice, "Bid must be at least the start price");
        require(newBid >= auction.highestBid.add(auction.minIncrement), "Bid increment too low");

        auction.bids[msg.sender] = newBid;

        if (auction.highestBidder != address(0)) {
            pendingReturns[auction.highestBidder] = pendingReturns[auction.highestBidder].add(auction.highestBid);
        }

        auction.highestBidder = msg.sender;
        auction.highestBid = newBid;

        emit NewBid(_auctionId, msg.sender, newBid);

        // Check if the auction end time has been exceeded
        if (block.timestamp >= auction.endTime) {
            auction.active = false;
        }
    }

    function endAuction(uint256 _auctionId) public nonReentrant {
        Auction storage auction = auctions[_auctionId];
        require(auction.active, "Auction not active");
        require(block.timestamp >= auction.endTime, "Auction not ended yet");

        auction.active = false;

        if (auction.highestBidder != address(0)) {
            nftContract.safeTransferFrom(address(this), auction.highestBidder, _auctionId);
            uint256 commission = auction.highestBid.mul(10).div(100);
            contractBalance = contractBalance.add(commission);
            payable(auction.seller).transfer(auction.highestBid.sub(commission));
        } else {
            nftContract.safeTransferFrom(address(this), auction.seller, _auctionId);
        }

        emit AuctionEnded(_auctionId, auction.highestBidder, auction.highestBid);
    }

    function claimRefund() external nonReentrant {
        uint256 amount = pendingReturns[msg.sender];
        require(amount > 0, "No funds to claim");

        pendingReturns[msg.sender] = 0;
        payable(msg.sender).transfer(amount);

        emit FundsWithdrawn(msg.sender, amount);
    }

    function claimFees() external onlyOwner nonReentrant {
        uint256 amount = contractBalance;
        require(amount > 0, "No fees to claim");

        contractBalance = 0;
        payable(owner()).transfer(amount);

        emit FundsWithdrawn(owner(), amount);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
