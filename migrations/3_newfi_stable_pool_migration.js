const StablePool = artifacts.require('StablePoolProxy');

module.exports = async function (deployer) {
  deployer.deploy(StablePool);
};
