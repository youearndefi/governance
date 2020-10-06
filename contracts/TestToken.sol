pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestToken is ERC20 {
    constructor() public ERC20('Test YEF', 'tYEF') {

    }
    function mint(uint _amount) public {
        _mint(msg.sender, _amount);
    }
}