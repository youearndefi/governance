pragma solidity ^0.6.0;
import "../interfaces/IYouEarnFundGovernance.sol";
import "../interfaces/IYouEarnStaking.sol";
contract GovernorAccess {
    address public youearnFundGovernanceContract;

    event FundGovernanceContractChanged(address indexed previousAddress, address indexed newAddress);

    modifier onlyGovernor {
        require(IYouEarnFundGovernance(youearnFundGovernanceContract).getGovernor() == msg.sender, "caller is not the governor");
        _;
    }
    modifier onlyFundGovernanceContract {
        require(msg.sender == youearnFundGovernanceContract, "caller is not the fund governance smart contract");
        _;
    }

    modifier onlyGovernanceContract {
        require(msg.sender == yeFGCI().getYEGovernanceContractAddress(), "caller is not the main governance smart contract");
        _;
    }
    
    constructor(address _youearnFundGovernanceContract) public {
        require(_youearnFundGovernanceContract != address(0), "GovernorAccess: Please set _youearnFundGovernanceContract address");
        youearnFundGovernanceContract = _youearnFundGovernanceContract;
    }

    function changeFundGovernanceContract(address _newAddress) public onlyGovernor {
        emit FundGovernanceContractChanged(youearnFundGovernanceContract, _newAddress);
        youearnFundGovernanceContract = _newAddress;
    }

    /**
     * @dev return the YouEarnFundGovernance contract instance
     * yeFGCI means youearnFundGovernanceContractInstanace
     */
    function yeFGCI() internal returns (IYouEarnFundGovernance ) {
        return IYouEarnFundGovernance(youearnFundGovernanceContract);
    }

    function stakingCI() internal returns (IYouEarnStaking) {
        return IYouEarnStaking(yeFGCI().getStakingContractAddress());
    }

    // function tokenCI() internal returns () {

    // }
}