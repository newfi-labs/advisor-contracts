const NewfiToken = artifacts.require('NewfiToken');

module.exports = async function (deployer) {
  deployer.deploy(NewfiToken);
};
