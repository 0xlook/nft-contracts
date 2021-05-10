import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";
import { BigNumber } from "@ethersproject/bignumber";
export interface Signers {
  admin: SignerWithAddress;
}

export interface Stream {
  sender: string;
  recipient: string;
  deposit: BigNumber;
  tokenAddress: string;
  startTime: BigNumber;
  stopTime: BigNumber;
  remainingBalance: BigNumber;
  ratePerSecond: BigNumber;
}

export interface StreamRequest {
  sender: string;
  recipient: string;
  deposit: BigNumber;
  tokenAddress: string;
  duration: BigNumber;
  state: number;
}

export interface Auction {
  creator: string;
  creatorSharePercent: BigNumber;
  sharingSharePercent: BigNumber;
  startTime: BigNumber;
  bidEndTime: BigNumber;
  claimEndTime: BigNumber;
  feePercent: BigNumber;
  lastHighDeposit: BigNumber;
  depositor: string;
  tokenAddress: string;
  verifiedArtist: string;
  state: number;
}
