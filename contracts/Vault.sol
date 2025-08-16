// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

contract Vault {
    enum Mode { NORMAL, WIDENED, RISK_OFF }

    address public admin;
    address public lvrHook;

    Mode   private _mode;
    uint64 public lastEpoch;

    event HookSet(address hook);

    // Matches the subgraph handler signature: ModeApplied(indexed bytes32,string,uint256)
    event ModeApplied(bytes32 indexed poolId, string newMode, uint256 lvr);

    modifier onlyAdmin() {
        require(msg.sender == admin, "NOT_ADMIN");
        _;
    }

    modifier onlyHookOrAdmin() {
        require(msg.sender == lvrHook || msg.sender == admin, "NOT_AUTH");
        _;
    }

    constructor() {
        admin = msg.sender;
        _mode = Mode.NORMAL;
    }

    function setHook(address hook_) external onlyAdmin {
        lvrHook = hook_;
        emit HookSet(hook_);
    }

    function setAdmin(address newAdmin) external onlyAdmin {
        admin = newAdmin;
    }

    function currentMode() external view returns (Mode) {
        return _mode;
    }

    /// @notice Simple entrypoint your hook (or admin) can call to apply a mode.
    /// @param poolId If you don’t track pools yet, you can pass bytes32(0).
    /// @param mode_  New mode to apply.
    /// @param epoch  Optional epoch tag for demos/keepers.
    /// @param lvrE18 Optional LVR metric (1e18). Set 0 if not used.
    function applyMode(bytes32 poolId, Mode mode_, uint64 epoch, uint256 lvrE18)
        external
        onlyHookOrAdmin
    {
        _mode = mode_;
        lastEpoch = epoch;

        string memory label =
            mode_ == Mode.NORMAL  ? "NORMAL"  :
            mode_ == Mode.WIDENED ? "WIDENED" : "RISK_OFF";

        emit ModeApplied(poolId, label, lvrE18);
    }
}
