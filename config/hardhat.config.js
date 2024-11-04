require("@nomiclabs/hardhat-etherscan");

module.exports = {
    solidity: "0.8.27",
    networks: {
        rinkeby: {
            url: "YOUR_INFURA_OR_ALCHEMY_URL",
            accounts: ["YOUR_PRIVATE_KEY"],
        },
    },
    etherscan: {
        apiKey: "YOUR_ETHERSCAN_API_KEY",
    },
};
