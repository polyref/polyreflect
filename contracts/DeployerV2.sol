// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;

import "./interfaces/IQuickSwap.sol";
import "./interfaces/IQuickSwapFactory.sol";
import "./utils/Context.sol";
import "./utils/Ownable.sol";
import "./utils/SafeMath.sol";
import "./utils/Address.sol";
import "./PRF.sol";

interface DeployerV1 {
    function participants(uint256) external returns(address);
}

contract DeployerV2 is Context, Ownable {
    /* LIBS */
    using Address for address;
    using SafeMath for uint256;
    
    /* TOKEN */
    PolyReflect public reflectToken;
    uint256 internal _tokenDecimals = 9;
    uint256 internal totalRewards = 0;
    
    /* PRESALE CONFIG */    
    uint256 internal immutable SOFT_CAP = 250_000 * 10**18;
    uint256 internal immutable HARD_CAP = 625_000 * 10**18;
    uint256 private PRESALE_RATIO = 8000;
    uint256 private PRESALE_TOTAL = 10 * 10**9 * 10**_tokenDecimals;
    uint256 private INSTANT_LIMIT = 3000 * 10**18;
    
    uint256 public FARM_TOKENS = PRESALE_TOTAL.div(100).mul(80);
    uint256 public STAKING_TOKENS = FARM_TOKENS.div(100).mul(30);
    uint256 public LP_TOKENS = FARM_TOKENS.div(100).mul(70);
    uint256 public TEAM_TOKENS = 500_000_000 * 10**_tokenDecimals ;
    uint256 public PRESALE_TOKENS = PRESALE_TOTAL.sub(FARM_TOKENS);
    uint256 public START_TIME;
    uint256 public VALID_TILL;
    
    /* LEGACY */    
    DeployerV1 public _DeployerV1;
    mapping(address => bool) public round_one_participants;
    uint256 public BENEFITS_PERCENT = 10;

    /* SERVICE */
    address[] public participants;
    uint256 public totalMatic;
    mapping(address => uint) public liquidityShare;
    mapping(address => uint256) public balances;
    mapping(address => uint256) public rewards;
    
    /* QUICKSWAP */
    address internal QUICKSWAP_FACTORY_ADDRESS = 0x5757371414417b8C6CAad45bAeF941aBc7d3Ab32 ;
    address internal QUICKSWAP_ROUTER_ADDRESS = 0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff ;
    IQuickSwap internal quick_router;
    IQuickSwapFactory internal quick_factory;
    address public LP_TOKEN_ADDRESS; // internal
    IERC20 public lp_token; // internal
    
    constructor(
        // address legacyDeployer, 
        // uint8 legacyParticipants, 
        uint256 _startTime, 
        uint256 _presaleDays) public {
            // _DeployerV1 = DeployerV1(legacyDeployer);
            // for(uint8 i = 0; i < legacyParticipants; i++) {
            //     address participant = _DeployerV1.participants(i);
            //     if(participant != address(0)){
            //         round_one_participants[participant] = true;
            //     }
            // }
            reflectToken = new PolyReflect(address(this), QUICKSWAP_ROUTER_ADDRESS);
            quick_factory = IQuickSwapFactory(QUICKSWAP_FACTORY_ADDRESS);
            quick_router = IQuickSwap(QUICKSWAP_ROUTER_ADDRESS);
            
            /* INIT STAKINGS */
            
            /* */
            
            START_TIME = _startTime;
            VALID_TILL = _startTime + (_presaleDays * 1 days);
            reflectToken.approve(address(this), ~uint256(0));
            require(reflectToken.approve(QUICKSWAP_ROUTER_ADDRESS, ~uint256(0)), "Approve failed");
            IERC20(quick_router.WETH()).approve(QUICKSWAP_ROUTER_ADDRESS, ~uint256(0));
    }   

    function _startTime() public view returns (uint256) {
        return START_TIME;
    }
    
    function _endTime() public view returns (uint256) {
        return VALID_TILL;
    }
    
    function _participantsLength() public view returns (uint256) {
        return participants.length;
    }
    
    function _totalRewards() public view returns (uint256) {
        return totalRewards;
    }
    
    function adjustStart(uint256 timestamp) public onlyOwner() {
        START_TIME = timestamp;
    }
    
    function adjustEnd(uint256 timestamp) public onlyOwner() {
        VALID_TILL = timestamp;
    }
    
    function _rewardFromMatic(address user, uint256 _value) internal view returns (uint256 reward) {
        if(round_one_participants[user] == true) { 
            return _value.mul(PRESALE_RATIO.add(PRESALE_RATIO.div(100).mul(BENEFITS_PERCENT))).div(10**18).mul(10**_tokenDecimals);
        }else{
            return _value.mul(PRESALE_RATIO).div(10**18).mul(10**_tokenDecimals); 
        }
    }
    
    function _maticFromReward(address user, uint256 _value) internal view returns (uint256 ETH) {
        if(round_one_participants[user] == true) { 
            return _value.div(PRESALE_RATIO.add(PRESALE_RATIO.div(100).mul(BENEFITS_PERCENT))).div(10**18).mul(10**_tokenDecimals);
        }else{
            return _value.div(PRESALE_RATIO).div(10**18).mul(10**_tokenDecimals); 
        }
    }

    function addLiquidity(address sender, uint256 tokenAmount, uint256 maticAmount) internal {
        (,,uint liqidity) = quick_router.addLiquidityETH{ value: maticAmount }( 
                address(reflectToken), //token
                tokenAmount.div(2), // amountTokenDesired
                0, // amountTokenMin
                maticAmount, // amountETHMin
                address(this), 
                block.timestamp + 120 // deadline
            );
        
        if( LP_TOKEN_ADDRESS == address(0) ) {
            LP_TOKEN_ADDRESS = quick_factory.getPair( quick_router.WETH(), address(reflectToken) );
            lp_token = IERC20( LP_TOKEN_ADDRESS );
            require( lp_token.approve( QUICKSWAP_ROUTER_ADDRESS, ~uint256(0)) );
            reflectToken.setLPPair( LP_TOKEN_ADDRESS );
        }    
        
        liquidityShare[sender] = liquidityShare[sender].add(liqidity);
        reflectToken.transferFrom( address(this), sender, tokenAmount );
        reflectToken.increaseAllowanceFrom(sender, address(this), tokenAmount);
    }
    
    function removeLiquidity(address sender) internal returns(uint256 tokenAmount, uint256 maticAmount) {
        (uint256 _tokenAmount, uint256 _maticAmount) = quick_router.removeLiquidityETH(
                address(reflectToken),
                liquidityShare[sender],
                0,
                0,
                address(this),
                block.timestamp + 120
            );
        liquidityShare[sender] = 0;    
        return (_tokenAmount, _maticAmount);
    }
    
    function _getTokenAmountFromShare(address participant, uint256 tokenAmountTotal) internal view returns (uint256 _tokenAmount) {
        uint256 balance = balances[participant];
        uint256 balanceShare = (balance.div( address(this).balance.div(100) )).div(100);
        uint256 tokenAmount = tokenAmountTotal.mul(balanceShare);
        
        return tokenAmount;
    }
    
    function endPresale() public returns (bool) {
        require( block.timestamp > VALID_TILL, "Presale is not over yet" );

        if(totalMatic < SOFT_CAP) {
            for(uint256 i = 0; i < participants.length; i++){
                if ( participants[i] == address(0) ) { // skip purged elements of queue
                    continue;
                } else if ( balances[participants[i]] > 0 ) {
                    address participant = participants[i];
                    (,uint256 MaticFromLP) = removeLiquidity(participant);
                    uint256 _balance = balances[participant].add( MaticFromLP );
                    balances[participants[i]] = 0;
                    payable(participant).transfer( _balance );
                    
                }
            }
        } else { // Otherwise, add liquidity to router and burn LP
            (,uint256 maticAmount) = quick_router.removeLiquidityETH(
                    address(reflectToken),
                    lp_token.balanceOf(address(this)),
                    0,
                    0,
                    address(this),
                    block.timestamp + 120
                );
                
            quick_router.addLiquidityETH{ value: maticAmount }( 
                address(reflectToken), //token
                totalRewards.sub(TEAM_TOKENS), // amountTokenDesired
                0, // amountTokenMin
                maticAmount, // amountETHMin
                address(0), 
                block.timestamp + 120 // deadline
            );
                
            if (address(this).balance > 0) {
                address[] memory path;
                path[0] = quick_router.WETH();
                path[1] = address(reflectToken);
                
                
                
                uint[] memory amounts = quick_router.swapExactETHForTokens{value: address(this).balance}(
                    0,
                    path,
                    address(this),
                    block.timestamp + 120
                );
                
                for(uint256 i = 0; i < participants.length; i++) { // send tokens to participants
                    address participant = participants[i];
                    if(participant == address(0)){ // skip purged elements of queue
                        continue;
                    }
                    reflectToken.transferFrom( address(this), participant, _getTokenAmountFromShare(participant, amounts[0]) );
                }
            }

            require(reflectToken.transferNoFee(address(this), owner(), reflectToken.balanceOf( address(this) )), "Team tokens transfer failed");
            require(reflectToken.unlockAfterPresale(), "Token is not unlocked");
        }
        
        return true;
    }

    function withdraw() public { // Participans can withdraw their balance at anytime during the pre-sale
        require(block.timestamp < VALID_TILL, "Cannon withdraw after end of the pre-sale");
        address payable sender = payable(_msgSender());
        uint256 _balance = balances[sender];
        uint256 TokenFromLP;
        uint256 MaticFromLP;
        
        require(address(this).balance > 0 || liquidityShare[sender] > 0, "Nothing to withdraw");
        require(_balance > 0 || liquidityShare[sender] > 0, "Cannot withdraw zero balance");
        
        balances[sender] = 0;
        rewards[sender] = 0;
        for (uint256 i = 0; i < participants.length; i++){
            if( participants[i] == sender ) {
                delete participants[i]; // purge position in queue    
                break;
            }
        }
        
        if( liquidityShare[sender] > 0 ){
            (TokenFromLP, MaticFromLP) = removeLiquidity(sender);
        }
        
        uint256 _totalUserToken = reflectToken.balanceOf(sender);
        uint256 _totalUserMatic = _balance.add(MaticFromLP);
        totalMatic = totalMatic.sub(_totalUserMatic);
        
        totalRewards = totalRewards.sub(_totalUserToken);
        
        reflectToken.transferFrom(sender, address(this), _totalUserToken);
        sender.transfer(_totalUserMatic);
    }
    
    receive () external payable{
        address sender = _msgSender();
        if(!sender.isContract()) {
            uint256 _time = block.timestamp;
            require(_time >= START_TIME, "Presale does not started");
            require(_time <= VALID_TILL, "Presale is over");
            if(balances[sender] == 0 && rewards[sender] == 0) {
                participants.push(sender);
            }
            
            uint256 instantValue;
            uint256 delayedValue;
            
            uint256 _reward = _rewardFromMatic(sender, msg.value);
            uint256 _preTotalRewards = totalRewards.add( _reward );
    
            if( _preTotalRewards <= LP_TOKENS ) {
                if (msg.value <= INSTANT_LIMIT) {
                    instantValue = msg.value;
                    delayedValue = 0;
                } else {
                    delayedValue = msg.value.sub(INSTANT_LIMIT);
                    instantValue = msg.value.sub(delayedValue);
                }
                
                uint256 reward = _rewardFromMatic(sender, instantValue);
                rewards[sender] = rewards[sender].add( reward );
                totalRewards = totalRewards.add( reward );
                addLiquidity(sender, reward, instantValue);
    
                if (delayedValue > 0){
                    balances[sender] = balances[sender].add( delayedValue );
                }
                totalMatic = totalMatic.add( msg.value );
            } else {
                uint256 overflow = _preTotalRewards.sub( LP_TOKENS );
                uint256 _instantReward = _reward.sub( overflow );
                if ( _reward > 0 ){
                    rewards[sender] = rewards[sender].add( _instantReward );
                    uint256 _value = _maticFromReward(sender, _instantReward);
                    addLiquidity(sender, _reward, _value);
                }
                uint256 _matic =  _maticFromReward(sender, overflow);
                totalMatic = totalMatic.add( _matic );
                balances[sender] = balances[sender].add( _matic );
            }
        }
    }
}
