// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}

abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor () {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}


contract MachineStrategy is Ownable {
   
    struct MachineRange {
        uint minLoad;
        uint maxLoad;
        uint minExploit;
        uint maxExploit;
    }
    
    MachineRange[] public machineRanges;
    
    string public loadStr = "load";
    string public exploitStr = "exploit";
    
    
    function addRange(uint minLoad,uint maxLoad,uint minExploit,uint maxExploit) public onlyOwner {
        require(maxLoad>minLoad,"error range");
        require(maxExploit>minExploit,"error range");
        machineRanges.push(MachineRange({
            minLoad: minLoad,
            maxLoad: maxLoad,
            minExploit: minExploit,
            maxExploit: maxExploit
        }));
    }
    
    function setRange(uint id,uint minLoad,uint maxLoad,uint minExploit,uint maxExploit) public onlyOwner {
        require(maxLoad>minLoad,"error range");
        require(maxExploit>minExploit,"error range");
        machineRanges[id].minLoad = minLoad;
        machineRanges[id].maxLoad = maxLoad;
        machineRanges[id].minExploit = minExploit;
        machineRanges[id].maxExploit = maxExploit;
    }
  
    function buildSeed(uint _tokenId,uint,address to) external view returns(uint _model, uint _load,uint _exploit){
        uint256 ret = uint256(blockhash(block.number - 1));
        _model = uint256(keccak256(abi.encodePacked(ret, _tokenId, to, block.timestamp)))%machineRanges.length;
        MachineRange memory machineRage = machineRanges[_model];
        uint loadRange = machineRage.maxLoad - machineRage.minLoad;
        uint exploitRange = machineRage.maxExploit - machineRage.minExploit;
        _load = random(loadStr,ret,_model)%loadRange+machineRage.minLoad;
        _exploit = random(exploitStr,ret,_model)%exploitRange+machineRage.minExploit;
 
    }

    function random(string memory kind,uint ret, uint id ) public view returns(uint256){
        
        return uint256(keccak256(abi.encodePacked(kind, ret, block.timestamp, id)));
    }


}

