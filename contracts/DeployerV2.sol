// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "./interfaces/IQuickSwap.sol";
import "./interfaces/IQuickSwapFactory.sol";
import "./utils/Context.sol";
import "./utils/Ownable.sol";
import "./utils/SafeMath.sol";
import "./utils/Address.sol";
import "./PRF.sol";
import "./staking/Staking.sol";

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
    
    /* STAKING */
    Staking public LPStaking;
    Staking public NativeStaking;
    uint256 public REWARD_PER_BLOCK;
    
    /* PRESALE CONFIG */    
    uint256 internal constant SOFT_CAP = 250_000 * 10**18;
    uint256 internal constant HARD_CAP = 625_000 * 10**18;
    
    uint256 private TOTAL_TOKENS = 10 * 10**9 * 10**_tokenDecimals;
    
    uint256 internal FARM_TOKENS = TOTAL_TOKENS.div(100).mul(75);
        uint256 internal NATIVE_STAKING_TOKENS = FARM_TOKENS.div(100).mul(30);
        uint256 internal LP_STAKING_TOKENS = FARM_TOKENS.div(100).mul(70);
    uint256 internal TEAM_TOKENS = TOTAL_TOKENS.div(100).mul(5);
    uint256 internal PRESALE_TOKENS = TOTAL_TOKENS.sub(FARM_TOKENS).sub(TEAM_TOKENS);
        uint256 internal TOKENS_TO_LIQIDITY = PRESALE_TOKENS.div(2);
        uint256 public PRESALE_RATIO = ((PRESALE_TOKENS.sub(TOKENS_TO_LIQIDITY)).div(10**_tokenDecimals)).div(HARD_CAP.div(10**18));
        uint256 internal INSTANT_LIMIT = 3000 * 10**18;
    
    uint256 public START_TIME;
    uint256 public VALID_TILL;
    
    /* LEGACY */    
    DeployerV1 internal _DeployerV1;
    mapping(address => bool) public round_one_participants;
    uint256 public BENEFITS_PERCENT = 10;

    /* SERVICE */
    address[] public participants;
    uint256 public totalMatic;
    mapping(address => uint) private liquidityShare;
    mapping(address => uint256) private balances;
    mapping(address => uint256) private rewards;
    
    /* QUICKSWAP */
    address internal QUICKSWAP_FACTORY_ADDRESS = 0x5757371414417b8C6CAad45bAeF941aBc7d3Ab32 ;
    address internal QUICKSWAP_ROUTER_ADDRESS = 0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff ;
    IQuickSwapFactory internal quick_factory;
    IQuickSwap internal quick_router;
    
    address internal LP_TOKEN_ADDRESS;
    IERC20 internal lpToken;
    
    uint256 internal additionalBalanceAmount;
    uint256 internal additionalRewardAmount;
    uint256 internal additionalRewardRedeemed;
    
    constructor(
        address legacyDeployer, 
        uint8 legacyParticipants,
        uint256 _startTime, 
        uint256 _presaleDays) public payable {
            require(msg.value > 0, "constructor:: no balance for genesis liqidity");
            _DeployerV1 = DeployerV1(legacyDeployer);
            for(uint8 i = 0; i < legacyParticipants; i++) {
                address participant = _DeployerV1.participants(i);
                if(participant != address(0)){
                    round_one_participants[participant] = true;
                }
            }
            reflectToken = new PolyReflect(address(this), QUICKSWAP_ROUTER_ADDRESS);
            quick_factory = IQuickSwapFactory(QUICKSWAP_FACTORY_ADDRESS);
            quick_router = IQuickSwap(QUICKSWAP_ROUTER_ADDRESS);

            START_TIME = _startTime;
            VALID_TILL = _startTime + (_presaleDays * 1 days);
            reflectToken.approve(address(this), ~uint256(0));
            require(reflectToken.approve(QUICKSWAP_ROUTER_ADDRESS, ~uint256(0)), "Approve failed");
            REWARD_PER_BLOCK = FARM_TOKENS / (60 * 60 * 24 * 365 / 2);
            
            /* CREATING GENESIS LIQIDITY */ 
            uint256 tokenAmount = _rewardFromMatic(_msgSender(), msg.value);
            quick_router.addLiquidityETH{ value: msg.value }( 
                address(reflectToken), //token
                tokenAmount, // amountTokenDesired
                0, // amountTokenMin
                msg.value, // amountETHMin
                address(this),//address(0), 
                block.timestamp + 120 // deadline
            );
            totalRewards = totalRewards.add( tokenAmount );
            totalMatic = totalMatic.add( msg.value );
            LP_TOKEN_ADDRESS = quick_factory.getPair( quick_router.WETH(), address(reflectToken) );
            lpToken = IERC20( LP_TOKEN_ADDRESS );
            require( lpToken.approve( QUICKSWAP_ROUTER_ADDRESS, ~uint256(0)) );
            reflectToken.setLPPair( LP_TOKEN_ADDRESS );
            
            reflectToken.excludeAccount( address(this) );
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
    
    function _maticFromReward(address user, uint256 _value) internal view returns (uint256 _wei) {
        if(round_one_participants[user] == true) { 
            return _value.div(PRESALE_RATIO.add(PRESALE_RATIO.div(100).mul(BENEFITS_PERCENT))).mul(10**18).div(10**_tokenDecimals);
        }else{
            return _value.div(PRESALE_RATIO).mul(10**18).div(10**_tokenDecimals); 
        }
    }

    function addLiquidity(address sender, uint256 tokenAmount, uint256 maticAmount) internal {
        (,,uint liqidity) = quick_router.addLiquidityETH{ value: maticAmount }( 
                address(reflectToken), //token
                tokenAmount, // amountTokenDesired
                0, // amountTokenMin
                maticAmount, // amountETHMin
                address(this), 
                block.timestamp + 120 // deadline
            );

        liquidityShare[sender] = liquidityShare[sender].add(liqidity);
        totalRewards = totalRewards.add( tokenAmount );
        reflectToken.transferFrom( address(this), sender, tokenAmount );
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
    
    function _getTokenAmountFromShare(uint256 _balance, address participant, uint256 tokenAmountTotal) internal view returns (uint256 _tokenAmount) {
        uint256 balance = balances[participant];
        if(balance > 0){ 
            uint256 balanceShare = (balance.div( _balance.div(100) )).div(100);
            uint256 tokenAmount = tokenAmountTotal.mul(balanceShare);
            return tokenAmount;
        } else {
            return 0;
        }
        
    }
    
    function refundAll(uint256 offsetLower, uint256 offsetUpper) public onlyOwner() {
        require( block.timestamp > VALID_TILL, "Presale is not over yet" );
        if(totalMatic < SOFT_CAP) {
            for(uint256 i = offsetLower; i <= offsetUpper; i++){
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
        }
    }
    
    function endPresale() public returns (bool) {
        require( block.timestamp > VALID_TILL, "Presale is not over yet" );
        require( totalMatic >= SOFT_CAP, "Soft cap didnt reached");

        if(address(this).balance > 0) {
            uint256 _balance = address(this).balance;
            address[] memory path = new address[](2);
            path[0] = quick_router.WETH();
            path[1] = address(reflectToken);
            uint[] memory amounts = quick_router.swapExactETHForTokens{value: _balance}(
                0,
                path,
                address(this),
                block.timestamp + 120
            );
            
            additionalBalanceAmount = _balance;
            additionalRewardAmount = amounts[ amounts.length - 1 ];
        
        }
        
        /* INIT STAKINGS */
        uint256 _stakingStart = block.timestamp + (60 * 60 * 4)/2;
        
        LPStaking = new Staking(
            reflectToken,
            REWARD_PER_BLOCK,
            _stakingStart
            );
        reflectToken.transferNoFee( address(this), address(LPStaking), LP_STAKING_TOKENS );
        LPStaking.fund(LP_STAKING_TOKENS);
        LPStaking.add( reflectToken.balanceOf(address(LPStaking)), lpToken, false);
        
        NativeStaking = new Staking(
            reflectToken,
            REWARD_PER_BLOCK,
            _stakingStart
            );
        reflectToken.transferNoFee( address(this), address(NativeStaking), NATIVE_STAKING_TOKENS );
        NativeStaking.fund(NATIVE_STAKING_TOKENS);
        NativeStaking.add( reflectToken.balanceOf(address(NativeStaking)), reflectToken, false);
        
        
        reflectToken.approve( address(NativeStaking), ~uint256(0) );                
        reflectToken.approve( address(LPStaking), ~uint256(0) );                
        /*                   */
        
        require(reflectToken.transferNoFee(address(this), owner(), TEAM_TOKENS), "Team tokens transfer failed");
        require(reflectToken.unlockAfterPresale(), "Token is not unlocked");

        return true;
    }

    function claimReward() public {
        address participant = _msgSender();
        uint256 _share = _getTokenAmountFromShare(additionalBalanceAmount, participant, additionalRewardAmount);
        require(_share > 0, "Nothing to claim");
        additionalRewardRedeemed = additionalRewardRedeemed.add(_share);
        reflectToken.transferFrom( address(this), participant, _share );    
    }
    
    function burnRemainingTokens() public onlyOwner() {
        require(additionalRewardRedeemed >= additionalRewardAmount, "Cannot burn");
        reflectToken.transferNoFee( address(this), address(0), reflectToken.balanceOf(address(this)));
    }

    function withdraw() public { // Participans can withdraw their balance at anytime during the pre-sale
        require(
            (block.timestamp < VALID_TILL) ||
            (block.timestamp > VALID_TILL + 2 days), "Cannot withdraw");
        address payable sender = payable(_msgSender());
        uint256 _balance = balances[sender];
        uint256 _reward = rewards[sender];
        
        require(address(this).balance > 0 || liquidityShare[sender] > 0, "Nothing to withdraw");
        require(_balance > 0 || rewards[sender] > 0, "Cannot withdraw zero balance");
        
        balances[sender] = 0;
        rewards[sender] = 0;

        if( liquidityShare[sender] > 0 ){
            removeLiquidity(sender);
        }
        
        uint256 _totalUserToken = _reward;
        uint256 _matic = _maticFromReward(sender, _totalUserToken);
        uint256 _totalUserMatic = _balance.add(_matic);
        
        totalMatic = totalMatic.sub(_totalUserMatic);
        totalRewards = totalRewards.sub(_totalUserToken);
        
        reflectToken.transferFrom(sender, address(this), _totalUserToken);
        sender.transfer(_totalUserMatic);
    }
     
    receive () external payable {
        require(msg.value > 0, 'receive:: Cannot deposit zero MATIC');
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
    
            if( _preTotalRewards <= TOKENS_TO_LIQIDITY ) {
                if (msg.value <= INSTANT_LIMIT) {
                    instantValue = msg.value;
                    delayedValue = 0;
                } else {
                    delayedValue = msg.value.sub(INSTANT_LIMIT);
                    instantValue = msg.value.sub(delayedValue);
                }
                
                uint256 reward = _rewardFromMatic(sender, instantValue);
                rewards[sender] = rewards[sender].add( reward );
                addLiquidity(sender, reward, instantValue);
    
                if (delayedValue > 0){
                    balances[sender] = balances[sender].add( delayedValue );
                }
                totalMatic = totalMatic.add( msg.value );
            } else {
                uint256 overflow = _preTotalRewards.sub( TOKENS_TO_LIQIDITY , "Receive:: underflow");
                uint256 instantTokenValue = _reward.sub( overflow );
                if ( instantTokenValue > 0 ){
                    rewards[sender] = rewards[sender].add( instantTokenValue );
                    instantValue = _maticFromReward(sender, instantTokenValue);
                    addLiquidity(sender, instantTokenValue, instantValue);
                }
                uint256 _matic =  _maticFromReward(sender, overflow);
                totalMatic = totalMatic.add( _matic ).add(instantValue);
                balances[sender] = balances[sender].add( _matic );
            }
        }
    }
}
