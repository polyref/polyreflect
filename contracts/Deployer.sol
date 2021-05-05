contract Deployer is Context, Ownable {
    using SafeMath for uint256;
    using Address for address;
    
    PolyReflect public reflectToken;
    uint256 internal _tokenDecimals = 9;
    uint256 internal totalRewards = 0;
    uint256 internal START_TIME = block.timestamp + 60*60*72;
    uint256 internal immutable TOKENS_FOR_PRESALE = 5_000_000_000 * 10**_tokenDecimals;
    uint256 internal immutable TOKENS_FOR_LIQUIDITY = 4_500_000_000 * 10**_tokenDecimals;
    uint256 internal immutable TEAM_TOKENS = 500_000_000 * 10**_tokenDecimals;
    uint256 internal immutable SOFT_CAP = 250_000 * 10**18; // 250k MATIC
    uint256 internal immutable VALID_TILL = block.timestamp + 60 * 60 * 24 + 15*60; // 1 day after deploy + 15 minutes to verify contracts
    uint256 internal immutable PRESALE_RATIO = 8000; // For 1 MATIC you'll receive 8 PRF
    address internal QUICKSWAP_ROUTER_ADDRESS = 0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff ;
    IQuickSwap internal quick_router;
    
    address[] public participants;
    mapping (address => uint256) public balances;
    
    
    constructor () public {
        reflectToken = new PolyReflect(address(this)); //Create token and receive 
        reflectToken.excludeAccount(address(this));
        quick_router = IQuickSwap(QUICKSWAP_ROUTER_ADDRESS);
    }
    
    function _startTime() public view returns (uint256) {
        return START_TIME;
    }
    
    function _totalRewards() public view returns (uint256) {
        return totalRewards;
    }
    
    function adjustStart(uint256 timestamp) public onlyOwner() {
        START_TIME = timestamp;
    }
    
    function _getReward(address participant) internal view returns (uint256) {
        return (uint256) ( ( (balances[participant] * PRESALE_RATIO) / 10**18 ) * 10**_tokenDecimals );
    }
    
    function endPresale() public returns (bool) {
        require((block.timestamp > VALID_TILL || totalRewards > TOKENS_FOR_PRESALE), "Presale is not over yet");
        
        if(address(this).balance < SOFT_CAP) { // Returns MATIC to senders
            for(uint256 i = 0; i < participants.length; i++){
                if (balances[participants[i]] > 0){
                    payable(participants[i]).transfer(balances[participants[i]]);
                    balances[participants[i]] = 0;
                }
            }
        } else { // Otherwise, add liquidity to router and burn LP
            require(reflectToken.approve(QUICKSWAP_ROUTER_ADDRESS, TOKENS_FOR_LIQUIDITY), 'Approve failed');
            require(reflectToken.transfer(owner(), TEAM_TOKENS), 'Team tokens transfer failed');
            quick_router.addLiquidityETH{value: address(this).balance}(
                address(reflectToken), //token
                TOKENS_FOR_LIQUIDITY, // amountTokenDesired
                TOKENS_FOR_LIQUIDITY, // amountTokenMin
                address(this).balance, // amountETHMin
                address(0), // to => liquidity tokens are locked forever by sending them to dead address
                block.timestamp + 120 // deadline
                );
            
            for(uint256 i = 0; i < participants.length; i++) { // send tokens to participants
                uint256 _payoutAmount = _getReward(participants[i]);
                uint256 _tokensRemaining = reflectToken.balanceOf( address(this) );
                if( _tokensRemaining > 0 && _payoutAmount > 0 && _payoutAmount <= _tokensRemaining) {
                    if(reflectToken.transfer(
                        participants[i], 
                        _payoutAmount
                        )){ balances[participants[i]] = 0; }
                        
                } else  {
                    if (_payoutAmount > 0) {
                        payable(participants[i]).transfer( balances[participants[i]] );
                        balances[participants[i]] = 0;
                    }
                }
            }
            
            reflectToken.transfer(payable(0x000000000000000000000000000000000000dEaD), reflectToken.balanceOf( address(this) )); // And burn remaining tokens
        }
        
        return true;
    }
    
    function withdraw() external { // Participans can withdraw their balance in case of unpredictable events 1 hour after presale ends.
        address payable sender = payable(_msgSender());
        require(address(this).balance > 0, "Nothing to withdraw");
        require(block.timestamp >= VALID_TILL + 60*60, "Function not available at this moment");
        require(balances[sender] > 0, "Cannot withdraw zero balance");
        sender.transfer(balances[sender]);
        balances[sender] = 0;
    }
    
    receive () payable external {
        uint256 _time = block.timestamp;
        require(_time >= START_TIME, "Presale does not started");
        require(_time <= VALID_TILL, "Presale is over");
        address sender = _msgSender();
        if(balances[sender] == 0) {
            participants.push(sender);
        }

        balances[sender] = balances[sender].add(msg.value);
        totalRewards = totalRewards.add( _getReward(sender) );
    } 
}
