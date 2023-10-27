// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

contract Marketplace is ERC721Holder{

    using SafeMath for uint256;

    uint256 public serviceFee;
    address public nftContract;
    address payable public marketPlaceOwner;

    constructor(uint256 _serviceFee, address _nftContract){
        serviceFee = _serviceFee;
        nftContract = _nftContract;
        marketPlaceOwner = payable(msg.sender);
    }

    struct FixpriceListing{
        bool isListed;
        uint256 price;
        address seller;
        uint256 tokenid;
    }
    struct AuctionListing{
        bool isSold;
        bool isListed;
        address seller;
        uint256 tokenid;
        uint256 endTime;
        uint256 reservePrice;
    }
    struct bidding{
        bool isBiPplaced;
        uint256 currentBidValue;
        address currentBidder;
    }

    mapping(uint256=> bidding) public bidinformation;
    mapping(uint256 => AuctionListing) public auctionListings;
    mapping(uint256 => FixpriceListing) public fixpriceListings;

    modifier adminOnly(){
        require(msg.sender == marketPlaceOwner,"unautherized caller");
        _;
    }

    event nftClaim(uint256 indexed tokenid, address indexed claimer);
    event bidPlace(uint256 indexed tokenid, uint256 indexed bidValue, address indexed bidder);
    event auctionsListed(uint256 indexed tokenid, address indexed seller, uint256 indexed resPrice);
    event fixpriceListed(uint256 indexed tokenid, address indexed seller, uint256 indexed nftprice);
    event unlistAuctions(uint256 indexed tokenid, address indexed seller, uint256 indexed unlistedAt);
    event unlistFixprice(uint256 indexed tokenid, address indexed seller, uint256 indexed unlistedAt);
    event endAuctionTime(uint256 indexed tokenid, address indexed Winner, uint256 indexed winingBidValue);
    event buyFixpriceNft(uint256 indexed tokenid, address indexed buyer,  uint256 indexed totalPricePaid);

    // admin can update the servicefee/platform fee with following function

    function updateServiceFee(uint256 _newServiceFee) public adminOnly{
        require(_newServiceFee <= 1000 && _newServiceFee >= 100,"Can not be greater than 10 % ");
        serviceFee = _newServiceFee;
    }

    // this function is calculating the service fee that is charged by the platform

    function calculateServiceFee(uint256 _nftprice, uint256 _pbp) private pure returns(uint256){
        uint256 servicefees = _nftprice.mul(_pbp).div(10000);
        return servicefees;
    }

    // this function will list the nft on fixed price    

    function listNftOnFixedprice(uint256 _tokenid, uint256 _price) public {
        require(_price > 0,"price can not be zero");
        require(!fixpriceListings[_tokenid].isListed,"already listed");
        fixpriceListings[_tokenid] = FixpriceListing({
            isListed:true, price:_price, seller:msg.sender, tokenid:_tokenid
        });
        IERC721(nftContract).safeTransferFrom(msg.sender, address(this), _tokenid);
        emit fixpriceListed(_tokenid,  msg.sender, _price);
    }

    // this function will list the nft on timed auction

    function listNftOnAuction(uint256 _tokenid, uint256 _reservePrice, uint256 _endTime) public{
        require(_reservePrice > 0,"price can not be zero");
        require(!auctionListings[_tokenid].isListed, "already listed");
        require(_endTime >= block.timestamp.add(5 minutes),"auction period at least for 10 minutes");

        auctionListings[_tokenid] = AuctionListing({
            isSold:false, isListed:true, seller:msg.sender, tokenid:_tokenid, endTime:_endTime, reservePrice:_reservePrice
        });

        IERC721(nftContract).safeTransferFrom(msg.sender, address(this), _tokenid);
        emit auctionsListed(_tokenid, msg.sender, _reservePrice);
    }

    // this function will use to buy the nft that is listed on fixed price

    function buyFixedpriceNft(uint256 _tokenid) public payable {
        require(msg.sender != fixpriceListings[_tokenid].seller,"can not buy your own item");
        require(msg.value == fixpriceListings[_tokenid].price,"pay exact price");

        uint256 servicefee = calculateServiceFee(msg.value, serviceFee);
        marketPlaceOwner.transfer(servicefee);
        uint256 paymentToSeller = msg.value.sub(servicefee);
        payable(fixpriceListings[_tokenid].seller).transfer(paymentToSeller);

        IERC721(nftContract).safeTransferFrom(address(this), msg.sender, _tokenid);
        emit buyFixpriceNft(_tokenid, msg.sender, msg.value);
        delete fixpriceListings[_tokenid];
    }

    // this function will place the bids on the nfts that are listed on the timed auctions

    function bidOnAuction(uint256 _tokenid) public payable{
        require(msg.sender != auctionListings[_tokenid].seller,"seller can not bid");
        require(msg.value >= auctionListings[_tokenid].reservePrice,"bid can not be less then reserve price");
        require(msg.value > bidinformation[_tokenid].currentBidValue,"place high bid then existing");

        uint256 currentBidVal = bidinformation[_tokenid].currentBidValue;
        address currentBidder = bidinformation[_tokenid].currentBidder;

        payable(currentBidder).transfer(currentBidVal);

        bidinformation[_tokenid].isBiPplaced = true;
        bidinformation[_tokenid].currentBidder = msg.sender;
        bidinformation[_tokenid].currentBidValue = msg.value;

        emit bidPlace(_tokenid , msg.value, msg.sender);
    }

    // seller can end the auction (event before the time runs out) and the NFT will be transfer to the highet bidder at that time

    function endAuction(uint256 _tokenid) public {
        require(msg.sender == auctionListings[_tokenid].seller,"you are not the seller");

        uint256 _bidVal = bidinformation[_tokenid].currentBidValue;
        address _bidWinner = bidinformation[_tokenid].currentBidder;

        uint256 _servicefee = calculateServiceFee(_bidVal, serviceFee);
        marketPlaceOwner.transfer(_servicefee);
        uint256 paymentToSeller = _bidVal.sub(_servicefee);
        payable(auctionListings[_tokenid].seller).transfer(paymentToSeller);

        IERC721(nftContract).safeTransferFrom(address(this), _bidWinner, _tokenid);

        emit endAuctionTime(_tokenid, _bidWinner, _bidVal);

        delete auctionListings[_tokenid];
        delete bidinformation[_tokenid];

    }

    // user/bidwinner can claim the nft after the time for the auction is completed

    function claimNft(uint256 _tokenid)  public {
        require(msg.sender == bidinformation[_tokenid].currentBidder,"you are not the highest bidder");
        require(block.timestamp >= auctionListings[_tokenid].endTime,"auction time not completed");

        uint256 _bidVal = bidinformation[_tokenid].currentBidValue;
        address _bidWinner = bidinformation[_tokenid].currentBidder;

        uint256 _servicefee = calculateServiceFee(_bidVal, serviceFee);
        marketPlaceOwner.transfer(_servicefee);
        uint256 paymentToSeller = _bidVal.sub(_servicefee);
        payable(auctionListings[_tokenid].seller).transfer(paymentToSeller);

        IERC721(nftContract).safeTransferFrom(address(this),_bidWinner,_tokenid);

        emit nftClaim(_tokenid, msg.sender);

        delete auctionListings[_tokenid];
        delete bidinformation[_tokenid];
    }
    
    // user can remove the nft from that that is listed on the fix price
    function removeListingFixedprice(uint256 _tokenid) public{
        require(msg.sender == fixpriceListings[_tokenid].seller,"you are not the seller");
        IERC721(nftContract).safeTransferFrom(address(this), msg.sender, _tokenid);
        delete fixpriceListings[_tokenid];
        emit unlistFixprice(_tokenid, msg.sender, block.timestamp);
    }

    // user can remove the nft that is listed with timed auction , but only if there is no bid placed
    function removeListingAuction(uint256 _tokenid) public {
        require(msg.sender == auctionListings[_tokenid].seller,"you are not the seller");
        require(!bidinformation[_tokenid].isBiPplaced,"bid is placed , can not remove from listing");
        IERC721(nftContract).safeTransferFrom(address(this), msg.sender, _tokenid);
        delete auctionListings[_tokenid];
        emit unlistAuctions(_tokenid, msg.sender, block.timestamp);
    }

    // vrf v2 request recieve funding from subscription accounts. the subscriotion manager lets you create an account and pre pay for the vrf v2 , so yoo dont need to pay for the everytime you  make the rewuest.abi

}
