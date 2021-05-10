import hre from "hardhat";
import { Artifact } from "hardhat/types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";
import { BigNumber } from "@ethersproject/bignumber";
import { expect } from "chai";

import { PriviPodAuction } from "../typechain/PriviPodAuction";
import { MockERC20 } from "../typechain/MockERC20";

import { ether, getTimeStamp, increaseTime, getSnapShot, revertEvm, ADDRESS_ZERO, ZERO, MAX_UINT_256 } from "../utils";

import { Auction } from "../types";

const { deployContract } = hre.waffle;

const ONE_HOUR = 3600;

describe("PriviPodAuction Test", () => {
  let owner: SignerWithAddress;
  let ownerAddress: string;
  let creator: SignerWithAddress;
  let creatorAddress: string;
  let artist: SignerWithAddress;
  let artistAddress: string;
  let feePoolAddress: string;
  let bidders: Array<SignerWithAddress> = [];
  let bidderAddresses: Array<string> = [];

  let auctionContract: PriviPodAuction;
  let tokenContract: MockERC20;

  let startTime: number;
  let bidEndTime: number;
  let claimEndTime: number;
  let creatorSharePercent: BigNumber;
  let sharingSharePercent: BigNumber;
  let feePercent: BigNumber;

  let auctionId: number;

  let onePercent = ether(1).div(100);
  let hundredPercent = ether(1);
  let providerEvmId: any;

  before(async () => {
    const signers: SignerWithAddress[] = await hre.ethers.getSigners();

    owner = signers[0];
    creator = signers[1];
    artist = signers[2];
    bidders.push(signers[3]);
    bidderAddresses.push(await signers[3].getAddress());
    bidders.push(signers[4]);
    bidderAddresses.push(await signers[4].getAddress());
    bidders.push(signers[5]);
    bidderAddresses.push(await signers[5].getAddress());

    ownerAddress = await owner.getAddress();
    creatorAddress = await creator.getAddress();
    artistAddress = await artist.getAddress();
    feePoolAddress = await signers[6].getAddress();

    const auctionArtifact: Artifact = await hre.artifacts.readArtifact("PriviPodAuction");
    auctionContract = <PriviPodAuction>await deployContract(owner, auctionArtifact, [feePoolAddress]);

    const tokenArtifact: Artifact = await hre.artifacts.readArtifact("MockERC20");
    tokenContract = <MockERC20>await deployContract(owner, tokenArtifact);

    providerEvmId = await getSnapShot();
  });

  describe("createPodAuction", async () => {
    beforeEach(async () => {
      const now = await getTimeStamp();
      startTime = now + ONE_HOUR; // start after 1 hour
      bidEndTime = startTime + ONE_HOUR; // bid end after 1 hour;
      claimEndTime = bidEndTime + ONE_HOUR; // claim end after 1 hour
      auctionId = 1;
      creatorSharePercent = onePercent.mul(25);
      sharingSharePercent = onePercent.mul(15);
      feePercent = onePercent.mul(10);
      auctionContract = auctionContract.connect(creator);
    });

    it("should revert with invalid creator share percent", async () => {
      creatorSharePercent = onePercent.mul(30);

      await expect(
        auctionContract.createPodAuction(
          creatorSharePercent,
          sharingSharePercent,
          startTime,
          bidEndTime,
          claimEndTime,
          feePercent,
          tokenContract.address,
        ),
      ).to.be.revertedWith("invalid creator share");
    });

    it("should revert with invalid sharing share percent", async () => {
      sharingSharePercent = onePercent.mul(30);

      await expect(
        auctionContract.createPodAuction(
          creatorSharePercent,
          sharingSharePercent,
          startTime,
          bidEndTime,
          claimEndTime,
          feePercent,
          tokenContract.address,
        ),
      ).to.be.revertedWith("invalid sharing share");
    });

    it("should revert with invalid fee percent", async () => {
      feePercent = onePercent.mul(30);

      await expect(
        auctionContract.createPodAuction(
          creatorSharePercent,
          sharingSharePercent,
          startTime,
          bidEndTime,
          claimEndTime,
          feePercent,
          tokenContract.address,
        ),
      ).to.be.revertedWith("invalid fee value");
    });

    it("should revert with invalid start time", async () => {
      startTime = startTime - ONE_HOUR;

      await expect(
        auctionContract.createPodAuction(
          creatorSharePercent,
          sharingSharePercent,
          startTime,
          bidEndTime,
          claimEndTime,
          feePercent,
          tokenContract.address,
        ),
      ).to.be.revertedWith("start time before block.timestamp");
    });

    it("should revert with invalid bid end time", async () => {
      bidEndTime = startTime - 1;

      await expect(
        auctionContract.createPodAuction(
          creatorSharePercent,
          sharingSharePercent,
          startTime,
          bidEndTime,
          claimEndTime,
          feePercent,
          tokenContract.address,
        ),
      ).to.be.revertedWith("bid end time before the start time");
    });

    it("should revert with invalid claim end time", async () => {
      claimEndTime = bidEndTime - 1;

      await expect(
        auctionContract.createPodAuction(
          creatorSharePercent,
          sharingSharePercent,
          startTime,
          bidEndTime,
          claimEndTime,
          feePercent,
          tokenContract.address,
        ),
      ).to.be.revertedWith("claim end time before the bid end time");
    });

    it("should revert with invalid fee percent", async () => {
      feePercent = BigNumber.from("0");

      await expect(
        auctionContract.createPodAuction(
          creatorSharePercent,
          sharingSharePercent,
          startTime,
          bidEndTime,
          claimEndTime,
          feePercent,
          tokenContract.address,
        ),
      ).to.be.revertedWith("invalid fee value");
    });

    it("should create an auction", async () => {
      await auctionContract.createPodAuction(
        creatorSharePercent,
        sharingSharePercent,
        startTime,
        bidEndTime,
        claimEndTime,
        feePercent,
        tokenContract.address,
      );

      auctionId = 1;

      const newAuction = <Auction>await auctionContract.getAuction(auctionId);
      expect(newAuction.creator).to.equal(creatorAddress);
      expect(newAuction.creatorSharePercent).to.equal(creatorSharePercent);
      expect(newAuction.sharingSharePercent).to.equal(sharingSharePercent);
      expect(newAuction.startTime).to.equal(BigNumber.from(startTime));
      expect(newAuction.claimEndTime).to.equal(BigNumber.from(claimEndTime));
      expect(newAuction.feePercent).to.equal(BigNumber.from(feePercent));
      expect(newAuction.lastHighDeposit).to.equal(ZERO);
      expect(newAuction.depositor).to.equal(ADDRESS_ZERO);
      expect(newAuction.state).to.equal(0);
    });
  });

  describe("bid", async () => {
    // before(async () => {
    //   await increaseTime(ONE_HOUR / 2);
    // });

    before(async () => {
      await tokenContract.mint(bidderAddresses[0], ether(100));
      await tokenContract.mint(bidderAddresses[1], ether(100));
      await tokenContract.mint(bidderAddresses[2], ether(100));

      await tokenContract.connect(bidders[0]).approve(auctionContract.address, MAX_UINT_256);
      await tokenContract.connect(bidders[1]).approve(auctionContract.address, MAX_UINT_256);
      await tokenContract.connect(bidders[2]).approve(auctionContract.address, MAX_UINT_256);
    });

    it("should be fail before start time", async () => {
      auctionContract = auctionContract.connect(bidders[0]);
      await expect(auctionContract.bid(auctionId, ether(1))).to.be.revertedWith("invalid time to bid");
    });

    it("should be success after star time", async () => {
      await increaseTime(ONE_HOUR);
      const deposit = ether(1);
      const fee = deposit.mul(feePercent).div(hundredPercent);
      const delta = deposit.sub(fee);

      await auctionContract.bid(auctionId, deposit);

      const auction = <Auction>await auctionContract.getAuction(auctionId);
      expect(auction.lastHighDeposit).to.equal(deposit);
      expect(auction.depositor).to.equal(bidderAddresses[0]);

      expect(await tokenContract.balanceOf(bidderAddresses[0])).to.equal(ether(100).sub(deposit));
      expect(await tokenContract.balanceOf(auctionContract.address)).to.equal(delta);
      expect(await tokenContract.balanceOf(feePoolAddress)).to.equal(fee);
    });

    it("should be failed with lower deposit", async () => {
      await expect(auctionContract.connect(bidders[1]).bid(auctionId, ether(1).div(2))).to.be.revertedWith(
        "deposit is lower than the high deposit",
      );
    });

    it("should success with higher deposit and auto withdraw the last deposit", async () => {
      const deposit = ether(2);
      const fee = deposit.mul(feePercent).div(hundredPercent);
      const delta = deposit.sub(fee);

      const bidder0Balance = await tokenContract.balanceOf(bidderAddresses[0]);
      const auctionContractBalance = await tokenContract.balanceOf(auctionContract.address);
      const feePoolBalance = await tokenContract.balanceOf(feePoolAddress);

      await auctionContract.connect(bidders[1]).bid(auctionId, deposit);
      const auction = <Auction>await auctionContract.getAuction(auctionId);
      expect(auction.lastHighDeposit).to.equal(deposit);
      expect(auction.depositor).to.equal(bidderAddresses[1]);

      expect(await tokenContract.balanceOf(auctionContract.address)).to.equal(delta);
      expect(await tokenContract.balanceOf(feePoolAddress)).to.equal(feePoolBalance.add(fee));
      expect(await tokenContract.balanceOf(bidderAddresses[0])).to.equal(bidder0Balance.add(auctionContractBalance));
    });

    it("should be revert after bid end time", async () => {
      await increaseTime(ONE_HOUR);

      await expect(auctionContract.connect(bidders[2]).bid(auctionId, ether(3))).to.be.revertedWith(
        "invalid time to bid",
      );
    });
  });

  describe("claimFunds & claimSharingShare", async () => {
    let balance: BigNumber;
    let creatorShare: BigNumber;
    let sharingShare: BigNumber;
    let claimableFund: BigNumber;

    before(async () => {
      await auctionContract.connect(owner).verifyArtist(auctionId, artistAddress);
      await auctionContract.connect(owner).sharedPod(auctionId, bidderAddresses);
    });

    it("should be revert if not artist", async () => {
      await expect(auctionContract.connect(bidders[2]).claimFunds(auctionId)).to.be.revertedWith(
        "invalid address to claim",
      );
    });

    it("should claim the raised fund by artist", async () => {
      balance = await tokenContract.balanceOf(auctionContract.address);
      creatorShare = balance.mul(creatorSharePercent).div(hundredPercent);
      sharingShare = balance.mul(sharingSharePercent).div(hundredPercent);
      claimableFund = balance.sub(creatorShare).sub(sharingShare);

      await auctionContract.connect(artist).claimFunds(auctionId);

      expect(await tokenContract.balanceOf(artistAddress)).to.be.equal(claimableFund);
      expect(await tokenContract.balanceOf(creatorAddress)).to.be.equal(creatorShare);
    });

    it("should claim the sharing share", async () => {
      const sharingSharePerUser = sharingShare.div(3);

      await auctionContract.connect(bidders[0]).claimSharingShare(auctionId);
      await auctionContract.connect(bidders[1]).claimSharingShare(auctionId);
      await auctionContract.connect(bidders[2]).claimSharingShare(auctionId);

      expect(await tokenContract.balanceOf(bidderAddresses[2])).to.equal(ether(100).add(sharingSharePerUser));
    });

    it("should be reverted on double claim", async () => {
      await expect(auctionContract.connect(artist).claimFunds(auctionId)).to.be.revertedWith(
        "invalid auction state to claim",
      );

      await expect(auctionContract.connect(bidders[0]).claimSharingShare(auctionId)).to.be.revertedWith(
        "no shares to claim",
      );
    });
  });

  after(async () => {
    await revertEvm(providerEvmId);
  });
});
