pragma solidity 0.5.9;

import "./upgradeability/UpgradeabilityAdmin.sol";

/// @dev first stripped down implementation
contract ValidatorSetHbbft is UpgradeabilityAdmin {
    /* using SafeMath for uint256; */

    // =============================================== Storage ========================================================

    // WARNING: since this contract is upgradeable, do not remove
    // existing storage variables and do not change their types!

    address[] internal _currentValidators;
    address[] internal _pendingValidators;
    address[] internal _previousValidators;
    struct ValidatorsList {
        bool forNewEpoch;
        address[] list;
    }
    ValidatorsList internal _finalizeValidators;

    /// @dev The address of the `BlockRewardHbbft` contract.
    address public blockRewardContract;

    /// @dev A boolean flag indicating whether the specified mining address is in the current validator set.
    /// See the `getValidators` getter.
    mapping(address => bool) public isValidator;

    /// @dev A boolean flag indicating whether the specified mining address was a validator in the previous set.
    /// See the `getPreviousValidators` getter.
    mapping(address => bool) public isValidatorPrevious;

    /// @dev A mining address bound to a specified staking address.
    /// See the `_setStakingAddress` internal function.
    mapping(address => address) public miningByStakingAddress;

    /// @dev The staking address of the non-removable validator.
    /// Returns zero if a non-removable validator is not defined.
    address public unremovableValidator;

    /// @dev How many times the given mining address has become a validator.
    mapping(address => uint256) public validatorCounter;

    /// @dev The block number when the `finalizeChange` function was called to apply
    /// the current validator set formed by the `newValidatorSet` function. If it is zero,
    /// it means the `newValidatorSet` function has already been called (a new staking epoch has been started),
    /// but the new staking epoch's validator set hasn't yet been finalized by the `finalizeChange` function.
    uint256 public validatorSetApplyBlock;

    // ============================================== Constants =======================================================

    /// @dev The max number of validators.
    uint256 public constant MAX_VALIDATORS = 19;

    // ================================================ Events ========================================================


    // ============================================== Modifiers =======================================================

    /// @dev Ensures the `initialize` function was called before.
    modifier onlyInitialized {
        require(isInitialized());
        _;
    }

    /// @dev Ensures the caller is the SYSTEM_ADDRESS. See https://wiki.parity.io/Validator-Set.html
    modifier onlySystem() {
        require(msg.sender == 0xffffFFFfFFffffffffffffffFfFFFfffFFFfFFfE);
        _;
    }

    // =============================================== Setters ========================================================

    /// @dev Called by the system when an initiated validator set change reaches finality and is activated.
    /// This function is called at the beginning of a block (before all the block transactions).
    /// Only valid when msg.sender == SUPER_USER (EIP96, 2**160 - 2). Stores a new validator set saved
    /// before by the `emitInitiateChange` function and passed through the `InitiateChange` event.
    /// After this function is called, the `getValidators` getter returns the new validator set.
    /// If this function finalizes a new validator set formed by the `newValidatorSet` function,
    /// an old validator set is also stored and can be read by the `getPreviousValidators` getter.
    /// The `finalizeChange` is only called once for each `InitiateChange` event emitted. The next `InitiateChange`
    /// event is not emitted until the previous one is not yet finalized by the `finalizeChange`
    /// (see the code of `emitInitiateChangeCallable` getter).
    function finalizeChange() external onlySystem {
        if (_finalizeValidators.forNewEpoch) {
            // Apply a new validator set formed by the `newValidatorSet` function
            _savePreviousValidators();
            _finalizeNewValidators(true);
            //IBlockRewardAuRa(blockRewardContract).clearBlocksCreated();
            validatorSetApplyBlock = _getCurrentBlockNumber();
        } else if (_finalizeValidators.list.length != 0) {
            // Apply the changed validator set after malicious validator is removed
            _finalizeNewValidators(false);
        } else {
            // This is the very first call of the `finalizeChange` (block #1 when starting from genesis)
            validatorSetApplyBlock = _getCurrentBlockNumber();
        }
        delete _finalizeValidators; // since this moment the `emitInitiateChange` is allowed
    }

    /// @dev Initializes the network parameters. Used by the
    /// constructor of the contract.
    /// @param _blockRewardContract The address of the `BlockRewardHbbft` contract.
    /// @param _initialMiningAddresses The array of initial validators' mining addresses.
    /// @param _initialStakingAddresses The array of initial validators' staking addresses.
    /// @param _firstValidatorIsUnremovable The boolean flag defining whether the first validator in the
    /// `_initialMiningAddresses/_initialStakingAddresses` array is non-removable.
    /// Should be `false` for a production network.
    function initialize(
        address _blockRewardContract,
        address[] calldata _initialMiningAddresses,
        address[] calldata _initialStakingAddresses,
        bool _firstValidatorIsUnremovable
    ) external {
        require(_getCurrentBlockNumber() == 0 || msg.sender == _admin());
        require(!isInitialized()); // initialization can only be done once
        require(_blockRewardContract != address(0));
        require(_initialMiningAddresses.length > 0);
        require(_initialMiningAddresses.length == _initialStakingAddresses.length);

        blockRewardContract = _blockRewardContract;

        // Add initial validators to the `_currentValidators` array
        for (uint256 i = 0; i < _initialMiningAddresses.length; i++) {
            address miningAddress = _initialMiningAddresses[i];
            _currentValidators.push(miningAddress);
            _pendingValidators.push(miningAddress);
            isValidator[miningAddress] = true;
            validatorCounter[miningAddress]++;
            //_setStakingAddress(miningAddress, _initialStakingAddresses[i]);
        }

        if (_firstValidatorIsUnremovable) {
            unremovableValidator = _initialStakingAddresses[0];
        }
    }

    // =============================================== Getters ========================================================

    /// @dev Returns the previous validator set (validators' mining addresses array).
    /// The array is stored by the `finalizeChange` function
    /// when a new staking epoch's validator set is finalized.
    function getPreviousValidators() public view returns(address[] memory) {
        return _previousValidators;
    }

    /// @dev Returns the current array of validators which should be passed to the `InitiateChange` event.
    /// The pending array is changed when a validator is removed as malicious
    /// or the validator set is updated by the `newValidatorSet` function.
    /// Every time the pending array is changed, it is marked by the `_setPendingValidatorsChanged` and then
    /// used by the `emitInitiateChange` function which emits the `InitiateChange` event to all
    /// validator nodes.
    function getPendingValidators() public view returns(address[] memory) {
        return _pendingValidators;
    }

    /// @dev Returns the current validator set (an array of mining addresses)
    /// which always matches the validator set kept in validator's node.
    function getValidators() public view returns(address[] memory) {
        return _currentValidators;
    }

    /// @dev Returns a boolean flag indicating if the `initialize` function has been called.
    function isInitialized() public view returns(bool) {
        return blockRewardContract != address(0);
    }

    /// @dev Returns a validator set about to be finalized by the `finalizeChange` function.
    /// @param miningAddresses An array set by the `emitInitiateChange` function.
    /// @param forNewEpoch A boolean flag indicating whether the `miningAddresses` array was formed by the
    /// `newValidatorSet` function. The `finalizeChange` function logic depends on this flag.
    function validatorsToBeFinalized() public view returns(address[] memory miningAddresses, bool forNewEpoch) {
        return (_finalizeValidators.list, _finalizeValidators.forNewEpoch);
    }

    // ============================================== Internal ========================================================

    /// @dev Sets a new validator set stored in `_finalizeValidators.list` array.
    /// Called by the `finalizeChange` function.
    /// @param _newStakingEpoch A boolean flag defining whether the validator set was formed by the
    /// `newValidatorSet` function.
    function _finalizeNewValidators(bool _newStakingEpoch) internal {
        address[] memory validators;
        uint256 i;

        validators = _currentValidators;
        for (i = 0; i < validators.length; i++) {
            isValidator[validators[i]] = false;
        }

        _currentValidators = _finalizeValidators.list;

        validators = _currentValidators;
        for (i = 0; i < validators.length; i++) {
            address miningAddress = validators[i];
            isValidator[miningAddress] = true;
            if (_newStakingEpoch) {
                validatorCounter[miningAddress]++;
            }
        }
    }

    /// @dev Stores previous validators. Used by the `finalizeChange` function.
    function _savePreviousValidators() internal {
        uint256 length;
        uint256 i;

        // Save the previous validator set
        length = _previousValidators.length;
        for (i = 0; i < length; i++) {
            isValidatorPrevious[_previousValidators[i]] = false;
        }
        length = _currentValidators.length;
        for (i = 0; i < length; i++) {
            isValidatorPrevious[_currentValidators[i]] = true;
        }
        _previousValidators = _currentValidators;
    }

    /// @dev Sets a new validator set as a pending (which is not yet passed to the `InitiateChange` event).
    /// Called by the `newValidatorSet` function.
    /// @param _stakingAddresses The array of the new validators' staking addresses.
    function _setPendingValidators(
        address[] memory _stakingAddresses
    ) internal {
        if (_stakingAddresses.length == 0 && unremovableValidator == address(0)) return;

        delete _pendingValidators;

        if (unremovableValidator != address(0)) {
            _pendingValidators.push(miningByStakingAddress[unremovableValidator]);
        }

        for (uint256 i = 0; i < _stakingAddresses.length; i++) {
            _pendingValidators.push(miningByStakingAddress[_stakingAddresses[i]]);
        }
    }

    /// @dev Returns the current block number. Needed mostly for unit tests.
    function _getCurrentBlockNumber() internal view returns(uint256) {
        return block.number;
    }

}