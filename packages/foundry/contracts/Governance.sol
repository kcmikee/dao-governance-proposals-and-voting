// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Governance {
  IERC20 public token;
  uint256 public votingPeriod;

  struct Vote {
    uint8 voteType;
    uint256 weight;
  }

  struct Proposal {
    string title;
    uint256 deadline;
    address creator;
    uint256 votesFor;
    uint256 votesAgainst;
    uint256 votesAbstain;
    mapping(address => Vote) votes;
    bool exists;
  }

  mapping(uint256 => Proposal) public proposals;
  uint256 public proposalCount;
  uint256 public activeProposalId;
  uint256 public queuedProposalId;

  event ProposalCreated(
    uint256 proposalId, string title, uint256 votingDeadline, address creator
  );
  event VoteCasted(
    uint256 proposalId, address voter, uint8 vote, uint256 weight
  );
  event VotesRemoved(address voter, uint8 vote, uint256 weight);

  modifier onlyToken() {
    require(msg.sender == address(token), "Only token contract can call");
    _;
  }

  constructor(address _tokenAddress, uint256 _votingPeriod) {
    token = IERC20(_tokenAddress);
    votingPeriod = _votingPeriod;
  }

  function propose(
    string memory _title
  ) external returns (uint256) {
    require(token.balanceOf(msg.sender) > 0, "Must hold tokens to propose");

    if (
      activeProposalId != 0
        && block.timestamp <= proposals[activeProposalId].deadline
    ) {
      require(queuedProposalId == 0, "Proposal already queued");
    }

    proposalCount++;
    uint256 proposalId = proposalCount;

    Proposal storage proposal = proposals[proposalId];
    proposal.title = _title;
    proposal.deadline = block.timestamp + votingPeriod;
    proposal.creator = msg.sender;
    proposal.exists = true;

    if (
      activeProposalId == 0
        || block.timestamp > proposals[activeProposalId].deadline
    ) {
      activeProposalId = proposalId;
    } else {
      queuedProposalId = proposalId;
    }

    emit ProposalCreated(proposalId, _title, proposal.deadline, msg.sender);
    return proposalId;
  }

  function getProposal(
    uint256 id
  )
    external
    view
    returns (string memory title, uint256 deadline, address creator)
  {
    require(proposals[id].exists, "Proposal does not exist");
    Proposal storage proposal = proposals[id];
    return (proposal.title, proposal.deadline, proposal.creator);
  }

  function vote(
    uint8 _vote
  ) external {
    require(token.balanceOf(msg.sender) > 0, "No voting power");
    require(_vote <= 2, "Invalid vote type");

    updateActiveProposal();
    require(activeProposalId != 0, "No active proposal");

    Proposal storage proposal = proposals[activeProposalId];
    require(block.timestamp <= proposal.deadline, "Voting period ended");
    require(proposal.votes[msg.sender].weight == 0, "Already voted");

    uint256 weight = token.balanceOf(msg.sender);

    if (_vote == 1) {
      proposal.votesFor += weight;
    } else if (_vote == 0) {
      proposal.votesAgainst += weight;
    } else {
      proposal.votesAbstain += weight;
    }

    proposal.votes[msg.sender].voteType = _vote;
    proposal.votes[msg.sender].weight = weight;

    emit VoteCasted(activeProposalId, msg.sender, _vote, weight);
  }

  function removeVotes(
    address from
  ) external onlyToken {
    updateActiveProposal();
    if (activeProposalId == 0) return;

    Proposal storage proposal = proposals[activeProposalId];
    if (block.timestamp > proposal.deadline) return;

    Vote storage userVote = proposal.votes[from];
    if (userVote.weight == 0) return;

    if (userVote.voteType == 1) {
      proposal.votesFor -= userVote.weight;
    } else if (userVote.voteType == 0) {
      proposal.votesAgainst -= userVote.weight;
    } else {
      proposal.votesAbstain -= userVote.weight;
    }

    emit VotesRemoved(from, userVote.voteType, userVote.weight);
    delete proposal.votes[from];
  }

  function getResult(
    uint256 proposalId
  ) external view returns (bool) {
    require(proposals[proposalId].exists, "Proposal does not exist");
    require(
      block.timestamp > proposals[proposalId].deadline,
      "Voting period not ended"
    );

    Proposal storage proposal = proposals[proposalId];
    return proposal.votesFor > proposal.votesAgainst;
  }

  function updateActiveProposal() internal {
    if (
      activeProposalId != 0
        && block.timestamp > proposals[activeProposalId].deadline
    ) {
      if (queuedProposalId != 0) {
        activeProposalId = queuedProposalId;
        queuedProposalId = 0;
      } else {
        activeProposalId = 0;
      }
    }
  }
}
