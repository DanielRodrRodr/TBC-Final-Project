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

    function burn(address from, uint256 amount) external onlyOwner {
        _burn(from, amount);
    }
}

contract SimpleERC20 {

    string public name = "VotingToken";
    string public symbol = "VTK";
    uint8 public decimals = 18;

    uint256 public totalSupply;
    address public owner;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor() {
        owner = msg.sender;
    }

    function mint(address to, uint256 amount) external {
        require(msg.sender == owner, "No autorizado");
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function burn(address from, uint256 amount) external {
        require(msg.sender == owner, "No autorizado");
        require(balanceOf[from] >= amount, "Insuficiente");
        balanceOf[from] -= amount;
        totalSupply -= amount;
    }

    function transferFrom(address from, address to, uint256 amount) external {
        require(balanceOf[from] >= amount, "Saldo bajo");
        require(allowance[from][msg.sender] >= amount, "No aprobado");

        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external {
        allowance[msg.sender][spender] = amount;
    }
}

contract QuadraticVoting {

    address public owner;
    SimpleERC20 public token;

    uint256 public tokenPrice;
    uint256 public maxTokens;

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
        maxTokens = _maxTokens;

        token = new SimpleERC20();
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
        votingOpen = true;
        budget = msg.value;
    }

    function addParticipant() external payable {
        require(!participants[msg.sender], "Ya registrado");
        require(msg.value >= tokenPrice, "Compra minima 1 token");

        participants[msg.sender] = true;
        numParticipants++;

        uint256 tokensToMint = msg.value / tokenPrice;
        token.mint(msg.sender, tokensToMint);

        //Devolvemos el eth sobrante
        uint256 cost = tokensToMint * tokenPrice;
        uint256 refund = msg.value - cost;
        if (refund > 0) {
            payable(msg.sender).transfer(refund);
        }
    }

    function removeParticipant() external onlyParticipant {
        participants[msg.sender] = false;
        numParticipants--;
    }

    function addProposal(string memory title,string memory description, uint256 _budget, address executable) external onlyParticipant isOpen returns(uint256) {

        bool signaling = (_budget == 0);

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

        p.canceled = true;
        address[] memory addr = votersKeys[id];
        for (uint i = 0; i < addr.length; i++) {
            token.transferFrom(address(this), addr, tokensUsed[id][addr]);
        }
    }

    function buyTokens() external payable onlyParticipant {
        uint256 tokensToMint = msg.value / tokenPrice;
        token.mint(msg.sender, tokensToMint);
    }

    function sellTokens(uint256 amount) external onlyParticipant {
        token.burn(msg.sender, amount);
        payable(msg.sender).transfer(amount * tokenPrice);
    }

    function getERC20() external view returns(address) {
        return address(token);
    }

    function getPendingProposals() isOpen external view returns(uint[] memory ids)  {
        uint count;
        for (uint i = 0; i < proposals.length; i++)
            if (!proposals[i].approved && !proposals[i].canceled && !proposals[i].signaling)
                count++;
        ids = new uint[](count);

        uint j = 0;
        for (uint i = 0; i < proposals.length; i++)
            if (!proposals[i].approved && !proposals[i].canceled && !proposals[i].signaling)
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
        //Hay que mirar que no se pueda cancelar mientras se ejecuta stake
        Proposal storage p = proposals[id];
        require(!p.approved && !p.canceled, "No valida");

        uint256 prevVotes = votesPerUser[id][msg.sender];
        uint256 newVotes = prevVotes + numVotes;

        uint256 cost = (newVotes * newVotes) - (prevVotes * prevVotes);

        token.transferFrom(msg.sender, address(this), cost);

        votesPerUser[id][msg.sender] = newVotes;
        tokensUsed[id][msg.sender] += cost;

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

        token.transferFrom(address(this), msg.sender, refund);
    }

    function _checkAndExecuteProposal(uint256 id) internal {

        Proposal storage p = proposals[id];
        if (p.signaling || p.approved || p.canceled) return;

        uint256 pending = _pendingProposals();

        uint256 threshold =
            ((20 + (p.budget * 100) / budget) * numParticipants) / 100
            + pending;

        if (p.voteCount >= threshold && budget >= p.budget) {

            p.approved = true;

            budget += p.tokensCollected;
            budget -= p.budget;

            (bool success, ) = p.executable.call{value: p.budget, gas: 100000}(
                abi.encodeWithSignature(
                    "executeProposal(uint256,uint256,uint256)",
                    id,
                    p.voteCount,
                    p.tokensCollected
                )
            );

            require(success, "Fallo ejecucion");

            token.burn(address(this), p.tokensCollected);
        }
    }

   
    function closeVoting() external onlyOwner {

        votingOpen = false;

        for (uint i = 0; i < proposals.length; i++) {
            Proposal storage p = proposals[i];

            if (p.signaling) {
                p.executable.call{gas: 100000}(
                    abi.encodeWithSignature(
                        "executeProposal(uint256,uint256,uint256)",
                        i,
                        p.voteCount,
                        p.tokensCollected
                    )
                );
            }
        }

        payable(owner).transfer(budget);
        budget = 0;
    }
}
