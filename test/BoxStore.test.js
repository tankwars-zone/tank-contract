const { expectRevert, expectEvent, time, BN } = require('@openzeppelin/test-helpers');
const assert = require('assert');
const { contract, accounts } = require('@openzeppelin/test-environment');
const MysteryBox = contract.fromArtifact('MysteryBox');
const Tank = contract.fromArtifact('Tank');
const TGold = contract.fromArtifact('TGold');
const BoxStore = contract.fromArtifact('BoxStore');
const __SECONDS_PER_DATE__ = 86400;
const BigNumber = require('bignumber.js');

describe("BoxStore", () => {
  const [dev, admin, minter] = accounts;
  beforeEach(async () => {
    this.box = await MysteryBox.new("BOX", "BOX", "https://tank-dev-metadata.fiberbox.net/boxs", { from: minter });
    this.tank = await Tank.new("TANK", "TANK", "https://tank-dev-metadata.fiberbox.net/tanks", { from: minter });
    this.wbond = await TGold.new("WBOND", "WBOND", { from: minter });
    this.boxStore = await BoxStore.new(this.box.address, this.tank.address, this.wbond.address, admin, { from: minter });
    await this.wbond.mint(minter, "1000000000000000000000000", { from: minter });
  });

  it('Test', async () => {
    const price = new BigNumber("1500000000000000000000");
    const startTime = (await time.latest()).toNumber();
    const endTime = startTime + (__SECONDS_PER_DATE__ * 3);
    await this.boxStore.setRound(
      1,
      price.toFixed(),
      10000,
      startTime,
      endTime,
      startTime,
      endTime,
      10000
      , { from: minter });
    await this.boxStore.setOpenBoxTime(endTime, { from: minter });
    await this.boxStore.setRarity(
      100,
      [1, 2, 3, 4, 5],
      [5000, 2500, 1000, 1000, 500]
      , { from: minter });
    await this.wbond.approve(this.boxStore.address, (price.times(10000)).toFixed(), { from: minter });
    await this.box.grantRole(
      (await this.box.MINTER_ROLE.call()),
      this.boxStore.address,
      { from: minter }
    );
    await this.tank.grantRole(
      (await this.tank.MINTER_ROLE.call()),
      this.boxStore.address,
      { from: minter }
    );
    await time.increase(12);
    await this.boxStore.buyBoxInPublicSale(1, 10, { from: minter });
    let balanceAdminWallet = await this.wbond.balanceOf(admin);
    assert.equal(balanceAdminWallet.toString(), (price.times(10)).toFixed());
    await time.increase(endTime);

    let res = {};
    for (let i = 1; i <= 10; i++) {
      await this.box.safeTransferFrom(minter, this.boxStore.address, i, { from: minter });
      assert.equal((await this.tank.ownerOf(i)).toString(), minter);
      await time.increase(12);
    }
    console.log(await this.boxStore.getRatiry(0));
    console.log(await this.boxStore.getRatiry(1));
    console.log(await this.boxStore.getRatiry(2));
    console.log(await this.boxStore.getRatiry(3));
    console.log(await this.boxStore.getRatiry(4));
  })
});
