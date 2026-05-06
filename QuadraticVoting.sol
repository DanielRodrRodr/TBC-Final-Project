// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

interface IExecutableProposal {
    function executeProposal(uint proposalId, uint numVotes, uint numTokens) external payable;
}

contract VotingToken is ERC20, Ownable {

    uint256 public maxSupply;

    constructor(uint256 _maxSupply) ERC20("VotingToken", "VTK") Ownable(msg.sender) { maxSupply = _maxSupply; }

    function mint(address to, uint256 amount) external onlyOwner {
        require(totalSupply() + amount <= maxSupply, "Max supply alcanzado");
        _mint(to, amount);
    }

    function burn(uint256 amount) external onlyOwner {
        _burn(address(this), amount);
    }
}

contract QuadraticVoting {

    address public owner;
    VotingToken public token;
    uint256 public tokenPrice;

    bool public votingOpen;
    uint256 public budget;

    uint256 public numParticipants;

    struct Proposal {
        string title;
        string description;
        uint256 budget;
        address executable;

        uint256 voteCount;
        uint256 tokensCollected;

        bool approved;
        bool canceled;
        bool signaling;

        address creator;
    }

    Proposal[] public proposals;

    mapping(address => bool) public participants;
    mapping(uint256 => address[] users) public votersKeys; ///////////////////////////////
    mapping(uint256 => mapping(address => uint256)) public votesPerUser;
    mapping(uint256 => mapping(address => uint256)) public tokensUsed;

    constructor(uint256 _price, uint256 _maxTokens) {
        owner = msg.sender;
        tokenPrice = _price;

        token = new VotingToken(_maxTokens);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "No autorizado");
        _;
    }

    modifier onlyParticipant() {
        require(participants[msg.sender], "No participante");
        _;
    }

    modifier isOpen() {
        require(votingOpen, "No abierto");
        _;
    }

    //Funciones
    function openVoting() external payable onlyOwner {
        require(!votingOpen, "Ya abierta");
        require(msg.value > 0, "Debe haber presupuesto inicial");

        votingOpen = true;
        budget = msg.value;
    }

    function addParticipant() external payable {
        require(!participants[msg.sender], "Ya registrado");
        require(msg.value >= tokenPrice, "Compra minima 1 token");

        uint256 tokensToMint = msg.value / tokenPrice;

        require(token.totalSupply() + tokensToMint <= token.maxSupply(), "Max tokens superado");

        participants[msg.sender] = true;
        numParticipants++;

        token.mint(msg.sender, tokensToMint);

        uint256 cost = tokensToMint * tokenPrice;
        uint256 refund = msg.value - cost;
        if (refund > 0) {
            (bool success, ) = msg.sender.call{value: refund}("");
            require(success, "Error al enviar ETH");
        }
    }

    function removeParticipant() external onlyParticipant {
        participants[msg.sender] = false;
        numParticipants--;
    }

    function addProposal(string memory title,string memory description, uint256 _budget, address executable) external onlyParticipant isOpen returns(uint256) {

        bool signaling = (_budget == 0);

        if (!signaling) {
            require(executable != address(0), "Direccion invalida");
        }

        proposals.push(Proposal({
            title: title,
            description: description,
            budget: _budget,
            executable: executable,
            voteCount: 0,
            tokensCollected: 0,
            approved: false,
            canceled: false,
            signaling: signaling,
            creator: msg.sender
        }));

        return proposals.length - 1;
    }

    function cancelProposal(uint256 id) external isOpen {
        Proposal storage p = proposals[id];

        require(msg.sender == p.creator, "No creador");
        require(!p.approved, "Ya aprobada");
        require(!p.canceled, "Ya cancelada");

        p.canceled = true;
        address[] memory addr = votersKeys[id];
        for (uint i = 0; i < addr.length; i++) {
            address user = addr[i];
            uint256 amount = tokensUsed[id][user];

            if (amount > 0)
                token.transfer(user, amount);
        }

        p.voteCount = 0;
        p.tokensCollected = 0;
    }

    function buyTokens() external payable onlyParticipant {
        uint256 tokensToMint = msg.value / tokenPrice;
        require(tokensToMint > 0, "Compra minima 1 token");

        uint256 cost = tokensToMint * tokenPrice;
        uint256 refund = msg.value - cost;

        token.mint(msg.sender, tokensToMint);

        if (refund > 0) {
            (bool ok, ) = msg.sender.call{value: refund}("");
            require(ok);
        }
    }

    function sellTokens(uint256 amount) external onlyParticipant {
        require(token.balanceOf(msg.sender) >= amount, "Saldo insuficiente");

        token.burn(amount);

        (bool success, ) = msg.sender.call{value: amount * tokenPrice}("");
        require(success, "Error al enviar ETH");
    }

    function getERC20() external view returns(address) {
        return address(token);
    }

    function getPendingProposals() isOpen external view returns(uint[] memory ids)  {
        uint count;
        for (uint i = 0; i < proposals.length; i++)
            if (!proposals[i].approved && !proposals[i].canceled)
                count++;
        ids = new uint[](count);

        uint j = 0;
        for (uint i = 0; i < proposals.length; i++)
            if (!proposals[i].approved && !proposals[i].canceled)
                ids[j++] = i;
    }

    function getApprovedProposals() isOpen external view returns(uint[] memory ids) {
        uint count;
        for (uint i = 0; i < proposals.length; i++)
            if (proposals[i].approved)
                count++;

        ids = new uint[](count);
        uint j = 0;

        for (uint i = 0; i < proposals.length; i++)
            if (proposals[i].approved) ids[j++] = i;
    }

    function getSignalingProposals() isOpen external view returns(uint[] memory ids) {
        uint count;
        for (uint i = 0; i < proposals.length; i++)
            if (proposals[i].signaling)
                count++;

        ids = new uint[](count);
        uint j = 0;

        for (uint i = 0; i < proposals.length; i++)
            if (proposals[i].signaling) ids[j++] = i;
    }

    function getProposalInfo(uint id) isOpen external view returns(Proposal memory) {
        return proposals[id];
    }

    function stake(uint256 id, uint256 numVotes) external onlyParticipant isOpen {
        
        Proposal storage p = proposals[id];
        require(!p.approved && !p.canceled, "No valida");

        uint256 prevVotes = votesPerUser[id][msg.sender];
        uint256 newVotes = prevVotes + numVotes;
        uint256 cost = (newVotes * newVotes) - (prevVotes * prevVotes);

        token.transferFrom(msg.sender, address(this), cost);

        votesPerUser[id][msg.sender] = newVotes;
        tokensUsed[id][msg.sender] += cost;

        votersKeys[id].push(msg.sender);

        p.voteCount += numVotes;
        p.tokensCollected += cost;

        _checkAndExecuteProposal(id);
    }

    function withdrawFromProposal(uint256 id, uint256 votesToRemove) external {

        Proposal storage p = proposals[id];

        require(!p.approved && !p.canceled, "No permitido");

        uint256 prevVotes = votesPerUser[id][msg.sender];
        require(prevVotes >= votesToRemove, "No tienes tantos votos");

        uint256 newVotes = prevVotes - votesToRemove;

        uint256 refund = (prevVotes * prevVotes) - (newVotes * newVotes);

        votesPerUser[id][msg.sender] = newVotes;
        tokensUsed[id][msg.sender] -= refund;

        p.voteCount -= votesToRemove;
        p.tokensCollected -= refund;

        token.transfer(msg.sender, refund);
    }

    function _checkAndExecuteProposal(uint256 id) internal {

        Proposal storage p = proposals[id];

        if (p.signaling || p.approved || p.canceled) return;

        uint256 pending = 0;
        for (uint i = 0; i < proposals.length; i++) {
            if (!proposals[i].approved && !proposals[i].canceled && !proposals[i].signaling) {
                pending++;
            }
        }

        uint256 threshold = ((20 + (p.budget * 100) / budget) * numParticipants) / 100 + pending;

        if (p.voteCount >= threshold && budget >= p.budget) {

            p.approved = true;

            budget -= p.budget;

            token.burn(p.tokensCollected);

            (bool success, ) = p.executable.call{value: p.budget, gas: 100000}(
                abi.encodeWithSignature(
                    "executeProposal(uint256,uint256,uint256)",
                    id,
                    p.voteCount,
                    p.tokensCollected
                )
            );

            require(success, "Fallo ejecucion");
        }
    }

    function closeVoting() external onlyOwner {

        votingOpen = false;

        for (uint i = 0; i < proposals.length; i++) {

            Proposal storage p = proposals[i];
            address[] memory addr = votersKeys[i];

            if (p.signaling) {
                (bool success, ) = p.executable.call{gas: 100000}(
                    abi.encodeWithSignature(
                        "executeProposal(uint256,uint256,uint256)",
                        i,
                        p.voteCount,
                        p.tokensCollected
                    )
                );
                require(success);
            }

            if (p.signaling || !p.approved) {
                for (uint j = 0; j < addr.length; j++) {
                    address user = addr[j];
                    uint256 amount = tokensUsed[i][user];

                    if (amount > 0) {
                        token.transfer(user, amount);
                    }
                }
            }
        }

        (bool ok, ) = owner.call{value: budget}("");
        require(ok);

        budget = 0;
    }
}