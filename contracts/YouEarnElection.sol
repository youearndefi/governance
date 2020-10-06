pragma solidity ^0.6.0;
import "@openzeppelin/contracts/math/SafeMath.sol";
contract YouEarnElection{
    using SafeMath for uint;
    struct CandidateInfo{
        uint id;
        string name;
        address addr;
        string lectureURL;
        bool isUsed;
    }

    mapping(uint => mapping(uint => CandidateInfo)) public candidates;
    mapping(uint => uint[]) public candidateIdList;
    mapping(uint => mapping(uint => uint)) public voteCounting;
    mapping(uint => address) winnerList;

    uint public electionPeriod = 2100000; //blocks. ~1 years (15s/block)
    uint public prepairForElectionPeriod = 175316; //blocks. ~1 month (15s/block)
    uint public electionDuration = 40320; //election duration ~40320 blocks ~7 days
    uint public nextElectionBlock = 0;

    uint internal currentYear = 2020; //the starting currentYear is 2020

    modifier onlyAuthority() virtual { _; }
    modifier onlyDuringPrepairForElectionTime() {
        require(block.number >= nextElectionBlock.sub(prepairForElectionPeriod) && block.number < nextElectionBlock, "YouEarnElection: Require during prepair for eclection time"); 
        _; 
    }
    modifier onlyDuringElectionTime() { 
        require(block.number >= nextElectionBlock && block.number < nextElectionBlock.add(electionDuration), "YouEarnElection: Require during election time");
        _;
    }
    modifier onlyElectionEnded() {
        require(block.number >= nextElectionBlock.add(electionDuration), "YouEarnElection: Require election is ended");
        _;
    }
    
    constructor() public {
        nextElectionBlock = block.number.add(electionPeriod);
    }

    function getCurrentYear() public view returns (uint) {
        return currentYear;
    }

    function getCandidateInfo(uint _year, uint _id) public view returns (uint, address, string memory, string memory){
        return (candidates[_year][_id].id, candidates[_year][_id].addr, candidates[_year][_id].name, candidates[_year][_id].lectureURL);
    }

    function getCurrentWinner() public view onlyDuringElectionTime returns (uint _winnerId){
        uint[] memory _candidateIdList = candidateIdList[currentYear+1];
        uint winnerVote = 0;
        for(uint i = 0; i < _candidateIdList.length; ++i){
            uint _candidateId = _candidateIdList[i];
            if(voteCounting[currentYear+1][_candidateId] > winnerVote){
                winnerVote = voteCounting[currentYear+1][_candidateId];
                _winnerId = i;
            }
        }
    }

    function totalCandidates() public view onlyDuringPrepairForElectionTime returns (uint) {
        return candidateIdList[currentYear+1].length;
    }

    function addCandidate(uint _id, address _addr, string memory _name, string memory _lectureURL) public onlyAuthority onlyDuringPrepairForElectionTime {
        require(!candidates[currentYear+1][_id].isUsed, "This candidate id is used");
        candidates[currentYear+1][_id] = CandidateInfo({
            id: _id,
            name: _name,
            lectureURL: _lectureURL,
            isUsed: true,
            addr: _addr
        });
    }

    function _voteCandidate(uint _id, uint _amount) internal onlyDuringElectionTime returns (uint256){
        voteCounting[currentYear+1][_id] = voteCounting[currentYear+1][_id].add(_amount);
        return currentYear+1;
    }

    function _executeElection() internal onlyElectionEnded returns(address _winnerAddress) {
        uint[] memory _candidateIdList = candidateIdList[currentYear+1];
        //check if _candidateIdList is zero candidates
        uint winnerVote = 0;
        uint winnerId = 0;
        for(uint i = 0; i < _candidateIdList.length; ++i){
            uint _candidateId = _candidateIdList[i];
            if(voteCounting[currentYear+1][_candidateId] > winnerVote){
                winnerVote = voteCounting[currentYear+1][_candidateId];
                winnerId = i;
            }
        }
        nextElectionBlock = block.number.add(electionPeriod);
        currentYear = currentYear + 1;
        _winnerAddress = candidates[currentYear][winnerId].addr;
        winnerList[currentYear] = _winnerAddress;
    }
}