require("dotenv").config();
require("@nomicfoundation/hardhat-toolbox");
require('solidity-coverage')

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity:{
    version: "0.8.20",
    settings: {
      optimizer: {
          enabled: true,
          runs: 20000
      }
    }
  },
  networks: {
    eth: {
        url: process.env.ETH_MAIN_URL || "",
        accounts:
            process.env.PRIVATE_KEY !== undefined ? [process.env.PRIVATE_KEY] : [],
    },
    sepolia: {
        url: process.env.SIPOLIA_URL || "",
        accounts:
            process.env.PRIVATE_KEY_TEST !== undefined ? [process.env.PRIVATE_KEY_TEST] : [],
    }
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
  sourcify: {
    enabled: true
  },
  gasReporter: {
    enabled: true,
    currency: "USD",
  }
};
