pragma solidity ^0.6.0;

import "./interfaces/IQuickSwap.sol";
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
    
    /* PRESALE CONFIG */    
    uint256 internal immutable SOFT_CAP = 250_000 * 10**18;
    uint256 internal immutable HARD_CAP = 625_000 * 10**18;
    uint256 private PRESALE_RATIO = 8000;
    uint256 private PRESALE_TOTAL = 100;
    
    uint256 private FARM_TOKENS = PRESALE_TOTAL.div(100).mul(80);
    uint256 private STAKING_TOKENS = FARM_TOKENS.div(100).mul(30);
    uint256 private LP_TOKENS = FARM_TOKENS.div(100).mul(70);
    uint256 private TEAM_TOKENS = 0;
    uint256 private PRESALE_TOKENS = PRESALE_TOTAL.sub(FARM_TOKENS.add(TEAM_TOKENS));
    uint256 public START_TIME;
    uint256 public VALID_TILL;
    
    /* LEGACY */    
    DeployerV1 public _DeployerV1;
    mapping(address => bool) public round_one_participants;
    uint256 BENEFITS_PERCENT = 10;

    /* SERVICE */
    address[] public participants;
    mapping(address => uint256) public balances;

    /* TOKEN */
    PolyReflect public reflectToken;
    uint256 internal _tokenDecimals = 9;
    uint256 internal totalRewards = 0;
    
    constructor(address legacyDeployer, uint8 legacyParticipants, uint256 _startTime, uint8 _presaleDays) public {
        _DeployerV1 = DeployerV1(legacyDeployer);
        for(uint8 i = 0; i < legacyParticipants; i++) {
            address participant = _DeployerV1.participants(i);
            if(participant != address(0)){
                round_one_participants[participant] = true;
            }
        }
        reflectToken = new PolyReflect(address(this));
        
        START_TIME = _startTime;
        VALID_TILL = _startTime + (_presaleDays * 1 days);
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
    
    // END PRESALE CHECK QUEUE POSITION FOR not address(0)

    function withdraw() external { // Participans can withdraw their balance at anytime
        address payable sender = payable(_msgSender());
        require(address(this).balance > 0, "Nothing to withdraw");
        require(balances[sender] > 0, "Cannot withdraw zero balance");
        sender.transfer(balances[sender]);
        totalRewards.sub(balances[sender].mul(PRESALE_RATIO));
        balances[sender] = 0;
        for (uint256 i = 0; i < participants.length; i++){
            if( participants[i] == sender ) {
                delete participants[i]; //purge position in queue    
                break;
            }
        }
    }
    
    receive () payable external {
        require(tx.origin == msg.sender); // Preventing flash-loan attack
        uint256 _time = block.timestamp;
        require(_time >= START_TIME, "Presale does not started");
        require(_time <= VALID_TILL, "Presale is over");
        address sender = _msgSender();
        if(balances[sender] == 0) {
            participants.push(sender);
        }
        balances[sender] = balances[sender].add(msg.value);
        
        uint256 reward;
        if(round_one_participants[sender] == true) { 
            reward = msg.value.mul(PRESALE_RATIO.add(PRESALE_RATIO.div(100).mul(BENEFITS_PERCENT))).div(10**18).mul(10**_tokenDecimals);
        }else{
            reward = msg.value.mul(PRESALE_RATIO).div(10**18).mul(10**_tokenDecimals); 
        }
        
        totalRewards = totalRewards.add( reward );
        require(balances[sender] <= 2500 * 10**18);
    }
}
