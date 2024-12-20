//SPDX-License-Identifier: Unlicense
pragma solidity >=0.6.6;

import "hardhat/console.sol";

// Uniswap interface and library imports
import "./libraries/UniswapV2Library.sol";
import "./libraries/SafeERC20.sol";
import "./interfaces/IUniswapV2Router01.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/IERC20.sol";

contract FlashLoan {
    using SafeERC20 for IERC20;

    address private constant UNISWAP_FACTORY =
        0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address private constant UNISWAP_ROUTER =
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address private constant SUSHI_FACTORY =
        0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address private constant SUSHI_ROUTER =
        0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;

    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant LINK = 0x514910771AF9Ca656af840dff83E8264EcF986CA;

    uint256 private deadline = block.timestamp + 1 days;
    uint256 private constant MAX_INT =
        115792089237316195423570985008687907853269984665640564039457584007913129639935;

    function getBalanceOfToken(address _address) public view returns (uint256) {
        return IERC20(_address).balanceOf(address(this));
    }

    function placeTrade(
        address _fromToken,
        address _toToken,
        uint256 _amountIn,
        address factory,
        address router
     ) private returns (uint256) {
        address pair = IUniswapV2Factory(factory).getPair(_fromToken, _toToken);
        require(pair != address(0), "Pool does not exist");

    
        address[] memory path = new address[](2);
        path[0] = _fromToken;
        path[1] = _toToken;

        uint256 amountRequired = IUniswapV2Router01(router).getAmountsOut(
            _amountIn,
            path
        )[1];

        uint256 amountReceived = IUniswapV2Router01(router)
            .swapExactTokensForTokens(
                _amountIn, 
                amountRequired, 
                path, 
                address(this),
                deadline 
            )[1];

        require(amountReceived > 0, "Aborted Tx: Trade returned zero");

        return amountReceived;
    }


    function checkProfitability(uint256 _repay, uint256 _afterprof) pure
        private
        returns (bool)
    {
        console.log("\nThis is input" ,_repay );
        console.log("\nThis is output" ,_afterprof );
        
        return _afterprof > _repay;
    }

    //1. Approval dia uniswap router ko to use our tokens
    function initiateArbitrage(address _tokenBorrow, uint256 _amount) external {

        IERC20(WETH).safeApprove(address(UNISWAP_ROUTER), MAX_INT);
        IERC20(USDC).safeApprove(address(UNISWAP_ROUTER), MAX_INT);
        IERC20(LINK).safeApprove(address(UNISWAP_ROUTER), MAX_INT);

        IERC20(WETH).safeApprove(address(SUSHI_ROUTER), MAX_INT);
        IERC20(USDC).safeApprove(address(SUSHI_ROUTER), MAX_INT);
        IERC20(LINK).safeApprove(address(SUSHI_ROUTER), MAX_INT);

//liquidity pool ko access kia to see we have that pair available to swap
        address pair = IUniswapV2Factory(UNISWAP_FACTORY).getPair(
            _tokenBorrow,
            WETH
        );

        console.log("\n========>We are getting the pair address" ,pair );

        require(pair != address(0), "Pool does not exist");

        address token0 = IUniswapV2Pair(pair).token0();  //usdc
        console.log("\n=====> Adress of token0" , token0);

        address token1 = IUniswapV2Pair(pair).token1();//link

        console.log("\n====> Adress of token1" , token1);

        uint256 amount0Out = _tokenBorrow == token0 ? _amount : 0;
        console.log("\n====> Token Borrow ki amount isme ja rahi ha?" , amount0Out);
        uint256 amount1Out = _tokenBorrow == token1 ? _amount : 0;
        console.log("\n====> Token Borrow ki amount isme ja rahi ha?" , amount1Out);

        bytes memory data = abi.encode(_tokenBorrow, _amount, msg.sender);
        
        //Mere contract me borrow tokens ki amount transfer hogi
        IUniswapV2Pair(pair).swap(amount0Out, amount1Out, address(this), data);
    }

    function uniswapV2Call(
        address _sender,
        uint256 _amount0,
        uint256 _amount1,
        bytes calldata _data
    ) external {
    
        address token0 = IUniswapV2Pair(msg.sender).token0();
        address token1 = IUniswapV2Pair(msg.sender).token1();
        address pair = IUniswapV2Factory(UNISWAP_FACTORY).getPair(
            token0,
            token1
        );
        require(msg.sender == pair, "The sender needs to match the pair");
        require(_sender == address(this), "Sender should match this contract");
        //jo byte array encode ki thi usko decode kia
        (address tokenBorrow, uint256 amount, address myAddress) = abi.decode(
            _data,
            (address, uint256, address)
        );
        
        //flash loan kay liye amount borrow ki,  amount+fee will have to return
        uint256 fee = ((amount * 3) / 997) + 1;
        uint256 repayAmount = amount + fee;

        console.log("===Amount jo me repay kr rha hu borrow krky+Fee" ,repayAmount);

        uint256 loanAmount = _amount0 > 0 ? _amount0 : _amount1;
        console.log("\nYoo Yoo Loan Amount" ,loanAmount);

        //Triangular Abitrage

        uint256 trade1Coin = placeTrade(
            USDC,
            LINK,
            loanAmount,
            UNISWAP_FACTORY,
            UNISWAP_ROUTER
        );
        console.log("Coins of pair1/LINK in WEI's" ,trade1Coin);
       
        uint256 trade2Coin = placeTrade(
            LINK,
            USDC,
            trade1Coin,
            SUSHI_FACTORY,
            SUSHI_ROUTER
        );
        console.log("\nCoins of pair2/USDC-apna final profit" ,trade2Coin);

        console.log("\n Yo Yo Yo Check the profit by calling profitability function");

        bool profCheck = checkProfitability(repayAmount, trade2Coin);
        //if get's true then arbitrage will not be profitble
        require(profCheck, "Arbitrage not profitable");

        IERC20 otherToken = IERC20(USDC);
        otherToken.transfer(myAddress, trade2Coin - repayAmount);
        //returning pair and repay amount to liquidity pool
        IERC20(tokenBorrow).transfer(pair, repayAmount);
    }
}