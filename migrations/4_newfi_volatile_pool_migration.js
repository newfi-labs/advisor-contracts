const VolatilePool = artifacts.require('VolatilePoolProxy');

module.exports = async function (deployer) {
  deployer.deploy(VolatilePool);
};
