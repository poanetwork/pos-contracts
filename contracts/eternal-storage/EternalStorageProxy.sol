pragma solidity 0.5.2;

import "./EternalStorage.sol";
import "../interfaces/IEternalStorageProxy.sol";


/**
 * @title EternalStorageProxy
 * @dev This proxy holds the storage of the token contract and delegates every call to the current implementation set.
 * It allows to upgrade the token's behaviour towards further implementations, and provides
 * authorization control functionalities
 */
contract EternalStorageProxy is EternalStorage, IEternalStorageProxy {

    /**
     * @dev This event will be emitted every time the implementation gets upgraded
     * @param version representing the version number of the upgraded implementation
     * @param implementation representing the address of the upgraded implementation
     */
    event Upgraded(uint256 version, address indexed implementation);
    
    /**
     * @dev This event will be emitted every time the ownership of this
     * contract changes.
     * @param previousOwner representing the previous owner of the contract
     * @param newOwner representing the new owner of the contract
     */
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor(bytes memory _bytecode, address _owner) public {
        // solhint-disable no-inline-assembly
        address _implementationAddress;
        assembly {
            let len := mload(_bytecode)
            let data := add(_bytecode, 0x20)
            _implementationAddress := create(0, data, len)
        }
        // solhint-enable no-inline-assembly
        _implementation = _implementationAddress;
        if (_owner != address(0)) {
            _setOwner(_owner);
        } else {
            _setOwner(msg.sender);
        }
    }

    /**
     * @dev Fallback function allowing to perform a delegatecall to the given
     * implementation.  This function will return whatever the implementation
     * call returns.
     */
    // solhint-disable no-complex-fallback, no-inline-assembly
    function() external payable {
        address _impl = _implementation;
        require(_impl != address(0));

        assembly {
            // Copy msg.data. We take full control of memory in this inline assembly
            // block because it will not return to Solidity code. We overwrite the
            // Solidity scratch pad at memory position 0
            calldatacopy(0, 0, calldatasize)

            // Call the implementation.
            // out and outsize are 0 because we don't know the size yet
            let result := delegatecall(gas, _impl, 0, calldatasize, 0, 0)

            // Copy the returned data
            returndatacopy(0, 0, returndatasize)

            switch result
            // delegatecall returns 0 on error
            case 0 { revert(0, returndatasize) }
            default { return(0, returndatasize) }
        }
    }
    // solhint-enable no-complex-fallback, no-inline-assembly


    /**
     * @dev Tells the address of the current implementation
     * @return address of the current implementation
     */
    function implementation() external view returns(address) {
        return _implementation;
    }

    /**
     * @dev Allows the current owner to transfer control of the contract to a _newOwner.
     * @param _newOwner The address to transfer ownership to.
     */
    function transferOwnership(address _newOwner) external onlyOwner {
        require(_newOwner != address(0));
        emit OwnershipTransferred(_owner, _newOwner);
        _setOwner(_newOwner);
    }

    /**
     * @dev Allows owner to upgrade the current implementation.
     * @param _newImplementation representing the address of the new implementation to be set.
     */
    function upgradeTo(address _newImplementation) external onlyOwner returns(bool) {
        if (_newImplementation == address(0)) return false;
        if (_implementation == _newImplementation) return false;
        if (!_isContract(_newImplementation)) return false;

        uint256 newVersion = _version + 1;
        if (newVersion <= _version) return false;

        _version = newVersion;
        _implementation = _newImplementation;

        emit Upgraded(newVersion, _newImplementation);
        return true;
    }

    /**
     * @dev Returns the owner of the contract, or 0 if the contract has not
     * been initialized.
     */
    function getOwner() external view returns(address) {
        return _owner;
    }

    /**
     * @dev Tells the version number of the current implementation
     * @return uint representing the number of the current version
     */
    function version() external view returns(uint256) {
        return _version;
    }

    function _setOwner(address owner) private {
        _owner = owner;
    }

    function _isContract(address _addr) private view returns(bool) {
        uint256 size;
        assembly { size := extcodesize(_addr) } // solhint-disable-line no-inline-assembly
        return size != 0;
    }
}
