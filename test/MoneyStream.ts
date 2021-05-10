import hre from "hardhat";
import { Artifact } from "hardhat/types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";
import { BigNumber } from "@ethersproject/bignumber";
import { expect } from "chai";

import { PriviMoneyStream } from "../typechain/PriviMoneyStream";
import { MockERC20 } from "../typechain/MockERC20";

import { ether, increaseTime, getTimeStamp, getSnapShot, revertEvm } from "../utils";

import { Stream, StreamRequest } from "../types";

const { deployContract } = hre.waffle;

const SECONDS_IN_DAY = 86400;
const ONE_HOUR = 3600;

describe("PriviMoneyStream Test", () => {
  let owner: string;
  let senderAddress: string;
  let receiverAddress: string;
  let deployer: SignerWithAddress;
  let sender: SignerWithAddress;
  let receiver: SignerWithAddress;
  let randUser: SignerWithAddress;
  let streamContract: PriviMoneyStream;
  let tokenContract: MockERC20;

  let startTime: number;
  let endTime: number;
  let deposit: BigNumber;
  let duration: number;
  let streamId: number;
  let streamRequestId: number;
  let providerEvmId: any;

  before(async () => {
    const signers: SignerWithAddress[] = await hre.ethers.getSigners();

    deployer = signers[0];
    sender = signers[1];
    receiver = signers[2];
    randUser = signers[3];
    owner = await deployer.getAddress();
    senderAddress = await sender.getAddress();
    receiverAddress = await receiver.getAddress();

    const streamArtifact: Artifact = await hre.artifacts.readArtifact("PriviMoneyStream");
    streamContract = <PriviMoneyStream>await deployContract(deployer, streamArtifact);

    const tokenArtifact: Artifact = await hre.artifacts.readArtifact("MockERC20");
    tokenContract = <MockERC20>await deployContract(deployer, tokenArtifact);

    providerEvmId = await getSnapShot();
  });

  describe("createStream", async () => {
    beforeEach(async () => {
      tokenContract = tokenContract.connect(sender);
      await tokenContract.mint(senderAddress, ether(100));
      await tokenContract.approve(streamContract.address, ether(100));
    });

    it("should create the stream", async () => {
      streamContract = streamContract.connect(sender);

      const now = await getTimeStamp();
      duration = 10000; // roughly 2.7 hours;
      startTime = now + ONE_HOUR; // start after 1 hour
      endTime = startTime + duration;
      deposit = ether(10);
      streamId = 1;

      await streamContract.createStream(receiverAddress, deposit, tokenContract.address, startTime, endTime);

      const stream = <Stream>await streamContract.getStream(streamId);
      expect(stream.sender).to.equal(senderAddress);
      expect(stream.recipient).to.equal(receiverAddress);
      expect(stream.deposit).to.equal(deposit);
      expect(stream.tokenAddress).to.equal(tokenContract.address);
      expect(stream.startTime).to.equal(BigNumber.from(startTime));
      expect(stream.stopTime).to.equal(BigNumber.from(endTime));
      expect(stream.remainingBalance).to.equal(BigNumber.from(deposit));
    });
  });

  describe("withdrawFromStream", async () => {
    it("should withdraw half of the deposit", async () => {
      const halfTime = ONE_HOUR + duration / 2 - 1;
      await increaseTime(halfTime);

      streamContract = streamContract.connect(receiver);
      const delta = await streamContract.deltaOf(streamId);
      expect(delta).to.equal(BigNumber.from(duration / 2));
      const balance = await streamContract.balanceOf(streamId, receiverAddress);
      expect(balance).to.equal(deposit.div(2));

      await streamContract.withdrawFromStream(streamId, deposit.div(2));
      const receiverBalance = await tokenContract.balanceOf(receiverAddress);
      expect(receiverBalance).to.equal(deposit.div(2));
    });
  });

  describe("requestStream", async () => {
    it("should create stream request", async () => {
      streamContract = streamContract.connect(receiver);

      duration = 10000; // roughly 2.7 hours;
      deposit = ether(10);

      await streamContract.requestStream(senderAddress, deposit, duration, tokenContract.address);
      streamRequestId = 1;

      const streamRequest = <StreamRequest>await streamContract.getStreamRequest(streamRequestId);
      expect(streamRequest.sender).to.equal(senderAddress);
      expect(streamRequest.recipient).to.equal(receiverAddress);
      expect(streamRequest.deposit).to.equal(deposit);
      expect(streamRequest.tokenAddress).to.equal(tokenContract.address);
      expect(streamRequest.duration).to.equal(BigNumber.from(duration));
      expect(streamRequest.state).to.equal(0);
    });
  });

  describe("acceptStreamRequest", async () => {
    beforeEach(async () => {
      const now = await getTimeStamp();
      startTime = now + ONE_HOUR; // start after 1 hour
    });

    it("should revert when request id is not valid", async () => {
      await expect(
        streamContract.connect(sender).acceptStreamRequest(streamRequestId + 1, startTime),
      ).to.be.revertedWith("stream request does not exist");
    });

    it("should revert when not sender address", async () => {
      await expect(streamContract.connect(randUser).acceptStreamRequest(streamRequestId, startTime)).to.be.revertedWith(
        "invalid sender of stream",
      );
    });

    it("should revert when start time is past time", async () => {
      startTime = startTime - ONE_HOUR;

      await expect(streamContract.connect(sender).acceptStreamRequest(streamRequestId, startTime)).to.be.revertedWith(
        "start time before block.timestamp",
      );
    });

    it("should accept the stream request & create the stream", async () => {
      await streamContract.connect(sender).acceptStreamRequest(streamRequestId, startTime);

      const streamRequest = <StreamRequest>await streamContract.getStreamRequest(streamRequestId);
      expect(streamRequest.state).to.equal(1);

      streamId = 2;

      const stream = <Stream>await streamContract.getStream(streamId);
      expect(stream.sender).to.equal(senderAddress);
      expect(stream.recipient).to.equal(receiverAddress);
      expect(stream.deposit).to.equal(deposit);
      expect(stream.tokenAddress).to.equal(tokenContract.address);
      expect(stream.startTime).to.equal(BigNumber.from(startTime));
      expect(stream.stopTime).to.equal(BigNumber.from(startTime + duration));
      expect(stream.remainingBalance).to.equal(BigNumber.from(deposit));
    });

    it("should revert already accepted", async () => {
      await expect(streamContract.connect(sender).acceptStreamRequest(streamRequestId, startTime)).to.be.revertedWith(
        "invalid stream request state",
      );
    });
  });

  describe("rejectStreamRequest", async () => {
    beforeEach(async () => {
      const now = await getTimeStamp();
      startTime = now + ONE_HOUR; // start after 1 hour
    });

    it("should create another stream request", async () => {
      streamContract = streamContract.connect(receiver);

      duration = 10000; // roughly 2.7 hours;
      deposit = ether(10);

      await streamContract.requestStream(senderAddress, deposit, duration, tokenContract.address);
      streamRequestId = 2;

      const streamRequest = <StreamRequest>await streamContract.getStreamRequest(streamRequestId);
      expect(streamRequest.sender).to.equal(senderAddress);
      expect(streamRequest.recipient).to.equal(receiverAddress);
      expect(streamRequest.deposit).to.equal(deposit);
      expect(streamRequest.tokenAddress).to.equal(tokenContract.address);
      expect(streamRequest.duration).to.equal(BigNumber.from(duration));
      expect(streamRequest.state).to.equal(0);
    });

    it("should revert when not sender address", async () => {
      await expect(streamContract.connect(randUser).rejectStreamRequest(streamRequestId)).to.be.revertedWith(
        "invalid sender of stream",
      );
    });

    it("should reject the request", async () => {
      await streamContract.connect(sender).rejectStreamRequest(streamRequestId);

      const streamRequest = <StreamRequest>await streamContract.getStreamRequest(streamRequestId);
      expect(streamRequest.state).to.equal(2);
    });
  });

  after(async () => {
    await revertEvm(providerEvmId);
  });
});
