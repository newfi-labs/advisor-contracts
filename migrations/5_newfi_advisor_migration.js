const StablePool = artifacts.require('StablePoolProxy');
const VolatilePool = artifacts.require('VolatilePoolProxy');
const NewfiToken = artifacts.require('NewfiToken');
const NewfiAdvisor = artifacts.require('NewfiAdvisor');

module.exports = async function (deployer) {
  deployer.deploy(
    NewfiAdvisor,
    StablePool.address,
    VolatilePool.address,
    NewfiToken.address
  );
};
