pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;


contract Oracle {
    UniswapRouter UR = UniswapRouter(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D );
    uint[] price;
    function getUniPrice(uint _eth_amount) public view returns(uint[] memory amount) {
        address[] memory path = new address[](2);
        path[0] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        path[1] = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;

        uint256[] memory result = UR.getAmountsOut(_eth_amount, path);
        return result;
    }
    function showUniPrice() public view returns(uint[] memory amount) {
      return price;
    }

    function setPrice() public {
      price = getUniPrice(25000000000000000);
    }
}

interface UniswapRouter {
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
}

