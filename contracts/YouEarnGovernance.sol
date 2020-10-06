pragma solidity ^0.6.0;

import "./access/GovernorAccess.sol";
import "./types/ProposalType.sol";
import "./interfaces/IVotingExecutor.sol";
import "./lib/BytesConverter.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./interfaces/IYouEarnStaking.sol";
contract YouEarnGovernance is GovernorAccess, ProposalType {
    using BytesConverter for bytes;
    using SafeMath for uint;
    using Address for address;
    struct Proposal {
        mapping(address => uint) forVotes;
        mapping(address => uint) againstVotes;
        mapping(address => bool) isCountedQuorum;
        address executor;
        uint totalForVotes;
        uint totalAgainstVotes;
        uint start; // block start;
        uint end; // start + period
        string hash;
        uint quorum;
        bool isOpening;
        bytes data;
        ProposalType proposalType;
    }
    mapping (uint => Proposal) public proposals;
    uint public quorumRequired = 200;
    uint public minQuorum = 100;
    uint public minAmountToPropose = 1000;
    bool isGovernorSetTheMinAmountToPropose = false;
    uint public proposalCount;
    uint public period = 17280; // voting period in blocks ~ 17280 3 days for 15s/block

    event NewProposal(uint indexed id, address creator, uint start, uint duration, address executor, uint proposalTypeIndex, bytes data);
    event ProposalFinished(uint indexed id, uint forPercentage, uint againstPercentage, uint quorum);
    event Vote(uint indexed id, address indexed voter, bool vote, uint weight);

    constructor(address _youearnFundGovernanceContract) public GovernorAccess(_youearnFundGovernanceContract){
        
    }

    /**
     * @dev set the quorum for the main governanace
     * Requirements:
     * - Only governor
     * - The new quorum cannot less than the minQuorum
     * Note: Comunity enables to vote to change the quorum minimum by create a proposal with type of 
     */
    function setQuorum(uint _newQuorum) public onlyGovernor {
        require(_newQuorum >= minQuorum, "Cannot set the quorum that less than the min quorum");
        quorumRequired = _newQuorum;
    }

    /**
     * @dev allow Governor to set the minimum amount required to propose a proposal
     *
     * Requirements:
     *
     * - Sender is the governor
     * - `isGovernorSetTheMinAmountToPropose` is false. That means the governor only has 1 time to call this function
     */
    function setMinAmountToPropose(uint _newMinAmountToPurpose) public onlyGovernor {
        require(isGovernorSetTheMinAmountToPropose == false, "Governor enables to set the min amount to propose only one.");
        minAmountToPropose = _newMinAmountToPurpose;
    }

    /**
     * @dev to create a new proposal
     * 
     * Requirements:
     * - Staking at least `minAmountToPropose`
     *
     * Parameters:
     * @param _executor the address being delegate call when the proposal is ended
     * @param _hash the has of the URL to describe the proposal purpose
     * @param _proposalTypeIndex the index of the enum ProposalType. Default: 0 - COMMON
     * @param _data the optional data in bytes
     */
    function propose(address _executor, string memory _hash, uint _proposalTypeIndex, bytes memory _data) public {
        require(stakingCI().balanceOf(msg.sender) >= minAmountToPropose, "Sender hasn't met the required amount to propose");
         proposals[proposalCount++] = Proposal({
            totalForVotes: 0,
            totalAgainstVotes: 0,
            start: block.number,
            end: period.add(block.number),
            hash: _hash,
            quorum: 0,
            isOpening: true,
            proposalType: ProposalType(_proposalTypeIndex),
            data: _data,
            executor: _executor
        });
        
        //TODO lock the amount + 3 days in staking contract
        
        emit NewProposal(proposalCount, msg.sender, block.number, period, _executor, _proposalTypeIndex, _data);
    }

    function execute(uint id) public {
        require(proposals[id].end < block.number , "The proposal has not ended (yet)");
        require(proposals[id].isOpening == true, "The proposal is closed");
        
        (uint _forPercentage, uint _againstPercentage, uint _quorum) = getStats(id);
        require(_quorum >= quorumRequired);
        if(proposals[id].executor.isContract()){
            IVotingExecutor(proposals[id].executor).execute(id, _forPercentage, _againstPercentage, _quorum, uint(proposals[id].proposalType), proposals[id].data);
        }
        if(_forPercentage >= 50){
            //change the minQuorum is required
            if(proposals[id].proposalType == ProposalType.CHANGING_MAIN_GOVERNANACE_MIN_QUORUM){
                minQuorum = proposals[id].data.toUint256(0);
            }else 
            //change the `minAmountToPropose` varaiable
            if(proposals[id].proposalType == ProposalType.CHANGING_MAIN_GOVERNANACE_MIN_AMOUNT_TO_PROPOSE){
                minAmountToPropose = proposals[id].data.toUint256(0);
            }
        }
        
        emit ProposalFinished(id, _forPercentage, _againstPercentage, _quorum);
        //close the proposal
        proposals[id].isOpening = false;
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
    
        
        emit Vote(id, msg.sender, false, vote);
    }

    function votesOf(address voter) public view returns (uint _stakingBalance, uint _holdingBalance, uint _totalBalance) {
        return IYouEarnFundGovernance(youearnFundGovernanceContract).votesOf(voter);
    }

    function getStats(uint id) public view returns (uint _forPercentage, uint _againstPercentage, uint _quorum) {
        uint _for = proposals[id].totalForVotes;
        uint _against = proposals[id].totalAgainstVotes;
        uint _total = _for.add(_against);
        _forPercentage = _for.mul(10000).div(_total);
        _againstPercentage = _against.mul(10000).div(_total);
        _quorum = proposals[id].quorum;
    }

}