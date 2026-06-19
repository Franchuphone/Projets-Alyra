import { expect } from "chai";
import { network } from "hardhat";

const { ethers } = await network.create();

async function setUpSmartContract() {
  const votingContract = await ethers.deployContract("Voting");
  const [owner, voter1, voter2, voter3, nonVoter] = await ethers.getSigners();

  return { votingContract, owner, voter1, voter2, voter3, nonVoter };
}

describe("Voting Contract", function () {
  let votingContract: any;
  let owner: any;
  let voter1: any;
  let voter2: any;
  let voter3: any;
  let nonVoter: any;

  enum WorkflowStatus {
    RegisteringVoters,
    ProposalsRegistrationStarted,
    ProposalsRegistrationEnded,
    VotingSessionStarted,
    VotingSessionEnded,
    VotesTallied,
  }

  ///// SET UP TO TEST PROPOSAL PHASE /////
  async function AddThreeVotersAndStartsProposalRegistration() {
    await votingContract.connect(owner).addVoter(voter1.address);
    await votingContract.connect(owner).addVoter(voter2.address);
    await votingContract.connect(owner).addVoter(voter3.address);
    await votingContract.connect(owner).startProposalsRegistering();
  }
  ///// SET UP TO TEST VOTING PHASE   /////
  async function AddFourProposalsAndStartsVotingSession() {
    await AddThreeVotersAndStartsProposalRegistration();
    await votingContract.connect(voter1).addProposal("Proposal A");
    await votingContract.connect(voter2).addProposal("Proposal B");
    await votingContract.connect(voter1).addProposal("Proposal C");
    await votingContract.connect(voter3).addProposal("Proposal D");
    await votingContract.connect(owner).endProposalsRegistering();
    await votingContract.connect(owner).startVotingSession();
  }
  ///// SET UP TO TEST TALLY PHASE    /////
  async function fullSetup() {
    await AddFourProposalsAndStartsVotingSession();
    await votingContract.connect(voter1).setVote(1);
    await votingContract.connect(voter2).setVote(1);
    await votingContract.connect(voter3).setVote(2);
    await votingContract.connect(owner).endVotingSession();
  }

  beforeEach(async function () {
    ({ votingContract, owner, voter1, voter2, voter3, nonVoter } =
      await setUpSmartContract());
  });

  ////////////////////////////////////////////////
  //                DEPLOYMENT                  //
  ////////////////////////////////////////////////

  describe("Initial deployment", function () {
    it("Should set the right owner", async function () {
      expect(await votingContract.owner()).to.equal(owner.address);
    });

    it("Should start in RegisteringVoters status", async function () {
      expect(await votingContract.workflowStatus()).to.equal(
        WorkflowStatus.RegisteringVoters,
      );
    });

    it("Should initialize winningProposalID to 0", async function () {
      expect(await votingContract.winningProposalID()).to.equal(0);
    });
  });

  ////////////////////////////////////////////////
  //                GETTERS (onlyVoters)        //
  ////////////////////////////////////////////////

  describe("Getters (onlyVoters)", function () {
    beforeEach(async function () {
      await AddThreeVotersAndStartsProposalRegistration();
    });

    it("Should return voter information called by another voter", async function () {
      const voterInfo = await votingContract
        .connect(voter1)
        .getVoter(voter2.address);
      expect(voterInfo.isRegistered).to.be.true;
      expect(voterInfo.hasVoted).to.be.false;
      expect(voterInfo.votedProposalId).to.equal(0);
    });

    it("Should revert getVoter if caller is not a voter", async function () {
      await expect(
        votingContract.connect(nonVoter).getVoter(voter1.address),
      ).to.be.revertedWith("You're not a voter");
    });

    it("Should return proposal information called by a voter", async function () {
      const proposal = await votingContract.connect(voter1).getOneProposal(0);
      expect(proposal.description).to.equal("GENESIS");
      expect(proposal.voteCount).to.equal(0);
    });

    it("Should revert getOneProposal if caller is not a voter", async function () {
      await expect(
        votingContract.connect(nonVoter).getOneProposal(0),
      ).to.be.revertedWith("You're not a voter");
    });

    it("Should revert getOneProposal on non existing id", async function () {
      // ONLY GENESIS EXISTS AT INDEX 0
      await expect(
        votingContract.connect(voter1).getOneProposal(99),
      ).to.be.revert(ethers);
    });

    it("Should return non registered on calling getVoter with a non registered address", async function () {
      const voterInfo = await votingContract.connect(voter1).getVoter(owner);
      expect(voterInfo.isRegistered).to.be.false;
    });
  });

  ////////////////////////////////////////////////
  //              WORKFLOW TRANSITIONS          //
  ////////////////////////////////////////////////

  describe("Workflow Transitions", function () {
    ///////// START PROPOSALS REGISTERING /////////

    describe("startProposalsRegistering", function () {
      it("Should update status to ProposalsRegistrationStarted", async function () {
        await votingContract.connect(owner).startProposalsRegistering();
        expect(await votingContract.workflowStatus()).to.equal(
          WorkflowStatus.ProposalsRegistrationStarted,
        );
      });

      it("Should emit event with correct args on startProposalsRegistering", async function () {
        await expect(votingContract.connect(owner).startProposalsRegistering())
          .to.emit(votingContract, "WorkflowStatusChange")
          .withArgs(
            WorkflowStatus.RegisteringVoters,
            WorkflowStatus.ProposalsRegistrationStarted,
          );
      });

      it("Should revert if caller is not owner", async function () {
        await expect(
          votingContract.connect(voter1).startProposalsRegistering(),
        ).to.be.revertedWithCustomError(
          votingContract,
          "OwnableUnauthorizedAccount",
        );
      });

      it("Should revert startProposalsRegistering if not in RegisteringVoters status", async function () {
        expect(await votingContract.workflowStatus()).to.equal(
          WorkflowStatus.RegisteringVoters,
        );
        await votingContract.connect(owner).startProposalsRegistering();
        await expect(
          votingContract.connect(owner).startProposalsRegistering(),
        ).to.be.revertedWith("Registering proposals cant be started now");
      });

      it("Should initialize GENESIS proposal at index 0", async function () {
        await AddThreeVotersAndStartsProposalRegistration();
        const genesis = await votingContract.connect(voter1).getOneProposal(0);
        expect(genesis.description).to.equal("GENESIS");
        expect(genesis.voteCount).to.equal(0);
      });
    });

    ///////// END PROPOSALS REGISTERING /////////

    describe("endProposalsRegistering", function () {
      beforeEach(async function () {
        await votingContract.connect(owner).startProposalsRegistering();
      });

      it("Should update status to endProposalsRegistering", async function () {
        await votingContract.connect(owner).endProposalsRegistering();
        expect(await votingContract.workflowStatus()).to.equal(
          WorkflowStatus.ProposalsRegistrationEnded,
        );
      });

      it("Should emit event with correct args on endProposalsRegistering", async function () {
        await expect(votingContract.connect(owner).endProposalsRegistering())
          .to.emit(votingContract, "WorkflowStatusChange")
          .withArgs(
            WorkflowStatus.ProposalsRegistrationStarted,
            WorkflowStatus.ProposalsRegistrationEnded,
          );
      });

      it("Should revert if caller is not owner", async function () {
        await expect(
          votingContract.connect(voter1).endProposalsRegistering(),
        ).to.be.revertedWithCustomError(
          votingContract,
          "OwnableUnauthorizedAccount",
        );
      });

      it("Should revert endProposalsRegistering if not in ProposalsRegistrationStarted status", async function () {
        expect(await votingContract.workflowStatus()).to.equal(
          WorkflowStatus.ProposalsRegistrationStarted,
        );
        await votingContract.connect(owner).endProposalsRegistering();
        await expect(
          votingContract.connect(owner).endProposalsRegistering(),
        ).to.be.revertedWith("Registering proposals havent started yet");
      });
    });

    //////// START VOTING SESSION /////////

    describe("startVotingSession", function () {
      beforeEach(async function () {
        await AddThreeVotersAndStartsProposalRegistration();
        await votingContract.connect(owner).endProposalsRegistering();
      });

      it("Should update status to VotingSessionStarted", async function () {
        await votingContract.connect(owner).startVotingSession();
        expect(await votingContract.workflowStatus()).to.equal(
          WorkflowStatus.VotingSessionStarted,
        );
      });

      it("Should emit event with correct args on startVotingSession", async function () {
        await expect(votingContract.connect(owner).startVotingSession())
          .to.emit(votingContract, "WorkflowStatusChange")
          .withArgs(
            WorkflowStatus.ProposalsRegistrationEnded,
            WorkflowStatus.VotingSessionStarted,
          );
      });

      it("Should revert if caller is not owner", async function () {
        await expect(
          votingContract.connect(voter1).startVotingSession(),
        ).to.be.revertedWithCustomError(
          votingContract,
          "OwnableUnauthorizedAccount",
        );
      });

      it("Should revert startVotingSession if not in ProposalsRegistrationEnded status", async function () {
        expect(await votingContract.workflowStatus()).to.equal(
          WorkflowStatus.ProposalsRegistrationEnded,
        );
        await votingContract.connect(owner).startVotingSession();
        await expect(
          votingContract.connect(owner).startVotingSession(),
        ).to.be.revertedWith("Registering proposals phase is not finished");
      });
    });

    //////// END VOTING SESSION /////////

    describe("endVotingSession", function () {
      beforeEach(async function () {
        await AddFourProposalsAndStartsVotingSession();
      });

      it("Should update status to VotingSessionEnded", async function () {
        await votingContract.connect(owner).endVotingSession();
        expect(await votingContract.workflowStatus()).to.equal(
          WorkflowStatus.VotingSessionEnded,
        );
      });

      it("Should emit event with correct args on endVotingSession", async function () {
        await expect(votingContract.connect(owner).endVotingSession())
          .to.emit(votingContract, "WorkflowStatusChange")
          .withArgs(
            WorkflowStatus.VotingSessionStarted,
            WorkflowStatus.VotingSessionEnded,
          );
      });

      it("Should revert if caller is not owner", async function () {
        await expect(
          votingContract.connect(voter1).endVotingSession(),
        ).to.be.revertedWithCustomError(
          votingContract,
          "OwnableUnauthorizedAccount",
        );
      });

      it("Should revert endVotingSession if not in VotingSessionStarted status", async function () {
        expect(await votingContract.workflowStatus()).to.equal(
          WorkflowStatus.VotingSessionStarted,
        );
        await votingContract.connect(owner).endVotingSession();
        await expect(
          votingContract.connect(owner).endVotingSession(),
        ).to.be.revertedWith("Voting session havent started yet");
      });
    });
  });

  ////////////////////////////////////////////////
  //              VOTER REGISTRATION            //
  ////////////////////////////////////////////////

  describe("Voter Registration", function () {
    it("Should store a voter correctly", async function () {
      await votingContract.addVoter(voter1.address);
      // SELF-CALL (onlyVoters)
      const voter = await votingContract
        .connect(voter1)
        .getVoter(voter1.address);
      expect(voter.isRegistered).to.be.true;
      expect(voter.hasVoted).to.be.false;
      expect(voter.votedProposalId).to.equal(0);
    });

    it("Should emit event on voter registration", async function () {
      await expect(votingContract.addVoter(voter1.address))
        .to.emit(votingContract, "VoterRegistered")
        .withArgs(voter1.address);
    });

    it("Should revert if non-owner tries to add a voter", async function () {
      await expect(
        votingContract.connect(voter1).addVoter(voter2.address),
      ).to.be.revertedWithCustomError(
        votingContract,
        "OwnableUnauthorizedAccount",
      );
    });

    it("Should revert if workflow status is not RegisteringVoters", async function () {
      // WORKFLOW NEEDS TO BE CHANGED TO TEST THIS ONE
      await votingContract.connect(owner).startProposalsRegistering();
      await expect(
        votingContract.connect(owner).addVoter(voter1.address),
      ).to.be.revertedWith("Voters registration is not open yet");
    });

    it("Should revert on double registration", async function () {
      await votingContract.connect(owner).addVoter(voter1.address);
      await expect(
        votingContract.connect(owner).addVoter(voter1.address),
      ).to.be.revertedWith("Already registered");
    });

    it("Should allow registering multiple voters", async function () {
      await votingContract.connect(owner).addVoter(voter1.address);
      await votingContract.connect(owner).addVoter(voter2.address);

      const registeredVoter1 = await votingContract
        .connect(voter1)
        .getVoter(voter1.address);
      const registeredVoter2 = await votingContract
        .connect(voter1)
        .getVoter(voter2.address);
      expect(registeredVoter1.isRegistered).to.be.true;
      expect(registeredVoter2.isRegistered).to.be.true;
    });
  });

  ////////////////////////////////////////////////
  //            PROPOSALS REGISTRATION          //
  ////////////////////////////////////////////////

  describe("Proposals Registration", function () {
    beforeEach(async function () {
      await AddThreeVotersAndStartsProposalRegistration();
    });

    it("Should store the proposal description correctly", async function () {
      await votingContract.connect(voter1).addProposal("Proposal A");
      const expectedProposal = await votingContract
        .connect(voter1)
        .getOneProposal(1);
      expect(expectedProposal.description).to.equal("Proposal A");
      expect(expectedProposal.voteCount).to.equal(0);
    });

    it("Should emit event on proposal registration", async function () {
      await expect(votingContract.connect(voter1).addProposal("Proposal A"))
        .to.emit(votingContract, "ProposalRegistered")
        .withArgs(1);
    });

    it("Should revert if non-voter tries to add a proposal", async function () {
      await expect(
        votingContract.connect(nonVoter).addProposal("Bad Proposal"),
      ).to.be.revertedWith("You're not a voter");
    });

    it("Should revert if workflow status is not ProposalsRegistration", async function () {
      await votingContract.connect(owner).endProposalsRegistering();
      await expect(
        votingContract.connect(voter1).addProposal("Bad Proposal"),
      ).to.be.revertedWith("Proposals are not allowed yet");
    });

    it("Should revert on empty proposal", async function () {
      await expect(
        votingContract.connect(voter1).addProposal(""),
      ).to.be.revertedWith("Vous ne pouvez pas ne rien proposer");
    });

    it("Should assign incremental IDs to proposals", async function () {
      await votingContract.connect(voter1).addProposal("Proposal A");
      await votingContract.connect(voter2).addProposal("Proposal B");

      const expectedProposal1 = await votingContract
        .connect(voter1)
        .getOneProposal(1);
      const expectedProposal2 = await votingContract
        .connect(voter1)
        .getOneProposal(2);
      expect(expectedProposal1.description).to.equal("Proposal A");
      expect(expectedProposal2.description).to.equal("Proposal B");
    });
  });

  ////////////////////////////////////////////////
  //                VOTING SESSION              //
  ////////////////////////////////////////////////

  describe("Voting Session", function () {
    beforeEach(async function () {
      await AddFourProposalsAndStartsVotingSession();
    });

    it("Should increment proposal voteCount", async function () {
      await votingContract.connect(voter1).setVote(1);
      await votingContract.connect(voter2).setVote(1);
      await votingContract.connect(voter3).setVote(2);
      const proposal1 = await votingContract.connect(voter1).getOneProposal(1);
      const proposal2 = await votingContract.connect(voter1).getOneProposal(2);
      expect(proposal1.voteCount).to.equal(2);
      expect(proposal2.voteCount).to.equal(1);
    });

    it("Should update voter state after vote", async function () {
      await votingContract.connect(voter1).setVote(1);
      const voterInfo = await votingContract
        .connect(voter1)
        .getVoter(voter1.address);
      expect(voterInfo.hasVoted).to.be.true;
      expect(voterInfo.votedProposalId).to.equal(1);
    });

    it("Should emit event on vote registration", async function () {
      await expect(votingContract.connect(voter1).setVote(1))
        .to.emit(votingContract, "Voted")
        .withArgs(voter1.address, 1);
    });

    it("Should revert if non-voter tries to vote", async function () {
      await expect(
        votingContract.connect(nonVoter).setVote(1),
      ).to.be.revertedWith("You're not a voter");
    });

    it("Should revert if workflow status is not VotingSessionStarted", async function () {
      await votingContract.connect(owner).endVotingSession();
      await expect(
        votingContract.connect(voter1).setVote(1),
      ).to.be.revertedWith("Voting session havent started yet");
    });

    it("Should revert on double vote", async function () {
      await votingContract.connect(voter1).setVote(1);
      await expect(
        votingContract.connect(voter1).setVote(2),
      ).to.be.revertedWith("You have already voted");
    });

    it("Should revert if voter votes for non-existent proposal", async function () {
      await expect(
        votingContract.connect(voter1).setVote(99),
      ).to.be.revertedWith("Proposal not found");
    });
  });

  ////////////////////////////////////////////////
  //                TALLYING VOTES              //
  ////////////////////////////////////////////////

  describe("Tallying Votes", function () {
    it("Should determine the correct winner", async function () {
      await fullSetup();
      await votingContract.connect(owner).tallyVotes();
      expect(await votingContract.winningProposalID()).to.equal(1);
    });

    it("Should change workflow status to VotesTallied", async function () {
      await fullSetup();
      await votingContract.connect(owner).tallyVotes();
      expect(await votingContract.workflowStatus()).to.equal(
        WorkflowStatus.VotesTallied,
      );
    });

    it("Should emit event on tallyVotes", async function () {
      await fullSetup();
      await expect(votingContract.connect(owner).tallyVotes())
        .to.emit(votingContract, "WorkflowStatusChange")
        .withArgs(
          WorkflowStatus.VotingSessionEnded,
          WorkflowStatus.VotesTallied,
        );
    });

    it("Should revert tallyVotes if called by non-owner", async function () {
      await fullSetup();
      await expect(
        votingContract.connect(voter1).tallyVotes(),
      ).to.be.revertedWithCustomError(
        votingContract,
        "OwnableUnauthorizedAccount",
      );
    });

    it("Should revert if workflow status is not VotingSessionEnded", async function () {
      await expect(
        votingContract.connect(owner).tallyVotes(),
      ).to.be.revertedWith("Current status is not voting session ended");
    });

    it("Should keep first proposal in case of tie", async function () {
      await AddFourProposalsAndStartsVotingSession();
      await votingContract.connect(voter1).setVote(1);
      await votingContract.connect(voter3).setVote(2);
      await votingContract.connect(owner).endVotingSession();
      await votingContract.connect(owner).tallyVotes();

      expect(await votingContract.winningProposalID()).to.equal(1);
    });

    it("Crash test of tallyVotes on incremented number of proposals", async function () {
      // PUSH TIMEOUT DURATION TO AVOID BLOCKING EXECUTION
      this.timeout(300_000);
      // ARBITRARY NUMBERS, CAN BE CHANGED EASILY TO WIDE TESTS
      const step = 500;
      const maxProposals = 10000;

      for (let size = step; size <= maxProposals; size += step) {
        // NEEDS NEW CONTRACT DECLARATION ON EACH LOOP DUE TO WORKFLOW LIMITATIONS
        ({ votingContract, owner } = await setUpSmartContract());
        const sendAsOwner = votingContract.connect(owner);
        await sendAsOwner.addVoter(owner.address);
        await sendAsOwner.startProposalsRegistering();
        for (let p = 1; p <= size; p++) {
          await sendAsOwner.addProposal("P" + p);
        }

        await sendAsOwner.endProposalsRegistering();
        await sendAsOwner.startVotingSession();
        await sendAsOwner.setVote(1);
        await sendAsOwner.endVotingSession();

        // CATCHING THE ERROR AVOID TO HAVE THE TEST REJECTED BUT RETURNED THE FAILURE POINT
        try {
          const tx = await sendAsOwner.tallyVotes();
          const receipt = await tx.wait();
          console.log(`  ✓ ${size} proposals | gas used : ${receipt?.gasUsed}`);
          expect(await votingContract.winningProposalID()).to.equal(1);
        } catch (err: any) {
          console.log(`  X ${size} proposals | REVERTED: ${err.message}`);
          break;
        }
      }
    });
  });
});
