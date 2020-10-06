import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
interface IYouEarnStaking is IERC20 {
    function voteOnFundGovernance(address _voter, uint _voteAmount, uint _proposalId) external;
    function voteOnElection(address _voter, uint _voteAmount, uint _year) external;
}