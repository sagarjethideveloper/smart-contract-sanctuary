//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

interface INFTContract {
    function mintNFT(string memory _name, string memory _uri)
        external
        returns (uint256);

    function burnNFT(uint256 _nftId) external;

    function transferNFT(address _to, uint256 _nftId) external;

    function getNFTLevelById(uint256 _nftId) external returns (uint256);

    function getNFTById(uint256 _nftId)
        external
        returns (
            uint256,
            string memory,
            string memory,
            uint256
        );

    function setNFTLevelUp(uint256 _nftId) external;

    function setNFTURI(uint256 _nftId, string memory _uri) external;

    function ownerOf(uint256 _nftId) external returns (address);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./INFTContract.sol";

contract MintContract {
    INFTContract nft_;

    mapping(address => uint256) freeNfts_;

    string NFT_NAME = "GamyFi TRITON NFT";
    string NFT_URI =
        "https://ipfs.io/ipfs/bafybeibt65tydbeh5qoyalk2fd7tlkbxbinu5vxrdqotjhpgattroueeii";

    constructor(address _nft) {
        nft_ = INFTContract(_nft);
    }

    function mint() public {
        require(
            msg.sender != nft_.ownerOf(freeNfts_[msg.sender]),
            "MintContract: Already have"
        );

        uint256 nftId =
            nft_.mintNFT(
                "GamyFi TRITON NFT",
                "https://ipfs.io/ipfs/bafybeibt65tydbeh5qoyalk2fd7tlkbxbinu5vxrdqotjhpgattroueeii"
            );
        freeNfts_[msg.sender] = nftId;
    }
}

