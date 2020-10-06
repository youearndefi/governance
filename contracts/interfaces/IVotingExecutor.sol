
interface IVotingExecutor{
    function execute(uint id, uint _forPercentage, uint _againstPercentage, uint _quorum, uint _typeIndex, bytes calldata _data) external;
}