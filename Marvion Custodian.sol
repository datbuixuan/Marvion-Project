// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MarvionCustodianWallet is Ownable {
    struct Token721Item{
        address tokenAddress;
        uint256 tokenId;
        uint256 userId;
    }

    Token721Item[] token721Items;
    mapping (address => mapping (uint256 => uint256)) token721Index;
    mapping (uint256 => mapping (address => uint256)) userCryptoAmounts; // ERC20 (COTK, BUSD....)

    event TokenIdAdded(uint256 userId, address contractAddress, uint256 tokenId);
    event TokenIdWithdrawn(uint256 userId, address contractAddress, uint256 tokenId);
    event TokenIdTranferred(uint256 userId, address contractAddress, uint256 tokenId, uint256 receiverId);
    event TokenIdTranferredTo(uint256 userId, address contractAddress, uint256 tokenId, address receiverAddress);

    event AmountAdded(uint256 userId, address contractAddress, uint256 amount);
    event AmountWithdrawn(uint256 userId, address contractAddress, uint256 amount);
    event AmountTranferred(uint256 userId, address contractAddress, uint256 amount, uint256 receiverId);
    event AmountTranferredTo(uint256 userId, address contractAddress, uint256 amount, address receiverAddress);

    // modifier
    //Erc 721
    modifier isExsistNFT(address contractAddress, uint256 tokenId){       
        uint256 indexIdOfNFT = token721Index[contractAddress][tokenId];
        require(token721Items[indexIdOfNFT].userId <= 0, "TokenId already exists");

        _;
    }

    modifier isApprovedNFT721(address contractAddress, uint256 tokenId){
         IERC721 tokenContract = IERC721(contractAddress);
         bool isApprovedAll = tokenContract.isApprovedForAll(msg.sender, address(this));
         address approvedAddress = tokenContract.getApproved(tokenId);

         require(isApprovedAll || approvedAddress == address(this), "Item is not approved for this contract");
         _;
    }

    modifier ownerNFT(address contractAddress, uint256 tokenId){
         IERC721 tokenContract = IERC721(contractAddress);
         address ownerAddress = tokenContract.ownerOf(tokenId);

         require(ownerAddress == msg.sender,"You are not owner of NFT");
         _;
    }

    modifier validNFTonContract(uint256 userId, address contractAddress, uint tokenId){
        uint256 indexIdOfNFT = token721Index[contractAddress][tokenId];
        require (token721Items[indexIdOfNFT].userId == userId, "TokenId not exists on this Contract");
        _;
    }


    // Crypto
    modifier validAmountForAddCrypto(address contractAddress, uint256 amount){
        if (contractAddress == address(0)) { //Coin
            require(msg.value == amount, "Input data is incorrect");
        }
        else { // Token
            require(amount > 0, "Input data is incorrect");
            IERC20 _contractAddress = IERC20(contractAddress);
            require(_contractAddress.balanceOf(msg.sender) >= amount, "Not enough balance");
            require(_contractAddress.allowance(msg.sender, address(this)) >= amount, "Not approved with amount");
        }
        _;
    }

    
    modifier validAmountOfUser(uint256 userId, address contractAddress, uint256 amount){
        require(userCryptoAmounts[userId][contractAddress] > amount && amount > 0, "Balance not enough");
        _;
    }


    // batch modifier
    // Erc 721
    modifier isValidForBatchAddToken(uint256[] memory userIds, address contractAddress, uint256[] memory tokenIds){
        require(userIds.length == tokenIds.length,"The input data is incorect");

        IERC721 tokenContract = IERC721(contractAddress);
        bool isApprovedAll = tokenContract.isApprovedForAll(msg.sender, address(this));

        for(uint256 i = 0; i < tokenIds.length; i++){
            require(userIds[i] > 0, "CW 001");

            uint256 indexOfNFT = token721Index[contractAddress][tokenIds[i]];
            
            uint256 userIdOfNFT = token721Items[indexOfNFT].userId;
            require (userIdOfNFT <= 0, "TokenId already exists");
            
            address ownerAddress = tokenContract.ownerOf(tokenIds[i]);
            require(ownerAddress == msg.sender, "You are not owner of NFT");

            if(isApprovedAll == false){
                address approvedAddress = tokenContract.getApproved(tokenIds[i]);
                require(approvedAddress == address(this), "Item is not approved for this contract");
            }           
        }   
        _;
    }
    
    modifier isValidForBatchTransferToken(uint256[] memory userIds, address contractAddress, uint256[] memory tokenIds, uint256[] memory receiverIds){
        require (userIds.length == tokenIds.length, "The input data is incorrect");
        require(userIds.length == receiverIds.length, "The input data in incorrect");

        for(uint256 i = 0; i < tokenIds.length; i++){
            require(userIds[i] > 0 && receiverIds[i] > 0, "CW 001");
            uint256 indexOfNFT = token721Index[contractAddress][tokenIds[i]];
            uint256 userIdOfNFT = token721Items[indexOfNFT].userId;
            require(userIdOfNFT == userIds[i], "TokenId not exists on this Contract");
        }

        _;
    }

    modifier isValidForBatchTransferTokenToAddress(uint256[] memory userIds, address contractAddress, uint256[] memory tokenIds, address[] memory receiverAddresses){
        require (userIds.length == tokenIds.length, "The input data is incorrect");
        require(userIds.length == receiverAddresses.length, "The input data in incorrect");

        for(uint256 i = 0; i < tokenIds.length; i++){
            require(userIds[i] > 0 && receiverAddresses[i] > address(0), "CW 001");

            uint256 indexOfNFT = token721Index[contractAddress][tokenIds[i]];
            uint256 userIdOfNFT = token721Items[indexOfNFT].userId;
            require(userIdOfNFT == userIds[i], "TokenId not exists on this Contract");
        }

        _;
    }

    modifier isValidForBatchWithdrawTokenId(uint256[] memory userIds, address contractAddress, uint256[] memory tokenIds){
        require (userIds.length == tokenIds.length, "The input data is incorrect");

         for(uint256 i = 0; i < tokenIds.length; i++){
            require(userIds[i] > 0, "CW 001");

            uint256 indexOfNFT = token721Index[contractAddress][tokenIds[i]];
            uint256 userIdOfNFT = token721Items[indexOfNFT].userId;
            require(userIdOfNFT == userIds[i], "TokenId not exists on this Contract");
        }

        _;
    }

    // Crypto
    modifier isValidForBatchAddCrypto(uint256[] memory userIds, address contractAddress, uint256[] memory amounts){
        require(userIds.length == amounts.length, "Input data is incorrect");

        uint256 totalAmount = 0;
        for(uint i = 0; i < amounts.length; i++){
            require(amounts[i] > 0, "Input data is incorrect");
            require(userIds[i] > 0, "Input data is incorrect");

            totalAmount += amounts[i];
        }

        if(contractAddress == address(0)){
            require(totalAmount == msg.value, "Input data is incorrect");
        }
        else{
            require(totalAmount > 0, "Input data is incorrect");
            IERC20 _contractAddress = IERC20(contractAddress);
            require(_contractAddress.balanceOf(msg.sender) >= totalAmount, "Not enough balance");
            require(_contractAddress.allowance(msg.sender, address(this)) >= totalAmount, "Not approved with amount");
        }
        _;
    }

    modifier isValidForBatchTransferCrypto(uint256[] memory userIds, address contractAddress, uint256[] memory amounts, uint256[] memory receiverIds){
        require(userIds.length == amounts.length, "The input data is incorrect");
        require(receiverIds.length == amounts.length, "The input data is incorrect");

        for(uint256 i = 0; i < userIds.length; i++){
            require(userIds[i] > 0, "The input data is incorrect");
            require(receiverIds[i] > 0, "The input data is incorrect");

            require(userCryptoAmounts[userIds[i]][contractAddress] > amounts[i] && amounts[i] > 0, "Balance not enough");
        }
        _;
    }

     modifier isValidForBatchTransferTo(uint256[] memory userIds, address contractAddress, uint256[] memory amounts, address[] memory receiverAddresses){
        require(userIds.length == amounts.length, "The input data is incorrect");     
        require(userIds.length == receiverAddresses.length, "The input data is incorrect");     

        for(uint256 i = 0; i < amounts.length; i++){
            require(userIds[i] > 0, "The input data is incorrect");     
            require(amounts[i] > 0, "The input data is incorrect");   
            require(receiverAddresses[i] != address(0), "The input data is incorrect");  

            uint256 amount = userCryptoAmounts[userIds[i]][contractAddress];
            require(amount >= amounts[i], "Balance not enough");
        }       
        _;
    }

    //  Function
    // ERC 721

    constructor (){
        token721Items.push(Token721Item(address(0), 0, 0));
    }

    function addTokenId(uint256 userId, address contractAddress, uint256 tokenId) external 
        onlyOwner ownerNFT(contractAddress, tokenId)
        isExsistNFT(contractAddress, tokenId)
        isApprovedNFT721(contractAddress, tokenId) {
             require(userId > 0, "CW 001");
            _addTokenId(userId, contractAddress, tokenId);
    }

    function batchAddTokenId(uint256[] memory userIds, address contractAddress, uint256[] memory tokenIds) external 
        onlyOwner
        isValidForBatchAddToken (userIds, contractAddress, tokenIds) {          
            for (uint256 i = 0; i < userIds.length; i++){
                _addTokenId(userIds[i], contractAddress, tokenIds[i]);
            }   
    } 



    function transferTokenId(uint256 userId, address contractAddress, uint256 tokenId, uint256 receiverId) external 
        onlyOwner validNFTonContract(userId, contractAddress, tokenId){
            require(receiverId > 0 && userId > 0, "CW 001");
            _transferTokenId(userId, contractAddress, tokenId, receiverId);            
    }

    function batchTransferTokenId(uint256[] memory userIds, address contractAddress, uint256[] memory tokenIds, uint256[] memory receiverIds) external 
        onlyOwner isValidForBatchTransferToken(userIds, contractAddress, tokenIds, receiverIds) {
            for(uint256 i = 0; i < userIds.length; i++){
                _transferTokenId(userIds[i], contractAddress, tokenIds[i], receiverIds[i]);   
            }
    }



    function transferTokenIdTo(uint256 userId, address contractAddress, uint256 tokenId, address receiverAddress) external 
        onlyOwner validNFTonContract(userId, contractAddress, tokenId) {
            require (receiverAddress != address(0), "The address is incorrect");

            _transferTokenIdTo(userId, contractAddress, tokenId, receiverAddress);
    }

    function batchTransferTokenIdTo(uint256[] memory userIds, address contractAddress, uint256[] memory tokenIds, address[] memory receiverAddresses) external 
        onlyOwner isValidForBatchTransferTokenToAddress(userIds, contractAddress, tokenIds, receiverAddresses) {
            for(uint256 i = 0; i < userIds.length; i++){
                _transferTokenIdTo(userIds[i], contractAddress, tokenIds[i], receiverAddresses[i]);
            }            
    }



    function withdrawTokenId(uint256 userId, address contractAddress, uint256 tokenId) external 
        onlyOwner validNFTonContract(userId, contractAddress, tokenId) {
            _withdrawTokenId(userId, contractAddress, tokenId);
    }

    function batchWithdrawTokenId(uint256[] memory userIds, address contractAddress, uint256[] memory tokenIds) external 
        onlyOwner isValidForBatchWithdrawTokenId(userIds, contractAddress, tokenIds) {
            for(uint256 i = 0; i < tokenIds.length; i++){
                _withdrawTokenId(tokenIds[i], contractAddress, tokenIds[i]);
            }       
    }



    
    // Crypto
    
    function addCryptoAmount(uint256 userId, address contractAddress, uint256 amount) external payable 
        onlyOwner validAmountForAddCrypto(contractAddress, amount) {
            require(userId > 0, "The input data is incorrect.");          

            _addCryptoAmount(userId, contractAddress, amount);
    } 

    function batchAddCryptoAmount(uint256[] memory userIds, address contractAddress, uint256[] memory amounts) external payable
        onlyOwner isValidForBatchAddCrypto(userIds, contractAddress, amounts){
            for(uint256 i = 0; i < userIds.length; i++){
                _addCryptoAmount(userIds[i], contractAddress, amounts[i]);
            }
    }
 


    function transferAmount(uint256 userId, address contractAddress, uint256 amount, uint256 receiverId) external 
        onlyOwner validAmountOfUser(userId, contractAddress, amount){
            require(userId > 0 , "The input data is incorrect");
            require(receiverId > 0, "The input data is incorrect");  

            _transferAmount(userId, contractAddress, amount, receiverId);
    }

    function batchTransferAmount(uint256[] memory userIds, address contractAddress, uint256[] memory amounts, uint256[] memory receiverIds) external 
        onlyOwner isValidForBatchTransferCrypto(userIds, contractAddress, amounts, receiverIds){
            for(uint256 i = 0; i < amounts.length; i++){
                _transferAmount(userIds[i], contractAddress, amounts[i], receiverIds[i]);
            }
    }



    function transferAmountTo(uint256 userId, address contractAddress, uint256 amount, address receiverAddress) external 
        onlyOwner validAmountOfUser(userId, contractAddress, amount) {
            require(userId > 0, "The input data is incorrect");
            require(receiverAddress != address(0), "The input data is incorrect");         

            _transferAmountTo(userId, contractAddress, amount, receiverAddress);  
    }

    function batchTransferAmountTo(uint256[] memory userIds, address contractAddress, uint256[] memory amounts, address[] memory receiverAddresses) external 
        onlyOwner isValidForBatchTransferTo(userIds, contractAddress, amounts, receiverAddresses) {
            for(uint256 i = 0; i < userIds.length; i++){
                _transferAmountTo(userIds[i], contractAddress, amounts[i], receiverAddresses[i]);
            }    
    }


    function withdrawAmount(uint256 userId, address contractAddress, uint256 amount) external 
        onlyOwner validAmountOfUser(userId, contractAddress, amount) {    
            require(userId > 0, "The input data is incorrect"); 
            _withdrawAmount(userId, contractAddress, amount);  
    }

    modifier isValidForBatchWithdrawCrypto(uint256[] memory userIds, address contractAddress, uint256[] memory amounts) {
        require(userIds.length == amounts.length, "The input data is incorrect");
        for(uint256 i = 0; i < userIds.length; i++){
            require(userIds[i] > 0, "The input data is incorrect");
            require(amounts[i] > 0, "The input data is incorrect");

            require(userCryptoAmounts[userIds[i]][contractAddress] > amounts[i], "Balance not enough");
        }
        _;
    }

    function batchWithdrawAmount(uint256[] memory userIds, address contractAddress, uint256[] memory amounts) external 
        onlyOwner isValidForBatchWithdrawCrypto(userIds, contractAddress, amounts) {    
            for(uint256 i = 0; i < userIds.length; i++){
                _withdrawAmount(userIds[i], contractAddress, amounts[i]);  
            } 
    }


    // public function
    function getAmount(uint256 userId, address contractAddress) public view returns(uint256) {
        return userCryptoAmounts[userId][contractAddress];
    }

    function getUserOfNFT721(address contractAddress, uint256 tokenId) public view returns(Token721Item memory){
        uint256 indexOfNFT = token721Index[contractAddress][tokenId];
        return token721Items[indexOfNFT];
    }

   function getNFTs721(uint256 userId) public view returns (Token721Item[] memory) {       
        uint256 j = 0;
        for(uint256 i = 0; i < token721Items.length; i++){
            if(token721Items[i].userId == userId){               
                j++;
            }
        }
        Token721Item[] memory lstNewItems = new Token721Item[](j);
        j = 0;
         for(uint256 i = 0; i < token721Items.length; i++){
            if(token721Items[i].userId == userId){
                lstNewItems[j] = token721Items[i];
                j++;
            }
        }
        return lstNewItems;
   }



    // Private
    // ERC 721
    function _addTokenId(uint256 userId, address contractAddress, uint256 tokenId) private{
        IERC721 tokenContract = IERC721(contractAddress); 
        tokenContract.transferFrom(msg.sender, address(this), tokenId);

        token721Items.push(Token721Item(contractAddress, tokenId, userId));
        
        uint256 length = token721Items.length;

        token721Index[contractAddress][tokenId] = length - 1;

        emit TokenIdAdded(userId, contractAddress, tokenId);
    }

    function _transferTokenId(uint256 userId, address contractAddress, uint256 tokenId, uint256 receiverId) private{
        uint256 indexOfNFT = token721Index[contractAddress][tokenId];
       
        Token721Item storage token721Item = token721Items[indexOfNFT];
        token721Item.userId = receiverId;
     
        emit TokenIdTranferred(userId, contractAddress, tokenId, receiverId);
    }

    function _transferTokenIdTo(uint256 userId, address contractAddress, uint256 tokenId, address receiverAddress) private {         
        IERC721(contractAddress).transferFrom(address(this), receiverAddress, tokenId);
        
        uint256 indexOfNFT = token721Index[contractAddress][tokenId];
       
        Token721Item storage token721Item = token721Items[indexOfNFT];
        token721Item.userId = 0;

        emit TokenIdTranferredTo(userId, contractAddress, tokenId, receiverAddress);
    }

    function _withdrawTokenId(uint256 userId, address contractAddress, uint256 tokenId) private{
        IERC721(contractAddress).transferFrom(address(this), msg.sender, tokenId);
        
        uint256 indexOfNFT = token721Index[contractAddress][tokenId];
       
        Token721Item storage token721Item = token721Items[indexOfNFT];
        token721Item.userId = 0;
        
        emit TokenIdWithdrawn(userId, contractAddress, tokenId);
    } 


    // Crypto
    function _addCryptoAmount(uint256 userId, address contractAddress, uint256 amount) private {
        if(contractAddress != address(0)) {
            IERC20 _contractAddress = IERC20(contractAddress);           
            _contractAddress.transferFrom(msg.sender, address(this), amount);
        }    

        userCryptoAmounts[userId][contractAddress] += amount;
        emit AmountAdded(userId, contractAddress, amount);
    }

    function _transferAmount(uint256 userId, address contractAddress, uint256 amount, uint256 receiverId) private {    
        userCryptoAmounts[receiverId][contractAddress] += amount;
        userCryptoAmounts[userId][contractAddress] -= amount;

        emit AmountTranferred(userId, contractAddress, amount, receiverId);
    } 


    function _transferAmountTo (uint256 userId, address contractAddress, uint256 amount, address receiverAddress) private{
        _payout(contractAddress, receiverAddress, amount);

        userCryptoAmounts[userId][contractAddress] -= amount;
        emit AmountTranferredTo(userId, contractAddress, amount, receiverAddress);
    }

    function _withdrawAmount (uint256 userId, address contractAddress, uint256 amount) private{
        _payout(contractAddress, msg.sender, amount);

        userCryptoAmounts[userId][contractAddress] -= amount;
        emit AmountWithdrawn(userId, contractAddress, amount);
    }


    function _payout(address contractAddress, address receiverAddress, uint256 amount) private {     
        if (contractAddress == address(0)) {
            uint256 balance = address(this).balance;
            require(balance > 0 && balance >= amount, "Balance not enough");
            payable(receiverAddress).transfer(amount);
        } else {
            uint256 balance = IERC20(contractAddress).balanceOf(address(this));
            require(balance > 0 && balance >= amount, "Balance not enough");
            IERC20(contractAddress).transferFrom(address(this), receiverAddress, amount);
        }
    }
}