// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IVault {
    enum Mode { NORMAL, WIDENED, RISK_OFF }

    event ModeApplied(bytes32 indexed poolId, uint8 mode, uint64 epoch, string reason);
    event LiquidityAction(bytes32 indexed poolId, uint8 mode, uint64 epoch, int256 baseDelta, int256 quoteDelta, string reason);

    event AdminChanged(address indexed admin);
    event HookChanged(address indexed hook);
    event KeeperChanged(address indexed keeper);

    function poolId() external view returns (bytes32);
    function currentMode() external view returns (Mode);
    function modeEpoch() external view returns (uint64);

    function admin() external view returns (address);
    function hook() external view returns (address);
    function keeper() external view returns (address);

    function setAdmin(address admin_) external;
    function setHook(address hook_) external;
    function setKeeper(address keeper_) external;

    function applyMode(Mode mode, uint64 epoch, string calldata reason) external;
    function keeperRebalance(int256 baseDelta, int256 quoteDelta, string calldata reason) external;
}
