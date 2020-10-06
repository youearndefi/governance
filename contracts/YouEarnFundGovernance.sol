pragma solidity ^0.6.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "./YouEarnElection.sol";
import "./types/ProposalType.sol";
import "./lib/BytesConverter.sol";
import "./interfaces/IYouEarnStaking.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

contract YouEarnFundGovernance is YouEarnElection, ProposalType {
    using BytesConverter for bytes;
    using SafeERC20 for IERC20;
    using SafeMath for uint;
    struct WithdrawProposal {
        mapping(address => uint) forVotes;
        mapping(address => uint) againstVotes;
        mapping(address => bool) isCountedQuorum;
        uint totalForVotes;
        uint totalAgainstVotes;
        uint start; // block start;
        uint end; // start + period
        string hash;
        uint quorum;
        bool isOpening;
        bool isPassed;
        uint withdrawAmount;
        address withdrawAddress;
        uint totalFeeAmount;
    }

    mapping (uint => WithdrawProposal) public proposals;
    uint public proposalCount;
    uint public quorum = 200;
    uint public feeCommission = 2; //default 2 %
    uint public maximumFeeCommission = 5; //default maximum fee commission is 5
    uint public period = 17280; // voting period in blocks ~ 17280 3 days for 15s/block
    
    address public stakingContract;
    address private governor;    
    address private youearnGovernance;

    IERC20 public token = IERC20(0xdF5e0e81Dff6FAF3A7e52BA697820c5e32D806A8);
    IYouEarnStaking public youearnStakingContract;
    /**
     * @dev Only allow the governor to call the function
     */
    modifier onlyGovernor (){
        require(msg.sender == governor, "Caller is not the governor");
        _;
    }
    modifier onlyYouEarnGovernance(){
        require(msg.sender == youearnGovernance, "Callet is not the youearnGovernance");
        _;
    }

    event NewWithdrawProposal(uint id, address creator, uint start, uint duration, address withdrawAddress, uint withdrawAmount);
    event Vote(uint indexed id, address indexed voter, bool vote, uint weight);
    event WithdrawProposalFinished(uint indexed id, uint _for, uint _against, uint quorum);
    event GovernorTransferred(address indexed previousGovernor, address indexed newGovernor);

    constructor(address _governor, uint _requiredQuorum) public {
        governor = _governor;
        proposalCount = 0;
        quorum = _requiredQuorum;
    }

    function getGovernor() public view returns (address) {
        return governor;
    }

    function getStakingContractAddress() public view returns (address) {
        return address(youearnStakingContract);
    }

    function getYEGovernanceContractAddress() public view returns (address) {
        return youearnGovernance;
    }

    function getProposalDetail(uint id) public view returns (
        bool isOpening, 
        bool isPassed, 
        uint totalForVotes, 
        uint totalAgainstVotes, 
        uint start, 
        uint end, 
        string memory hash, 
        uint withdrawAmount, 
        address withdrawAddress
    ) {
        isOpening = proposals[id].isOpening;
        isPassed = proposals[id].isPassed;
        totalForVotes = proposals[id].totalForVotes;
        totalAgainstVotes = proposals[id].totalAgainstVotes;
        start = proposals[id].start;
        end = proposals[id].end;
        hash = proposals[id].hash;
        withdrawAmount = proposals[id].withdrawAmount;
        withdrawAddress = proposals[id].withdrawAddress;
    }

    function computeEarned(address _account, uint _proposalId, uint _votedAmount) public view returns (uint) {
        uint _for = proposals[_proposalId].totalForVotes;
        uint _against = proposals[_proposalId].totalAgainstVotes;
        uint _total = _for.add(_against);
        return _votedAmount.mul(proposals[_proposalId].totalFeeAmount).div(_total);
    }

    /**
     * @dev this function enables the main YouEarn governance contract to call
     * Community could create the proposal on the main YouEarn governance contract
     * following the _type supported
     * once the proposal is executed, the main contract will call this function to make the change
     * 
     * Requirements:
     * - Only the youearn's governance contract
     * - Meet the current quorum
     */
    function execute(uint id, uint _forPercentage, uint _againstPercentage, uint _quorum, uint _typeIndex, bytes memory _data) public onlyYouEarnGovernance {
        require(_quorum >= quorum, "YouEarnFundGovernance: The quorum requirement not met");
        ProposalType _type = ProposalType(_typeIndex);
        if(_type == ProposalType.CHANGING_GOVERNOR){
            /**
             * @dev vote to change the governor
             * 
             * Requirements:
             * - At least 95% of total supply vote for
             */
            uint _requirePassAmount = token.totalSupply().mul(95).div(100);
            require(_forPercentage >= _requirePassAmount, "YouEarnFundGovernance: The requirement to be passed not met");
            address _newGovernor = _data.toAddress(0);
            emit GovernorTransferred(governor, _newGovernor);

            governor = _newGovernor;
            

        }else if(_type == ProposalType.CHANGING_FUND_GOVERNANACE_QUORUM){
            /**
             * @dev vote to change the quorum
             * Requirements:
             * - At least 50% of total supply vote for
             */
            uint _requirePassAmount = token.totalSupply().mul(50).div(100);
            require(_forPercentage >= _requirePassAmount, "YouEarnFundGovernance: The requirement to be passed not met");
            quorum = _data.toUint256(0);
        }else if(_type == ProposalType.CHANGING_PERCENT_PER_WITHDRAWAL){
            /**
             * @dev vote to change the fee percent of each withdrawal.
             * Requirements:
             * - At least 50% of total supply vote for
             * - Less than or equal to maximumFeeCommission
             */
            uint _requirePassAmount = token.totalSupply().mul(50).div(100);
            require(_forPercentage >= _requirePassAmount, "YouEarnFundGovernance: The requirement to be passed not met");
            uint _newFeeCommission = _data.toUint256(0);
            require(_newFeeCommission <= maximumFeeCommission, "YouEarnFundGovernance: the new fee commission is too high");
            feeCommission = _newFeeCommission;
        }else if(_type == ProposalType.CHANGING_MAXIMUM_PERCENT_PER_WITHDRAWAL){
            /**
             * @dev vote to change the maximum fee percent of each withdrawal. Maximum 5%
             * Requirements:
             * - At least 90% of total supply vote for
             */
            uint _requirePassAmount = token.totalSupply().mul(90).div(100);
            require(_forPercentage >= _requirePassAmount, "YouEarnFundGovernance: The requirement to be passed not met");
            maximumFeeCommission = _data.toUint256(0);
        }
    }

    /**
     * @dev Allows governor collect the other ERC20 tokens
     * Remquirments:
     * - sender is the governor
     * - ERC20 token is not the reward token
     * - ERC20 token is not the voting token
     */
    // function seize(IERC20 _token, uint amount) external onlyGovernor {
    //     // require(_token != token, "reward");
    //     // require(_token != vote, "vote");
    //     _token.safeTransfer(governor, amount);
    // }
    
    function setGovernor(address _governor) public onlyGovernor {
        governor = _governor;
    }
    
    function setPeriod(uint _period) public onlyGovernor {
        period = _period;
    }

    function setStakingContract(address _stakingContract) public onlyGovernor {
        stakingContract = _stakingContract;
        youearnStakingContract = IYouEarnStaking(_stakingContract);
    }

    function setYouearnGovernance(address _youearnGovernance) public onlyGovernor {
        youearnGovernance = _youearnGovernance;
    }
    
    /**
     * @dev Create the withdraw proposal
     *
     * Requirements:
     * - sender must the governance
     */
    function propose(address _withdrawAddress, uint _withdrawAmount, string memory _hash) public onlyGovernor {
        require(stakingContract != address(0), "Please update stakingContract address");
        require(youearnGovernance != address(0), "Please update youearnGovernance address");
        proposals[proposalCount++] = WithdrawProposal({
            totalForVotes: 0,
            totalAgainstVotes: 0,
            start: block.number,
            end: period.add(block.number),
            hash: _hash,
            quorum: 0,
            isOpening: true,
            isPassed: false,
            withdrawAmount: _withdrawAmount,
            withdrawAddress: _withdrawAddress,
            totalFeeAmount: _withdrawAmount.mul(feeCommission).div(100)
        });
        
        emit NewWithdrawProposal(proposalCount, msg.sender, block.number, period, _withdrawAddress, _withdrawAmount);
    }
    
    /**
     * @dev this contract is manage the fund, so this function should be called from the governor only
     *
     * Requirements:
     * - 
     */
    function executeProposal(uint id) public onlyGovernor {
        require(block.number > proposals[id].end , "The proposal has not ended (yet)");
        require(proposals[id].isOpening == true, "The proposal is closed");
        (uint _forPercentage, uint _againstPercentage, uint _quorum) = getStats(id);
        if(_forPercentage >= 50 && _quorum >= quorum){
            //Transfer the requested amount to the withdrawal address
            payable(proposals[id].withdrawAddress).transfer(proposals[id].withdrawAmount.sub(proposals[id].totalFeeAmount));

            //Set the proposal is passed
            proposals[id].isPassed = true;
            emit WithdrawProposalFinished(id, _forPercentage, _againstPercentage, _quorum);
        }
        //close the proposal
        proposals[id].isOpening = false;
    }
    
    function getStats(uint id) public view returns (uint _forPercentage, uint _againstPercentage, uint _quorum) {
        uint _for = proposals[id].totalForVotes;
        uint _against = proposals[id].totalAgainstVotes;
        uint _total = _for.add(_against);
        _forPercentage = _for.mul(10000).div(_total);
        _againstPercentage = _against.mul(10000).div(_total);
        _quorum = proposals[id].quorum;
    }
    
    function votesOf(address voter) public view returns (uint _stakingBalance, uint _holdingBalance, uint _totalBalance) {
        _stakingBalance =  youearnStakingContract.balanceOf(voter);
        _holdingBalance = token.balanceOf(voter);
        _totalBalance = _holdingBalance.add(_stakingBalance);
    }

    function voteFor(uint id) public {
        require(proposals[id].start < block.number , "The proposal has not started yet");
        require(proposals[id].end > block.number , "The proposal is ended");
        
        uint _against = proposals[id].againstVotes[msg.sender];
        if (_against > 0) {
            proposals[id].totalAgainstVotes = proposals[id].totalAgainstVotes.sub(_against);
            proposals[id].againstVotes[msg.sender] = 0;
        }
        (uint _stakingBalance, uint _holdingBalance, uint _voteAmount) = votesOf(msg.sender);
        uint vote = _voteAmount.sub(proposals[id].forVotes[msg.sender]);
        require(vote > 0, "No balance left to vote");
        proposals[id].totalForVotes = proposals[id].totalForVotes.add(vote);
        proposals[id].forVotes[msg.sender] = _voteAmount;
        
        if(!proposals[id].isCountedQuorum[msg.sender]){
            proposals[id].quorum = proposals[id].quorum.add(1);
            proposals[id].isCountedQuorum[msg.sender] = true;
        }    
        if(_stakingBalance > 0){
            youearnStakingContract.voteOnFundGovernance(msg.sender, vote, id);
        }
        
        emit Vote(id, msg.sender, true, vote);
    }
    
    function voteAgainst(uint id) public {
        require(proposals[id].start < block.number , "The proposal has not started yet");
        require(proposals[id].end > block.number , "The proposal is ended");
        
        uint _for = proposals[id].forVotes[msg.sender];
        if (_for > 0) {
            proposals[id].totalForVotes = proposals[id].totalForVotes.sub(_for);
            proposals[id].forVotes[msg.sender] = 0;
        }
        (uint _stakingBalance, uint _holdingBalance, uint _voteAmount) = votesOf(msg.sender);
        uint vote = _voteAmount.sub(proposals[id].againstVotes[msg.sender]);
        require(vote > 0, "No balance left to vote");
        proposals[id].totalAgainstVotes = proposals[id].totalAgainstVotes.add(vote);
        proposals[id].againstVotes[msg.sender] = _voteAmount;
        
        if(!proposals[id].isCountedQuorum[msg.sender]){
            proposals[id].quorum = proposals[id].quorum.add(1);
            proposals[id].isCountedQuorum[msg.sender] = true;
        }
        if(_stakingBalance > 0){
            youearnStakingContract.voteOnFundGovernance(msg.sender, vote, id);
        }
        
        emit Vote(id, msg.sender, false, vote);
    }

    /* For Election */

    /**
     * @dev thow if called by any account other than the authority.
     * The authoritys are:
     * - The governor
     * - Any addresses are holding greater or equal than 1% of the total supply
     */
    modifier onlyAuthority() override { 
        require(governor == msg.sender || token.balanceOf(msg.sender) >= token.totalSupply().mul(1).div(100), "Election: Require an authority");
        _;
    }

    function voteInElection(uint _id) public onlyDuringElectionTime {
        (uint _stakingBalance,uint _, uint _totalBalance ) = votesOf(msg.sender);
        require(_totalBalance > 0, "Cannot vote 0");
        uint _votingYear = _voteCandidate(_id, _totalBalance);
        if(_stakingBalance > 0){
            youearnStakingContract.voteOnElection(msg.sender, _totalBalance, _votingYear);
        }
    }

    function executeElection() public onlyElectionEnded {
        address _winnerAddress = _executeElection();
        if(_winnerAddress != address(0)){
            emit GovernorTransferred(governor, _winnerAddress);
            governor = _winnerAddress;
        }
    }

}