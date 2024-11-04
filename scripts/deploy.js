const { ethers, upgrades } = require("hardhat");

async function main() {
    const TtestToken = await ethers.getContractFactory("TtestToken");
    const token = await upgrades.deployProxy(TtestToken, { initializer: "initialize" });
    await token.deployed();
    console.log("TtestToken deployed to:", token.address);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
