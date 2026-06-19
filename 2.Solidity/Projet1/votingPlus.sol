// SPDX-License-Identifier: MIT
pragma solidity  0.8.35;

import "@openzeppelin/contracts/access/Ownable.sol";

contract VotingPlus is Ownable {

    // Custom errors
    // Optimisation pour utiliser moins de gas sur les erreurs
    error UnauthorizedAccountAccess();
    error UnauthorizedActionOnSessionStatus();
    error MinimalTurnoutNotReached();
    error InvalidParameter();
    error DuplicateEntry();
    error InvalidConditionsForSessionChanges();
    error LimiterSecurityProtection();
    error Blacklisted();
    error DelegatedAddressIsNotAuthorized();

    // Structuring datas
    // Quelques données supp pour rajouter des fonctionnalités
    struct Voter {
        bool isRegistered;
        bool hasAdminVoted;
        bool hasPropVoted;
        bool hasCensureVoted;
        uint votedProposalId;
        uint weight;
        address delegatedTo;
    }
    struct Proposal {
        bytes32 descriptionHash;
        uint voteCount;
    }
    struct Turnout {
        uint votersCount;
        uint minimumVoters;
        uint propsVotesCount;
        uint adminVotesFor;
        uint adminVotesAgainst;
        uint censureVotesCount;
    }

    // Global variables
    // Je profite du getter sur les variables publiques 
    Proposal[] public proposals;
    Turnout public turnout;
    WorkflowStatus public sessionStatus;
    address[] public registeredVoters;
    // Security limiters to avoid out of gas revert on reboot function call
    uint public constant MAX_PROPOSALS = 50;
    uint public constant MAX_VOTERS = 100;

    // Je renvoie les données des variables internal dans des getter sur mesure pour restreindre leur acces
    // Pour la variable du gagnant en particulier, c'est essentiellement pour empecher sa lecture avant la fin du vote
    mapping (address => Voter)  _voters;
    mapping (bytes32 => bool) _propsHashList;
    uint _winnerProposalId;
    // Security exceptions addresses handle here
    // Used only at the moment for admin restriction
    mapping (address => bool) _blacklist;
 
    // Process States declaration
    // Pareil que pour les struct, rajout de fonctionnalités
    enum WorkflowStatus { 
        RegisteringVotersStarted,
        AllowingAdminVoter,
        RegisteringVotersEnded,
        ProposalsRegistrationStarted,
        ProposalsRegistrationEnded,
        VotingSessionStarted,
        VotingSessionEnded,
        VotesTallied
    }

    // Events declaration
    event VoterRegistered(address voterAddress);
    event WorkflowStatusChange(WorkflowStatus previousStatus, WorkflowStatus newStatus);
    event PropRegistered(uint propId, bytes32 indexed propHash, string propDescription);
    event PropVoted (address voter, uint propId);
    event AdminAuthVoted (address voter, bool vote);
    event CensureVoted (address voter, bool vote);
    event DelegatedVote(address fromVoter, address toVoter);

    // Getters
    function getAllProposals() public view returns(Proposal[] memory allProposals) {
        allProposals = new Proposal[](proposals.length);
        for (uint i=0;i<proposals.length;i++) {
            allProposals[i] = proposals[i];
        }
    }

    function getAllVoters() public view returns(address[] memory) {
        return registeredVoters;
    }

    function getVoterDetails(address _addr) public view returns(Voter memory voterDescription) {
        return _voters[_addr];
    }

    function getWinnerProposal() public view checkStatus(WorkflowStatus.VotesTallied) returns(uint winnerId, Proposal memory winnerProposal) {
        return (_winnerProposalId, proposals[_winnerProposalId]);
    }

    // Implementing modifiers
    // Un peu moins précis sur les erreurs mais plus de lisibilité générale
    modifier checkStatus ( WorkflowStatus _status) {
        if (_status != sessionStatus) {
            revert UnauthorizedActionOnSessionStatus();
        }
        _;
    }

    modifier checkAccess () {
        Voter storage voter = _voters[msg.sender];
        if (!voter.isRegistered || voter.weight == 0) {
            revert UnauthorizedAccountAccess();
        }        
        _;
    }

    modifier checkTurnout () {
        if (turnout.votersCount < turnout.minimumVoters) {
            revert MinimalTurnoutNotReached();
        }
        _;
    }

    modifier checkAddress (address _addr) {
        if (_addr == address(0)) {
            revert InvalidParameter();
        }
        _;
    }

    modifier checkDuplicate ( bool condition) {
        _checkDuplicate(condition);
        _;
    }

    modifier checkVotersList () {
        if (turnout.votersCount == 0) {
            revert InvalidConditionsForSessionChanges();
        }
        _;
    }

    modifier checkBlackList (address _addr) {
        if (_blacklist[_addr]) {
            revert Blacklisted();
        }
        _;        
    }

    // Hybrid use in functions implementation and modifier
    function _checkDuplicate(bool condition) private pure {
        if (condition) {
            revert DuplicateEntry();
        }
    }

    // Logical functions 
    function _handleAdminVoter() private  {
        uint vFor = turnout.adminVotesFor ;
        uint vAgainst = turnout.adminVotesAgainst ;
        uint vTotal = turnout.votersCount;
        if (vFor > (vTotal / 2 )) {
            address admin = owner();
            _blacklist[admin] = false;
            _addVoter(admin, 1);
            _handleSessionStatusChange(WorkflowStatus.RegisteringVotersEnded);
        } else if ( vAgainst >= ( vTotal / 2) || (vFor + vAgainst) >= (vTotal * 4/5)) {
            _handleSessionStatusChange(WorkflowStatus.RegisteringVotersEnded);
        } 
    }

    function _handleSessionStatusChange(WorkflowStatus newStatus) private {
        emit WorkflowStatusChange(sessionStatus, newStatus);
        sessionStatus = newStatus;
    }

    function _handleProposalSubmission(bytes32 _propHash) private {
        proposals.push(Proposal({
            descriptionHash: _propHash,
            voteCount: 0
        }) );
        _propsHashList[_propHash] = true;
    }

    function _handleVoteSubmission(uint _proposalId) private {
        Voter storage sender = _voters[msg.sender];
        sender.votedProposalId = _proposalId;
        sender.hasPropVoted = true;
        proposals[_proposalId].voteCount += sender.weight ;
        turnout.propsVotesCount += sender.weight;
    }

    function _handleVoteCalculation () private view returns(uint winnerPropId){
        uint highestScore;
        for (uint i=0; i<proposals.length; i++) {
            uint currentScore = proposals[i].voteCount;
            if (currentScore > highestScore) {
                highestScore = currentScore;
                winnerPropId = i;
            }
        }
    }

    function _handleVoteCensure (bool censureVote) private {
        Voter storage voter = _voters[msg.sender];
        voter.hasCensureVoted = true;
        turnout.censureVotesCount += voter.weight;
        emit CensureVoted(msg.sender, censureVote);
    }

    function _handleCensureProcess () private {
        for (uint i=0; i<proposals.length; i++) {
            bytes32 hash = proposals[i].descriptionHash;
            delete _propsHashList[hash];
        }
        for (uint i=0; i<registeredVoters.length; i++) {
            address addr = registeredVoters[i];
            delete _voters[addr];
        }
        delete proposals;
        delete registeredVoters;
        delete turnout;
        _winnerProposalId = 0;
        _blacklist[owner()] = true;
        _handleSessionStatusChange(WorkflowStatus.RegisteringVotersStarted);
    }

    function _addVoter(address _addr, uint _weight) private  checkBlackList(_addr) {
        Voter storage voter = _voters[_addr];
        if (!voter.isRegistered) {
            voter.isRegistered = true;
            registeredVoters.push(_addr);
            emit VoterRegistered(_addr);
        }
        voter.weight += _weight;
        turnout.votersCount += _weight;
    }

    function _addDelegation(address _addr) private {
        Voter storage delegator = _voters[msg.sender];
        _addVoter(_addr, delegator.weight);
        delegator.delegatedTo = _addr;
        turnout.votersCount -= delegator.weight;
        delegator.weight = 0;
        emit DelegatedVote(msg.sender,_addr);
    }

    // Ownable contract initialisation
    constructor() Ownable(msg.sender) {
        // Blocks admin auto add in voters list
        _blacklist[msg.sender]=true;
    }

    // Voting course

    // 1. Registration round
    // Set the minimal voters count
    function setMinTurnout(uint _min) external onlyOwner checkStatus(WorkflowStatus.RegisteringVotersStarted) {
        if (_min==0) {
            revert InvalidParameter();
        }
        turnout.minimumVoters = _min;
    }

    function submitNewVoter(address _addr) external onlyOwner checkStatus(WorkflowStatus.RegisteringVotersStarted) checkAddress(_addr) checkDuplicate(_voters[_addr].isRegistered) {
        if (turnout.votersCount > MAX_VOTERS) {
            revert LimiterSecurityProtection();
        }
        _addVoter(_addr,1);        
    }

    /** 
     *  bypass and authorize are mutually exclusives
     *  launching one blocks the other
     *  bypass allows to go directly to proposal step
     *  otherwise, if Admin wants to vote, he will need an authorization 
     *  that must be taken by absolute majority
     *  before process could go to the proposal step
     */
    function bypassAdminVoter () external onlyOwner checkStatus(WorkflowStatus.RegisteringVotersStarted) checkTurnout checkVotersList {
        _handleSessionStatusChange(WorkflowStatus.RegisteringVotersEnded);
    }

    function authorizeAdminVoter () external onlyOwner checkStatus(WorkflowStatus.RegisteringVotersStarted) checkTurnout checkVotersList {
        _handleSessionStatusChange(WorkflowStatus.AllowingAdminVoter);
    }

    function allowAdminVoter(bool _adminVote) external checkStatus(WorkflowStatus.AllowingAdminVoter) checkAccess checkDuplicate(_voters[msg.sender].hasAdminVoted) {
       Voter storage voter = _voters[msg.sender];
       if (_adminVote) turnout.adminVotesFor += voter.weight ;
        else turnout.adminVotesAgainst += voter.weight;
        voter.hasAdminVoted = true;
        emit AdminAuthVoted(msg.sender,_adminVote);
        _handleAdminVoter();
    }

    // 2. Proposal round
    function startProposalSession() external onlyOwner checkStatus(WorkflowStatus.RegisteringVotersEnded) {
        _handleSessionStatusChange(WorkflowStatus.ProposalsRegistrationStarted);
    }

    // Using keccak hash to lower gas usage and retrieve information using logs
    function submitProposal(string calldata _proposal) external checkStatus(WorkflowStatus.ProposalsRegistrationStarted) checkAccess {
        if (proposals.length >= MAX_PROPOSALS) {
            revert LimiterSecurityProtection();
        }
        if (bytes(_proposal).length == 0) {
            revert InvalidParameter();
        }
        bytes32 propHash = keccak256(abi.encodePacked(_proposal));
        _checkDuplicate(_propsHashList[propHash]);
        _handleProposalSubmission(propHash);
        emit PropRegistered(proposals.length-1, propHash, _proposal);
    }

    function stopProposalSession() external onlyOwner checkStatus(WorkflowStatus.ProposalsRegistrationStarted) {
        if (proposals.length == 0 ) {
            revert InvalidConditionsForSessionChanges();
        }
        _handleSessionStatusChange(WorkflowStatus.ProposalsRegistrationEnded);
    }

    // 3. Voting round
    function startVotingSession() external onlyOwner checkStatus(WorkflowStatus.ProposalsRegistrationEnded) {
        _handleSessionStatusChange(WorkflowStatus.VotingSessionStarted);
    }

    function submitVote(uint _proposalId) external checkStatus(WorkflowStatus.VotingSessionStarted) checkAccess checkDuplicate(_voters[msg.sender].hasPropVoted){
        if (_proposalId >= proposals.length) {
            revert InvalidParameter();
        }
        _handleVoteSubmission(_proposalId);
        emit PropVoted(msg.sender, _proposalId);
    }

    function stopVotingSession() external onlyOwner checkStatus(WorkflowStatus.VotingSessionStarted) {
        // Requires 2/3 voters of total possible voters to proceed
        if (turnout.propsVotesCount < (turnout.votersCount * 2 / 3)) {
            revert MinimalTurnoutNotReached();
        }
        _handleSessionStatusChange(WorkflowStatus.VotingSessionEnded);
    }

    // 4. Tally round
    function tallyVotes() external onlyOwner checkStatus(WorkflowStatus.VotingSessionEnded) returns(uint){
        _handleSessionStatusChange(WorkflowStatus.VotesTallied);
        return _winnerProposalId = _handleVoteCalculation();
    }

    // 5. Special actions
    function censureVotingProcess(bool censureVote) external checkAccess checkDuplicate(_voters[msg.sender].hasCensureVoted) {
        if (sessionStatus == WorkflowStatus.RegisteringVotersStarted || 
            sessionStatus == WorkflowStatus.VotesTallied ) {
            revert UnauthorizedActionOnSessionStatus();
        }
        _handleVoteCensure (censureVote);
        // Requires 2/3 of total voters to reboot integrality of process
        if (turnout.censureVotesCount > (turnout.votersCount * 2 /3 )) {
            _handleCensureProcess ();
        }
    }

    function delegateVote(address _addr) external checkStatus(WorkflowStatus.RegisteringVotersStarted) checkAccess checkAddress(_addr) {
        if (_addr == msg.sender) {
            revert InvalidParameter();
        }
        _addDelegation(_addr);
    }

}