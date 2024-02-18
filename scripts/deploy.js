const hre = require("hardhat");

async function main() {
  const owner = process.env.owner_test;
  const market_v1 = await hre.ethers.deployContract("InscriptionMarket_v1", [owner], {
    value: 0,
  });

  await market_v1.waitForDeployment();

  console.log(
    `market_v1 deployed to ${market_v1.target}`
  );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
