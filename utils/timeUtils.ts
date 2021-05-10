import hre from "hardhat";

export const increaseTime = async (sec: number) => {
  await hre.network.provider.send("evm_increaseTime", [sec]);
  await hre.network.provider.send("evm_mine");
};

export const getStartTimeStamp = async () => {
  const blockTimestamp = (await hre.network.provider.send("eth_getBlockByNumber", ["0x0", false])).timestamp;
  return parseInt(blockTimestamp.slice(2), 16);
};

export const getTimeStamp = async () => {
  const blockNumber = await hre.network.provider.send("eth_blockNumber");
  const blockTimestamp = (await hre.network.provider.send("eth_getBlockByNumber", [blockNumber, false])).timestamp;
  return parseInt(blockTimestamp.slice(2), 16);
};

export const getSnapShot = async () => {
  return await hre.network.provider.send("evm_snapshot");
};

export const revertEvm = async (snapshotID: any) => {
  await hre.network.provider.send("evm_revert", [snapshotID]);
};
