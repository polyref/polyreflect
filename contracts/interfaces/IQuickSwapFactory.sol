pragma solidity ^0.6.0;

interface IQuickSwapFactory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

