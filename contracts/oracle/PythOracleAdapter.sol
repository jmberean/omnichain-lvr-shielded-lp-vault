// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IPyth {
  function getUpdateFee(bytes[] calldata updateData) external view returns (uint fee);
  function updatePriceFeeds(bytes[] calldata updateData) external payable;
  function getPrice(bytes32 id) external view returns (int64, uint64, int32, uint);
}

contract PythOracleAdapter {
  IPyth public immutable pyth;
  constructor(address pyth_) { pyth = IPyth(pyth_); }

  function pullPrice(bytes32 priceId, bytes[] calldata updateData)
    external
    payable
    returns (int256 priceE18, uint publishTime)
  {
    uint fee = pyth.getUpdateFee(updateData);
    require(msg.value >= fee, "insufficient Pyth fee");
    pyth.updatePriceFeeds{value: fee}(updateData);

    (int64 p, , int32 expo, uint ts) = pyth.getPrice(priceId);
    int256 scaled = int256(p);
    if (expo < 0) {
      uint32 e = uint32(uint32(-expo));
      for (uint32 i=0; i<e; i++) { scaled *= 10; }
    }
    priceE18 = scaled * 1e10; // coarse scale to 1e18; adjust to your precision needs
    publishTime = ts;
  }
}
