// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

// Definição do contrato NFTAuction que implementa as interfaces IERC721Receiver, ReentrancyGuard e Ownable
contract NFTAuction is IERC721Receiver, ReentrancyGuard, Ownable {
    using SafeMath for uint256; // Uso da biblioteca SafeMath para operações seguras com uint256

    // Estrutura que define um leilão
    struct Auction {
        address seller; // Endereço do vendedor
        address highestBidder; // Endereço do maior licitante
        uint256 highestBid; // Valor do maior lance
        uint256 startPrice; // Preço inicial do leilão
        uint256 endTime; // Tempo de término do leilão
        uint256 minIncrement; // Incremento mínimo para novos lances
        bool active; // Indica se o leilão está ativo
        mapping(address => uint256) bids; // Mapeamento de lances por endereço
    }

    IERC721 public nftContract; // Contrato do NFT
    uint256 public auctionCount; // Contador de leilões
    mapping(uint256 => Auction> public auctions; // Mapeamento de leilões por ID
    mapping(address => uint256> public pendingReturns; // Mapeamento de retornos pendentes por endereço
    uint256 public contractBalance; // Saldo do contrato

    // Eventos para notificar sobre ações no leilão
    event AuctionStarted(uint256 auctionId, address seller, uint256 startPrice, uint256 endTime, uint256 minIncrement);
    event NewBid(uint256 auctionId, address bidder, uint256 amount);
    event AuctionEnded(uint256 auctionId, address winner, uint256 amount);
    event FundsWithdrawn(address indexed user, uint256 amount);

    // Função para iniciar um leilão
    function startAuction(uint256 _tokenId, uint256 _startPrice, uint256 _duration, uint256 _minIncrement) external payable nonReentrant {
        require(nftContract.ownerOf(_tokenId) == msg.sender, "You must own the NFT"); // Verifica se o chamador é o dono do NFT

        uint256 fee = _startPrice.mul(2).div(100); // Calcula a taxa de 2% do preço inicial
        require(msg.value == fee, "Must send 2% of start price as fee"); // Verifica se a taxa foi paga
        contractBalance = contractBalance.add(fee); // Adiciona a taxa ao saldo do contrato

        auctionCount++; // Incrementa o contador de leilões
        Auction storage auction = auctions[auctionCount]; // Cria um novo leilão
        auction.seller = msg.sender; // Define o vendedor
        auction.startPrice = _startPrice; // Define o preço inicial
        auction.endTime = block.timestamp.add(_duration); // Define o tempo de término
        auction.minIncrement = _minIncrement; // Define o incremento mínimo
        auction.active = true; // Ativa o leilão

        nftContract.safeTransferFrom(msg.sender, address(this), _tokenId); // Transfere o NFT para o contrato

        emit AuctionStarted(auctionCount, msg.sender, _startPrice, auction.endTime, _minIncrement); // Emite evento de início do leilão
    }

    function startAuction(uint256 _tokenId, uint256 _startPrice, uint256 _duration, uint256 _minIncrement) external payable nonReentrant {
        require(nftContract.ownerOf(_tokenId) == msg.sender, "You must own the NFT"); // Verifica se o chamador é o dono do NFT

        uint256 fee = _startPrice.mul(2).div(100); // Calcula a taxa de 2% do preço inicial
        require(msg.value == fee, "Must send 2% of start price as fee"); // Verifica se a taxa foi paga
        contractBalance = contractBalance.add(fee); // Adiciona a taxa ao saldo do contrato

        auctionCount++; // Incrementa o contador de leilões
        Auction storage auction = auctions[auctionCount]; // Cria um novo leilão
        auction.seller = msg.sender; // Define o vendedor
        auction.startPrice = _startPrice; // Define o preço inicial
        auction.endTime = block.timestamp.add(_duration); // Define o tempo de término
        auction.minIncrement = _minIncrement; // Define o incremento mínimo
        auction.active = true; // Ativa o leilão

        nftContract.safeTransferFrom(msg.sender, address(this), _tokenId); // Transfere o NFT para o contrato

        emit AuctionStarted(auctionCount, msg.sender, _startPrice, auction.endTime, _minIncrement); // Emite evento de início do leilão
    }

    // Função para fazer um lance
    function bid(uint256 _auctionId) external payable nonReentrant {
        Auction storage auction = auctions[_auctionId]; // Obtém o leilão
        require(auction.active, "Auction not active"); // Verifica se o leilão está ativo

        require(msg.value > 0, "Bid must be greater than zero"); // Verifica se o lance é maior que zero

        uint256 newBid = auction.bids[msg.sender].add(msg.value); // Calcula o novo lance
        require(newBid >= auction.startPrice, "Bid must be at least the start price"); // Verifica se o lance é maior ou igual ao preço inicial
        require(newBid >= auction.highestBid.add(auction.minIncrement), "Bid increment too low"); // Verifica se o incremento do lance é suficiente

        auction.bids[msg.sender] = newBid; // Atualiza o lance do licitante

        if (auction.highestBidder != address(0)) {
            pendingReturns[auction.highestBidder] = pendingReturns[auction.highestBidder].add(auction.highestBid); // Adiciona o lance anterior aos retornos pendentes
        }

        auction.highestBidder = msg.sender; // Define o novo maior licitante
        auction.highestBid = newBid; // Atualiza o maior lance

        emit NewBid(_auctionId, msg.sender, newBid); // Emite evento de novo lance

        // Verifica se o tempo do leilão terminou
        if (block.timestamp >= auction.endTime) {
            auction.active = false; // Desativa o leilão
        }
    }

    // Função para finalizar um leilão
    function endAuction(uint256 _auctionId) public nonReentrant {
        Auction storage auction = auctions[_auctionId]; // Obtém o leilão
        require(auction.active, "Auction not active"); // Verifica se o leilão está ativo
        require(block.timestamp >= auction.endTime, "Auction not ended yet"); // Verifica se o leilão terminou

        auction.active = false; // Desativa o leilão

        if (auction.highestBidder != address(0)) {
            nftContract.safeTransferFrom(address(this), auction.highestBidder, _auctionId); // Transfere o NFT para o maior licitante
            uint256 commission = auction.highestBid.mul(10).div(100); // Calcula a comissão de 10%
            contractBalance = contractBalance.add(commission); // Adiciona a comissão ao saldo do contrato
            payable(auction.seller).transfer(auction.highestBid.sub(commission)); // Transfere o valor do lance menos a comissão para o vendedor
        } else {
            nftContract.safeTransferFrom(address(this), auction.seller, _auctionId); // Transfere o NFT de volta para o vendedor
        }

        emit AuctionEnded(_auctionId, auction.highestBidder, auction.highestBid); // Emite evento de término do leilão
    }

    // Função para reclamar reembolso
    function claimRefund() external nonReentrant {
        uint256 amount = pendingReturns[msg.sender]; // Obtém o valor pendente
        require(amount > 0, "No funds to claim"); // Verifica se há fundos para reclamar

        pendingReturns[msg.sender] = 0; // Zera o valor pendente
        payable(msg.sender).transfer(amount); // Transfere o valor para o chamador

        emit FundsWithdrawn(msg.sender, amount); // Emite evento de retirada de fundos
    }

    // Função para o dono do contrato reclamar as taxas
    function claimFees() external onlyOwner nonReentrant {
        uint256 amount = contractBalance; // Obtém o saldo do contrato
        require(amount > 0, "No fees to claim"); // Verifica se há taxas para reclamar

        contractBalance = 0; // Zera o saldo do contrato
        payable(owner()).transfer(amount); // Transfere o valor para o dono do contrato

        emit FundsWithdrawn(owner(), amount); // Emite evento de retirada de fundos
    }

    // Função para receber NFTs
    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return this.onERC721Received.selector; // Retorna o seletor da função
    }
}
