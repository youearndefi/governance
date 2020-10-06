pragma solidity ^0.6.0;


import "./interfaces/IYouEarnFundGovernance.sol";
import "./access/GovernorAccess.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
contract YouEarnStaking is ERC20, GovernorAccess {
    using SafeERC20 for IERC20;
    using SafeMath for uint;

    struct VoteDetail {
        uint proposalId;
        uint voteAmount;
    }

    mapping (address => bool) internal hasPermission; 
    mapping (address => uint[]) private voteIdHistory;
    mapping (address => mapping(uint => uint)) private voteAmountHistory;
    mapping (address => mapping(uint => uint)) private electionVoteHistory;
    mapping (address => uint) private withdrawLock;
    uint public withdrawBlockLockPeriod = 17280; // voting period in blocks ~ 17280 3 days for 15s/block
    uint public electionDuration = 40320; //election duration ~40320 blocks ~7 days

    IERC20 public yefToken = IERC20(0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e);

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);

    constructor(address _youearnFundGovernanceContract) public GovernorAccess(_youearnFundGovernanceContract) ERC20("YEF Staking Token", "sYEF"){        
    }

    function voteOnFundGovernance(address _voter, uint _voteAmount, uint _proposalId) external onlyFundGovernanceContract {
        if(voteAmountHistory[_voter][_proposalId] > 0){
            //update the amount only
            voteAmountHistory[_voter][_proposalId] = voteAmountHistory[_voter][_proposalId].add(_voteAmount);
        }else{
            voteIdHistory[_voter].push(_proposalId);
            voteAmountHistory[_voter][_proposalId] = _voteAmount;
        }
       
        //withdraw lock plus 3 days
        withdrawLock[_voter] = withdrawBlockLockPeriod.add(block.number);
    }

    function voteOnElection(address _voter, uint _voteAmount, uint _year) external onlyGovernanceContract {
        electionVoteHistory[_voter][_year] = _voteAmount;//electionVoteHistory[_voter][_year].add(_voteAmount);
        //withdraw lock plus 7 days
        withdrawLock[_voter] = electionDuration.add(block.number);
    }

    function grantPermission(address _addr) public onlyGovernor {
        require(_addr.isContract(), "Require the address is a contract");
        hasPermission[_addr] = true;
    }

    function revokePermission(address _addr) public onlyGovernor {
        hasPermission[_addr] = false;
    }

    function stake(uint256 amount) public {
        require(amount > 0, "Cannot stake 0");
        _mint(msg.sender, amount);
        yefToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);

    }
    
    function withdraw(uint256 amount) public {
        require(amount > 0, "Cannot withdraw 0");
        require(block.number > withdrawLock[msg.sender], "The withdrawal for this address is locked");
        yefToken.safeTransfer(msg.sender, amount);
        _burn(msg.sender, amount);
        if(voteIdHistory[msg.sender].length > 0){
            _earnFundGovernanceFee(msg.sender);
        }
        uint _earnedElectionFee = earnedElectionFee(msg.sender);
        if(_earnedElectionFee > 0){
            _earnElectionFee(msg.sender, _earnedElectionFee);
        }
        emit Withdrawn(msg.sender, amount);
    }

    /**
     * @dev See {ERC20-_beforeTokenTransfer}
     *
     * Lock the transfer between accounts. Only permission addresses.
     */
    function _beforeTokenTransfer(address from, address to, uint amount) internal override {
        require(hasPermission[to] || to == address(0), "The destination address is not allowed to receive sYEF.");
    }

    function getCurrentYearReward() public view returns (uint) {
        uint _currentYear = IYouEarnFundGovernance(youearnFundGovernanceContract).getCurrentYear();

    }

    function earned(address _account) public view returns (uint) {
        return earnedFundGovernanceFee(_account).add(earnedElectionFee(_account));
    }

    function earnedFundGovernanceFee(address _account) public view returns (uint _totalEarned) {
        uint[] memory _votedProposalIdList = voteIdHistory[_account];
        for (uint i; i < _votedProposalIdList.length; ++i){
            _totalEarned = _totalEarned.add(
                IYouEarnFundGovernance(youearnFundGovernanceContract).computeEarned(
                    _account, 
                    _votedProposalIdList[i], 
                    voteAmountHistory[_account][_votedProposalIdList[i]]
                )
            );
        }
    }

    function earnedElectionFee(address _account) public view returns (uint) {
        uint _currentYear = IYouEarnFundGovernance(youearnFundGovernanceContract).getCurrentYear();
        if(electionVoteHistory[_account][_currentYear] == 0) return 0;
        return electionVoteHistory[_account][_currentYear].mul(getCurrentYearReward()).div(yefToken.totalSupply());
    }

    function _earnFundGovernanceFee(address _sender) private {
        uint _totalEarned = 0;
        uint[] memory _votedProposalIdList = voteIdHistory[_sender];
        for (uint i; i < _votedProposalIdList.length; ++i){
            _totalEarned = _totalEarned.add(
                IYouEarnFundGovernance(youearnFundGovernanceContract).computeEarned(
                    _sender, 
                    _votedProposalIdList[i], 
                    voteAmountHistory[_sender][_votedProposalIdList[i]]
                )
            );
            voteAmountHistory[_sender][_votedProposalIdList[i]] = 0;
        }
        //transfer the reward
        if(_totalEarned > 0)
            payable(_sender).transfer(_totalEarned);
        delete voteIdHistory[_sender];
    }

    function _earnElectionFee(address _sender, uint _earnedElectionFee) private {
        payable(_sender).transfer(_earnedElectionFee);
    }


}