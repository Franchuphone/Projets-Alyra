// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";

contract Voting is Ownable {

    // Structuring datas
    struct Voter {
        bool isRegistered;
        bool hasVoted;
        uint votedProposalId;
    }
    struct Proposal {
        string description;
        uint voteCount;
    }

    // Global variables
    mapping (address => Voter)  _voters;
    Proposal[] _proposals;
    WorkflowStatus _sessionStatus;
    uint  _winningProposalId;
    uint  _votersCount;

    // Machine states declaration
    enum WorkflowStatus { 
        RegisteringVoters,
        ProposalsRegistrationStarted,
        ProposalsRegistrationEnded,
        VotingSessionStarted,
        VotingSessionEnded,
        VotesTallied
    }

    // Events declaration
    event VoterRegistered(address voterAddress);
    event WorkflowStatusChange(WorkflowStatus previousStatus, WorkflowStatus newStatus);
    event ProposalRegistered(uint proposalId);
    event Voted (address voter, uint proposalId);

    // Implementing modifiers
    modifier checkStatus ( WorkflowStatus _status) {
        require(_status == _sessionStatus, "You're not allowed to perform this action in the current state of vote");
        _;
    }

    modifier checkVoter () {
        require(_voters[msg.sender].isRegistered, "Restricted to authorized participants");
        _;
    }

    // Getters
    function getTotalVotes() public view returns(uint total) {
        for (uint i=0; i<_proposals.length;i++) {
            total += _proposals[i].voteCount;
        }
    }

    function getAllProposals() public view returns(Proposal[] memory allProposals) {
        allProposals = new Proposal[](_proposals.length);
        for (uint i=0;i<_proposals.length;i++) {
            allProposals[i] = _proposals[i];
        }
    }

    function getProposal(uint _proposalId) public view returns(Proposal memory) {
        return _proposals[_proposalId];
    }

    function getVoterDetails(address _addr) public view checkVoter returns(Voter memory voterDescription) {
        return _voters[_addr];
    }

    function getWinningProposal() public view checkStatus(WorkflowStatus.VotesTallied) returns(uint winningId, Proposal memory winningProposal) {
        return (_winningProposalId, _proposals[_winningProposalId]);
    }

    function getSessionStatus() public view returns (string memory) {
        if (_sessionStatus == WorkflowStatus.RegisteringVoters) {
            return "Registering Voters";
        } 
        else if (_sessionStatus == WorkflowStatus.ProposalsRegistrationStarted) {
            return "Proposals Registration Started";
        } 
        else if (_sessionStatus == WorkflowStatus.ProposalsRegistrationEnded) {
            return "Proposals Registration Ended";
        } 
        else if (_sessionStatus == WorkflowStatus.VotingSessionStarted) {
            return "Voting Session Started";
        } 
        else if (_sessionStatus == WorkflowStatus.VotingSessionEnded) {
            return "Voting Session Ended";
        } 
        else if (_sessionStatus == WorkflowStatus.VotesTallied) {
            return "Votes Tallied";
        } 
        else {
            return "Unknown"; // Security fallback
        }
    }

    // Ownable contract declaration
    constructor() Ownable(msg.sender) {}

    // Votation course
    // 1. Registration round
    function submitNewVoter(address _addr) external onlyOwner checkStatus(WorkflowStatus.RegisteringVoters) {
        require (!_voters[_addr].isRegistered, "Voter is already registered");
        require (_addr != address(0), "Invalid address");
        _voters[_addr].isRegistered = true;
        _votersCount ++;
        emit VoterRegistered(_addr);
    }

    // 2. Proposal round
    function startProposalSession() external onlyOwner checkStatus(WorkflowStatus.RegisteringVoters) {
        require (_votersCount > 0, "Can't initiate a vote without voters");
        _sessionStatus = WorkflowStatus.ProposalsRegistrationStarted;
        emit WorkflowStatusChange(WorkflowStatus.RegisteringVoters, _sessionStatus);
    }

    function submitProposal(string memory _proposal) public checkStatus(WorkflowStatus.ProposalsRegistrationStarted) checkVoter {
        require (bytes(_proposal).length > 0, "Proposal can't be empty");
        _proposals.push(Proposal({
            description: _proposal,
            voteCount: 0
        }) );
        emit ProposalRegistered(_proposals.length-1);
    }

    function stopProposalSession() external onlyOwner checkStatus(WorkflowStatus.ProposalsRegistrationStarted) {
        require (_proposals.length > 0 , "Can't end proposal registration with any proposal ");
        _sessionStatus = WorkflowStatus.ProposalsRegistrationEnded;
        emit WorkflowStatusChange(WorkflowStatus.ProposalsRegistrationStarted, _sessionStatus);
    }

    // 3. Voting round
    function startVotingSession() external onlyOwner checkStatus(WorkflowStatus.ProposalsRegistrationEnded) {
        _sessionStatus = WorkflowStatus.VotingSessionStarted;
        emit WorkflowStatusChange(WorkflowStatus.ProposalsRegistrationEnded, _sessionStatus);
    }

    function submitVote(uint _proposalId) public checkStatus(WorkflowStatus.VotingSessionStarted) checkVoter {
        Voter storage sender = _voters[msg.sender];
        require (!sender.hasVoted, "You have already voted");
        require (_proposalId < _proposals.length, "Invalid proposal Id");
        sender.votedProposalId = _proposalId;
        sender.hasVoted = true;
        _proposals[_proposalId].voteCount ++;
        emit Voted(msg.sender, _proposalId);
    }

    function stopVotingSession() external onlyOwner checkStatus(WorkflowStatus.VotingSessionStarted) {
        require (getTotalVotes() > 0, "Can't end voting round with any vote");
        _sessionStatus = WorkflowStatus.VotingSessionEnded;
        emit WorkflowStatusChange(WorkflowStatus.VotingSessionStarted, _sessionStatus);
    }

    // 4. Tally round
    function tallyVotes() external onlyOwner checkStatus(WorkflowStatus.VotingSessionEnded) {
        uint highestScore = 0;
        uint winningPropId = 0;
        for (uint i=0; i<_proposals.length; i++) {
            if (_proposals[i].voteCount > highestScore) {
                highestScore = _proposals[i].voteCount;
                winningPropId = i;
            }
        }
        _winningProposalId = winningPropId;
        _sessionStatus = WorkflowStatus.VotesTallied;
        emit    WorkflowStatusChange(WorkflowStatus.VotingSessionEnded, _sessionStatus);
    }

}