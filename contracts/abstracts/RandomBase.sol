pragma solidity 0.5.2;

import "../interfaces/IRandom.sol";
import "../interfaces/IValidatorSet.sol";
import "../eternal-storage/OwnedEternalStorage.sol";
import "../libs/SafeMath.sol";


contract RandomBase is OwnedEternalStorage, IRandom {
    using SafeMath for uint256;

    // ============================================== Constants =======================================================

    // This address must be set before deploy
    address public constant VALIDATOR_SET_CONTRACT = address(0x1000000000000000000000000000000000000001);

    // =============================================== Getters ========================================================

    // This function is called by ValidatorSet contract.
    function currentRandom() public view returns(uint256[] memory) {
        return uintArrayStorage[RANDOM_ARRAY];
    }

    // =============================================== Private ========================================================

    bytes32 internal constant RANDOM_ARRAY = keccak256("randomArray");

}
