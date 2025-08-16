// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IVault {
    enum Mode { NORMAL, WIDENED, RISK_OFF }

    event ModeApplied(bytes32 indexed poolId, uint8 mode, uint64 epoch, string reason);

    function poolId() external view returns (bytes32);
    function currentMode() external view returns (Mode);
    function modeEpoch() external view returns (uint64);

    function applyMode(Mode mode, uint64 epoch, string calldata reason) external;
}