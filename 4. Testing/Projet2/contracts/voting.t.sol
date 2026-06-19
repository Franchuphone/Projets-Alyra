// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "./voting.sol";

////////////////////////////////////////////////
//   TESTING RELIABILITY ON MULTIPLE RUNS     //
////////////////////////////////////////////////

contract VotingTest is Test {

    Voting voting;
    address owner = address(1);
    address voter1 = address(2);
    address voter2 = address(3);
    address voter3 = address(4);

    function _addThreeVotersAndStartProposals() internal {
        vm.startPrank(owner);
        voting.addVoter(voter1);
        voting.addVoter(voter2);
        voting.addVoter(voter3);
        voting.startProposalsRegistering();
        vm.stopPrank();
    }

    function _addFourProposalsAndStartVoting() internal {
        _addThreeVotersAndStartProposals();
        vm.prank(voter1); voting.addProposal("Proposal A");
        vm.prank(voter2); voting.addProposal("Proposal B");
        vm.prank(voter3); voting.addProposal("Proposal C");
        vm.prank(voter1); voting.addProposal("Proposal D");
        vm.prank(owner);  voting.endProposalsRegistering();
        vm.prank(owner);  voting.startVotingSession();
    }

    function setUp() public {
        vm.prank(owner);
        voting = new Voting();
    }

    //////////////////////////////////////////////
    //                ADDVOTER                  //
    //////////////////////////////////////////////

    /// @notice DOUBLE REGISTRATION ALWAYS REVERT
    function testFuzz_doubleRegistrationReverts(address addr) public {
        vm.assume(addr != address(0));
        vm.startPrank(owner);
        voting.addVoter(addr);
        vm.expectRevert("Already registered");
        voting.addVoter(addr);
        vm.stopPrank();
    }

    ////////////////////////////////////////////////
    //                  SETVOTE                   //
    ////////////////////////////////////////////////

    /// @notice ANY ADDRESSES NON REGISTERED CAN'T VOTE
    function testFuzz_unregisteredCannotVote(address stranger) public {
        _addFourProposalsAndStartVoting();
        vm.assume(stranger != voter1);
        vm.assume(stranger != voter2);
        vm.assume(stranger != voter3);
        vm.prank(stranger);
        vm.expectRevert("You're not a voter");
        voting.setVote(1);
    }

    /// @notice A REGISTERED VOTER CAN VOTE FOR ANY PROPOSAL ID AND HIS STATE IS CORRECTLY UPDATED
    function testFuzz_validVoteSucceeds(uint256 proposalId) public {
        _addFourProposalsAndStartVoting();
        proposalId = bound(proposalId, 0, 3); // borne dans la plage valide
        vm.startPrank(voter1);
        voting.setVote(proposalId);
        Voting.Voter memory v = voting.getVoter(voter1);
        vm.stopPrank();
        assertTrue(v.hasVoted);
        assertEq(v.votedProposalId, proposalId);
    }

    /// @notice A VOTE FOR AN OUT OF BOND PROPOSAL ID ALWAYS REVERTS
    function testFuzz_voteOutOfBoundsReverts(uint256 proposalId) public {
        _addFourProposalsAndStartVoting();
        // 4 proposals + GENESIS = index 0..4
        vm.assume(proposalId > 4);
        vm.prank(voter1);
        vm.expectRevert("Proposal not found");
        voting.setVote(proposalId);
    }


    ////////////////////////////////////////////////
    //                TALLYVOTES                  //
    ////////////////////////////////////////////////

    /// @notice WINNER PROPOSAL ALWAYS HAVE SUP OR EQUAL VOTES THAN OTHERS PROPOSALS 
    function testFuzz_tallyPicksHighestVoteCount(
        uint8 v1Vote,
        uint8 v2Vote,
        uint8 v3Vote
    ) public {
        _addFourProposalsAndStartVoting();
        // 4 proposals (GENESIS + A + B + C), indices 0..3
        v1Vote = uint8(bound(v1Vote, 0, 3));
        v2Vote = uint8(bound(v2Vote, 0, 3));
        v3Vote = uint8(bound(v3Vote, 0, 3));

        vm.prank(voter1); voting.setVote(v1Vote);
        vm.prank(voter2); voting.setVote(v2Vote);
        vm.prank(voter3); voting.setVote(v3Vote);
        vm.prank(owner);  voting.endVotingSession();
        vm.prank(owner);  voting.tallyVotes();

        vm.startPrank(voter1);
        uint256 winnerId = voting.winningProposalID();
        Voting.Proposal memory winner = voting.getOneProposal(winnerId);

        // Vérifie qu'aucune autre proposal n'a plus de votes
        for (uint256 i = 0; i < 4; i++) {
            Voting.Proposal memory p = voting.getOneProposal(i);
            assertGe(winner.voteCount, p.voteCount);
        }
        vm.stopPrank();
    }

    /// @notice CRASH TEST ON INCREMENTED NUMBER OF PROPOSALS
    function test_tallyVotesResistanceOnScalingProposals() public {
        vm.skip(true);
        uint256 step = 500;
        uint256 maxProposals  = 10000;
        

        for (uint256 size = step; size <= maxProposals; size += step) {
            vm.startPrank(owner);
            voting = new Voting();
            voting.addVoter(owner);
            voting.startProposalsRegistering();
            for (uint256 p = 1; p <= size; p++) {
                voting.addProposal(string(abi.encodePacked("P", vm.toString(p))));
            }
            voting.endProposalsRegistering();
            voting.startVotingSession();
            voting.setVote(1);
            voting.endVotingSession();

            uint256 gasBefore = gasleft();

            try voting.tallyVotes() {
                vm.stopPrank();
                uint256 gasUsed = gasBefore - gasleft();
                // uint256 gasUsed = vm.snapshotGasLastCall(
                //     string(abi.encodePacked("tallyVotes"))
                // );
                if (gasUsed > 20000000) revert ("Run out of gas");
                console.log("* %d proposals | gas used : %d", size, gasUsed);
            } catch (bytes memory reason) {
                console.log("* %d proposals | FAILED (out of gas or revert)", size);
                console.logBytes(reason);
                break;
            }
        }
    } 
}