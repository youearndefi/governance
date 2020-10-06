pragma solidity ^0.6.0;
interface IYouEarnFundGovernance {
    function getGovernor() external view returns (address);
    function getStakingContractAddress() external view returns (address);
    function getYEGovernanceContractAddress() external view returns (address);
    function votesOf(address voter) external view returns (uint _stakingBalance, uint _holdingBalance, uint _totalBalance);
    function computeEarned(address _account, uint _proposalId, uint _votedAmount) external view returns (uint);
    function getCurrentYear() external view returns (uint);
}